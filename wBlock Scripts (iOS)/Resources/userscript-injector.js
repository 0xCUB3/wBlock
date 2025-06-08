/**
 * wBlock Userscript Injector for iOS Safari Web Extension
 * Injects and manages userscripts from the native app
 * Based on the robust macOS implementation
 */

console.log('[wBlock Userscript Injector] Script loaded, readyState:', document.readyState);

// Main userscript injection engine
class UserScriptInjector {
    constructor() {
        this.injectedScripts = new Set();
        this.pendingScripts = [];
        this.hasRequestedScripts = false;
        
        console.log('[wBlock Userscript Injector] Initializing...');
        this.init();
    }

    init() {
        // Handle different document ready states
        if (document.readyState === 'loading') {
            // Document still loading, wait for DOMContentLoaded
            document.addEventListener('DOMContentLoaded', () => {
                console.log('[wBlock Userscript Injector] DOMContentLoaded event fired');
                this.requestAndInjectScripts();
            });
        } else {
            // Document already loaded or interactive
            console.log('[wBlock Userscript Injector] Document already ready, requesting scripts immediately');
            this.requestAndInjectScripts();
        }

        // Also listen for window load for document-idle scripts
        window.addEventListener('load', () => {
            console.log('[wBlock Userscript Injector] Window load event fired');
            this.injectPendingScripts('document-idle');
        });
    }

    async requestAndInjectScripts() {
        if (this.hasRequestedScripts) {
            console.log('[wBlock Userscript Injector] Scripts already requested, skipping');
            return;
        }
        
        this.hasRequestedScripts = true;
        console.log('[wBlock Userscript Injector] Requesting userscripts from native app...');
        
        try {
            // Send message to background script which will communicate with native app
            const response = await browser.runtime.sendMessage({
                action: 'getUserScripts',
                url: window.location.href
            });
            
            console.log('[wBlock Userscript Injector] Received response:', response);
            
            if (response && response.userScripts && Array.isArray(response.userScripts)) {
                console.log(`[wBlock Userscript Injector] Got ${response.userScripts.length} userscripts`);
                this.processUserScripts(response.userScripts);
            } else {
                console.log('[wBlock Userscript Injector] No userscripts received');
            }
        } catch (error) {
            console.error('[wBlock Userscript Injector] Failed to get userscripts:', error);
        }
    }

    processUserScripts(userScripts) {
        userScripts.forEach(script => {
            console.log(`[wBlock Userscript Injector] Processing script: ${script.name}, runAt: ${script.runAt || 'document-end'}`);
            
            const runAt = script.runAt || 'document-end';
            
            if (this.shouldInjectNow(runAt)) {
                this.injectUserScript(script);
            } else {
                console.log(`[wBlock Userscript Injector] Queueing script ${script.name} for later injection`);
                this.pendingScripts.push(script);
            }
        });
    }

    shouldInjectNow(runAt) {
        const readyState = document.readyState;
        
        switch (runAt) {
            case 'document-start':
                return true; // Always inject immediately for document-start
            case 'document-end':
                return readyState === 'interactive' || readyState === 'complete';
            case 'document-idle':
                return readyState === 'complete';
            default:
                return readyState === 'interactive' || readyState === 'complete';
        }
    }

    injectPendingScripts(targetRunAt) {
        console.log(`[wBlock Userscript Injector] Checking pending scripts for runAt: ${targetRunAt}`);
        
        this.pendingScripts = this.pendingScripts.filter(script => {
            const runAt = script.runAt || 'document-end';
            
            if (runAt === targetRunAt || (targetRunAt === 'document-end' && this.shouldInjectNow(runAt))) {
                console.log(`[wBlock Userscript Injector] Injecting pending script: ${script.name}`);
                this.injectUserScript(script);
                return false; // Remove from pending
            }
            return true; // Keep in pending
        });
    }

    injectUserScript(script) {
        // Avoid double injection
        if (this.injectedScripts.has(script.name)) {
            console.log(`[wBlock Userscript Injector] Script ${script.name} already injected, skipping`);
            return;
        }

        try {
            console.log(`[wBlock Userscript Injector] Injecting userscript: ${script.name}`);
            
            // Create script element
            const scriptElement = document.createElement('script');
            scriptElement.textContent = this.wrapUserScript(script);
            scriptElement.setAttribute('data-userscript', script.name);
            
            // Inject into page
            (document.head || document.documentElement).appendChild(scriptElement);
            
            // Clean up script element after execution
            setTimeout(() => {
                if (scriptElement.parentNode) {
                    scriptElement.parentNode.removeChild(scriptElement);
                }
            }, 100);

            this.injectedScripts.add(script.name);
            console.log(`[wBlock Userscript Injector] Successfully injected userscript: ${script.name}`);
            
        } catch (error) {
            console.error(`[wBlock Userscript Injector] Failed to inject userscript ${script.name}:`, error);
        }
    }

    wrapUserScript(script) {
        // Wrap userscript in an isolated function to prevent variable conflicts
        return `
(function() {
    'use strict';
    console.log('[wBlock] Executing userscript: ${script.name}');
    
    // Basic Greasemonkey API stubs
    const GM = {
        info: {
            script: {
                name: '${script.name}',
                version: '1.0.0'
            }
        }
    };
    
    // Legacy GM functions
    window.GM_info = GM.info;
    
    try {
        ${script.content}
        console.log('[wBlock] Userscript ${script.name} executed successfully');
    } catch (error) {
        console.error('[wBlock] Userscript error in ${script.name}:', error);
    }
})();
        `;
    }
}

// Initialize the userscript injector
console.log('[wBlock Userscript Injector] Creating injector instance...');
const injector = new UserScriptInjector();
