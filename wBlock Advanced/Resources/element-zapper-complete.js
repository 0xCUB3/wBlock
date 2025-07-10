/**
 * wBlock Element Zapper - Complete Implementation
 * Safari-compatible element picker and hiding tool
 * Based on uBlock Origin Lite patterns with Safari adaptations
 */

class WBlockElementZapper {
    constructor() {
        this.isActive = false;
        this.isPickerMode = false;
        this.highlightElement = null;
        this.currentElement = null;
        this.candidates = [];
        this.selectedCandidateIndex = 0;
        this.previewElements = new Set();
        
        this.init();
    }

    /**
     * Initialize the element zapper
     */
    init() {
        this.createOverlay();
        this.setupEventListeners();
        this.setupKeyboardShortcuts();
        this.isActive = true;
        
        // Load existing rules for this hostname
        this.loadRulesForHostname();
        
        console.log('wBlock Element Zapper initialized');
    }

    /**
     * Create the zapper overlay and UI
     */
    createOverlay() {
        // Create main overlay container
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
        `;

        // Create toolbar
        this.toolbar = document.createElement('div');
        this.toolbar.id = 'wblock-zapper-toolbar';
        this.toolbar.innerHTML = `
            <span class="zapper-status">Click elements to hide them</span>
            <button class="zapper-button" id="toggle-picker">Selector</button>
            <button class="zapper-button danger" id="quit-zapper">Exit</button>
        `;

        // Create picker panel
        this.pickerPanel = document.createElement('div');
        this.pickerPanel.id = 'wblock-picker-panel';
        this.pickerPanel.innerHTML = `
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
        `;

        this.overlay.appendChild(this.toolbar);
        this.overlay.appendChild(this.pickerPanel);
        document.documentElement.appendChild(this.overlay);
    }

    /**
     * Setup event listeners for the UI
     */
    setupEventListeners() {
        // Make toolbar and picker panel interactive
        this.toolbar.style.pointerEvents = 'auto';
        this.pickerPanel.style.pointerEvents = 'auto';

        // Toolbar buttons
        const quitBtn = document.getElementById('quit-zapper');
        const togglePickerBtn = document.getElementById('toggle-picker');
        
        quitBtn.addEventListener('click', () => this.quit());
        togglePickerBtn.addEventListener('click', () => this.togglePickerPanel());

        // Picker panel controls
        const selectorInput = document.getElementById('selector-input');
        const previewBtn = document.getElementById('preview-btn');
        const createRuleBtn = document.getElementById('create-rule-btn');

        selectorInput.addEventListener('input', () => this.onSelectorInput());
        previewBtn.addEventListener('click', () => this.previewSelector());
        createRuleBtn.addEventListener('click', () => this.createRule());

        // Mouse events for element picking
        document.addEventListener('mouseover', (e) => this.onMouseOver(e), true);
        document.addEventListener('click', (e) => this.onClick(e), true);
        document.addEventListener('mouseout', (e) => this.onMouseOut(e), true);
    }

    /**
     * Setup keyboard shortcuts
     */
    setupKeyboardShortcuts() {
        document.addEventListener('keydown', (e) => {
            if (!this.isActive) return;

            switch (e.key) {
                case 'Escape':
                    e.preventDefault();
                    this.quit();
                    break;
                case 'Enter':
                    if (this.currentElement && !this.isPickerMode) {
                        e.preventDefault();
                        this.zapElement(this.currentElement);
                    }
                    break;
                case 'ArrowUp':
                    if (this.candidates.length > 0) {
                        e.preventDefault();
                        this.selectCandidate(Math.max(0, this.selectedCandidateIndex - 1));
                    }
                    break;
                case 'ArrowDown':
                    if (this.candidates.length > 0) {
                        e.preventDefault();
                        this.selectCandidate(Math.min(this.candidates.length - 1, this.selectedCandidateIndex + 1));
                    }
                    break;
            }
        });
    }

    /**
     * Handle mouse over events for element highlighting
     */
    onMouseOver(event) {
        if (!this.isActive || this.isPickerMode) return;
        
        const element = event.target;
        if (this.isZapperElement(element)) return;

        this.highlightElement = element;
        this.showHighlight(element);
        this.generateCandidatesForElement(element);
    }

    /**
     * Handle mouse out events
     */
    onMouseOut(event) {
        // Keep highlight visible for better UX
    }

    /**
     * Handle click events for element selection
     */
    onClick(event) {
        if (!this.isActive) return;
        
        const element = event.target;
        if (this.isZapperElement(element)) return;

        event.preventDefault();
        event.stopPropagation();

        if (this.isPickerMode) {
            this.selectElementForPicker(element);
        } else {
            this.zapElement(element);
        }
    }

    /**
     * Check if an element belongs to the zapper UI
     */
    isZapperElement(element) {
        return element.closest('#wblock-zapper-overlay') !== null;
    }

    /**
     * Show highlight around an element
     */
    showHighlight(element) {
        this.removeHighlight();
        
        const rect = element.getBoundingClientRect();
        const highlight = document.createElement('div');
        highlight.className = 'element-highlight';
        highlight.style.cssText = `
            position: fixed !important;
            top: ${rect.top}px !important;
            left: ${rect.left}px !important;
            width: ${rect.width}px !important;
            height: ${rect.height}px !important;
            pointer-events: none !important;
            border: 2px solid #007AFF !important;
            background: rgba(0, 122, 255, 0.1) !important;
            box-shadow: 0 0 0 1px rgba(0, 122, 255, 0.3) !important;
            z-index: 2147483646 !important;
        `;

        this.overlay.appendChild(highlight);
        this.currentHighlight = highlight;
        this.currentElement = element;
    }

    /**
     * Remove current highlight
     */
    removeHighlight() {
        if (this.currentHighlight) {
            this.currentHighlight.remove();
            this.currentHighlight = null;
        }
    }

    /**
     * Generate CSS selector candidates for an element
     */
    generateCandidatesForElement(element) {
        this.candidates = [];
        
        // Generate various selector candidates
        const candidates = [];
        
        // ID selector
        if (element.id) {
            candidates.push(`#${CSS.escape(element.id)}`);
        }
        
