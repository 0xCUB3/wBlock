/**
 * wBlock Userscript Injector for iOS Safari Web Extension
 * Injects and manages userscripts from the native app
 */

// Userscript execution engine for iOS
class UserScriptEngine {
    constructor() {
        this.injectedScripts = new Set();
        this.init();
    }

    init() {
        // Request userscripts from native app via background script
        this.requestUserScripts();
    }

    async requestUserScripts() {
        try {
            // Send message to background script which will communicate with native app
            const response = await browser.runtime.sendMessage({
                action: 'getUserScripts',
                url: window.location.href
            });
            
            if (response && response.userScripts) {
                this.injectUserScripts(response.userScripts);
            }
        } catch (error) {
            console.log('[wBlock] Could not get userscripts:', error);
        }
    }

    injectUserScripts(userScripts) {
        userScripts.forEach(script => {
            this.injectUserScript(script);
        });
    }

    injectUserScript(script) {
        // Avoid double injection
        if (this.injectedScripts.has(script.name)) {
            return;
        }

        try {
            // Check if script should run at this timing
            if (!this.shouldRunScript(script)) {
                return;
            }

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
            console.log(`[wBlock] Injected userscript: ${script.name}`);
            
        } catch (error) {
            console.error(`[wBlock] Failed to inject userscript ${script.name}:`, error);
        }
    }

    shouldRunScript(script) {
        const runAt = script.runAt || 'document-end';
        const readyState = document.readyState;

        switch (runAt) {
            case 'document-start':
                return true; // Always run if we got here
            case 'document-end':
                return readyState === 'interactive' || readyState === 'complete';
            case 'document-idle':
                return readyState === 'complete';
            default:
                return readyState === 'interactive' || readyState === 'complete';
        }
    }

    wrapUserScript(script) {
        // Wrap userscript in an isolated function to prevent variable conflicts
        return `
(function() {
    'use strict';
    
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
    } catch (error) {
        console.error('[wBlock] Userscript error in ${script.name}:', error);
    }
})();
        `;
    }
}

// Initialize userscript engine when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        new UserScriptEngine();
    });
} else {
    new UserScriptEngine();
}

// Also initialize on window load for document-idle scripts
window.addEventListener('load', () => {
    new UserScriptEngine();
});
