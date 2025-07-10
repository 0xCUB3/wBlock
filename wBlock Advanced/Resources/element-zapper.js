/**
 * wBlock Element Zapper
 * Safari-compatible element picker and custom rule creator
 * Based on uBlock Origin Lite's implementation with Safari adaptations
 */

class WBlockElementZapper {
    constructor() {
        this.isActive = false;
        this.isPickerMode = false;
        this.isPreviewMode = false;
        this.currentElement = null;
        this.highlightedElements = [];
        this.candidates = [];
        this.selectedCandidateIndex = -1;
        this.customRules = new Set();
        
        this.overlay = null;
        this.toolbar = null;
        this.pickerPanel = null;
        
        this.bindEvents();
        this.loadCustomRules();
    }

    /**
     * Initialize event listeners
     */
    bindEvents() {
        // Document event listeners
        document.addEventListener('mouseover', this.onMouseOver.bind(this), true);
        document.addEventListener('mouseout', this.onMouseOut.bind(this), true);
        document.addEventListener('click', this.onClick.bind(this), true);
        document.addEventListener('keydown', this.onKeyDown.bind(this), true);
        
        // Wait for DOM to be ready
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => this.initializeUI());
        } else {
            this.initializeUI();
        }
    }

    /**
     * Initialize the zapper UI
     */
    initializeUI() {
        // Create overlay
        this.overlay = document.createElement('div');
        this.overlay.id = 'wblock-zapper-overlay';
        this.overlay.style.cssText = `
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            width: 100vw !important;
            height: 100vh !important;
            pointer-events: none !important;
            z-index: 2147483647 !important;
            background: transparent !important;
        `;
        document.documentElement.appendChild(this.overlay);

        // Get UI elements
        this.toolbar = document.getElementById('wblock-zapper-toolbar');
        this.pickerPanel = document.getElementById('wblock-picker-panel');
        
        if (!this.toolbar || !this.pickerPanel) {
            console.error('wBlock Zapper: UI elements not found');
            return;
        }

        // Bind UI events
        document.getElementById('quit-zapper').addEventListener('click', () => this.quit());
        document.getElementById('toggle-picker').addEventListener('click', () => this.togglePicker());
        document.getElementById('preview-btn').addEventListener('click', () => this.togglePreview());
        document.getElementById('create-rule-btn').addEventListener('click', () => this.createRule());
        
        const selectorInput = document.getElementById('selector-input');
        selectorInput.addEventListener('input', () => this.onSelectorInput());
        selectorInput.addEventListener('focus', () => this.onSelectorFocus());
        
        // Activate zapper
        this.activate();
    }

    /**
     * Activate the element zapper
     */
    activate() {
        this.isActive = true;
        document.body.style.cursor = 'crosshair';
        this.updateStatus('Click elements to hide them');
    }

    /**
     * Deactivate and cleanup
     */
    quit() {
        this.isActive = false;
        this.isPickerMode = false;
        this.isPreviewMode = false;
        
        // Cleanup highlights
        this.clearHighlights();
        this.clearPreviews();
        
        // Restore cursor
        document.body.style.cursor = '';
        
        // Remove UI
        if (this.overlay && this.overlay.parentNode) {
            this.overlay.parentNode.removeChild(this.overlay);
        }
        
        // Notify Safari extension
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zapperController) {
            window.webkit.messageHandlers.zapperController.postMessage({
                action: 'quit'
            });
        }
    }

    /**
     * Toggle picker mode
     */
    togglePicker() {
        this.isPickerMode = !this.isPickerMode;
        this.pickerPanel.classList.toggle('visible', this.isPickerMode);
        
        if (this.isPickerMode) {
            this.updateStatus('Select elements to build CSS selector');
            document.getElementById('toggle-picker').textContent = 'Hide';
        } else {
            this.updateStatus('Click elements to hide them');
            document.getElementById('toggle-picker').textContent = 'Selector';
            this.clearPreviews();
        }
    }

    /**
     * Handle mouse over events
     */
    onMouseOver(event) {
        if (!this.isActive || this.isPreviewMode) return;
        
        event.preventDefault();
        event.stopPropagation();
        
        const element = event.target;
        if (this.shouldIgnoreElement(element)) return;
        
        this.currentElement = element;
        this.highlightElement(element);
        
        if (this.isPickerMode) {
            this.generateCandidates(element);
        }
    }

    /**
     * Handle mouse out events
     */
    onMouseOut(event) {
        if (!this.isActive || this.isPreviewMode) return;
        
        this.clearHighlights();
        this.currentElement = null;
    }

    /**
     * Handle click events
     */
    onClick(event) {
        if (!this.isActive) return;
        
        event.preventDefault();
        event.stopPropagation();
        
        const element = event.target;
        if (this.shouldIgnoreElement(element)) return;
        
        if (this.isPickerMode) {
            // In picker mode, clicking selects the element for selector building
            this.selectElementForPicker(element);
        } else {
            // In zapper mode, clicking hides the element
            this.zapElement(element);
        }
    }

    /**
     * Handle keyboard events
     */
    onKeyDown(event) {
        if (!this.isActive) return;
        
        switch (event.key) {
            case 'Escape':
                event.preventDefault();
                this.quit();
                break;
            case 'Delete':
            case 'Backspace':
                if (this.currentElement && !this.isPickerMode) {
                    event.preventDefault();
                    this.zapElement(this.currentElement);
                }
                break;
            case 'p':
            case 'P':
                if (!this.isPickerMode) {
                    event.preventDefault();
                    this.togglePicker();
                }
                break;
            case 'Enter':
                if (this.currentElement && !this.isPickerMode) {
                    event.preventDefault();
                    this.zapElement(this.currentElement);
                }
                break;
            case 'ArrowUp':
                if (this.isPickerMode && this.candidates.length > 0) {
                    event.preventDefault();
                    const newIndex = Math.max(0, this.selectedCandidateIndex - 1);
                    this.selectCandidate(newIndex);
                }
                break;
            case 'ArrowDown':
                if (this.isPickerMode && this.candidates.length > 0) {
                    event.preventDefault();
                    const newIndex = Math.min(this.candidates.length - 1, this.selectedCandidateIndex + 1);
                    this.selectCandidate(newIndex);
                }
                break;
        }
    }

    /**
     * Check if element should be ignored
     */
    shouldIgnoreElement(element) {
        if (!element || element === document.documentElement || element === document.body) {
            return true;
        }
        
        // Ignore our own UI elements
        if (element.closest('#wblock-zapper-toolbar') || 
            element.closest('#wblock-picker-panel') ||
            element.closest('#wblock-zapper-overlay')) {
            return true;
        }
        
        return false;
    }

    /**
     * Highlight an element
     */
    highlightElement(element) {
        this.clearHighlights();
        
        const rect = element.getBoundingClientRect();
        const highlight = document.createElement('div');
        highlight.className = 'element-highlight';
        highlight.style.cssText = `
            position: fixed !important;
            top: ${rect.top}px !important;
            left: ${rect.left}px !important;
            width: ${rect.width}px !important;
            height: ${rect.height}px !important;
            border: 2px solid #007AFF !important;
            background: rgba(0, 122, 255, 0.1) !important;
            box-shadow: 0 0 0 1px rgba(0, 122, 255, 0.3) !important;
            pointer-events: none !important;
            z-index: 2147483646 !important;
        `;
        
        this.overlay.appendChild(highlight);
        this.highlightedElements.push(highlight);
    }

    /**
     * Clear all highlights
     */
    clearHighlights() {
        this.highlightedElements.forEach(highlight => {
            if (highlight.parentNode) {
                highlight.parentNode.removeChild(highlight);
            }
        });
        this.highlightedElements = [];
    }

    /**
     * Zap (hide) an element
     */
    zapElement(element) {
        if (!element) return;
        
        // Create a simple CSS selector for the element
        const selector = this.generateSimpleSelector(element);
        
        // Apply the hiding rule immediately
        this.applyHidingRule(selector);
        
        // Save the rule
        this.saveCustomRule(selector);
        
        this.updateStatus(`Hidden: ${selector}`);
        
        // Clear highlights
        this.clearHighlights();
    }

    /**
     * Generate a simple CSS selector for an element
     */
    generateSimpleSelector(element) {
        const parts = [];
        
        // Add tag name
        parts.push(element.tagName.toLowerCase());
        
        // Add ID if present
        if (element.id) {
            parts.push(`#${CSS.escape(element.id)}`);
        }
        
        // Add classes if present
        if (element.className && typeof element.className === 'string') {
            const classes = element.className.trim().split(/\s+/);
            classes.forEach(cls => {
                if (cls) {
                    parts.push(`.${CSS.escape(cls)}`);
                }
            });
        }
        
        return parts.join('');
    }

    /**
     * Generate candidate selectors for picker mode
     */
    generateCandidates(element) {
        this.candidates = [];
        
        // Walk up the DOM tree to generate candidates
        let current = element;
        const selectorParts = [];
        
        while (current && current !== document.documentElement) {
            const parts = [];
            
            // Tag name
            parts.push(current.tagName.toLowerCase());
            
            // ID
            if (current.id) {
                parts.push(`#${CSS.escape(current.id)}`);
            }
            
            // Classes
            if (current.className && typeof current.className === 'string') {
                const classes = current.className.trim().split(/\s+/);
                classes.slice(0, 3).forEach(cls => { // Limit to 3 classes
                    if (cls) {
                        parts.push(`.${CSS.escape(cls)}`);
                    }
                });
            }
            
            // Attributes (limited set)
            const attributeSelectors = [];
            for (const attr of ['data-ad', 'data-banner', 'data-widget', 'role']) {
                if (current.hasAttribute(attr)) {
                    const value = current.getAttribute(attr);
                    if (value) {
                        attributeSelectors.push(`[${attr}="${CSS.escape(value)}"]`);
                    } else {
                        attributeSelectors.push(`[${attr}]`);
                    }
                }
            }
            
            const elementSelector = parts.join('') + attributeSelectors.join('');
            selectorParts.unshift(elementSelector);
            
            // Generate candidates
            for (let i = 0; i < selectorParts.length; i++) {
                const candidate = selectorParts.slice(i).join(' > ');
                if (!this.candidates.includes(candidate)) {
                    this.candidates.push(candidate);
                }
            }
            
            current = current.parentElement;
        }
        
        // Update candidates UI
        this.updateCandidatesList();
    }

    /**
     * Update the candidates list in the UI
     */
    updateCandidatesList() {
        const candidatesList = document.getElementById('candidates-list');
        candidatesList.innerHTML = '';
        
        this.candidates.slice(0, 10).forEach((candidate, index) => {
            const item = document.createElement('div');
            item.className = 'candidate-item';
            item.textContent = candidate;
            item.addEventListener('click', () => {
                this.selectCandidate(index);
            });
            candidatesList.appendChild(item);
        });
    }

    /**
     * Select a candidate selector
     */
    selectCandidate(index) {
        this.selectedCandidateIndex = index;
        const candidate = this.candidates[index];
        
        // Update input
        document.getElementById('selector-input').value = candidate;
        
        // Update UI
        document.querySelectorAll('.candidate-item').forEach((item, i) => {
            item.classList.toggle('selected', i === index);
        });
        
        // Preview the selection
        this.previewSelector(candidate);
        this.updateElementCount(candidate);
    }

    /**
     * Handle selector input changes
     */
    onSelectorInput() {
        const selector = document.getElementById('selector-input').value.trim();
        if (selector) {
            this.previewSelector(selector);
            this.updateElementCount(selector);
        } else {
            this.clearPreviews();
        }
    }

    /**
     * Handle selector input focus
     */
    onSelectorFocus() {
        const selector = document.getElementById('selector-input').value.trim();
        if (selector) {
            this.previewSelector(selector);
        }
    }

    /**
     * Preview elements matching a selector
     */
    previewSelector(selector) {
        this.clearPreviews();
        
        try {
            const elements = document.querySelectorAll(selector);
            elements.forEach(element => {
                if (!this.shouldIgnoreElement(element)) {
                    element.style.setProperty('border', '2px dashed #FF3B30', 'important');
                    element.style.setProperty('background', 'rgba(255, 59, 48, 0.15)', 'important');
                    element.style.setProperty('opacity', '0.7', 'important');
                    element.classList.add('wblock-preview-element');
                }
            });
        } catch (e) {
            // Invalid selector
        }
    }

    /**
     * Clear preview styles
     */
    clearPreviews() {
        document.querySelectorAll('.wblock-preview-element').forEach(element => {
            element.style.removeProperty('border');
            element.style.removeProperty('background');
            element.style.removeProperty('opacity');
            element.classList.remove('wblock-preview-element');
        });
    }

    /**
     * Toggle preview mode
     */
    togglePreview() {
        const selector = document.getElementById('selector-input').value.trim();
        if (!selector) return;
        
        this.isPreviewMode = !this.isPreviewMode;
        
        if (this.isPreviewMode) {
            this.previewSelector(selector);
            document.getElementById('preview-btn').textContent = 'Stop Preview';
            this.updateStatus('Previewing selector');
        } else {
            this.clearPreviews();
            document.getElementById('preview-btn').textContent = 'Preview';
            this.updateStatus('Select elements to build CSS selector');
        }
    }

    /**
     * Update element count display
     */
    updateElementCount(selector) {
        const countElement = document.getElementById('element-count');
        
        if (!selector) {
            countElement.textContent = 'Enter a CSS selector';
            return;
        }
        
        try {
            const elements = document.querySelectorAll(selector);
            const count = elements.length;
            countElement.textContent = count === 1 ? '1 element' : `${count} elements`;
        } catch (e) {
            countElement.textContent = 'Invalid selector';
        }
    }

    /**
     * Create a custom hiding rule
     */
    createRule() {
        const selector = document.getElementById('selector-input').value.trim();
        if (!selector) return;
        
        // Validate selector
        try {
            document.querySelectorAll(selector);
        } catch (e) {
            alert('Invalid CSS selector');
            return;
        }
        
        // Apply the hiding rule
        this.applyHidingRule(selector);
        
        // Save the rule
        this.saveCustomRule(selector);
        
        this.updateStatus(`Rule created: ${selector}`);
        
        // Clear the picker
        document.getElementById('selector-input').value = '';
        this.clearPreviews();
        this.updateElementCount('');
        
        // Exit picker mode
        this.isPickerMode = false;
        this.pickerPanel.classList.remove('visible');
        document.getElementById('toggle-picker').textContent = 'Selector';
        this.updateStatus('Click elements to hide them');
    }

    /**
     * Apply a hiding rule to the page
     */
    applyHidingRule(selector) {
        // Create or get the style element
        let styleElement = document.getElementById('wblock-custom-rules');
        if (!styleElement) {
            styleElement = document.createElement('style');
            styleElement.id = 'wblock-custom-rules';
            styleElement.type = 'text/css';
            document.head.appendChild(styleElement);
        }
        
        // Add the rule
        const rule = `${selector} { display: none !important; }`;
        styleElement.textContent += rule + '\n';
    }

    /**
     * Save a custom rule
     */
    saveCustomRule(selector) {
        this.customRules.add(selector);
        
        // Send to Safari extension for persistence
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zapperController) {
            window.webkit.messageHandlers.zapperController.postMessage({
                action: 'saveRule',
                selector: selector,
                hostname: location.hostname
            });
        }
    }

    /**
     * Load custom rules
     */
    loadCustomRules() {
        // Request rules from Safari extension
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zapperController) {
            window.webkit.messageHandlers.zapperController.postMessage({
                action: 'loadRules',
                hostname: location.hostname
            });
        }
    }

    /**
     * Apply loaded custom rules
     */
    applyCustomRules(rules) {
        if (!rules || !Array.isArray(rules)) return;
        
        rules.forEach(selector => {
            this.customRules.add(selector);
            this.applyHidingRule(selector);
        });
    }

    /**
     * Select element for picker
     */
    selectElementForPicker(element) {
        this.generateCandidates(element);
        
        if (this.candidates.length > 0) {
            this.selectCandidate(0); // Auto-select the first candidate
        }
    }

    /**
     * Update status message
     */
    updateStatus(message) {
        const statusElement = document.querySelector('.zapper-status');
        if (statusElement) {
            statusElement.textContent = message;
        }
    }
}

// Auto-initialize when script loads
let zapperInstance = null;

// Handle messages from Safari extension
window.addEventListener('message', function(event) {
    if (event.data && event.data.action === 'loadRulesResponse') {
        if (zapperInstance) {
            zapperInstance.applyCustomRules(event.data.rules);
        }
    }
});

// Initialize zapper
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        zapperInstance = new WBlockElementZapper();
    });
} else {
    zapperInstance = new WBlockElementZapper();
}

// Export for external access
window.WBlockElementZapper = WBlockElementZapper;
