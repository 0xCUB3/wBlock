/**
 * wBlock Userscript Injector
 * Injects and manages userscripts from the native app
 */

// Prevent multiple executions of this entire script in the same context
if (window.wBlockUserscriptInjectorHasRun) {
    console.log('[wBlock] Userscript injector already ran in this frame.');
} else {
    window.wBlockUserscriptInjectorHasRun = true;
    console.log('[wBlock] Initializing Userscript Injector for this frame.');

    // Userscript execution engine
    class UserScriptEngine {
        constructor() {
            this.injectedScripts = new Set();
            this.pendingScripts = []; // Scripts waiting for document to be ready
            this.messageListenerAttached = false; // Ensure listener is attached only once
            console.log('[wBlock] UserScriptEngine constructor called.');
            this.init();
        }

        init() {
            console.log('[wBlock] UserScriptEngine init.');
            this.setupDocumentEventListeners();
            // Request userscripts from native app
            this.requestUserScripts();
            
            // Listen for response from native app
            this.setupMessageListener();
        }

        setupDocumentEventListeners() {
            // Listen for document ready states to inject pending scripts
            if (document.readyState === 'loading') {
                console.log('[wBlock] Document is loading, setting up event listeners for ready states.');
                
                document.addEventListener('DOMContentLoaded', () => {
                    console.log('[wBlock] DOMContentLoaded event fired, retrying pending scripts.');
                    this.retryPendingScripts();
                });
                
                window.addEventListener('load', () => {
                    console.log('[wBlock] Window load event fired, retrying pending scripts.');
                    this.retryPendingScripts();
                });
            } else {
                console.log(`[wBlock] Document already ready (${document.readyState}), no need for event listeners.`);
            }
        }

        retryPendingScripts() {
            if (this.pendingScripts.length === 0) {
                console.log('[wBlock] No pending scripts to retry.');
                return;
            }

            console.log(`[wBlock] Retrying ${this.pendingScripts.length} pending scripts...`);
            const scriptsToRetry = [...this.pendingScripts];
            this.pendingScripts = [];
            
            for (const script of scriptsToRetry) {
                this.injectSingleScript(script);
            }
        }

        requestUserScripts() {
            const requestId = 'userscripts-' + Date.now();
            const messagePayload = {
                action: 'requestUserScripts', // Consistent action name
                requestId: requestId,
                url: window.location.href
            };
            console.log(`[wBlock] Requesting userscripts for URL: ${window.location.href} with requestId: ${requestId}`);

            if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.sendMessage) {
                console.log('[wBlock] Sending requestUserScripts via browser.runtime.sendMessage');
                browser.runtime.sendMessage(messagePayload, (response) => {
                    if (browser.runtime.lastError) {
                        console.error('[wBlock] Error sending message to native via browser.runtime.sendMessage:', browser.runtime.lastError);
                    } else {
                        console.log('[wBlock] browser.runtime.sendMessage response (if any):', response);
                    }
                }).catch(error => {
                     console.error('[wBlock] Failed to send message via browser.runtime.sendMessage:', error);
                });
            } else if (typeof safari !== 'undefined' && safari.extension && safari.extension.dispatchMessage) {
                console.log('[wBlock] Sending requestUserScripts via safari.extension.dispatchMessage');
                safari.extension.dispatchMessage('requestUserScripts', { 
                    requestId: requestId,
                    url: window.location.href
                });
            } else {
                console.error('[wBlock] No suitable messaging API found for sending requestUserScripts.');
            }
        }

        setupMessageListener() {
            if (this.messageListenerAttached) {
                console.log('[wBlock] Message listener already attached.');
                return;
            }
            console.log('[wBlock] Setting up message listener.');

            if (typeof browser !== 'undefined' && browser.runtime && browser.runtime.onMessage) {
                console.log('[wBlock] Using browser.runtime.onMessage for listening.');
                browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
                    console.log('[wBlock] Received message via browser.runtime.onMessage:', JSON.parse(JSON.stringify(message || {})));
                    let scriptsToInject = null;
                    if (message && message.userScripts) {
                        scriptsToInject = message.userScripts;
                    } else if (message && message.payload && message.payload.userScripts) {
                        scriptsToInject = message.payload.userScripts;
                    }

                    if (scriptsToInject) {
                        console.log('[wBlock] Extracted userscripts from message (browser.runtime.onMessage):', scriptsToInject);
                        this.injectUserScripts(scriptsToInject);
                    } else {
                        console.log('[wBlock] No userscripts found in received message (browser.runtime.onMessage).');
                    }
                });
                this.messageListenerAttached = true;
                console.log('[wBlock] browser.runtime.onMessage listener attached.');
            } else if (typeof safari !== 'undefined' && safari.extension && typeof safari.self !== 'undefined' && safari.self.addEventListener) {
                console.log('[wBlock] Using safari.self.addEventListener for listening.');
                safari.self.addEventListener('message', (event) => {
                    console.log('[wBlock] Received message via safari.self.addEventListener:', event.name, JSON.parse(JSON.stringify(event.message || {})));
                    let scriptsToInject = null;
                    if (event.name === 'requestUserScripts' && event.message && event.message.userScripts) {
                        scriptsToInject = event.message.userScripts;
                    } else if (event.name === 'requestRules' && event.message && event.message.payload && event.message.payload.userScripts) {
                        scriptsToInject = event.message.payload.userScripts;
                    }

                    if (scriptsToInject) {
                        console.log('[wBlock] Extracted userscripts from message (safari.self.addEventListener):', scriptsToInject);
                        this.injectUserScripts(scriptsToInject);
                    } else {
                        console.log('[wBlock] No userscripts found in received message (safari.self.addEventListener).');
                    }
                }, false);
                this.messageListenerAttached = true;
                console.log('[wBlock] safari.self.addEventListener listener attached.');
            } else {
                 console.error('[wBlock] No suitable event listener API found.');
            }
        }

        injectUserScripts(userScripts) {
            console.log('[wBlock] injectUserScripts called with:', userScripts);
            if (!Array.isArray(userScripts)) {
                console.warn('[wBlock] injectUserScripts called with non-array:', userScripts);
                return;
            }
            if (userScripts.length === 0) {
                console.log('[wBlock] No userscripts to inject.');
                return;
            }
            userScripts.forEach(script => {
                this.injectUserScript(script);
            });
        }

        injectUserScript(script) {
            if (!script || !script.name) {
                console.warn('[wBlock] Attempted to inject invalid script object:', script);
                return;
            }
            console.log(`[wBlock] Processing userscript: ${script.name}`);

            if (this.injectedScripts.has(script.name)) {
                console.log(`[wBlock] Userscript ${script.name} already injected. Skipping.`);
                return;
            }

            this.injectSingleScript(script);
        }

        injectSingleScript(script) {
            try {
                if (!this.shouldRunScript(script)) {
                    // Add to pending scripts if it's not ready to run
                    if (!this.pendingScripts.some(s => s.name === script.name)) {
                        console.log(`[wBlock] Adding ${script.name} to pending scripts list.`);
                        this.pendingScripts.push(script);
                    }
                    return;
                }

                console.log(`[wBlock] Injecting userscript: ${script.name}`);
                const scriptElement = document.createElement('script');
                scriptElement.textContent = this.wrapUserScript(script);
                scriptElement.setAttribute('data-userscript', script.name);
                scriptElement.setAttribute('type', 'text/javascript'); 
                
                (document.head || document.documentElement).appendChild(scriptElement);
                console.log(`[wBlock] Appended <script> tag for ${script.name} to the DOM.`);
                
                this.injectedScripts.add(script.name);
                console.log(`[wBlock] Successfully injected and registered userscript: ${script.name} at ${script.runAt || 'document-end'}`);
                
            } catch (error) {
                console.error(`[wBlock] Failed to inject userscript ${script.name}:`, error);
            }
        }

        shouldRunScript(script) {
            const runAt = script.runAt || 'document-end'; 
            const readyState = document.readyState;
            let shouldRun = false;

            console.log(`[wBlock] Checking shouldRunScript for ${script.name}: runAt='${runAt}', document.readyState='${readyState}'`);

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
                    console.warn(`[wBlock] Unknown runAt value: '${runAt}' for script ${script.name}. Defaulting to document-end behavior.`);
                    shouldRun = readyState === 'interactive' || readyState === 'complete';
                    break;
            }
            
            if (!shouldRun) {
                console.log(`[wBlock] Userscript ${script.name} will NOT run at this time (runAt: '${runAt}', readyState: '${readyState}').`);
            } else {
                console.log(`[wBlock] Userscript ${script.name} WILL run at this time (runAt: '${runAt}', readyState: '${readyState}').`);
            }
            return shouldRun;
        }

        wrapUserScript(script) {
            // console.log(`[wBlock] Wrapping script content for ${script.name}`);
            return `
// wBlock Userscript Wrapper for: ${script.name}
(function() {
    'use strict';
    console.log('[wBlock UserScript] Executing: ${script.name}');
    
    const GM = {
        info: {
            script: {
                name: '${script.name || 'Unknown Script'}',
                version: '${script.version || '1.0.0'}'
            },
            scriptHandler: 'wBlock Injector',
            version: '0.1.1' // Incremented version for this logging update
        },
        log: function(...args) { console.log('[UserScript:${script.name}]', ...args); }
        // TODO: Implement other GM functions by messaging the extension
        // GM_setValue: async function(key, value) { console.log('GM_setValue called'); /* browser.runtime.sendMessage(...) */ },
        // GM_getValue: async function(key, defaultValue) { console.log('GM_getValue called'); /* browser.runtime.sendMessage(...) */ },
    };
    
    window.GM_info = GM.info;
    window.GM = GM; // Expose the GM object

    try {
        ${script.content}
        console.log('[wBlock UserScript] Finished executing: ${script.name}');
    } catch (error) {
        console.error('[wBlock UserScript Execution Error] in ${script.name}:', error);
    }
})();
        `;
        }
    }

    if (document.documentElement) {
        console.log('[wBlock] document.documentElement exists, creating UserScriptEngine instance.');
        new UserScriptEngine();
    } else {
        console.log('[wBlock] document.documentElement does not exist, deferring UserScriptEngine instance creation to DOMContentLoaded.');
        document.addEventListener('DOMContentLoaded', () => {
            console.log('[wBlock] DOMContentLoaded fired, creating UserScriptEngine instance.');
            new UserScriptEngine();
        });
    }
}

// Ensure that if this script is injected multiple times (e.g. in iframes),
// each frame gets its own engine, but a single frame doesn't run it multiple times.
// The window.wBlockUserscriptInjectorHasRun flag handles the single-frame case.