        // Class selectors
        if (element.className) {
            const classes = Array.from(element.classList);
            candidates.push(`.${classes.map(c => CSS.escape(c)).join('.')}`);
            
            // Individual classes
            classes.forEach(cls => {
                candidates.push(`.${CSS.escape(cls)}`);
            });
        }
        
        // Attribute selectors
        Array.from(element.attributes).forEach(attr => {
            if (attr.name !== 'class' && attr.name !== 'id') {
                if (attr.value) {
                    candidates.push(`[${attr.name}="${CSS.escape(attr.value)}"]`);
                } else {
                    candidates.push(`[${attr.name}]`);
                }
            }
        });
        
        // Tag selector
        candidates.push(element.tagName.toLowerCase());
        
        // Parent-child combinations
        const parent = element.parentElement;
        if (parent && parent !== document.body) {
            if (parent.className) {
                const parentClass = Array.from(parent.classList)[0];
                if (parentClass) {
                    candidates.push(`.${CSS.escape(parentClass)} ${element.tagName.toLowerCase()}`);
                }
            }
        }
        
        // Remove duplicates and sort by specificity
        this.candidates = [...new Set(candidates)].slice(0, 8);
        this.selectedCandidateIndex = 0;
        
        this.updateCandidatesList();
    }

    /**
     * Update the candidates list in the picker panel
     */
    updateCandidatesList() {
        const candidatesList = document.getElementById('candidates-list');
        if (!candidatesList) return;
        
        candidatesList.innerHTML = '';
        
        this.candidates.forEach((candidate, index) => {
            const item = document.createElement('div');
            item.className = `candidate-item ${index === this.selectedCandidateIndex ? 'selected' : ''}`;
            item.textContent = candidate;
            item.addEventListener('click', () => this.selectCandidate(index));
            candidatesList.appendChild(item);
        });
    }

    /**
     * Select a candidate by index
     */
    selectCandidate(index) {
        this.selectedCandidateIndex = index;
        this.updateCandidatesList();
        
        const selectorInput = document.getElementById('selector-input');
        if (selectorInput && this.candidates[index]) {
            selectorInput.value = this.candidates[index];
            this.onSelectorInput();
        }
    }

    /**
     * Handle selector input changes
     */
    onSelectorInput() {
        const selectorInput = document.getElementById('selector-input');
        const elementCount = document.getElementById('element-count');
        
        if (!selectorInput || !elementCount) return;
        
        const selector = selectorInput.value.trim();
        if (!selector) {
            elementCount.textContent = 'Enter a CSS selector';
            return;
        }
        
        try {
            const elements = document.querySelectorAll(selector);
            const count = elements.length;
            
            if (count === 0) {
                elementCount.textContent = 'No elements match this selector';
            } else if (count === 1) {
                elementCount.textContent = '1 element matches';
            } else {
                elementCount.textContent = `${count} elements match`;
            }
        } catch (error) {
            elementCount.textContent = 'Invalid CSS selector';
        }
    }

    /**
     * Preview the current selector
     */
    previewSelector() {
        this.clearPreview();
        
        const selectorInput = document.getElementById('selector-input');
        if (!selectorInput) return;
        
        const selector = selectorInput.value.trim();
        if (!selector) return;
        
        try {
            const elements = document.querySelectorAll(selector);
            elements.forEach(element => {
                if (!this.isZapperElement(element)) {
                    element.classList.add('element-preview');
                    this.previewElements.add(element);
                }
            });
        } catch (error) {
            console.warn('Invalid selector for preview:', selector);
        }
    }

    /**
     * Clear preview highlighting
     */
    clearPreview() {
        this.previewElements.forEach(element => {
            element.classList.remove('element-preview');
        });
        this.previewElements.clear();
    }

    /**
     * Create a hiding rule from the current selector
     */
    createRule() {
        const selectorInput = document.getElementById('selector-input');
        if (!selectorInput) return;
        
        const selector = selectorInput.value.trim();
        if (!selector) return;
        
        try {
            // Test the selector
            document.querySelectorAll(selector);
            
            // Save the rule
            this.saveRule(selector);
            
            // Apply the rule immediately
            this.applyRule(selector);
            
            // Clear the form
            selectorInput.value = '';
            this.onSelectorInput();
            this.clearPreview();
            
            // Update status
            const status = document.querySelector('.zapper-status');
            if (status) {
                status.textContent = 'Rule created and applied';
                setTimeout(() => {
                    status.textContent = 'Click elements to hide them';
                }, 2000);
            }
            
        } catch (error) {
            console.warn('Invalid selector for rule creation:', selector);
        }
    }

    /**
     * Zap (hide) an element by generating and applying a rule
     */
    zapElement(element) {
        const selector = this.generateSimpleSelector(element);
        this.saveRule(selector);
        this.applyRule(selector);
        
        // Update status
        const status = document.querySelector('.zapper-status');
        if (status) {
            status.textContent = 'Element hidden';
            setTimeout(() => {
                status.textContent = 'Click elements to hide them';
            }, 1500);
        }
    }

    /**
     * Generate a simple CSS selector for an element
     */
    generateSimpleSelector(element) {
        // Try ID first
        if (element.id) {
            return `#${CSS.escape(element.id)}`;
        }
        
        // Try class combination
        if (element.className) {
            const classes = Array.from(element.classList);
            if (classes.length > 0) {
                return `.${classes.map(c => CSS.escape(c)).join('.')}`;
            }
        }
        
        // Try data attributes
        for (const attr of element.attributes) {
            if (attr.name.startsWith('data-') && attr.value) {
                return `[${attr.name}="${CSS.escape(attr.value)}"]`;
            }
        }
        
        // Fall back to tag with nth-child
        const parent = element.parentElement;
        if (parent) {
            const siblings = Array.from(parent.children);
            const index = siblings.indexOf(element) + 1;
            return `${element.tagName.toLowerCase()}:nth-child(${index})`;
        }
        
        return element.tagName.toLowerCase();
    }

    /**
     * Save a hiding rule for the current hostname
     */
    saveRule(selector) {
        const hostname = location.hostname;
        
        // Send message to Safari extension
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zapperController) {
            window.webkit.messageHandlers.zapperController.postMessage({
                action: 'saveRule',
                hostname: hostname,
                selector: selector
            });
        }
        
        console.log(`Saved zapper rule for ${hostname}: ${selector}`);
    }

    /**
     * Apply a hiding rule immediately
     */
    applyRule(selector) {
        let styleElement = document.getElementById('wblock-zapper-rules');
        if (!styleElement) {
            styleElement = document.createElement('style');
            styleElement.id = 'wblock-zapper-rules';
            styleElement.type = 'text/css';
            document.head.appendChild(styleElement);
        }
        
        const rule = `${selector} { display: none !important; }`;
        styleElement.textContent += rule + '\n';
        
        console.log(`Applied zapper rule: ${selector}`);
    }

    /**
     * Load existing rules for the current hostname
     */
    loadRulesForHostname() {
        const hostname = location.hostname;
        
        // Send message to Safari extension
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zapperController) {
            window.webkit.messageHandlers.zapperController.postMessage({
                action: 'loadRules',
                hostname: hostname
            });
        }
    }

    /**
     * Apply loaded rules from the extension
     */
    applyLoadedRules(rules) {
        if (!Array.isArray(rules)) return;
        
        let styleElement = document.getElementById('wblock-zapper-rules');
        if (!styleElement) {
            styleElement = document.createElement('style');
            styleElement.id = 'wblock-zapper-rules';
            styleElement.type = 'text/css';
            document.head.appendChild(styleElement);
        }
        
        const cssRules = rules.map(selector => `${selector} { display: none !important; }`).join('\n');
        styleElement.textContent = cssRules;
        
        console.log(`Applied ${rules.length} existing zapper rules for ${location.hostname}`);
    }

    /**
     * Toggle the picker panel visibility
     */
    togglePickerPanel() {
        const panel = document.getElementById('wblock-picker-panel');
        if (panel) {
            panel.classList.toggle('visible');
            this.isPickerMode = panel.classList.contains('visible');
            
            if (this.isPickerMode) {
                this.removeHighlight();
            }
        }
    }

    /**
     * Select an element for the picker (when in picker mode)
     */
    selectElementForPicker(element) {
        this.generateCandidatesForElement(element);
        
        const selectorInput = document.getElementById('selector-input');
        if (selectorInput && this.candidates.length > 0) {
            selectorInput.value = this.candidates[0];
            this.onSelectorInput();
        }
    }

    /**
     * Quit the element zapper
     */
    quit() {
        this.isActive = false;
        this.clearPreview();
        this.removeHighlight();
        
        // Remove event listeners
        document.removeEventListener('mouseover', this.onMouseOver, true);
        document.removeEventListener('click', this.onClick, true);
        document.removeEventListener('mouseout', this.onMouseOut, true);
        
        // Remove overlay
        if (this.overlay && this.overlay.parentNode) {
            this.overlay.parentNode.removeChild(this.overlay);
        }
        
        // Send quit message to extension
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zapperController) {
            window.webkit.messageHandlers.zapperController.postMessage({
                action: 'quit'
            });
        }
        
        console.log('wBlock Element Zapper deactivated');
    }
}

// Listen for messages from the extension
window.addEventListener('message', function(event) {
    if (event.data && event.data.action === 'loadRulesResponse') {
        if (window.wblockZapper) {
            window.wblockZapper.applyLoadedRules(event.data.rules);
        }
    }
});

// Initialize when loaded
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
        window.wblockZapper = new WBlockElementZapper();
    });
} else {
    window.wblockZapper = new WBlockElementZapper();
}

// Export for external access
window.WBlockElementZapper = WBlockElementZapper;
