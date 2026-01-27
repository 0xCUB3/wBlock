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

            // Request userscripts from native app
            this.requestUserScripts();
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
            const scriptElement = document.createElement('script');
            scriptElement.textContent = this.wrapUserScript(script, 'page');
            scriptElement.setAttribute('data-userscript', script.name);
            scriptElement.setAttribute('type', 'text/javascript');
            (document.head || document.documentElement).appendChild(scriptElement);
            wBlockLog(`[wBlock] Injected ${script.name} in page context via <script> tag`);
        }

        // Try page context, return false if CSP blocks
        tryInjectInPageContext(script) {
            try {
                // Test if we can inject a script tag (CSP check).
                // NOTE: In WebExtension/Safari extension isolated worlds, `window` is not shared
                // with the page context, so use a DOM side-effect to detect execution.
                const testElement = document.createElement('script');
                const testId = `__wblock_csp_test_${Date.now()}`;
                testElement.textContent = `try{document.documentElement && document.documentElement.setAttribute('${testId}','1');}catch(e){}`;
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
// wBlock Userscript Wrapper for: ${script.name} (${context} context)
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

    wBlockLog('[wBlock UserScript] Executing: ${script.name} in ${context} context');

    // Store resources for this script
    const scriptResources = ${resourcesJSON};

    // Storage change listeners registry
    const storageListeners = new Map(); // key -> Set of callbacks
    let listenerIdCounter = 0;

    // Listen for storage events from other tabs/windows
    window.addEventListener('storage', (e) => {
        if (e.key && e.key.startsWith('wblock_gm_')) {
            const actualKey = e.key.substring('wblock_gm_'.length);
            if (storageListeners.has(actualKey)) {
                const callbacks = storageListeners.get(actualKey);
                const oldValue = e.oldValue ? JSON.parse(e.oldValue) : undefined;
                const newValue = e.newValue ? JSON.parse(e.newValue) : undefined;
                callbacks.forEach(cb => {
                    try {
                        cb(actualKey, oldValue, newValue, false);
                    } catch (err) {
                        wBlockError('[wBlock] Storage listener error:', err);
                    }
                });
            }
        }
    });

    ${unsafeWindowCode}

    const GM = {
        info: {
            script: {
                name: '${script.name || 'Unknown Script'}',
                version: '${script.version || '1.0.0'}',
                description: '${script.description || ''}',
                namespace: 'wblock'
            },
            scriptHandler: 'wBlock Injector',
            version: '0.2.0'
        },
        log: function(...args) { wBlockLog('[UserScript:${script.name}]', ...args); },

        // Greasemonkey API implementations using localStorage
        getValue: function(key, defaultValue) {
            try {
                const stored = localStorage.getItem('wblock_gm_' + key);
                return stored !== null ? JSON.parse(stored) : defaultValue;
            } catch (e) {
                wBlockWarn('[wBlock] Failed to get value for key:', key, e);
                return defaultValue;
            }
        },

        setValue: function(key, value) {
            try {
                localStorage.setItem('wblock_gm_' + key, JSON.stringify(value));
            } catch (e) {
                wBlockWarn('[wBlock] Failed to save value for key:', key, e);
            }
        },

        deleteValue: function(key) {
            try {
                localStorage.removeItem('wblock_gm_' + key);
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
            // For basic compatibility, return the resource name as-is
            // In a full implementation, this would resolve @resource directives
            wBlockWarn('[wBlock] GM_getResourceURL called with:', resourceName);
            return resourceName;
        },

        getResourceText: function(resourceName) {
            wBlockLog('[wBlock] GM_getResourceText called with:', resourceName);
            if (scriptResources && scriptResources[resourceName]) {
                return scriptResources[resourceName];
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

        xmlhttpRequest: function(details) {
            // GM_xmlhttpRequest implementation using fetch API
            wBlockLog('[wBlock] GM_xmlhttpRequest called with:', details);

            if (!details || !details.url) {
                wBlockError('[wBlock] GM_xmlhttpRequest: No URL provided');
                return;
            }

            const method = (details.method || 'GET').toUpperCase();
            const headers = details.headers || {};
            const data = details.data;

            const fetchOptions = {
                method: method,
                headers: headers,
                credentials: details.anonymous ? 'omit' : 'include'
            };

            if (data && (method === 'POST' || method === 'PUT')) {
                fetchOptions.body = data;
            }

            fetch(details.url, fetchOptions)
                .then(response => {
                    const responseHeaders = {};
                    response.headers.forEach((value, key) => {
                        responseHeaders[key] = value;
                    });

                    return response.text().then(responseText => ({
                        status: response.status,
                        statusText: response.statusText,
                        responseHeaders: responseHeaders,
                        responseText: responseText,
                        response: responseText
                    }));
                })
                .then(result => {
                    if (details.onload) {
                        details.onload({
                            status: result.status,
                            statusText: result.statusText,
                            responseHeaders: result.responseHeaders,
                            responseText: result.responseText,
                            response: result.response,
                            readyState: 4,
                            finalUrl: details.url
                        });
                    }
                })
                .catch(error => {
                    wBlockError('[wBlock] GM_xmlhttpRequest error:', error);
                    if (details.onerror) {
                        details.onerror({
                            error: error.message,
                            statusText: error.message
                        });
                    }
                });

            // Return an abort controller-like object
            return {
                abort: function() {
                    wBlockLog('[wBlock] GM_xmlhttpRequest abort called');
                }
            };
        },

        // Provide access to the real page window object
        unsafeWindow: unsafeWindow
    };

    // Make sure unsafeWindow is defined at the global scope first
    window.unsafeWindow = unsafeWindow;

    window.GM_info = GM.info;
    window.GM = GM; // Expose the GM object

    // Legacy GM function aliases
    window.GM_getValue = GM.getValue;
    window.GM_setValue = GM.setValue;
    window.GM_deleteValue = GM.deleteValue;
    window.GM_listValues = GM.listValues;
    window.GM_getResourceURL = GM.getResourceURL;
    window.GM_getResourceText = GM.getResourceText;
    window.GM_addElement = GM.addElement;
    window.GM_addStyle = GM.addStyle;
    window.GM_openInTab = GM.openInTab;
    window.GM_notification = GM.notification;
    window.GM_xmlhttpRequest = GM.xmlhttpRequest;
    window.GM_registerMenuCommand = GM.registerMenuCommand;
    window.GM_unregisterMenuCommand = GM.unregisterMenuCommand;

    try {
        ${script.content}
        wBlockLog('[wBlock UserScript] Finished executing: ${script.name}');
    } catch (error) {
        wBlockError('[wBlock UserScript Execution Error] in ${script.name}:', error);
        wBlockError('[wBlock UserScript Error Stack]:', error.stack);

        // Show a console warning for userscript errors
        wBlockWarn('[wBlock] Error in userscript "${script.name}": ' + (error && error.message ? error.message : String(error)));
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
