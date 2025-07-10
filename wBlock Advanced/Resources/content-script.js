/**
 * wBlock Advanced - Main Content Script
 * This script loads on every page and provides the foundation for wBlock Advanced features
 */

(function() {
    'use strict';
    
    // Prevent multiple injections
    if (window.wBlockAdvancedLoaded) {
        return;
    }
    window.wBlockAdvancedLoaded = true;
    
    console.log('wBlock Advanced content script loaded');
    
    // Listen for messages from the Safari Extension Handler
    safari.self.addEventListener("message", function(event) {
        if (event.name === "wblockAdvanced" && event.message) {
            handleExtensionMessage(event.message);
        }
    }, false);

    function handleExtensionMessage(message) {
        if (message.action === 'injectZapper') {
            injectZapperUI(message.html, message.js);
        }
    }

    function injectZapperUI(html, js) {
        if (document.getElementById('wblock-zapper-container')) {
            return; // Already injected
        }

        const zapperContainer = document.createElement('div');
        zapperContainer.id = 'wblock-zapper-container';
        zapperContainer.innerHTML = html;
        document.body.appendChild(zapperContainer);

        const scriptElement = document.createElement('script');
        scriptElement.type = 'text/javascript';
        scriptElement.textContent = js;
        zapperContainer.appendChild(scriptElement);
    }
    
})();
