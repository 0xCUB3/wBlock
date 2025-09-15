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
    
    // Enhanced Greasemonkey API with popup support
    const wBlockPopup = new (function() {
        this.popupCounter = 0;
        
        // Show a notification popup
        this.showNotification = (options = {}) => {
            const {
                title = 'wBlock Notification',
                message = '',
                actions = [],
                timeout = 5000,
                position = 'top-right'
            } = options;
            
            return this.createPopup({
                type: 'notification',
                title,
                message,
                actions,
                timeout,
                position,
                dismissible: true
            });
        };
        
        // Show a settings modal
        this.showSettings = (options = {}) => {
            const {
                title = 'Settings',
                fields = [],
                onSave = null,
                onCancel = null
            } = options;
            
            return this.createPopup({
                type: 'settings',
                title,
                fields,
                onSave,
                onCancel,
                modal: true
            });
        };
        
        // Create and display a popup
        this.createPopup = (config) => {
            const popupId = 'wblock-popup-' + (++this.popupCounter);
            const popup = this.buildPopupElement(popupId, config);
            
            // Insert styles if not already present
            this.ensureStyles();
            
            // Add to page
            document.body.appendChild(popup);
            
            // Handle timeout
            if (config.timeout && config.timeout > 0) {
                setTimeout(() => {
                    this.removePopup(popupId);
                }, config.timeout);
            }
            
            // Return control object
            return {
                id: popupId,
                element: popup,
                close: () => this.removePopup(popupId),
                update: (newConfig) => this.updatePopup(popupId, newConfig)
            };
        };
        
        // Build popup HTML element
        this.buildPopupElement = (id, config) => {
            const popup = document.createElement('div');
            popup.id = id;
            popup.className = 'wblock-popup';
            
            if (config.modal) {
                popup.classList.add('wblock-modal');
            }
            
            if (config.position) {
                popup.classList.add('wblock-position-' + config.position);
            }
            
            const content = document.createElement('div');
            content.className = 'wblock-popup-content';
            
            // Title
            if (config.title) {
                const title = document.createElement('div');
                title.className = 'wblock-popup-title';
                title.textContent = config.title;
                content.appendChild(title);
            }
            
            // Message
            if (config.message) {
                const message = document.createElement('div');
                message.className = 'wblock-popup-message';
                message.textContent = config.message;
                content.appendChild(message);
            }
            
            // Settings fields
            if (config.fields && config.fields.length > 0) {
                const fieldsContainer = document.createElement('div');
                fieldsContainer.className = 'wblock-popup-fields';
                
                config.fields.forEach(field => {
                    const fieldElement = this.createFieldElement(field);
                    fieldsContainer.appendChild(fieldElement);
                });
                
                content.appendChild(fieldsContainer);
            }
            
            // Settings-specific actions (Save/Cancel)
            if (config.type === 'settings') {
                const actionsContainer = document.createElement('div');
                actionsContainer.className = 'wblock-popup-actions';
                
                // Save button
                const saveButton = document.createElement('button');
                saveButton.className = 'wblock-popup-action wblock-primary';
                saveButton.textContent = 'Save';
                saveButton.addEventListener('click', (e) => {
                    e.preventDefault();
                    const formData = this.getFormData(popup);
                    if (config.onSave) {
                        config.onSave(formData);
                    }
                    this.removePopup(id);
                });
                
                // Cancel button
                const cancelButton = document.createElement('button');
                cancelButton.className = 'wblock-popup-action';
                cancelButton.textContent = 'Cancel';
                cancelButton.addEventListener('click', (e) => {
                    e.preventDefault();
                    if (config.onCancel) {
                        config.onCancel();
                    }
                    this.removePopup(id);
                });
                
                actionsContainer.appendChild(cancelButton);
                actionsContainer.appendChild(saveButton);
                content.appendChild(actionsContainer);
            }
            // Regular actions
            else if (config.actions && config.actions.length > 0) {
                const actionsContainer = document.createElement('div');
                actionsContainer.className = 'wblock-popup-actions';
                
                config.actions.forEach(action => {
                    const button = document.createElement('button');
                    button.className = 'wblock-popup-action';
                    button.textContent = action.label || action.text || 'Action';
                    
                    if (action.primary) {
                        button.classList.add('wblock-primary');
                    }
                    
                    button.addEventListener('click', (e) => {
                        e.preventDefault();
                        if (action.callback) {
                            action.callback();
                        }
                        if (action.close !== false) {
                            this.removePopup(id);
                        }
                    });
                    
                    actionsContainer.appendChild(button);
                });
                
                content.appendChild(actionsContainer);
            }
            
            // Close button
            if (config.dismissible) {
                const closeBtn = document.createElement('button');
                closeBtn.className = 'wblock-popup-close';
                closeBtn.innerHTML = '×';
                closeBtn.addEventListener('click', () => this.removePopup(id));
                content.appendChild(closeBtn);
            }
            
            popup.appendChild(content);
            
            // Modal backdrop click to close
            if (config.modal) {
                popup.addEventListener('click', (e) => {
                    if (e.target === popup) {
                        this.removePopup(id);
                    }
                });
            }
            
            return popup;
        };
        
        // Create form field element
        this.createFieldElement = (field) => {
            const container = document.createElement('div');
            container.className = 'wblock-field';
            
            if (field.label) {
                const label = document.createElement('label');
                label.textContent = field.label;
                container.appendChild(label);
            }
            
            let input;
            switch (field.type) {
                case 'text':
                case 'url':
                case 'email':
                    input = document.createElement('input');
                    input.type = field.type || 'text';
                    input.value = field.value || '';
                    input.placeholder = field.placeholder || '';
                    break;
                case 'textarea':
                    input = document.createElement('textarea');
                    input.value = field.value || '';
                    input.placeholder = field.placeholder || '';
                    break;
                case 'select':
                    input = document.createElement('select');
                    if (field.options) {
                        field.options.forEach(option => {
                            const opt = document.createElement('option');
                            opt.value = option.value || option;
                            opt.textContent = option.label || option;
                            if (option.value === field.value) {
                                opt.selected = true;
                            }
                            input.appendChild(opt);
                        });
                    }
                    break;
                case 'checkbox':
                    input = document.createElement('input');
                    input.type = 'checkbox';
                    input.checked = field.value || false;
                    break;
                default:
                    input = document.createElement('input');
                    input.type = 'text';
            }
            
            if (field.name) {
                input.name = field.name;
                input.id = 'wblock-field-' + field.name;
            }
            
            container.appendChild(input);
            return container;
        };
        
        // Get form data from popup
        this.getFormData = (popup) => {
            const formData = {};
            const inputs = popup.querySelectorAll('input, textarea, select');
            
            inputs.forEach(input => {
                if (input.name) {
                    if (input.type === 'checkbox') {
                        formData[input.name] = input.checked;
                    } else {
                        formData[input.name] = input.value;
                    }
                }
            });
            
            return formData;
        };
        
        // Remove popup from DOM
        this.removePopup = (id) => {
            const popup = document.getElementById(id);
            if (popup) {
                popup.remove();
            }
        };
        
        // Update existing popup
        this.updatePopup = (id, newConfig) => {
            const popup = document.getElementById(id);
            if (popup) {
                // Simple implementation: replace content
                const newPopup = this.buildPopupElement(id, newConfig);
                popup.parentNode.replaceChild(newPopup, popup);
            }
        };
        
        // Ensure CSS styles are loaded
        this.ensureStyles = () => {
            if (!document.getElementById('wblock-popup-styles')) {
                const style = document.createElement('style');
                style.id = 'wblock-popup-styles';
                style.textContent = \`
                    .wblock-popup {
                        position: fixed;
                        z-index: 2147483647;
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                        font-size: 14px;
                    }
                    
                    .wblock-modal {
                        top: 0;
                        left: 0;
                        width: 100%;
                        height: 100%;
                        background: rgba(0, 0, 0, 0.5);
                        display: flex;
                        align-items: center;
                        justify-content: center;
                    }
                    
                    .wblock-position-top-right {
                        top: 20px;
                        right: 20px;
                        max-width: 400px;
                    }
                    
                    .wblock-position-top-left {
                        top: 20px;
                        left: 20px;
                        max-width: 400px;
                    }
                    
                    .wblock-position-bottom-right {
                        bottom: 20px;
                        right: 20px;
                        max-width: 400px;
                    }
                    
                    .wblock-popup-content {
                        background: white;
                        border-radius: 8px;
                        box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
                        padding: 20px;
                        position: relative;
                        max-width: 100%;
                        box-sizing: border-box;
                    }
                    
                    .wblock-popup-title {
                        font-weight: 600;
                        font-size: 16px;
                        margin-bottom: 10px;
                        color: #333;
                    }
                    
                    .wblock-popup-message {
                        color: #666;
                        line-height: 1.5;
                        margin-bottom: 15px;
                    }
                    
                    .wblock-popup-fields {
                        margin-bottom: 15px;
                    }
                    
                    .wblock-field {
                        margin-bottom: 15px;
                    }
                    
                    .wblock-field label {
                        display: block;
                        margin-bottom: 5px;
                        font-weight: 500;
                        color: #333;
                    }
                    
                    .wblock-field input,
                    .wblock-field textarea,
                    .wblock-field select {
                        width: 100%;
                        padding: 8px 12px;
                        border: 1px solid #ddd;
                        border-radius: 4px;
                        box-sizing: border-box;
                        font-size: 14px;
                    }
                    
                    .wblock-field input[type="checkbox"] {
                        width: auto;
                    }
                    
                    .wblock-popup-actions {
                        display: flex;
                        gap: 10px;
                        justify-content: flex-end;
                    }
                    
                    .wblock-popup-action {
                        padding: 8px 16px;
                        border: 1px solid #ddd;
                        border-radius: 4px;
                        background: white;
                        cursor: pointer;
                        font-size: 14px;
                        transition: all 0.2s ease;
                    }
                    
                    .wblock-popup-action:hover {
                        background: #f5f5f5;
                    }
                    
                    .wblock-popup-action.wblock-primary {
                        background: #007AFF;
                        color: white;
                        border-color: #007AFF;
                    }
                    
                    .wblock-popup-action.wblock-primary:hover {
                        background: #0056CC;
                    }
                    
                    .wblock-popup-close {
                        position: absolute;
                        top: 10px;
                        right: 10px;
                        background: none;
                        border: none;
                        font-size: 18px;
                        cursor: pointer;
                        color: #999;
                        width: 24px;
                        height: 24px;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                    }
                    
                    .wblock-popup-close:hover {
                        color: #333;
                    }
                \`;
                document.head.appendChild(style);
            }
        };
    })();
    
    // Enhanced Greasemonkey API
    const GM = {
        info: {
            script: {
                name: '${script.name}',
                version: '1.0.0'
            }
        },
        notification: wBlockPopup.showNotification.bind(wBlockPopup),
        popup: {
            show: wBlockPopup.createPopup.bind(wBlockPopup),
            notification: wBlockPopup.showNotification.bind(wBlockPopup),
            settings: wBlockPopup.showSettings.bind(wBlockPopup)
        },
        // Common userscript APIs that might be used for popups
        openInTab: (url) => window.open(url, '_blank'),
        getValue: (key, defaultValue) => {
            try {
                const stored = localStorage.getItem('wblock_gm_' + key);
                return stored !== null ? JSON.parse(stored) : defaultValue;
            } catch (e) {
                return defaultValue;
            }
        },
        setValue: (key, value) => {
            try {
                localStorage.setItem('wblock_gm_' + key, JSON.stringify(value));
            } catch (e) {
                console.warn('[wBlock] Failed to save value for key:', key);
            }
        },
        deleteValue: (key) => {
            try {
                localStorage.removeItem('wblock_gm_' + key);
            } catch (e) {
                console.warn('[wBlock] Failed to delete value for key:', key);
            }
        }
    };
    
    // Legacy GM functions
    window.GM_info = GM.info;
    window.GM_notification = GM.notification;
    window.GM_getValue = GM.getValue;
    window.GM_setValue = GM.setValue;
    window.GM_deleteValue = GM.deleteValue;
    window.GM_openInTab = GM.openInTab;
    
    // wBlock-specific API
    window.wBlock = {
        popup: GM.popup,
        showNotification: GM.notification,
        storage: {
            get: GM.getValue,
            set: GM.setValue,
            delete: GM.deleteValue
        }
    };
    
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
