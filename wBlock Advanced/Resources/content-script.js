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
    
    // Load the zapper injector
    const script = document.createElement('script');
    script.textContent = `
${zapperInjectorCode}
    `;
    
    // Inject the script into the page context
    (document.head || document.documentElement).appendChild(script);
    script.remove();
    
    // Setup message handling for activation
    function handleActivationMessage(event) {
        if (event.data && event.data.action === 'activateZapper') {
            // Activate the zapper if it's available
            if (window.WBlockZapperInjector) {
                window.WBlockZapperInjector.injectZapper();
            }
        }
    }
    
    window.addEventListener('message', handleActivationMessage);
    
    // Alternative activation via webkit message handlers
    if (window.webkit && window.webkit.messageHandlers) {
        const originalHandler = window.webkit.messageHandlers.wblockAdvanced;
        
        window.webkit.messageHandlers.wblockAdvanced = {
            postMessage: function(message) {
                if (message && message.action === 'activateZapper') {
                    if (window.WBlockZapperInjector) {
                        window.WBlockZapperInjector.injectZapper();
                    }
                } else if (originalHandler && originalHandler.postMessage) {
                    originalHandler.postMessage(message);
                }
            }
        };
    }
    
})();

// Include the full zapper injector code here
const zapperInjectorCode = \`
/**
 * wBlock Element Zapper Content Script
 * Injects the element zapper interface into web pages
 */

class WBlockZapperInjector {
    constructor() {
        this.isInjected = false;
        this.zapperFrame = null;
        this.customRules = new Map(); // hostname -> Set of selectors
        
        this.setupMessageHandlers();
        this.loadStoredRules();
    }

    /**
     * Setup message handlers for Safari extension communication
     */
    setupMessageHandlers() {
        // Listen for messages from the main script
        if (window.webkit && window.webkit.messageHandlers) {
            // Create message handler for zapper controller
            const messageHandler = {
                postMessage: (message) => {
                    this.handleZapperMessage(message);
                }
            };
            
            // Add to webkit messageHandlers
            if (!window.webkit.messageHandlers.zapperController) {
                window.webkit.messageHandlers.zapperController = messageHandler;
            }
        }
    }

    /**
     * Handle messages from the zapper interface
     */
    handleZapperMessage(message) {
        switch (message.action) {
            case 'quit':
                this.removeZapper();
                break;
                
            case 'saveRule':
                this.saveCustomRule(message.hostname, message.selector);
                break;
                
            case 'loadRules':
                this.loadRulesForHostname(message.hostname);
                break;
        }
    }

    /**
     * Inject the element zapper into the page
     */
    injectZapper() {
        if (this.isInjected) {
            return;
        }

        // Create iframe for zapper UI
        this.zapperFrame = document.createElement('iframe');
        this.zapperFrame.id = 'wblock-zapper-frame';
        this.zapperFrame.style.cssText = \\\`
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            width: 100vw !important;
            height: 100vh !important;
            border: none !important;
            background: transparent !important;
            pointer-events: none !important;
            z-index: 2147483647 !important;
        \\\`;

        // Load zapper HTML content
        const zapperHTML = this.getZapperHTML();
        
        document.documentElement.appendChild(this.zapperFrame);
        
        // Write content to iframe
        this.zapperFrame.contentDocument.open();
        this.zapperFrame.contentDocument.write(zapperHTML);
        this.zapperFrame.contentDocument.close();

        this.isInjected = true;
        
        // Setup communication with iframe
        this.setupIframeCommunication();
        
        // Listen for quit messages from the iframe
        window.addEventListener('message', (event) => {
            if (event.data && event.data.action === 'zapperQuit') {
                this.removeZapper();
            }
        });
    }

    /**
     * Remove the element zapper from the page
     */
    removeZapper() {
        if (this.zapperFrame && this.zapperFrame.parentNode) {
            this.zapperFrame.parentNode.removeChild(this.zapperFrame);
        }
        
        this.zapperFrame = null;
        this.isInjected = false;
    }

    /**
     * Setup communication with the zapper iframe
     */
    setupIframeCommunication() {
        if (!this.zapperFrame || !this.zapperFrame.contentWindow) {
            return;
        }

        // Override the webkit messageHandlers in the iframe
        const iframeWindow = this.zapperFrame.contentWindow;
        
        iframeWindow.webkit = {
            messageHandlers: {
                zapperController: {
                    postMessage: (message) => {
                        this.handleZapperMessage(message);
                    }
                }
            }
        };
    }

    /**
     * Save a custom rule for a hostname
     */
    saveCustomRule(hostname, selector) {
        if (!this.customRules.has(hostname)) {
            this.customRules.set(hostname, new Set());
        }
        
        this.customRules.get(hostname).add(selector);
        this.persistRules();
        
        // Apply the rule immediately to the main page
        this.applyRuleToPage(selector);
    }

    /**
     * Load rules for a specific hostname
     */
    loadRulesForHostname(hostname) {
        const rules = this.customRules.get(hostname);
        const rulesArray = rules ? Array.from(rules) : [];
        
        // Send rules back to zapper
        if (this.zapperFrame && this.zapperFrame.contentWindow) {
            this.zapperFrame.contentWindow.postMessage({
                action: 'loadRulesResponse',
                rules: rulesArray
            }, '*');
        }
        
        // Apply rules to the page
        rulesArray.forEach(selector => {
            this.applyRuleToPage(selector);
        });
    }

    /**
     * Apply a hiding rule to the main page
     */
    applyRuleToPage(selector) {
        let styleElement = document.getElementById('wblock-zapper-custom-rules');
        if (!styleElement) {
            styleElement = document.createElement('style');
            styleElement.id = 'wblock-zapper-custom-rules';
            styleElement.type = 'text/css';
            document.head.appendChild(styleElement);
        }
        
        const rule = \\\`\\\${selector} { display: none !important; }\\\`;
        styleElement.textContent += rule + '\\\\n';
    }

    /**
     * Load stored rules from localStorage
     */
    loadStoredRules() {
        try {
            const stored = localStorage.getItem('wblock-zapper-rules');
            if (stored) {
                const data = JSON.parse(stored);
                this.customRules = new Map();
                
                for (const [hostname, rules] of Object.entries(data)) {
                    this.customRules.set(hostname, new Set(rules));
                }
                
                // Apply rules for current hostname
                this.loadRulesForHostname(location.hostname);
            }
        } catch (e) {
            console.warn('wBlock Zapper: Failed to load stored rules', e);
        }
    }

    /**
     * Persist rules to localStorage
     */
    persistRules() {
        try {
            const data = {};
            for (const [hostname, rules] of this.customRules.entries()) {
                data[hostname] = Array.from(rules);
            }
            localStorage.setItem('wblock-zapper-rules', JSON.stringify(data));
        } catch (e) {
            console.warn('wBlock Zapper: Failed to persist rules', e);
        }
    }

    /**
     * Get the complete HTML content for the zapper
     */
    getZapperHTML() {
        return \\\`<!DOCTYPE html>
<html id="wblock-zapper">
<head>
    <meta charset="utf-8">
    <meta name="color-scheme" content="light dark">
    <title>wBlock Element Zapper</title>
    <style>
        :root {
            --surface-1: #ffffff;
            --surface-2: #f5f5f5;
            --ink-1: #000000;
            --ink-2: #666666;
            --accent-surface-1: #007AFF;
            --accent-ink-1: #ffffff;
            --error-surface-1: #FF3B30;
            --error-ink-1: #ffffff;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --surface-1: #1c1c1e;
                --surface-2: #2c2c2e;
                --ink-1: #ffffff;
                --ink-2: #8e8e93;
                --accent-surface-1: #0A84FF;
                --accent-ink-1: #ffffff;
                --error-surface-1: #FF453A;
                --error-ink-1: #ffffff;
            }
        }

        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            font-size: 13px;
            background: transparent;
            color: var(--ink-1);
        }

        #wblock-zapper-overlay {
            position: fixed;
            top: 0;
            left: 0;
            width: 100vw;
            height: 100vh;
            pointer-events: none;
            z-index: 2147483647;
        }

        #wblock-zapper-toolbar {
            position: fixed;
            top: 10px;
            right: 10px;
            background: var(--surface-1);
            border: 1px solid var(--surface-2);
            border-radius: 8px;
            padding: 8px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
            display: flex;
            gap: 8px;
            align-items: center;
            pointer-events: auto;
            z-index: 2147483648;
        }

        .zapper-button {
            background: var(--surface-2);
            border: 1px solid var(--surface-2);
            border-radius: 6px;
            padding: 8px 12px;
            cursor: pointer;
            color: var(--ink-1);
            font-size: 12px;
            font-weight: 500;
            transition: all 0.2s ease;
            min-width: 60px;
            text-align: center;
        }

        .zapper-button:hover {
            background: var(--accent-surface-1);
            color: var(--accent-ink-1);
            border-color: var(--accent-surface-1);
        }

        .zapper-button.primary {
            background: var(--accent-surface-1);
            color: var(--accent-ink-1);
            border-color: var(--accent-surface-1);
        }

        .zapper-button.danger {
            background: var(--error-surface-1);
            color: var(--error-ink-1);
            border-color: var(--error-surface-1);
        }

        .zapper-status {
            font-size: 12px;
            color: var(--ink-2);
            font-weight: 500;
        }

        .element-highlight {
            position: absolute;
            pointer-events: none;
            border: 2px solid var(--accent-surface-1) !important;
            background: rgba(0, 122, 255, 0.1) !important;
            box-shadow: 0 0 0 1px rgba(0, 122, 255, 0.3) !important;
            z-index: 2147483646 !important;
        }

        .element-preview {
            border: 2px dashed var(--error-surface-1) !important;
            background: rgba(255, 59, 48, 0.15) !important;
            opacity: 0.7 !important;
        }

        #wblock-picker-panel {
            position: fixed;
            top: 60px;
            right: 10px;
            width: 300px;
            max-height: 400px;
            background: var(--surface-1);
            border: 1px solid var(--surface-2);
            border-radius: 8px;
            padding: 12px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
            pointer-events: auto;
            z-index: 2147483648;
            display: none;
        }

        #wblock-picker-panel.visible {
            display: block;
        }

        .picker-section {
            margin-bottom: 12px;
        }

        .picker-section h4 {
            margin: 0 0 8px 0;
            font-size: 12px;
            font-weight: 600;
            color: var(--ink-2);
        }

        #selector-input {
            width: 100%;
            padding: 8px;
            border: 1px solid var(--surface-2);
            border-radius: 4px;
            background: var(--surface-1);
            color: var(--ink-1);
            font-family: 'SF Mono', Monaco, 'Cascadia Code', monospace;
            font-size: 11px;
            resize: none;
            min-height: 60px;
        }

        #selector-input:focus {
            outline: none;
            border-color: var(--accent-surface-1);
        }

        .element-count {
            font-size: 11px;
            color: var(--ink-2);
            margin-top: 4px;
        }

        .candidates-list {
            max-height: 120px;
            overflow-y: auto;
            border: 1px solid var(--surface-2);
            border-radius: 4px;
            background: var(--surface-1);
        }

        .candidate-item {
            padding: 6px 8px;
            cursor: pointer;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', monospace;
            font-size: 10px;
            border-bottom: 1px solid var(--surface-2);
            word-break: break-all;
        }

        .candidate-item:last-child {
            border-bottom: none;
        }

        .candidate-item:hover {
            background: var(--surface-2);
        }

        .candidate-item.selected {
            background: var(--accent-surface-1);
            color: var(--accent-ink-1);
        }

        .button-group {
            display: flex;
            gap: 8px;
            margin-top: 12px;
        }

        .button-group button {
            flex: 1;
        }
    </style>
</head>
<body>
    <div id="wblock-zapper-overlay"></div>
    
    <div id="wblock-zapper-toolbar">
        <span class="zapper-status">Click elements to hide them</span>
        <button class="zapper-button" id="toggle-picker">Selector</button>
        <button class="zapper-button danger" id="quit-zapper">Exit</button>
    </div>

    <div id="wblock-picker-panel">
        <div class="picker-section">
            <h4>CSS Selector</h4>
            <textarea id="selector-input" placeholder="div.ad, .banner, [data-ad]"></textarea>
            <div class="element-count" id="element-count">Enter a CSS selector</div>
        </div>

        <div class="picker-section">
            <h4>Suggested Selectors</h4>
            <div class="candidates-list" id="candidates-list"></div>
        </div>

        <div class="button-group">
            <button class="zapper-button" id="preview-btn">Preview</button>
            <button class="zapper-button primary" id="create-rule-btn">Create Rule</button>
        </div>
    </div>

    <script>
        ${this.getZapperJavaScript()}
    </script>
</body>
</html>\\\`;
    }

    // ... (rest of the zapper JavaScript code would be included here)
}

// Initialize the zapper injector
const zapperInjector = new WBlockZapperInjector();

// Export for external access
window.WBlockZapperInjector = zapperInjector;
\`;
