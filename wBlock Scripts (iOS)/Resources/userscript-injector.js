/**
 * wBlock Userscript Injector
 * Injects and manages userscripts from the native app
 */

// Debug logging flag - set to false to disable verbose console output
const WBLOCK_DEBUG_LOGGING = false;

// Debug logging helper
const wBlockLog = (...args) => {
    if (WBLOCK_DEBUG_LOGGING) {
        console.log(...args);
    }
};

const wBlockWarn = (...args) => {
    if (WBLOCK_DEBUG_LOGGING) {
        console.warn(...args);
    }
};

const wBlockError = (...args) => {
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
let wBlockCachedCspNonce = null;
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

// Detect sandboxed iframes that do not allow scripts (injection will always fail)
function isSandboxedWithoutScripts() {
    try {
        const frameEl = window.frameElement;
        if (!frameEl) return false;
        if (!frameEl.getAttribute || !frameEl.hasAttribute || !frameEl.hasAttribute('sandbox')) return false;
        const sandbox = frameEl.sandbox;
        if (sandbox && typeof sandbox.contains === 'function') {
            return !sandbox.contains('allow-scripts');
        }
        const attr = String(frameEl.getAttribute('sandbox') || '').trim();
        if (attr === '') return true;
        return !attr.split(/\s+/).includes('allow-scripts');
    } catch (e) {
        return false;
    }
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

                const { id, url, method, headers, body, anonymous, responseType } = data;

                this.proxyXhr({ url, method, headers, body, anonymous, responseType })
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
                    responseType: details.responseType || 'text'
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
                        responseType: details.responseType || 'text'
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
            // Safari App Extensions can have smaller message size limits than WebExtensions.
            const isSafariAppExtension = typeof safari !== 'undefined' && safari.extension && safari.extension.dispatchMessage;
            return isSafariAppExtension ? (32 * 1024) : (256 * 1024); // bytes (before base64)
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
            const chunks = new Array(totalChunks);
            chunks[0] = first.chunk;

            for (let i = 1; i < totalChunks; i++) {
                const resp = await this.sendNativeRequest(action, { ...params, chunkIndex: i, chunkSize });
                if (resp && resp.error) throw new Error(resp.error);
                chunks[i] = resp.chunk;
            }

            const byteArrays = chunks.map(c => this.base64ToBytes(c || ''));
            return decoder.decode(this.concatBytes(byteArrays));
        }

        async ensureScriptPayload(script) {
            if (script && typeof script.content === 'string' && script.content.length > 0) {
                // Legacy payload (already includes content/resources)
                if (script.resources == null && script.resourceContents != null) {
                    script.resources = script.resourceContents;
                }
                return script;
            }

            if (!script || !script.id) {
                throw new Error('Userscript descriptor missing id');
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

            return { ...script, content, resources };
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

        requestUserScripts() {
            const url = window.location.href;
            wBlockLog(`[wBlock] Requesting userscripts for URL: ${url}`);

            this.sendNativeRequest('getUserScripts', { url })
                .then((response) => {
                    const scripts = response && response.userScripts ? response.userScripts : [];
                    if (scripts.length === 0) {
                        wBlockLog('[wBlock] No userscripts found in getUserScripts response.');
                        return;
                    }
                    this.injectUserScripts(scripts);
                })
                .catch((error) => {
                    wBlockError('[wBlock] Failed to request userscripts:', error);
                });
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

        async injectSingleScriptAsync(script) {
            // Check @noframes directive - skip if in iframe
            if (script.noframes && window !== window.top) {
                wBlockLog(`[wBlock] Skipping ${script.name} in iframe due to @noframes directive`);
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

                const injectInto = fullScript.injectInto || 'page';
                wBlockLog(`[wBlock] Injecting userscript: ${fullScript.name} (mode: ${injectInto})`);

                if (injectInto === 'content') {
                    // Execute directly in content script context (CSP-safe)
                    this.injectInContentContext(fullScript);
                } else if (injectInto === 'auto') {
                    // Try page context first, fall back to content if CSP blocks
                    if (!this.tryInjectInPageContext(fullScript)) {
                        wBlockLog(`[wBlock] Page injection blocked (likely CSP), falling back to content context for ${fullScript.name}`);
                        this.injectInContentContext(fullScript);
                    }
                } else {
                    // Default: page context
                    this.injectInPageContext(fullScript);
                }

                this.injectedScripts.add(fullScript.name);
                wBlockLog(`[wBlock] Successfully injected and registered userscript: ${fullScript.name} at ${fullScript.runAt || 'document-end'}`);
            } finally {
                this.injectingScripts.delete(script.name);
            }
        }

        // Page context injection (default behavior - via <script> tag)
        injectInPageContext(script) {
            if (isSandboxedWithoutScripts()) {
                wBlockLog(`[wBlock] Skipping page-context injection in sandboxed frame (no allow-scripts): ${script.name}`);
                return;
            }
            const scriptElement = document.createElement('script');
            scriptElement.textContent = this.wrapUserScript(script, 'page');
            scriptElement.setAttribute('data-userscript', script.name);
            scriptElement.setAttribute('type', 'text/javascript');
            const nonce = getCspNonce();
            if (nonce) {
                scriptElement.nonce = nonce;
            }
            (document.head || document.documentElement).appendChild(scriptElement);
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
                testElement.textContent = `try{document.documentElement && document.documentElement.setAttribute('${testId}','1');}catch(e){}`;
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
            // Serialize resources as a JSON string for injection
            const resourcesJSON = script.resources ? JSON.stringify(script.resources) : '{}';
            const isContentContext = context === 'content';

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

            return `
// wBlock Userscript Wrapper for: ${escapeForJS(script.name)} (${context} context)
(function() {
    'use strict';

    // Debug logging helpers - defined in wrapper scope to be available in injected context
    const WBLOCK_DEBUG_LOGGING = ${WBLOCK_DEBUG_LOGGING};

    const wBlockLog = (...args) => {
        if (WBLOCK_DEBUG_LOGGING) {
            console.log(...args);
        }
    };

    const wBlockWarn = (...args) => {
        if (WBLOCK_DEBUG_LOGGING) {
            console.warn(...args);
        }
    };

    const wBlockError = (...args) => {
        console.error(...args);
    };

    wBlockLog('[wBlock UserScript] Executing: ${escapeForJS(script.name)} in ${context} context');

    // Store resources for this script
    const scriptResources = ${resourcesJSON};

    // Storage change listeners registry
    const storageListeners = new Map(); // key -> Map(listenerId, callback)
    let listenerIdCounter = 0;

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

    // Listen for storage events from other tabs/windows
    window.addEventListener('storage', (e) => {
        if (e.key && e.key.startsWith('wblock_gm_')) {
            const actualKey = e.key.substring('wblock_gm_'.length);
            notifyStorageListeners(actualKey, parseStoredValue(e.oldValue), parseStoredValue(e.newValue), true);
        }
    });

    ${unsafeWindowCode}

    const GM = {
        info: {
            script: {
                name: '${escapeForJS(script.name || 'Unknown Script')}',
                version: '${escapeForJS(script.version || '1.0.0')}',
                description: '${escapeForJS(script.description || '')}',
                namespace: 'wblock'
            },
            scriptHandler: 'wBlock Injector',
            version: '0.2.0'
        },
        log: function(...args) { wBlockLog('[UserScript:${escapeForJS(script.name)}]', ...args); },

        // Greasemonkey API implementations using localStorage
        getValue: function(key, defaultValue) {
            try {
                const stored = localStorage.getItem('wblock_gm_' + key);
                return stored !== null ? parseStoredValue(stored) : defaultValue;
            } catch (e) {
                wBlockWarn('[wBlock] Failed to get value for key:', key, e);
                return defaultValue;
            }
        },

        setValue: function(key, value) {
            try {
                const storageKey = 'wblock_gm_' + key;
                const oldValue = parseStoredValue(localStorage.getItem(storageKey));
                localStorage.setItem(storageKey, JSON.stringify(value));
                notifyStorageListeners(key, oldValue, value, false);
            } catch (e) {
                wBlockWarn('[wBlock] Failed to save value for key:', key, e);
            }
        },

        deleteValue: function(key) {
            try {
                const storageKey = 'wblock_gm_' + key;
                const oldValue = parseStoredValue(localStorage.getItem(storageKey));
                localStorage.removeItem(storageKey);
                notifyStorageListeners(key, oldValue, undefined, false);
            } catch (e) {
                wBlockWarn('[wBlock] Failed to delete value for key:', key, e);
            }
        },

        listValues: function() {
            try {
                const keys = [];
                const prefix = 'wblock_gm_';
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    if (key && key.startsWith(prefix)) {
                        keys.push(key.substring(prefix.length));
                    }
                }
                return keys;
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

        addElement: function(tagName, attributes) {
            try {
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

                const parent = attributes && attributes.parentNode ? attributes.parentNode : (document.head || document.documentElement);
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
            // Menu commands are not supported in Safari extensions
            // Return a mock ID for compatibility
            return 'menu-' + (++listenerIdCounter);
        },

        unregisterMenuCommand: function(menuCommandId) {
            wBlockLog('[wBlock] GM.unregisterMenuCommand called:', menuCommandId);
            // No-op for compatibility
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

            const onResult = (result) => {
                if (details.onload) {
                    details.onload({
                        status: result.status,
                        statusText: result.statusText,
                        responseHeaders: result.responseHeaders,
                        responseText: result.responseText,
                        response: result.response,
                        readyState: 4,
                        finalUrl: result.finalUrl || details.url
                    });
                }
            };
            const onFail = (errorMsg) => {
                wBlockError('[wBlock] GM_xmlhttpRequest error:', errorMsg);
                if (details.onerror) {
                    details.onerror({ error: errorMsg, statusText: errorMsg });
                }
            };

            const requestPayload = {
                url: details.url,
                method: method,
                headers: details.headers || {},
                body: details.data || null,
                anonymous: !!details.anonymous,
                responseType: details.responseType || 'text'
            };

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

            return { abort: function() { wBlockLog('[wBlock] GM_xmlhttpRequest abort called'); } };
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

    const GM_info = GM.info;
    const GM_getValue = GM.getValue;
    const GM_setValue = GM.setValue;
    const GM_deleteValue = GM.deleteValue;
    const GM_listValues = GM.listValues;
    const GM_getResourceURL = GM.getResourceURL;
    const GM_getResourceUrl = GM.getResourceUrl;
    const GM_getResourceText = GM.getResourceText;
    const GM_addElement = GM.addElement;
    const GM_addValueChangeListener = GM.addValueChangeListener;
    const GM_removeValueChangeListener = GM.removeValueChangeListener;
    const GM_addStyle = GM.addStyle;
    const GM_setClipboard = GM.setClipboard;
    const GM_openInTab = GM.openInTab;
    const GM_notification = GM.notification;
    const GM_download = GM.download;
    const GM_xmlhttpRequest = GM.xmlhttpRequest;
    const GM_registerMenuCommand = GM.registerMenuCommand;
    const GM_unregisterMenuCommand = GM.unregisterMenuCommand;

    // Make sure unsafeWindow is defined at the global scope first
    window.unsafeWindow = unsafeWindow;

    window.GM_info = GM_info;
    window.GM = GM; // Expose the GM object

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
    window.GM_registerMenuCommand = GM_registerMenuCommand;
    window.GM_unregisterMenuCommand = GM_unregisterMenuCommand;

    try {
        ${script.content}
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
