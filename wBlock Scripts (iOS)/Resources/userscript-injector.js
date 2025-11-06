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
            this.pendingScripts = []; // Scripts waiting for document to be ready
            this.messageListenerAttached = false; // Ensure listener is attached only once
            wBlockLog('[wBlock] UserScriptEngine constructor called.');
            this.init();
        }

        init() {
            wBlockLog('[wBlock] UserScriptEngine init.');
            this.setupDocumentEventListeners();
            // Request userscripts from native app
            this.requestUserScripts();
            
            // Listen for response from native app
            this.setupMessageListener();
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
            const requestId = 'userscripts-' + Date.now();
            const messagePayload = {
                action: 'getUserScripts', // Must match background.js listener
                requestId: requestId,
                url: window.location.href
            };
            wBlockLog(`[wBlock] Requesting userscripts for URL: ${window.location.href} with requestId: ${requestId}`);

            if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.sendMessage) {
                wBlockLog('[wBlock] Sending requestUserScripts via browser.runtime.sendMessage');
                browser.runtime.sendMessage(messagePayload, (response) => {
                    if (browser.runtime.lastError) {
                        wBlockError('[wBlock] Error sending message to native via browser.runtime.sendMessage:', browser.runtime.lastError);
                    } else {
                        wBlockLog('[wBlock] browser.runtime.sendMessage response:', response);
                        // Handle the response directly from the callback
                        if (response && response.userScripts) {
                            wBlockLog('[wBlock] Extracted userscripts from callback response:', response.userScripts);
                            this.injectUserScripts(response.userScripts);
                        } else {
                            wBlockLog('[wBlock] No userscripts found in callback response.');
                        }
                    }
                }).catch(error => {
                     wBlockError('[wBlock] Failed to send message via browser.runtime.sendMessage:', error);
                });
            } else if (typeof safari !== 'undefined' && safari.extension && safari.extension.dispatchMessage) {
                wBlockLog('[wBlock] Sending requestUserScripts via safari.extension.dispatchMessage');
                safari.extension.dispatchMessage('requestUserScripts', { 
                    requestId: requestId,
                    url: window.location.href
                });
            } else {
                wBlockError('[wBlock] No suitable messaging API found for sending requestUserScripts.');
            }
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
                    let scriptsToInject = null;
                    if (event.name === 'requestUserScripts' && event.message && event.message.userScripts) {
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
            userScripts.forEach(script => {
                this.injectUserScript(script);
            });
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

            this.injectSingleScript(script);
        }

        injectSingleScript(script) {
            try {
                if (!this.shouldRunScript(script)) {
                    // Add to pending scripts if it's not ready to run
                    if (!this.pendingScripts.some(s => s.name === script.name)) {
                        wBlockLog(`[wBlock] Adding ${script.name} to pending scripts list.`);
                        this.pendingScripts.push(script);
                    }
                    return;
                }

                wBlockLog(`[wBlock] Injecting userscript: ${script.name}`);
                const scriptElement = document.createElement('script');
                scriptElement.textContent = this.wrapUserScript(script);
                scriptElement.setAttribute('data-userscript', script.name);
                scriptElement.setAttribute('type', 'text/javascript'); 
                
                (document.head || document.documentElement).appendChild(scriptElement);
                wBlockLog(`[wBlock] Appended <script> tag for ${script.name} to the DOM.`);
                
                this.injectedScripts.add(script.name);
                wBlockLog(`[wBlock] Successfully injected and registered userscript: ${script.name} at ${script.runAt || 'document-end'}`);
                
            } catch (error) {
                wBlockError(`[wBlock] Failed to inject userscript ${script.name}:`, error);
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

        wrapUserScript(script) {
            // wBlockLog(`[wBlock] Wrapping script content for ${script.name}`);
            return `
// wBlock Userscript Wrapper for: ${script.name}
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

    wBlockLog('[wBlock UserScript] Executing: ${script.name}');

    // Get reference to the actual page window (not the isolated extension context)
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
    })();

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
    window.GM_addStyle = GM.addStyle;
    window.GM_openInTab = GM.openInTab;
    window.GM_notification = GM.notification;
    window.GM_xmlhttpRequest = GM.xmlhttpRequest;

    try {
        ${script.content}
        wBlockLog('[wBlock UserScript] Finished executing: ${script.name}');
    } catch (error) {
        wBlockError('[wBlock UserScript Execution Error] in ${script.name}:', error);
        wBlockError('[wBlock UserScript Error Stack]:', error.stack);

        // Show a console warning for userscript errors
        wBlockWarn(\`[wBlock] Error in userscript "\${script.name}": \${error.message}\`);
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
