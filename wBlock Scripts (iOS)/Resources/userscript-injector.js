/**
 * wBlock Userscript Injector
 * Injects and manages userscripts from the native app
 */

// Debug logging flag - set to false to disable verbose console output
var WBLOCK_DEBUG_LOGGING = false;

var wBlockLog = (...args) => {
    if (WBLOCK_DEBUG_LOGGING) {
        console.log(...args);
    }
};

var wBlockWarn = (...args) => {
    if (WBLOCK_DEBUG_LOGGING) {
        console.warn(...args);
    }
};

var wBlockError = (...args) => {
    // Always log errors
    console.error(...args);
};

// Escape a string for safe embedding inside a JavaScript string literal.
// Handles backslash, single/double quotes, backticks, newlines, and template
// literal interpolation sequences so that userscript metadata with special
// characters never produces malformed generated JavaScript.
function escapeForJS(str) {
    if (typeof str !== 'string') return '';
    return str
        .replace(/\\/g, '\\\\')
        .replace(/'/g, "\\'")
        .replace(/"/g, '\\"')
        .replace(/`/g, '\\`')
        .replace(/\n/g, '\\n')
        .replace(/\r/g, '\\r')
        .replace(/\$\{/g, '\\${');
}

// Best-effort CSP nonce detection for script-tag injection on strict CSP pages
var wBlockCachedCspNonce = null;
function getCspNonce() {
    if (wBlockCachedCspNonce) return wBlockCachedCspNonce;
    try {
        const el = document.querySelector('script[nonce]');
        const nonce = el ? (el.nonce || el.getAttribute('nonce') || '') : '';
        if (nonce) {
            wBlockCachedCspNonce = nonce;
        }
        return nonce || '';
    } catch (e) {
        return '';
    }
}

function setTrustedScriptText(scriptElement, source) {
    try {
        const tt = window.trustedTypes;
        if (tt && typeof tt.createPolicy === 'function') {
            const policy = tt.createPolicy('wblock-userscript-' + Math.random().toString(36).slice(2), { createScript: value => value });
            scriptElement.textContent = policy.createScript(source);
            return true;
        }
    } catch (e) {}
    scriptElement.textContent = source;
    return true;
}

// Opaque/sandboxed frames commonly throw Safari console access violations when
// probing frameElement. Avoid touching it; page-world injection cannot work in
// non-http(s) frames anyway.
function isSandboxedWithoutScripts() {
    return location.protocol !== 'http:' && location.protocol !== 'https:';
}

// Prevent multiple executions of this entire script in the same context
if (window.wBlockUserscriptInjectorHasRun) {
    wBlockLog('[wBlock] Userscript injector already ran in this frame.');
} else {
    window.wBlockUserscriptInjectorHasRun = true;
    wBlockLog('[wBlock] Initializing Userscript Injector for this frame.');

    // Userscript execution engine
    class UserScriptEngine {
        constructor() {
            this.injectedScripts = new Set();
            this.injectingScripts = new Set();
            this.pendingScripts = []; // Scripts waiting for document to be ready
            this.messageListenerAttached = false; // Ensure listener is attached only once
            this.pendingNativeRequests = new Map(); // requestId -> { resolve, reject, timeoutId }
            this.storageBridgeScriptIDs = new Map(); // bridgeId -> scriptId
            this.pageMenuBridgeElements = new Map(); // bridgeId -> script element
            this.pageMenuPostMessageBridgeIDs = new Set(); // bridgeIds registered by MAIN-world executeScript
            this.contentMenuCommandCallbacks = new Map(); // bridgeId -> Map(commandId, callback)
            this.registeredMenuCommands = new Map(); // bridgeId -> Map(commandId, descriptor)
            this.pendingMenuInvocations = new Map(); // requestId -> { resolve, timeoutId }
            this.menuCommandSequence = 0;
            this.userScriptRequestRetryDelays = [500, 1500, 4000, 8000];
            wBlockLog('[wBlock] UserScriptEngine constructor called.');
            this.init();
        }

        init() {
            wBlockLog('[wBlock] UserScriptEngine init.');
            this.setupDocumentEventListeners();
            // Listen for response from native app before making any requests.
            // On Safari App Extensions, responses can arrive very quickly and be missed
            // if the listener isn't attached yet.
            this.setupMessageListener();

            // Bridge GM menu command registration/invocation between userscripts
            // and the extension popup.
            this.setupMenuCommandBridge();

            // Bridge page-context GM storage writes through the extension/native layer.
            this.setupStorageBridge();

            // Bridge for GM_xmlhttpRequest: page-context scripts post messages here,
            // and we forward them through the background/native layer (CORS-free).
            this.setupXhrBridge();

            // Request userscripts from native app
            this.requestUserScripts();
        }

        setupXhrBridge() {
            window.addEventListener('message', (event) => {
                if (event.source !== window) return;
                const data = event.data;
                if (!data || data.type !== 'wblock-gm-xhr-request') return;

                const { id, url, method, headers, body, anonymous, responseType, timeout, redirect } = data;

                this.proxyXhr({ url, method, headers, body, anonymous, responseType, timeout, redirect })
                    .then(result => {
                        window.postMessage({
                            type: 'wblock-gm-xhr-response',
                            id: id,
                            success: true,
                            result: result
                        }, '*');
                    })
                    .catch(error => {
                        window.postMessage({
                            type: 'wblock-gm-xhr-response',
                            id: id,
                            success: false,
                            error: error.message || String(error)
                        }, '*');
                    });
            });
        }

        setupStorageBridge() {
            window.addEventListener('message', (event) => {
                if (event.source !== window) return;
                const data = event.data;
                if (!data || (data.type !== 'wblock-gm-storage-set' && data.type !== 'wblock-gm-storage-delete')) return;
                if (typeof data.bridgeId !== 'string' || typeof data.key !== 'string' || typeof data.requestId !== 'string') return;
                if (data.type === 'wblock-gm-storage-set' && typeof data.rawValue !== 'string') return;

                const scriptId = this.storageBridgeScriptIDs.get(data.bridgeId);
                if (!scriptId) return;

                const action = data.type === 'wblock-gm-storage-set'
                    ? 'setUserScriptStorageValue'
                    : 'deleteUserScriptStorageValue';
                const payload = {
                    scriptId: scriptId,
                    key: data.key
                };

                if (action === 'setUserScriptStorageValue') {
                    payload.rawValue = data.rawValue;
                }

                this.sendNativeRequest(action, payload)
                    .then((result) => {
                        const ok = !!result && result.ok !== false;
                        window.postMessage({
                            type: 'wblock-gm-storage-result',
                            requestId: data.requestId,
                            success: ok,
                            error: ok ? undefined : ((result && result.error) || 'Failed to persist GM storage change')
                        }, '*');
                    })
                    .catch((error) => {
                        const errorMessage = error && error.message ? error.message : String(error);
                        wBlockWarn('[wBlock] Failed to persist GM storage change:', errorMessage);
                        window.postMessage({
                            type: 'wblock-gm-storage-result',
                            requestId: data.requestId,
                            success: false,
                            error: errorMessage
                        }, '*');
                    });
            });
        }

        setupMenuCommandBridge() {
            window.__wBlockMenuCommandBridge = {
                registerMenuCommand: (bridgeId, commandId, details, callback) => {
                    if (typeof callback !== 'function') return;

                    let callbacks = this.contentMenuCommandCallbacks.get(bridgeId);
                    if (!callbacks) {
                        callbacks = new Map();
                        this.contentMenuCommandCallbacks.set(bridgeId, callbacks);
                    }
                    callbacks.set(commandId, callback);
                    this.registerMenuCommandDescriptor(bridgeId, commandId, details);
                },
                unregisterMenuCommand: (bridgeId, commandId) => {
                    const callbacks = this.contentMenuCommandCallbacks.get(bridgeId);
                    if (callbacks) {
                        callbacks.delete(commandId);
                        if (callbacks.size === 0) {
                            this.contentMenuCommandCallbacks.delete(bridgeId);
                        }
                    }
                    this.unregisterMenuCommandDescriptor(bridgeId, commandId);
                }
            };
            window.__wBlockUserscriptMenuState = this.getRegisteredMenuCommands();

            window.addEventListener('message', (event) => {
                if (event.source !== window) return;
                const data = event.data;
                if (!data || typeof data.type !== 'string') return;

                if (data.type === 'wblock-gm-menu-register') {
                    if (typeof data.bridgeId !== 'string' || typeof data.commandId !== 'string' || typeof data.caption !== 'string') return;
                    this.pageMenuPostMessageBridgeIDs.add(data.bridgeId);
                    this.registerMenuCommandDescriptor(data.bridgeId, data.commandId, data);
                    return;
                }

                if (data.type === 'wblock-gm-menu-unregister') {
                    if (typeof data.bridgeId !== 'string' || typeof data.commandId !== 'string') return;
                    this.unregisterMenuCommandDescriptor(data.bridgeId, data.commandId);
                    return;
                }

                if (data.type === 'wblock-gm-menu-invoke-result') {
                    if (typeof data.bridgeId !== 'string' || typeof data.requestId !== 'string') return;
                    const pending = this.pendingMenuInvocations.get(data.requestId);
                    if (!pending) return;
                    this.pendingMenuInvocations.delete(data.requestId);
                    clearTimeout(pending.timeoutId);
                    pending.resolve({
                        ok: data.success !== false,
                        error: typeof data.error === 'string' ? data.error : ''
                    });
                }
            });

            window.addEventListener('pagehide', () => {
                this.pageMenuBridgeElements.clear();
                this.pageMenuPostMessageBridgeIDs.clear();
                this.contentMenuCommandCallbacks.clear();
                this.registeredMenuCommands.clear();
                window.__wBlockUserscriptMenuState = [];
                this.syncMenuCommandsToBackground();
            }, { once: true });
        }

        registerMenuCommandDescriptor(bridgeId, commandId, details = {}) {
            if (typeof bridgeId !== 'string' || typeof commandId !== 'string') {
                return;
            }

            const bridgeCommands = this.registeredMenuCommands.get(bridgeId) || new Map();
            const existing = bridgeCommands.get(commandId);
            bridgeCommands.set(commandId, {
                bridgeId,
                commandId,
                caption: typeof details.caption === 'string' ? details.caption : '',
                title: typeof details.title === 'string' ? details.title : '',
                accessKey: typeof details.accessKey === 'string' ? details.accessKey : '',
                scriptName: typeof details.scriptName === 'string' ? details.scriptName : '',
                sortOrder: existing ? existing.sortOrder : (++this.menuCommandSequence)
            });
            this.registeredMenuCommands.set(bridgeId, bridgeCommands);
            this.syncMenuCommandsToBackground();
        }

        unregisterMenuCommandDescriptor(bridgeId, commandId) {
            if (typeof bridgeId !== 'string' || typeof commandId !== 'string') {
                return;
            }

            const bridgeCommands = this.registeredMenuCommands.get(bridgeId);
            if (!bridgeCommands) {
                return;
            }

            bridgeCommands.delete(commandId);
            if (bridgeCommands.size === 0) {
                this.registeredMenuCommands.delete(bridgeId);
            }
            this.syncMenuCommandsToBackground();
        }

        syncMenuCommandsToBackground() {
            const commands = this.getRegisteredMenuCommands();
            window.__wBlockUserscriptMenuState = commands;

            if (!(typeof browser !== 'undefined' && browser.runtime && browser.runtime.sendMessage)) {
                return;
            }

            browser.runtime.sendMessage({
                action: 'wblock:menu:updateFrameCommands',
                commands
            }).catch((error) => {
                wBlockWarn('[wBlock] Failed to sync menu commands to background:', error);
            });
        }

        attachPageMenuCommandBridge(scriptElement, script) {
            const bridgeId = script && script.menuBridgeId;
            if (!bridgeId || !scriptElement) {
                return;
            }

            this.pageMenuBridgeElements.set(bridgeId, scriptElement);
            scriptElement.addEventListener('wblock-gm-menu-register', (event) => {
                const detail = event && event.detail ? event.detail : {};
                if (detail.bridgeId !== bridgeId || typeof detail.commandId !== 'string' || typeof detail.caption !== 'string') {
                    return;
                }
                this.registerMenuCommandDescriptor(bridgeId, detail.commandId, detail);
            });

            scriptElement.addEventListener('wblock-gm-menu-unregister', (event) => {
                const detail = event && event.detail ? event.detail : {};
                if (detail.bridgeId !== bridgeId || typeof detail.commandId !== 'string') {
                    return;
                }
                this.unregisterMenuCommandDescriptor(bridgeId, detail.commandId);
            });

            scriptElement.addEventListener('wblock-gm-menu-invoke-result', (event) => {
                const detail = event && event.detail ? event.detail : {};
                if (detail.bridgeId !== bridgeId || typeof detail.requestId !== 'string') {
                    return;
                }

                const pending = this.pendingMenuInvocations.get(detail.requestId);
                if (!pending) {
                    return;
                }

                this.pendingMenuInvocations.delete(detail.requestId);
                clearTimeout(pending.timeoutId);
                pending.resolve({
                    ok: detail.success !== false,
                    error: typeof detail.error === 'string' ? detail.error : ''
                });
            });
        }

        getRegisteredMenuCommands() {
            const commands = [];
            this.registeredMenuCommands.forEach((bridgeCommands) => {
                bridgeCommands.forEach((descriptor) => {
                    commands.push(descriptor);
                });
            });

            commands.sort((left, right) => left.sortOrder - right.sortOrder);
            return commands.map(({ bridgeId, commandId, caption, title, accessKey, scriptName, sortOrder }) => ({
                bridgeId,
                commandId,
                caption,
                title,
                accessKey,
                scriptName,
                sortOrder
            }));
        }

        async invokeMenuCommand(bridgeId, commandId) {
            if (typeof bridgeId !== 'string' || typeof commandId !== 'string') {
                return { ok: false, error: 'Invalid menu command request' };
            }

            const contentCallbacks = this.contentMenuCommandCallbacks.get(bridgeId);
            if (contentCallbacks && contentCallbacks.has(commandId)) {
                try {
                    await Promise.resolve(contentCallbacks.get(commandId)());
                    return { ok: true, error: '' };
                } catch (error) {
                    return {
                        ok: false,
                        error: error && error.message ? error.message : String(error)
                    };
                }
            }

            const bridgeElement = this.pageMenuBridgeElements.get(bridgeId);
            const hasPostMessageBridge = this.pageMenuPostMessageBridgeIDs.has(bridgeId);
            if (!bridgeElement && !hasPostMessageBridge) {
                return { ok: false, error: 'Menu command not found' };
            }

            const requestId = this.generateRequestId('gmmenuinvoke');
            return await new Promise((resolve) => {
                const timeoutId = setTimeout(() => {
                    this.pendingMenuInvocations.delete(requestId);
                    resolve({ ok: false, error: 'Menu command timed out' });
                }, 15000);

                this.pendingMenuInvocations.set(requestId, { resolve, timeoutId });
                if (bridgeElement) {
                    bridgeElement.dispatchEvent(new CustomEvent('wblock-gm-menu-invoke', {
                        detail: { bridgeId, commandId, requestId }
                    }));
                } else {
                    window.postMessage({
                        type: 'wblock-gm-menu-invoke',
                        bridgeId,
                        commandId,
                        requestId
                    }, '*');
                }
            });
        }

        async proxyXhr(details) {
            // Route the fetch through the background script (WebExtension) or
            // native handler (Safari App Extension) to bypass page-level CORS.
            if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.sendMessage) {
                return await browser.runtime.sendMessage({
                    action: 'gmXmlhttpRequest',
                    url: details.url,
                    method: details.method || 'GET',
                    headers: details.headers || {},
                    body: details.body || null,
                    anonymous: !!details.anonymous,
                    responseType: details.responseType || 'text',
                    timeout: details.timeout || 0,
                    redirect: details.redirect || 'follow'
                });
            }

            if (typeof safari !== 'undefined' && safari.extension && safari.extension.dispatchMessage) {
                return await new Promise((resolve, reject) => {
                    const requestId = this.generateRequestId('gmxhr');
                    const timeoutId = setTimeout(() => {
                        this.pendingNativeRequests.delete(requestId);
                        reject(new Error('GM_xmlhttpRequest timeout'));
                    }, 30000);

                    this.pendingNativeRequests.set(requestId, { resolve, reject, timeoutId });
                    safari.extension.dispatchMessage('gmXmlhttpRequest', {
                        requestId,
                        url: details.url,
                        method: details.method || 'GET',
                        headers: details.headers || {},
                        body: details.body || null,
                        anonymous: !!details.anonymous,
                        responseType: details.responseType || 'text',
                        timeout: details.timeout || 0,
                        redirect: details.redirect || 'follow'
                    });
                });
            }

            throw new Error('No messaging API available for GM_xmlhttpRequest proxy');
        }

        generateRequestId(prefix) {
            return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
        }

        async sendNativeRequest(action, payload = {}) {
            const requestId = payload.requestId || this.generateRequestId(action);
            const messagePayload = { ...payload, requestId };

            if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.sendMessage) {
                return await browser.runtime.sendMessage({ action, ...messagePayload });
            }

            if (typeof safari !== 'undefined' && safari.extension && safari.extension.dispatchMessage) {
                return await new Promise((resolve, reject) => {
                    const timeoutMs = (typeof action === 'string' && action.includes('Chunk')) ? 120000 : 15000;
                    const timeoutId = setTimeout(() => {
                        this.pendingNativeRequests.delete(requestId);
                        reject(new Error(`[wBlock] Native request timeout: ${action}`));
                    }, timeoutMs);

                    this.pendingNativeRequests.set(requestId, { resolve, reject, timeoutId });
                    safari.extension.dispatchMessage(action, messagePayload);
                });
            }

            throw new Error('[wBlock] No suitable messaging API found for native requests.');
        }

        getPreferredChunkSize() {
            // Safari's WebExtension/native messaging bridge has tighter payload limits
            // than Chromium-style environments. Keep chunks small for both the
            // browser.runtime and Safari App Extension code paths.
            return 32 * 1024; // bytes, before base64 expansion
        }

        base64ToBytes(base64) {
            const binary = atob(base64);
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            return bytes;
        }

        concatBytes(arrays) {
            const totalLength = arrays.reduce((sum, arr) => sum + arr.length, 0);
            const out = new Uint8Array(totalLength);
            let offset = 0;
            for (const arr of arrays) {
                out.set(arr, offset);
                offset += arr.length;
            }
            return out;
        }

        async fetchTextFromChunks(action, params) {
            const decoder = new TextDecoder('utf-8');
            const chunkSize = this.getPreferredChunkSize();
            const first = await this.sendNativeRequest(action, { ...params, chunkIndex: 0, chunkSize });
            if (first && first.error) throw new Error(first.error);

            const totalChunks = (first && typeof first.totalChunks === 'number') ? first.totalChunks : 1;
            if (!Number.isInteger(totalChunks) || totalChunks < 1) {
                throw new Error('Invalid userscript chunk response');
            }

            const chunks = new Array(totalChunks);
            if (!first || typeof first.chunk !== 'string') {
                throw new Error('Missing userscript chunk data');
            }
            chunks[0] = first.chunk;

            for (let i = 1; i < totalChunks; i++) {
                const resp = await this.sendNativeRequest(action, { ...params, chunkIndex: i, chunkSize });
                if (resp && resp.error) throw new Error(resp.error);
                if (!resp || typeof resp.chunk !== 'string') {
                    throw new Error('Missing userscript chunk data');
                }
                chunks[i] = resp.chunk;
            }

            const byteArrays = chunks.map(c => this.base64ToBytes(c));
            return decoder.decode(this.concatBytes(byteArrays));
        }

        userScriptPayloadCacheKey(script) {
            if (!script || !script.id) return '';
            const version = typeof script.version === 'string' ? script.version : '';
            const lastUpdated = String(script.lastUpdated || '0');
            const resourceNames = Array.isArray(script.resourceNames) ? script.resourceNames.slice().sort().join('|') : '';
            return `wblock-userscript-payload:${script.id}:${version}:${lastUpdated}:${resourceNames}`;
        }

        async readCachedScriptPayload(script) {
            const cacheKey = this.userScriptPayloadCacheKey(script);
            if (!cacheKey || typeof browser === 'undefined' || !browser.storage || !browser.storage.local) {
                return null;
            }
            try {
                const result = await browser.storage.local.get(cacheKey);
                const cached = result && result[cacheKey];
                if (!cached || typeof cached.content !== 'string' || cached.content.length === 0) {
                    return null;
                }
                const resources = cached.resources && typeof cached.resources === 'object' ? cached.resources : {};
                return { ...script, content: cached.content, resources };
            } catch (error) {
                wBlockWarn('[wBlock] Failed to read userscript payload cache:', error);
                return null;
            }
        }

        async writeCachedScriptPayload(script) {
            const cacheKey = this.userScriptPayloadCacheKey(script);
            if (!cacheKey || typeof browser === 'undefined' || !browser.storage || !browser.storage.local) {
                return;
            }
            try {
                await browser.storage.local.set({
                    [cacheKey]: {
                        content: script.content || '',
                        resources: script.resources || {},
                        cachedAt: Date.now()
                    }
                });
            } catch (error) {
                wBlockWarn('[wBlock] Failed to write userscript payload cache:', error);
            }
        }

        async ensureScriptPayload(script) {
            if (script && typeof script.content === 'string' && script.content.length > 0) {
                // Hydrated payload may already include content/resources.
                if (script.resources == null && script.resourceContents != null) {
                    script.resources = script.resourceContents;
                }
                await this.writeCachedScriptPayload(script);
                return script;
            }

            if (!script || !script.id) {
                throw new Error('Userscript descriptor missing id');
            }

            const cached = await this.readCachedScriptPayload(script);
            if (cached) {
                return cached;
            }

            const content = await this.fetchTextFromChunks('getUserScriptContentChunk', { scriptId: script.id });
            const resourceNames = Array.isArray(script.resourceNames) ? script.resourceNames : [];
            const resources = {};
            for (const resourceName of resourceNames) {
                resources[resourceName] = await this.fetchTextFromChunks('getUserScriptResourceChunk', {
                    scriptId: script.id,
                    resourceName
                });
            }

            const hydrated = { ...script, content, resources };
            await this.writeCachedScriptPayload(hydrated);
            return hydrated;
        }

        setupDocumentEventListeners() {
            // Listen for document ready states to inject pending scripts
            if (document.readyState === 'loading') {
                wBlockLog('[wBlock] Document is loading, setting up event listeners for ready states.');
                
                document.addEventListener('DOMContentLoaded', () => {
                    wBlockLog('[wBlock] DOMContentLoaded event fired, retrying pending scripts.');
                    this.retryPendingScripts();
                });
                
                window.addEventListener('load', () => {
                    wBlockLog('[wBlock] Window load event fired, retrying pending scripts.');
                    this.retryPendingScripts();
                });

                if (!document.body && typeof MutationObserver !== 'undefined') {
                    const bodyObserver = new MutationObserver(() => {
                        if (!document.body) return;
                        bodyObserver.disconnect();
                        wBlockLog('[wBlock] document.body appeared, retrying pending scripts.');
                        this.retryPendingScripts();
                    });
                    bodyObserver.observe(document.documentElement || document, { childList: true, subtree: true });
                }
            } else {
                wBlockLog(`[wBlock] Document already ready (${document.readyState}), no need for event listeners.`);
            }
        }

        retryPendingScripts() {
            if (this.pendingScripts.length === 0) {
                wBlockLog('[wBlock] No pending scripts to retry.');
                return;
            }

            wBlockLog(`[wBlock] Retrying ${this.pendingScripts.length} pending scripts...`);
            const scriptsToRetry = [...this.pendingScripts];
            this.pendingScripts = [];
            
            for (const script of scriptsToRetry) {
                this.injectSingleScript(script);
            }
        }

        requestUserScripts(attempt = 0) {
            const url = window.location.href;
            wBlockLog(`[wBlock] Requesting userscripts for URL: ${url}`);

            this.sendNativeRequest('getUserScripts', {
                url,
                includeContent: true,
                maxInlineContentBytes: 128 * 1024
            })
                .then((response) => {
                    if (response && response.error) {
                        throw new Error(response.error);
                    }

                    const scripts = response && response.userScripts ? response.userScripts : [];
                    if (scripts.length === 0) {
                        wBlockLog('[wBlock] No userscripts found in getUserScripts response.');
                        return;
                    }
                    this.injectUserScripts(scripts);
                })
                .catch((error) => {
                    this.retryUserScriptRequest(attempt, error);
                });
        }

        retryUserScriptRequest(attempt, error) {
            const delay = this.userScriptRequestRetryDelays[attempt];
            if (typeof delay !== 'number') {
                wBlockError('[wBlock] Failed to request userscripts:', error);
                return;
            }

            setTimeout(() => this.requestUserScripts(attempt + 1), delay);
        }

        setupMessageListener() {
            if (this.messageListenerAttached) {
                wBlockLog('[wBlock] Message listener already attached.');
                return;
            }
            wBlockLog('[wBlock] Setting up message listener.');

            if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.onMessage) {
                wBlockLog('[wBlock] Using browser.runtime.onMessage for listening.');
                browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
                    wBlockLog('[wBlock] Received message via browser.runtime.onMessage:', JSON.parse(JSON.stringify(message || {})));

                    if (message && message.type === 'wblock:pageSupportProbe') {
                        return Promise.resolve({
                            ok: true,
                            host: typeof location !== 'undefined' ? location.hostname : '',
                            protocol: typeof location !== 'undefined' ? location.protocol : '',
                        });
                    }


                    if (message && message.type === 'wblock:menu:invokeCommand') {
                        return this.invokeMenuCommand(message.bridgeId, message.commandId);
                    }

                    if (message && message.type === 'wblock:menu:syncState') {
                        this.syncMenuCommandsToBackground();
                        return Promise.resolve({ ok: true });
                    }

                    let scriptsToInject = null;
                    if (message && message.userScripts) {
                        scriptsToInject = message.userScripts;
                    } else if (message && message.payload && message.payload.userScripts) {
                        scriptsToInject = message.payload.userScripts;
                    }

                    if (scriptsToInject) {
                        wBlockLog('[wBlock] Extracted userscripts from message (browser.runtime.onMessage):', scriptsToInject);
                        this.injectUserScripts(scriptsToInject);
                    } else {
                        wBlockLog('[wBlock] No userscripts found in received message (browser.runtime.onMessage).');
                    }

                });
                this.messageListenerAttached = true;
                wBlockLog('[wBlock] browser.runtime.onMessage listener attached.');
            } else if (typeof safari !== 'undefined' && safari.extension && typeof safari.self !== 'undefined' && safari.self.addEventListener) {
                wBlockLog('[wBlock] Using safari.self.addEventListener for listening.');
                safari.self.addEventListener('message', (event) => {
                    wBlockLog('[wBlock] Received message via safari.self.addEventListener:', event.name, JSON.parse(JSON.stringify(event.message || {})));
                    const requestId = event.message && event.message.requestId;
                    if (requestId && this.pendingNativeRequests.has(requestId)) {
                        const pending = this.pendingNativeRequests.get(requestId);
                        this.pendingNativeRequests.delete(requestId);
                        if (pending && pending.timeoutId) clearTimeout(pending.timeoutId);
                        pending.resolve(event.message);
                        return;
                    }
                    let scriptsToInject = null;
                    if ((event.name === 'getUserScripts' || event.name === 'requestUserScripts') && event.message && event.message.userScripts) {
                        scriptsToInject = event.message.userScripts;
                    } else if (event.name === 'requestRules' && event.message && event.message.payload && event.message.payload.userScripts) {
                        scriptsToInject = event.message.payload.userScripts;
                    }

                    if (scriptsToInject) {
                        wBlockLog('[wBlock] Extracted userscripts from message (safari.self.addEventListener):', scriptsToInject);
                        this.injectUserScripts(scriptsToInject);
                    } else {
                        wBlockLog('[wBlock] No userscripts found in received message (safari.self.addEventListener).');
                    }
                }, false);
                this.messageListenerAttached = true;
                wBlockLog('[wBlock] safari.self.addEventListener listener attached.');
            } else {
                 wBlockError('[wBlock] No suitable event listener API found.');
            }
        }

        injectUserScripts(userScripts) {
            wBlockLog('[wBlock] injectUserScripts called with:', userScripts);
            if (!Array.isArray(userScripts)) {
                wBlockWarn('[wBlock] injectUserScripts called with non-array:', userScripts);
                return;
            }
            if (userScripts.length === 0) {
                wBlockLog('[wBlock] No userscripts to inject.');
                return;
            }
            userScripts.forEach(script => this.injectUserScript(script));
        }

        injectUserScript(script) {
            if (!script || !script.name) {
                wBlockWarn('[wBlock] Attempted to inject invalid script object:', script);
                return;
            }
            wBlockLog(`[wBlock] Processing userscript: ${script.name}`);

            if (this.injectedScripts.has(script.name)) {
                wBlockLog(`[wBlock] Userscript ${script.name} already injected. Skipping.`);
                return;
            }
            if (this.injectingScripts.has(script.name)) {
                wBlockLog(`[wBlock] Userscript ${script.name} is already being injected. Skipping.`);
                return;
            }

            this.injectSingleScript(script);
        }

        injectSingleScript(script) {
            this.injectSingleScriptAsync(script).catch((error) => {
                wBlockError(`[wBlock] Failed to inject userscript ${script && script.name ? script.name : 'unknown'}:`, error);
            });
        }

        shouldSkipFrameForScript(script) {
            if (window === window.top) return false;
            if (!script || typeof script.name !== 'string') return false;
            if (!/\bBypass Paywalls Clean\b/i.test(script.name)) return false;

            // BPC's userscript returns immediately in iframes except for a small
            // allowlist. Avoid hydrating the large script payload in frames where
            // upstream would no-op anyway.
            const host = (location.hostname || '').toLowerCase();
            return host !== 'app.historytoday.com' && host !== 'appan.newscientist.com';
        }

        shouldPreferMainWorldInjection(script) {
            if (!script || typeof script.name !== 'string') return false;
            // Most userscripts are happier in the isolated content world on
            // Trusted Types-heavy sites such as YouTube. Use MAIN-world early
            // only for scripts known to need direct page globals when @inject-into
            // is left at auto.
            return /\bBypass Paywalls Clean\b/i.test(script.name);
        }

        async injectSingleScriptAsync(script) {
            // Check @noframes directive - skip if in iframe
            if (script.noframes && window !== window.top) {
                wBlockLog(`[wBlock] Skipping ${script.name} in iframe due to @noframes directive`);
                return;
            }

            if (this.shouldSkipFrameForScript(script)) {
                wBlockLog(`[wBlock] Skipping ${script.name} in iframe where upstream userscript no-ops`);
                return;
            }

            if (!this.shouldRunScript(script)) {
                // Add to pending scripts if it's not ready to run
                if (!this.pendingScripts.some(s => s.name === script.name)) {
                    wBlockLog(`[wBlock] Adding ${script.name} to pending scripts list.`);
                    this.pendingScripts.push(script);
                }
                return;
            }

            this.injectingScripts.add(script.name);
            try {
                const fullScript = await this.ensureScriptPayload(script);
                if (fullScript.id && !fullScript.storageBridgeId) {
                    fullScript.storageBridgeId = this.generateRequestId('gmstorage');
                    this.storageBridgeScriptIDs.set(fullScript.storageBridgeId, fullScript.id);
                }
                if (fullScript.id && !fullScript.menuBridgeId) {
                    fullScript.menuBridgeId = this.generateRequestId('gmmenu');
                }

                const injectInto = fullScript.injectInto || 'page';
                wBlockLog(`[wBlock] Injecting userscript: ${fullScript.name} (mode: ${injectInto})`);

                if (injectInto === 'content') {
                    // Execute directly in content script context (CSP-safe)
                    this.injectInContentContext(fullScript);
                } else if (injectInto === 'auto') {
                    // Preserve the old auto behavior for general userscripts:
                    // script-tag page injection first, then isolated content context.
                    // MAIN-world executeScript is reserved for known page-global scripts
                    // because it can expose userscripts to site Trusted Types policies.
                    const injectedInMainWorld = this.shouldPreferMainWorldInjection(fullScript)
                        ? await this.injectInMainWorldViaScripting(fullScript)
                        : false;
                    if (!injectedInMainWorld && !this.tryInjectInPageContext(fullScript)) {
                        wBlockLog(`[wBlock] Page injection blocked (likely CSP), falling back to content context for ${fullScript.name}`);
                        this.injectInContentContext(fullScript);
                    }
                } else {
                    // Default: page context
                    const injectedInMainWorld = await this.injectInMainWorldViaScripting(fullScript);
                    if (!injectedInMainWorld) {
                        this.injectInPageContext(fullScript);
                    }
                }

                this.injectedScripts.add(fullScript.name);
                wBlockLog(`[wBlock] Successfully injected and registered userscript: ${fullScript.name} at ${fullScript.runAt || 'document-end'}`);
            } finally {
                this.injectingScripts.delete(script.name);
            }
        }

        // Page context injection via browser.scripting MAIN world. This bypasses
        // page CSP that can block <script> tag injection while still sharing the
        // page's JavaScript globals.
        async injectInMainWorldViaScripting(script) {
            if (isSandboxedWithoutScripts()) {
                return false;
            }
            if (typeof browser === 'undefined' || !browser.runtime || !browser.runtime.sendMessage) {
                return false;
            }
            try {
                const response = await browser.runtime.sendMessage({
                    action: 'wblock:userscript:executeMainWorld',
                    source: this.wrapUserScript(script, 'page')
                });
                if (response && response.ok) {
                    wBlockLog(`[wBlock] Injected ${script.name} in MAIN world via browser.scripting`);
                    return true;
                }
                if (response && response.error) {
                    wBlockLog(`[wBlock] MAIN-world userscript injection unavailable for ${script.name}: ${response.error}`);
                }
            } catch (error) {
                wBlockLog(`[wBlock] MAIN-world userscript injection failed for ${script.name}: ${error && error.message ? error.message : error}`);
            }
            return false;
        }

        // Page context injection (default behavior - via <script> tag)
        injectInPageContext(script) {
            if (isSandboxedWithoutScripts()) {
                wBlockLog(`[wBlock] Skipping page-context injection in sandboxed frame (no allow-scripts): ${script.name}`);
                return;
            }
            const scriptElement = document.createElement('script');
            setTrustedScriptText(scriptElement, this.wrapUserScript(script, 'page'));
            scriptElement.setAttribute('data-userscript', script.name);
            scriptElement.setAttribute('type', 'text/javascript');
            const nonce = getCspNonce();
            if (nonce) {
                scriptElement.nonce = nonce;
            }
            if (script.menuBridgeId) {
                this.attachPageMenuCommandBridge(scriptElement, script);
            }
            (document.head || document.documentElement).appendChild(scriptElement);
            scriptElement.remove();
            wBlockLog(`[wBlock] Injected ${script.name} in page context via <script> tag`);
        }

        // Try page context, return false if CSP blocks
        tryInjectInPageContext(script) {
            try {
                if (isSandboxedWithoutScripts()) {
                    return false;
                }
                // Test if we can inject a script tag (CSP check).
                // NOTE: In WebExtension/Safari extension isolated worlds, `window` is not shared
                // with the page context, so use a DOM side-effect to detect execution.
                const testElement = document.createElement('script');
                const testId = `__wblock_csp_test_${Date.now()}`;
                setTrustedScriptText(testElement, `try{document.documentElement && document.documentElement.setAttribute('${testId}','1');}catch(e){}`);
                const nonce = getCspNonce();
                if (nonce) {
                    testElement.nonce = nonce;
                }
                (document.head || document.documentElement).appendChild(testElement);

                // Check if the script actually executed
                const executed = document.documentElement && document.documentElement.getAttribute(testId) === '1';
                testElement.remove();
                try { document.documentElement && document.documentElement.removeAttribute(testId); } catch (e) {}

                if (executed) {
                    this.injectInPageContext(script);
                    return true;
                }
                return false;
            } catch (e) {
                wBlockLog(`[wBlock] CSP test failed for ${script.name}: ${e.message}`);
                return false;
            }
        }

        // Content script context injection (CSP-safe, runs in extension context)
        injectInContentContext(script) {
            try {
                const wrappedCode = this.wrapUserScript(script, 'content');
                // Execute directly in the content script context using Function constructor
                const executeScript = new Function(wrappedCode);
                executeScript();
                wBlockLog(`[wBlock] Injected ${script.name} in content context (CSP-safe)`);
            } catch (error) {
                wBlockError(`[wBlock] Content context execution failed for ${script.name}:`, error);
            }
        }

        shouldRunScript(script) {
            const runAt = script.runAt || 'document-end'; 
            const readyState = document.readyState;
            let shouldRun = false;

            wBlockLog(`[wBlock] Checking shouldRunScript for ${script.name}: runAt='${runAt}', document.readyState='${readyState}'`);

            switch (runAt) {
                case 'document-start':
                    shouldRun = true; 
                    break;
                case 'document-end':
                    shouldRun = readyState === 'interactive' || readyState === 'complete';
                    break;
                case 'document-body':
                    shouldRun = !!document.body;
                    break;
                case 'document-idle':
                    shouldRun = readyState === 'complete';
                    break;
                default:
                    wBlockWarn(`[wBlock] Unknown runAt value: '${runAt}' for script ${script.name}. Defaulting to document-end behavior.`);
                    shouldRun = readyState === 'interactive' || readyState === 'complete';
                    break;
            }
            
            if (!shouldRun) {
                wBlockLog(`[wBlock] Userscript ${script.name} will NOT run at this time (runAt: '${runAt}', readyState: '${readyState}').`);
            } else {
                wBlockLog(`[wBlock] Userscript ${script.name} WILL run at this time (runAt: '${runAt}', readyState: '${readyState}').`);
            }
            return shouldRun;
        }

        wrapUserScript(script, context = 'page') {
            // Serialize resources and shared storage state for injection
            const resourcesJSON = script.resources ? JSON.stringify(script.resources) : '{}';
            const storageSnapshotJSON = script.storageSnapshot ? JSON.stringify(script.storageSnapshot) : '{}';
            const isContentContext = context === 'content';
            const exposePageGlobals = !isContentContext && script.name === 'AdGuard Popup Blocker';
            const exposeGMGlobals = isContentContext || exposePageGlobals;
            const exposeGMGlobalsPrefix = exposePageGlobals
                ? `if (location.hostname === 'popupblocker.adguard.com' && location.pathname.endsWith('/options.html')) {`
                : '';
            const exposeGMGlobalsSuffix = exposePageGlobals ? '}' : '';

            // In content context, unsafeWindow is just the content script's window (no page JS access)
            // In page context, we try to access the real page window
            const unsafeWindowCode = isContentContext
                ? `// Content context: unsafeWindow is the content script's window (no page JS access)
    const unsafeWindow = window;
    wBlockLog('[wBlock] Running in content context - unsafeWindow has no access to page JavaScript');`
                : `// Get reference to the actual page window (not the isolated extension context)
    // This is the real unsafeWindow that can access page variables
    const unsafeWindow = (function() {
        try {
            // Try to access the page's window through various methods
            if (typeof window.wrappedJSObject !== 'undefined') {
                return window.wrappedJSObject;
            }
            // In Safari, the window object we have IS the page context when injected via <script> tag
            return window;
        } catch (e) {
            wBlockWarn('[wBlock] Could not access page context, falling back to regular window');
            return window;
        }
    })();`;

            const strictModeDirective = isContentContext ? "'use strict';" : '';

            return `
// wBlock Userscript Wrapper for: ${escapeForJS(script.name)} (${context} context)
(function() {
    ${strictModeDirective}
    // Debug logging helpers - wrapper-private names avoid collisions with userscript globals.
    var __wBlockDebugLogging = ${WBLOCK_DEBUG_LOGGING};
    var wBlockLog = (...args) => {
        if (__wBlockDebugLogging) {
            console.log(...args);
        }
    };

    var wBlockWarn = (...args) => {
        if (__wBlockDebugLogging) {
            console.warn(...args);
        }
    };

    var wBlockError = (...args) => {
        console.error(...args);
    };

    wBlockLog('[wBlock UserScript] Executing: ${escapeForJS(script.name)} in ${context} context');

    // Store resources for this script
    const scriptResources = ${resourcesJSON};

    // Storage change listeners registry
    const storageListeners = new Map(); // key -> Map(listenerId, callback)
    const pendingStorageRequests = new Map(); // requestId -> { onFailure, timeoutId }
    const menuCommandCallbacks = new Map(); // commandId -> callback
    let listenerIdCounter = 0;
    const storageBridgeId = '${escapeForJS(script.storageBridgeId || '')}';
    const menuBridgeId = '${escapeForJS(script.menuBridgeId || '')}';
    const pageMenuBridgeElement = ${isContentContext ? 'null' : 'document.currentScript'};
    const contentMenuBridge = ${isContentContext ? 'window.__wBlockMenuCommandBridge' : 'null'};
    const canUseWindowPostMessageForMenu = ${isContentContext ? 'false' : 'true'};
    const scriptStorageState = Object.assign({}, ${storageSnapshotJSON});

    const parseStoredValue = (rawValue) => {
        if (rawValue === null || typeof rawValue === 'undefined') {
            return undefined;
        }
        try {
            return JSON.parse(rawValue);
        } catch (error) {
            wBlockWarn('[wBlock] Failed to parse stored GM value, returning raw string:', error);
            return rawValue;
        }
    };

    const serializeStoredValue = (value) => {
        const serialized = JSON.stringify(value);
        return typeof serialized === 'undefined' ? 'undefined' : serialized;
    };

    const notifyStorageListeners = (key, oldValue, newValue, remote) => {
        const listeners = storageListeners.get(key);
        if (!listeners || listeners.size === 0) {
            return;
        }

        listeners.forEach((callback) => {
            try {
                callback(key, oldValue, newValue, remote);
            } catch (error) {
                wBlockError('[wBlock] Storage listener error:', error);
            }
        });
    };

    const postMenuCommandResult = (requestId, success, error) => {
        if (typeof requestId !== 'string' || requestId.length === 0) return;
        const detail = {
            bridgeId: menuBridgeId,
            requestId: requestId,
            success: success !== false,
            error: typeof error === 'string' ? error : ''
        };
        if (pageMenuBridgeElement) {
            pageMenuBridgeElement.dispatchEvent(new CustomEvent('wblock-gm-menu-invoke-result', { detail }));
            return;
        }
        if (canUseWindowPostMessageForMenu) {
            window.postMessage({ type: 'wblock-gm-menu-invoke-result', ...detail }, '*');
        }
    };

    const normalizeMenuCommandOptions = (accessKey) => {
        if (typeof accessKey === 'string') {
            return { accessKey: accessKey, title: '' };
        }
        if (accessKey && typeof accessKey === 'object') {
            return {
                accessKey: typeof accessKey.accessKey === 'string' ? accessKey.accessKey : '',
                title: typeof accessKey.title === 'string' ? accessKey.title : ''
            };
        }
        return { accessKey: '', title: '' };
    };

    const publishMenuCommand = (kind, commandId, details, callback) => {
        if (!menuBridgeId || typeof commandId !== 'string' || commandId.length === 0) {
            return;
        }

        const normalizedDetails = {
            caption: typeof details.caption === 'string' ? details.caption : String(details.caption ?? ''),
            title: typeof details.title === 'string' ? details.title : '',
            accessKey: typeof details.accessKey === 'string' ? details.accessKey : '',
            scriptName: '${escapeForJS(script.name || 'Unknown Script')}'
        };

        if (contentMenuBridge && kind === 'register' && typeof contentMenuBridge.registerMenuCommand === 'function') {
            contentMenuBridge.registerMenuCommand(menuBridgeId, commandId, normalizedDetails, callback);
            return;
        }

        if (contentMenuBridge && kind === 'unregister' && typeof contentMenuBridge.unregisterMenuCommand === 'function') {
            contentMenuBridge.unregisterMenuCommand(menuBridgeId, commandId);
            return;
        }

        const messageType = kind === 'register' ? 'wblock-gm-menu-register' : 'wblock-gm-menu-unregister';
        const detail = kind === 'register'
            ? { bridgeId: menuBridgeId, commandId: commandId, ...normalizedDetails }
            : { bridgeId: menuBridgeId, commandId: commandId };

        if (pageMenuBridgeElement) {
            pageMenuBridgeElement.dispatchEvent(new CustomEvent(messageType, { detail }));
            return;
        }

        if (canUseWindowPostMessageForMenu) {
            window.postMessage({ type: messageType, ...detail }, '*');
        }
    };

    ${isContentContext ? `` : `
    const handleMenuInvoke = (detail) => {
        if (!detail || detail.bridgeId !== menuBridgeId || typeof detail.commandId !== 'string') return;

        const callback = menuCommandCallbacks.get(detail.commandId);
        if (!callback) {
            postMenuCommandResult(detail.requestId, false, 'Menu command not found');
            return;
        }

        try {
            Promise.resolve(callback())
                .then(() => postMenuCommandResult(detail.requestId, true, ''))
                .catch((error) => {
                    postMenuCommandResult(
                        detail.requestId,
                        false,
                        error && error.message ? error.message : String(error)
                    );
                });
        } catch (error) {
            postMenuCommandResult(
                detail.requestId,
                false,
                error && error.message ? error.message : String(error)
            );
        }
    };

    if (pageMenuBridgeElement) {
        pageMenuBridgeElement.addEventListener('wblock-gm-menu-invoke', (event) => {
            handleMenuInvoke(event && event.detail ? event.detail : {});
        });
    }

    window.addEventListener('message', (event) => {
        if (event.source !== window) return;
        const data = event.data;
        if (!data || data.type !== 'wblock-gm-menu-invoke') return;
        handleMenuInvoke(data);
    });
    `}

    ${isContentContext ? `` : `
    window.addEventListener('message', (event) => {
        if (event.source !== window) return;
        const data = event.data;
        if (!data || data.type !== 'wblock-gm-storage-result' || typeof data.requestId !== 'string') return;

        const pending = pendingStorageRequests.get(data.requestId);
        if (!pending) return;
        pendingStorageRequests.delete(data.requestId);
        clearTimeout(pending.timeoutId);

        if (data.success === false && typeof pending.onFailure === 'function') {
            pending.onFailure(data.error || 'Failed to persist GM storage change');
        }
    });
    `}

    const persistStorageChange = (kind, key, rawValue, onFailure) => {
        if (!key) {
            if (typeof onFailure === 'function') {
                onFailure('Missing GM storage key');
            }
            return;
        }

        ${isContentContext ? `
        const message = {
            action: kind === 'set' ? 'setUserScriptStorageValue' : 'deleteUserScriptStorageValue',
            scriptId: '${escapeForJS(script.id || '')}',
            key: key
        };
        if (kind === 'set') {
            message.rawValue = rawValue;
        }

        if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.sendMessage) {
            browser.runtime.sendMessage(message)
                .then((result) => {
                    if ((!result || result.ok === false) && typeof onFailure === 'function') {
                        onFailure((result && result.error) || 'Failed to persist GM storage change');
                    }
                })
                .catch((error) => {
                    if (typeof onFailure === 'function') {
                        onFailure(error && error.message ? error.message : String(error));
                    }
                });
            return;
        }

        if (typeof onFailure === 'function') {
            onFailure('No messaging API available for GM storage persistence');
        }
        ` : `
        if (!storageBridgeId) {
            if (typeof onFailure === 'function') {
                onFailure('Missing GM storage bridge identifier');
            }
            return;
        }

        const requestId = 'gmstorage-' + Date.now() + '-' + Math.random().toString(36).slice(2);
        if (typeof onFailure === 'function') {
            const timeoutId = setTimeout(() => {
                const pending = pendingStorageRequests.get(requestId);
                if (!pending) return;
                pendingStorageRequests.delete(requestId);
                pending.onFailure('GM storage persistence timed out');
            }, 15000);
            pendingStorageRequests.set(requestId, { onFailure, timeoutId });
        }

        const message = {
            type: kind === 'set' ? 'wblock-gm-storage-set' : 'wblock-gm-storage-delete',
            bridgeId: storageBridgeId,
            key: key,
            requestId: requestId
        };
        if (kind === 'set') {
            message.rawValue = rawValue;
        }
        window.postMessage(message, '*');
        `}
    };

    const inferResourceMimeType = (resourceName, resourceValue) => {
        const lowerName = String(resourceName || '').toLowerCase();
        if (lowerName.endsWith('.css')) return 'text/css';
        if (lowerName.endsWith('.js') || lowerName.endsWith('.mjs')) return 'text/javascript';
        if (lowerName.endsWith('.json')) return 'application/json';
        if (lowerName.endsWith('.xml')) return 'application/xml';
        if (lowerName.endsWith('.svg')) return 'image/svg+xml';
        if (lowerName.endsWith('.png')) return 'image/png';
        if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) return 'image/jpeg';
        if (lowerName.endsWith('.gif')) return 'image/gif';
        if (lowerName.endsWith('.webp')) return 'image/webp';
        if (lowerName.endsWith('.mp3')) return 'audio/mpeg';
        if (lowerName.endsWith('.ogg')) return 'audio/ogg';
        if (lowerName.endsWith('.wav')) return 'audio/wav';
        if (lowerName.endsWith('.woff2')) return 'font/woff2';
        if (lowerName.endsWith('.woff')) return 'font/woff';
        if (lowerName.endsWith('.ttf')) return 'font/ttf';

        const trimmedValue = typeof resourceValue === 'string' ? resourceValue.trim() : '';
        if (!trimmedValue) return 'text/plain';
        if (
            (trimmedValue.startsWith('{') && trimmedValue.endsWith('}'))
            || (trimmedValue.startsWith('[') && trimmedValue.endsWith(']'))
        ) {
            return 'application/json';
        }
        if (trimmedValue.startsWith('<svg')) {
            return 'image/svg+xml';
        }
        if (/(^|\\n)\s*(?:const|let|var|function|class|export|import)\b/.test(trimmedValue) || trimmedValue.includes('=>')) {
            return 'text/javascript';
        }
        if (/(^|\\n)\s*[@.#a-zA-Z0-9_-]+\s*\{/.test(trimmedValue) || /:\s*[^;]+;/.test(trimmedValue)) {
            return 'text/css';
        }
        return 'text/plain';
    };

    const isProbablyTextMimeType = (mimeType) => {
        const normalized = String(mimeType || '').toLowerCase();
        return normalized.startsWith('text/')
            || normalized.includes('json')
            || normalized.includes('javascript')
            || normalized.includes('xml')
            || normalized === 'image/svg+xml';
    };

    const decodeDataUrlText = (dataUrl) => {
        const match = String(dataUrl || '').match(/^data:([^;,]+)?(?:;charset=[^;,]+)?(;base64)?,([\s\S]*)$/i);
        if (!match) {
            return undefined;
        }

        const mimeType = match[1] || 'text/plain';
        if (!isProbablyTextMimeType(mimeType)) {
            return undefined;
        }

        try {
            if (match[2]) {
                const binary = atob(match[3] || '');
                const bytes = new Uint8Array(binary.length);
                for (let i = 0; i < binary.length; i++) {
                    bytes[i] = binary.charCodeAt(i);
                }
                return new TextDecoder('utf-8').decode(bytes);
            }
            return decodeURIComponent(match[3] || '');
        } catch (error) {
            wBlockWarn('[wBlock] Failed to decode data URL resource text:', error);
            return undefined;
        }
    };

    const resolveResourceValue = (resourceName) => {
        if (!scriptResources || !Object.prototype.hasOwnProperty.call(scriptResources, resourceName)) {
            return undefined;
        }
        return scriptResources[resourceName];
    };

    const makeResourceURL = (resourceName) => {
        const resourceValue = resolveResourceValue(resourceName);
        if (typeof resourceValue !== 'string' || resourceValue.length === 0) {
            return undefined;
        }

        if (/^(data:|blob:|https?:)/i.test(resourceValue)) {
            return resourceValue;
        }

        const mimeType = inferResourceMimeType(resourceName, resourceValue);
        return 'data:' + mimeType + ';charset=utf-8,' + encodeURIComponent(resourceValue);
    };

    ${unsafeWindowCode}

    const GM = {
        info: {
            script: {
                name: '${escapeForJS(script.name || 'Unknown Script')}',
                version: '${escapeForJS(script.version || '1.0.0')}',
                description: '${escapeForJS(script.description || '')}',
                namespace: 'wblock',
                updateURL: '${escapeForJS(script.updateURL || '')}',
                downloadURL: '${escapeForJS(script.downloadURL || '')}'
            },
            scriptUpdateURL: '${escapeForJS(script.updateURL || '')}',
            scriptDownloadURL: '${escapeForJS(script.downloadURL || '')}',
            scriptHandler: 'wBlock Injector',
            version: '0.2.0'
        },
        log: function(...args) { wBlockLog('[UserScript:${escapeForJS(script.name)}]', ...args); },

        // Greasemonkey API implementations backed by shared per-userscript storage
        getValue: function(key, defaultValue) {
            try {
                if (Object.prototype.hasOwnProperty.call(scriptStorageState, key)) {
                    return parseStoredValue(scriptStorageState[key]);
                }
                return defaultValue;
            } catch (e) {
                wBlockWarn('[wBlock] Failed to get value for key:', key, e);
                return defaultValue;
            }
        },

        setValue: function(key, value) {
            try {
                const hadValue = Object.prototype.hasOwnProperty.call(scriptStorageState, key);
                const previousRawValue = hadValue ? scriptStorageState[key] : undefined;
                const oldValue = hadValue ? parseStoredValue(previousRawValue) : undefined;
                const rawValue = serializeStoredValue(value);
                scriptStorageState[key] = rawValue;
                notifyStorageListeners(key, oldValue, value, false);
                persistStorageChange('set', key, rawValue, (error) => {
                    if (hadValue) {
                        scriptStorageState[key] = previousRawValue;
                    } else {
                        delete scriptStorageState[key];
                    }
                    wBlockWarn('[wBlock] Failed to persist value for key:', key, error);
                    notifyStorageListeners(key, value, oldValue, true);
                });
            } catch (e) {
                wBlockWarn('[wBlock] Failed to save value for key:', key, e);
            }
        },

        deleteValue: function(key) {
            try {
                if (!Object.prototype.hasOwnProperty.call(scriptStorageState, key)) {
                    return;
                }
                const previousRawValue = scriptStorageState[key];
                const oldValue = parseStoredValue(previousRawValue);
                delete scriptStorageState[key];
                notifyStorageListeners(key, oldValue, undefined, false);
                persistStorageChange('delete', key, undefined, (error) => {
                    scriptStorageState[key] = previousRawValue;
                    wBlockWarn('[wBlock] Failed to delete value for key:', key, error);
                    notifyStorageListeners(key, undefined, oldValue, true);
                });
            } catch (e) {
                wBlockWarn('[wBlock] Failed to delete value for key:', key, e);
            }
        },

        listValues: function() {
            try {
                return Object.keys(scriptStorageState);
            } catch (e) {
                wBlockWarn('[wBlock] Failed to list values:', e);
                return [];
            }
        },

        getResourceURL: function(resourceName) {
            const resolvedURL = makeResourceURL(resourceName);
            if (resolvedURL) {
                return resolvedURL;
            }
            wBlockWarn('[wBlock] Resource URL not found:', resourceName);
            return undefined;
        },

        getResourceUrl: function(resourceName) {
            return GM.getResourceURL(resourceName);
        },

        getResourceText: function(resourceName) {
            wBlockLog('[wBlock] GM_getResourceText called with:', resourceName);
            const resourceValue = resolveResourceValue(resourceName);
            if (typeof resourceValue === 'string') {
                if (/^data:/i.test(resourceValue)) {
                    return decodeDataUrlText(resourceValue);
                }
                return resourceValue;
            }
            wBlockWarn('[wBlock] Resource not found:', resourceName);
            return undefined;
        },

        addElement: function(parentOrTagName, tagNameOrAttributes, maybeAttributes) {
            try {
                let parent = null;
                let tagName = parentOrTagName;
                let attributes = tagNameOrAttributes;

                if (parentOrTagName && typeof parentOrTagName.appendChild === 'function') {
                    parent = parentOrTagName;
                    tagName = tagNameOrAttributes;
                    attributes = maybeAttributes;
                }

                wBlockLog('[wBlock] GM_addElement called:', tagName, attributes);
                const element = document.createElement(tagName);

                if (attributes) {
                    for (const [key, value] of Object.entries(attributes)) {
                        if (key === 'textContent') {
                            element.textContent = value;
                        } else if (key === 'innerHTML') {
                            element.innerHTML = value;
                        } else if (key === 'parentNode') {
                            continue;
                        } else {
                            element.setAttribute(key, value);
                        }
                    }
                }

                parent = parent || (attributes && attributes.parentNode ? attributes.parentNode : (document.head || document.documentElement));
                if (parent) {
                    parent.appendChild(element);
                }

                return element;
            } catch (e) {
                wBlockError('[wBlock] GM_addElement failed:', e);
                return null;
            }
        },

        addValueChangeListener: function(key, callback) {
            const listenerId = ++listenerIdCounter;
            wBlockLog('[wBlock] GM.addValueChangeListener:', key, listenerId);

            if (!storageListeners.has(key)) {
                storageListeners.set(key, new Map());
            }
            storageListeners.get(key).set(listenerId, callback);

            return listenerId;
        },

        removeValueChangeListener: function(listenerId) {
            wBlockLog('[wBlock] GM.removeValueChangeListener:', listenerId);

            for (const [key, listeners] of storageListeners.entries()) {
                if (listeners.has(listenerId)) {
                    listeners.delete(listenerId);
                    if (listeners.size === 0) {
                        storageListeners.delete(key);
                    }
                    return;
                }
            }
        },

        registerMenuCommand: function(caption, callback, accessKey) {
            wBlockLog('[wBlock] GM.registerMenuCommand called:', caption);
            if (typeof callback !== 'function') {
                wBlockWarn('[wBlock] Ignoring GM.registerMenuCommand with non-function callback:', caption);
                return null;
            }

            const menuCommandId = 'menu-' + (++listenerIdCounter);
            const normalizedCaption = typeof caption === 'string' ? caption : String(caption ?? '');
            const options = normalizeMenuCommandOptions(accessKey);
            menuCommandCallbacks.set(menuCommandId, callback);
            publishMenuCommand('register', menuCommandId, {
                caption: normalizedCaption,
                title: options.title,
                accessKey: options.accessKey
            }, callback);
            return menuCommandId;
        },

        unregisterMenuCommand: function(menuCommandId) {
            wBlockLog('[wBlock] GM.unregisterMenuCommand called:', menuCommandId);
            if (!menuCommandCallbacks.has(menuCommandId)) {
                return;
            }
            menuCommandCallbacks.delete(menuCommandId);
            publishMenuCommand('unregister', menuCommandId, {}, null);
        },

        addStyle: function(css) {
            try {
                const style = document.createElement('style');
                style.textContent = css;
                (document.head || document.documentElement).appendChild(style);
                return style;
            } catch (e) {
                wBlockError('[wBlock] GM.addStyle failed:', e);
                return null;
            }
        },

        setClipboard: function(data, info, callback) {
            const text = typeof data === 'string' ? data : String(data ?? '');
            const finish = () => {
                if (typeof callback === 'function') {
                    callback();
                }
            };

            const fallbackCopy = () => {
                const textarea = document.createElement('textarea');
                textarea.value = text;
                textarea.setAttribute('readonly', 'readonly');
                textarea.style.position = 'fixed';
                textarea.style.opacity = '0';
                (document.body || document.documentElement).appendChild(textarea);
                if (typeof textarea.select === 'function') {
                    textarea.select();
                }
                if (typeof textarea.setSelectionRange === 'function') {
                    textarea.setSelectionRange(0, text.length);
                }
                if (typeof document.execCommand === 'function') {
                    document.execCommand('copy');
                }
                textarea.remove();
                finish();
            };

            if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
                return navigator.clipboard.writeText(text)
                    .then(() => finish())
                    .catch((error) => {
                        wBlockWarn('[wBlock] navigator.clipboard.writeText failed, falling back:', error);
                        fallbackCopy();
                    });
            }

            fallbackCopy();
            return Promise.resolve();
        },

        openInTab: function(url, options) {
            const openInBackground = options && options.active === false;
            const newWindow = window.open(url, '_blank');
            if (!openInBackground && newWindow) {
                newWindow.focus();
            }
            return newWindow;
        },

        notification: function(options) {
            wBlockLog('[wBlock] GM_notification called with:', options);
            // Basic notification implementation
            if (typeof options === 'string') {
                wBlockLog('[wBlock] Notification:', options);
            } else if (options && options.text) {
                wBlockLog('[wBlock] Notification:', options.text);
            }
        },

        download: function(details, name) {
            const normalized = typeof details === 'string'
                ? { url: details, name: name }
                : (details || {});
            const downloadURL = normalized.url || normalized.href;
            const fileName = normalized.name || normalized.filename || name || '';

            if (!downloadURL) {
                const error = new Error('GM_download requires a URL');
                if (typeof normalized.onerror === 'function') {
                    normalized.onerror(error);
                }
                throw error;
            }

            const link = document.createElement('a');
            link.href = downloadURL;
            if (fileName) {
                link.download = fileName;
            }
            link.rel = 'noopener';
            link.style.display = 'none';
            (document.body || document.documentElement).appendChild(link);
            if (typeof link.click === 'function') {
                link.click();
            }
            link.remove();

            if (typeof normalized.onload === 'function') {
                setTimeout(() => normalized.onload(), 0);
            }

            return {
                abort: function() {
                    wBlockLog('[wBlock] GM_download abort requested for:', downloadURL);
                }
            };
        },

        xmlhttpRequest: function(details) {
            // GM_xmlhttpRequest routed through the extension's background/native
            // layer to bypass page-level CORS restrictions.
            wBlockLog('[wBlock] GM_xmlhttpRequest called with:', details);

            if (!details || !details.url) {
                wBlockError('[wBlock] GM_xmlhttpRequest: No URL provided');
                return;
            }

            const method = (details.method || 'GET').toUpperCase();
            const requestId = 'gmxhr-' + Date.now() + '-' + Math.random().toString(36).slice(2);

            const normalizeGMResponseHeaders = (headers) => {
                if (typeof headers === 'string') return headers;
                if (!headers || typeof headers !== 'object') return '';
                return Object.entries(headers)
                    .map(([key, value]) => key + ': ' + value)
                    .join('\\r\\n');
            };

            let completed = false;
            let timeoutId = null;

            const clearRequestTimeout = () => {
                if (timeoutId) {
                    clearTimeout(timeoutId);
                    timeoutId = null;
                }
            };

            const decodeBase64ToBytes = (base64) => {
                const binary = atob(base64 || '');
                const bytes = new Uint8Array(binary.length);
                for (let i = 0; i < binary.length; i++) {
                    bytes[i] = binary.charCodeAt(i);
                }
                return bytes;
            };

            const normalizeGMResponseObject = (result) => {
                const requestedType = String(result.responseType || details.responseType || 'text').toLowerCase();
                if (typeof result.responseBase64 === 'string') {
                    const bytes = decodeBase64ToBytes(result.responseBase64);
                    if (requestedType === 'arraybuffer') {
                        return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
                    }
                    if (requestedType === 'blob') {
                        return new Blob([bytes], { type: result.responseMimeType || '' });
                    }
                }
                return result.response;
            };

            const makeResponse = (result) => ({
                status: result.status,
                statusText: result.statusText,
                responseHeaders: normalizeGMResponseHeaders(result.responseHeaders),
                responseText: result.responseText,
                response: normalizeGMResponseObject(result),
                readyState: 4,
                finalUrl: result.finalUrl || details.url,
                responseURL: result.finalUrl || details.url
            });

            const onResult = (result) => {
                if (completed) return;
                completed = true;
                clearRequestTimeout();
                const response = makeResponse(result);
                if (typeof details.onreadystatechange === 'function') {
                    details.onreadystatechange(response);
                }
                if (typeof details.onload === 'function') {
                    details.onload(response);
                }
                if (typeof details.onloadend === 'function') {
                    details.onloadend(response);
                }
            };
            const onFail = (errorMsg, callbackName = 'onerror') => {
                if (completed) return;
                completed = true;
                clearRequestTimeout();
                wBlockError('[wBlock] GM_xmlhttpRequest error:', errorMsg);
                const response = { error: errorMsg, statusText: errorMsg, readyState: 4 };
                if (typeof details[callbackName] === 'function') {
                    details[callbackName](response);
                } else if (callbackName !== 'onerror' && typeof details.onerror === 'function') {
                    details.onerror(response);
                }
                if (typeof details.onloadend === 'function') {
                    details.onloadend(response);
                }
            };

            const requestPayload = {
                url: details.url,
                method: method,
                headers: details.headers || {},
                body: details.data || null,
                anonymous: !!details.anonymous,
                responseType: details.responseType || 'text',
                redirect: details.redirect || 'follow',
                timeout: details.timeout || 0
            };

            const timeoutMs = Number(details.timeout || 0);
            if (Number.isFinite(timeoutMs) && timeoutMs > 0) {
                timeoutId = setTimeout(() => {
                    onFail('GM_xmlhttpRequest timed out', 'ontimeout');
                }, timeoutMs);
            }

            ${isContentContext ? `
            // Content context: send directly via browser.runtime.sendMessage
            (async () => {
                try {
                    if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.sendMessage) {
                        const result = await browser.runtime.sendMessage({
                            action: 'gmXmlhttpRequest', ...requestPayload
                        });
                        if (result && result.error) { onFail(result.error); }
                        else { onResult(result); }
                        return;
                    }
                    onFail('No messaging API available');
                } catch (error) {
                    onFail(error.message || String(error));
                }
            })();

            return { abort: function() { wBlockLog('[wBlock] GM_xmlhttpRequest abort called'); onFail('GM_xmlhttpRequest aborted', 'onabort'); } };
            ` : `
            // Page context: proxy through the content script via postMessage
            const responseHandler = (event) => {
                if (event.source !== window) return;
                const msg = event.data;
                if (!msg || msg.type !== 'wblock-gm-xhr-response' || msg.id !== requestId) return;
                window.removeEventListener('message', responseHandler);

                if (msg.success) { onResult(msg.result); }
                else { onFail(msg.error); }
            };
            window.addEventListener('message', responseHandler);
            window.postMessage({
                type: 'wblock-gm-xhr-request',
                id: requestId,
                ...requestPayload
            }, '*');

            return {
                abort: function() {
                    window.removeEventListener('message', responseHandler);
                    wBlockLog('[wBlock] GM_xmlhttpRequest abort called');
                    onFail('GM_xmlhttpRequest aborted', 'onabort');
                }
            };
            `}
        },

        xmlHttpRequest: function(details) {
            return GM.xmlhttpRequest(details);
        },

        // Provide access to the real page window object
        unsafeWindow: unsafeWindow
    };

    const __wBlockLegacyGM = {
        getValue: GM.getValue.bind(GM),
        setValue: GM.setValue.bind(GM),
        deleteValue: GM.deleteValue.bind(GM),
        listValues: GM.listValues.bind(GM),
        getResourceURL: GM.getResourceURL.bind(GM),
        getResourceUrl: GM.getResourceUrl.bind(GM),
        getResourceText: GM.getResourceText.bind(GM),
        xmlhttpRequest: GM.xmlhttpRequest.bind(GM)
    };

    const __wBlockGMRequestPromise = (details) => {
        let requestHandle = null;
        const promise = new Promise((resolve, reject) => {
            const requestDetails = Object.assign({}, details || {});
            const originalOnload = requestDetails.onload;
            const originalOnerror = requestDetails.onerror;
            const originalOntimeout = requestDetails.ontimeout;
            const originalOnabort = requestDetails.onabort;

            requestDetails.onload = function(response) {
                try {
                    if (typeof originalOnload === 'function') originalOnload.call(this, response);
                } finally {
                    resolve(response);
                }
            };
            requestDetails.onerror = function(response) {
                try {
                    if (typeof originalOnerror === 'function') originalOnerror.call(this, response);
                } finally {
                    reject(response);
                }
            };
            requestDetails.ontimeout = function(response) {
                try {
                    if (typeof originalOntimeout === 'function') originalOntimeout.call(this, response);
                } finally {
                    reject(response);
                }
            };
            requestDetails.onabort = function(response) {
                try {
                    if (typeof originalOnabort === 'function') originalOnabort.call(this, response);
                } finally {
                    reject(response);
                }
            };

            requestHandle = __wBlockLegacyGM.xmlhttpRequest(requestDetails);
        });
        promise.abort = function() {
            if (requestHandle && typeof requestHandle.abort === 'function') {
                requestHandle.abort();
            }
        };
        return promise;
    };

    GM.getValue = function(key, defaultValue) {
        return Promise.resolve(__wBlockLegacyGM.getValue(key, defaultValue));
    };
    GM.setValue = function(key, value) {
        __wBlockLegacyGM.setValue(key, value);
        return Promise.resolve();
    };
    GM.deleteValue = function(key) {
        __wBlockLegacyGM.deleteValue(key);
        return Promise.resolve();
    };
    GM.listValues = function() {
        return Promise.resolve(__wBlockLegacyGM.listValues());
    };
    GM.getResourceURL = function(resourceName) {
        return Promise.resolve(__wBlockLegacyGM.getResourceURL(resourceName));
    };
    GM.getResourceUrl = function(resourceName) {
        return Promise.resolve(__wBlockLegacyGM.getResourceUrl(resourceName));
    };
    GM.getResourceText = function(resourceName) {
        return Promise.resolve(__wBlockLegacyGM.getResourceText(resourceName));
    };
    GM.xmlhttpRequest = __wBlockGMRequestPromise;
    GM.xmlHttpRequest = __wBlockGMRequestPromise;

    var GM_info = GM.info;
    var GM_getValue = __wBlockLegacyGM.getValue;
    var GM_setValue = __wBlockLegacyGM.setValue;
    var GM_deleteValue = __wBlockLegacyGM.deleteValue;
    var GM_listValues = __wBlockLegacyGM.listValues;
    var GM_getResourceURL = __wBlockLegacyGM.getResourceURL;
    var GM_getResourceUrl = __wBlockLegacyGM.getResourceUrl;
    var GM_getResourceText = __wBlockLegacyGM.getResourceText;
    var GM_addElement = GM.addElement;
    var GM_addValueChangeListener = GM.addValueChangeListener;
    var GM_removeValueChangeListener = GM.removeValueChangeListener;
    var GM_addStyle = GM.addStyle;
    var GM_setClipboard = GM.setClipboard;
    var GM_openInTab = GM.openInTab;
    var GM_notification = GM.notification;
    var GM_download = GM.download;
    var GM_xmlhttpRequest = __wBlockLegacyGM.xmlhttpRequest;
    var GM_xmlHttpRequest = __wBlockLegacyGM.xmlhttpRequest;
    var GM_registerMenuCommand = GM.registerMenuCommand;
    var GM_unregisterMenuCommand = GM.unregisterMenuCommand;

    ${exposeGMGlobals ? `
    ${exposeGMGlobalsPrefix}
    // Expose GM globals where the page can read them. Content-context scripts keep
    // these in the isolated world; AdGuard Popup Blocker's options page polls for
    // page-visible GM_* functions to decide whether the userscript is installed.
    window.unsafeWindow = unsafeWindow;
    window.GM_info = GM_info;
    window.GM = GM;

    // Legacy GM function aliases
    window.GM_getValue = GM_getValue;
    window.GM_setValue = GM_setValue;
    window.GM_deleteValue = GM_deleteValue;
    window.GM_listValues = GM_listValues;
    window.GM_getResourceURL = GM_getResourceURL;
    window.GM_getResourceUrl = GM_getResourceUrl;
    window.GM_getResourceText = GM_getResourceText;
    window.GM_addElement = GM_addElement;
    window.GM_addValueChangeListener = GM_addValueChangeListener;
    window.GM_removeValueChangeListener = GM_removeValueChangeListener;
    window.GM_addStyle = GM_addStyle;
    window.GM_setClipboard = GM_setClipboard;
    window.GM_openInTab = GM_openInTab;
    window.GM_notification = GM_notification;
    window.GM_download = GM_download;
    window.GM_xmlhttpRequest = GM_xmlhttpRequest;
    window.GM_xmlHttpRequest = GM_xmlHttpRequest;
    window.GM_registerMenuCommand = GM_registerMenuCommand;
    window.GM_unregisterMenuCommand = GM_unregisterMenuCommand;
    ${exposeGMGlobalsSuffix}
    ` : ``}

    var __wBlockRunUserScript = function() {
        ${script.content}
    };

    try {
        __wBlockRunUserScript();
        wBlockLog('[wBlock UserScript] Finished executing: ${escapeForJS(script.name)}');
    } catch (error) {
        wBlockError('[wBlock UserScript Execution Error] in ${escapeForJS(script.name)}:', error);
        wBlockError('[wBlock UserScript Error Stack]:', error.stack);

        // Show a console warning for userscript errors
        wBlockWarn('[wBlock] Error in userscript "${escapeForJS(script.name)}": ' + (error && error.message ? error.message : String(error)));
    }
})();
        `;
        }
    }

    if (document.documentElement) {
        wBlockLog('[wBlock] document.documentElement exists, creating UserScriptEngine instance.');
        new UserScriptEngine();
    } else {
        wBlockLog('[wBlock] document.documentElement does not exist, deferring UserScriptEngine instance creation to DOMContentLoaded.');
        document.addEventListener('DOMContentLoaded', () => {
            wBlockLog('[wBlock] DOMContentLoaded fired, creating UserScriptEngine instance.');
            new UserScriptEngine();
        });
    }
}

// Ensure that if this script is injected multiple times (e.g. in iframes),
// each frame gets its own engine, but a single frame doesn't run it multiple times.
// The window.wBlockUserscriptInjectorHasRun flag handles the single-frame case.
