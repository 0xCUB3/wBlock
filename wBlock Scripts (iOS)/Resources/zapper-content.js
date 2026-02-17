// wBlock Element Zapper (WebExtension content script)
//
// - Persists per-site CSS selectors in browser.storage.local
// - Applies saved selectors on every page load
// - Provides an in-page picker UI when activated from the extension popup

(function () {
  'use strict';

  const STORAGE_PREFIX = 'wblock.zapperRules.v1:';
  const STYLE_ID = 'wblock-zapper-style';
  const UI_STYLE_ID = 'wblock-zapper-ui-style';
  const UI_ROOT_ID = 'wblock-zapper-root';
  const HIGHLIGHT_ID = 'wblock-zapper-highlight';
  const TOAST_ID = 'wblock-zapper-toast';
  const MAX_RULES_PER_SITE = 200;

  const state = {
    active: false,
    host: '',
    rules: [],
    lastAddedSelector: null,
    lastPickAt: 0,
    candidateElement: null,
    traversalPath: [],
    cleanupFns: [],
    ui: {
      root: null,
      highlight: null,
      toast: null,
      statusText: null,
      undoButton: null,
      manualButton: null,
      doneButton: null,
      parentButton: null,
      childButton: null,
      hideButton: null,
      navGroup: null,
      defaultGroup: null,
    },
  };

  function safeHostname() {
    try {
      return typeof location !== 'undefined' ? (location.hostname || '') : '';
    } catch {
      return '';
    }
  }

  function storageKey(host) {
    return `${STORAGE_PREFIX}${host}`;
  }

  async function loadRulesForHost(host) {
    if (!host) return [];
    try {
      const key = storageKey(host);
      const result = await browser.storage.local.get(key);
      const value = result[key];
      if (!Array.isArray(value)) return [];
      return value
        .filter((s) => typeof s === 'string')
        .map((s) => s.trim())
        .filter((s) => s.length > 0);
    } catch {
      return [];
    }
  }

  async function saveRulesForHost(host, rules) {
    if (!host) return;
    const key = storageKey(host);
    const unique = Array.from(new Set(rules)).slice(0, MAX_RULES_PER_SITE);
    await browser.storage.local.set({ [key]: unique });
  }

  function ensureStyleElement(id) {
    let style = document.getElementById(id);
    if (!style) {
      style = document.createElement('style');
      style.id = id;
      (document.documentElement || document).appendChild(style);
    }
    return style;
  }

  function buildHideCss(selectors) {
    return selectors.map((sel) => `${sel} { display: none !important; }`).join('\n');
  }

  function applyRulesToPage(rules) {
    const style = ensureStyleElement(STYLE_ID);
    style.textContent = buildHideCss(rules);
  }

  function cssEscape(value) {
    try {
      if (window.CSS && typeof window.CSS.escape === 'function') {
        return window.CSS.escape(value);
      }
    } catch {}
    return String(value).replace(/[^a-zA-Z0-9_-]/g, (ch) => `\\${ch}`);
  }

  function isUniqueSelector(selector) {
    try {
      return document.querySelectorAll(selector).length === 1;
    } catch {
      return false;
    }
  }

  function selectorForElement(element) {
    if (!(element instanceof Element)) return null;
    if (element === document.documentElement || element === document.body) return null;
    if (element.id) {
      const idSel = `#${cssEscape(element.id)}`;
      if (isUniqueSelector(idSel)) return idSel;
    }

    const tag = element.tagName.toLowerCase();
    const classes = Array.from(element.classList || []).filter(Boolean).slice(0, 3);
    if (classes.length > 0) {
      const classSel = `${tag}${classes.map((c) => `.${cssEscape(c)}`).join('')}`;
      if (isUniqueSelector(classSel)) return classSel;
    }

    const segments = [];
    let current = element;
    let depth = 0;
    while (current && current instanceof Element && current !== document.documentElement && depth < 12) {
      const currentTag = current.tagName.toLowerCase();
      let segment = currentTag;

      const currentId = current.id ? `#${cssEscape(current.id)}` : '';
      if (currentId) {
        const candidate = `${currentTag}${currentId}`;
        if (isUniqueSelector(candidate)) return candidate;
      }

      const currentClasses = Array.from(current.classList || []).filter(Boolean).slice(0, 1);
      if (currentClasses.length) {
        segment += `.${cssEscape(currentClasses[0])}`;
      }

      const parent = current.parentElement;
      if (parent) {
        const siblingsOfType = Array.from(parent.children).filter(
          (child) => child.tagName === current.tagName
        );
        if (siblingsOfType.length > 1) {
          const index = siblingsOfType.indexOf(current) + 1;
          segment += `:nth-of-type(${index})`;
        }
      }

      segments.unshift(segment);
      const candidatePath = segments.join(' > ');
      if (isUniqueSelector(candidatePath)) return candidatePath;

      current = current.parentElement;
      depth += 1;
    }

    const fallback = segments.join(' > ');
    return fallback || null;
  }

  function shouldIgnoreTarget(target) {
    if (!(target instanceof Element)) return false;
    if (target.id === STYLE_ID || target.id === UI_STYLE_ID) return true;
    return Boolean(target.closest && target.closest(`#${UI_ROOT_ID}`));
  }

  function ensureUi() {
    if (state.ui.root) return;

    const uiStyle = ensureStyleElement(UI_STYLE_ID);
    uiStyle.textContent = `
      #${UI_ROOT_ID} { position: fixed; left: 12px; right: 12px; bottom: calc(12px + env(safe-area-inset-bottom)); z-index: 2147483647; font-family: -apple-system, system-ui, sans-serif; touch-action: none; }
      #${UI_ROOT_ID} .wblock-bar { display: flex; gap: 10px; align-items: center; justify-content: space-between; padding: 12px 14px; border-radius: 16px; backdrop-filter: blur(16px); background: rgba(20, 20, 22, 0.78); color: #fff; box-shadow: 0 10px 30px rgba(0,0,0,0.35); cursor: grab; }
      #${UI_ROOT_ID} .wblock-bar.wblock-dragging { cursor: grabbing; }
      #${UI_ROOT_ID} .wblock-drag-hint { width: 36px; height: 4px; border-radius: 2px; background: rgba(255,255,255,0.3); margin: 0 auto 6px; }
      #${UI_ROOT_ID} .wblock-status { font-size: 13px; line-height: 1.35; flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      #${UI_ROOT_ID} .wblock-actions { display: flex; gap: 10px; }
      #${UI_ROOT_ID} button { appearance: none; display: inline-flex; align-items: center; justify-content: center; border: 0; border-radius: 11px; padding: 10px 12px; min-height: 40px; line-height: 1.1; font-size: 13px; font-weight: 650; color: #fff; background: rgba(255,255,255,0.14); touch-action: manipulation; -webkit-tap-highlight-color: transparent; white-space: nowrap; flex-shrink: 0; }
      #${UI_ROOT_ID} button:disabled { opacity: 0.5; }
      #${UI_ROOT_ID} .wblock-nav { display: none; gap: 10px; }
      #${UI_ROOT_ID} .wblock-nav.wblock-active { display: flex; }
      @media (max-width: 430px) {
        #${UI_ROOT_ID} .wblock-bar { flex-direction: column; align-items: stretch; }
        #${UI_ROOT_ID} .wblock-status { font-size: 14px; }
        #${UI_ROOT_ID} .wblock-actions { width: 100%; }
        #${UI_ROOT_ID} .wblock-actions button { flex-grow: 1; min-height: 44px; }
      }
      #${HIGHLIGHT_ID} { position: fixed; pointer-events: none; z-index: 2147483646; border: 2px solid rgba(249,115,22,0.95); background: rgba(249,115,22,0.12); border-radius: 6px; transform: translate3d(0,0,0); }
      #${TOAST_ID} { position: absolute; left: 0; right: 0; bottom: 100%; margin-bottom: 8px; z-index: 2147483647; display: none; justify-content: center; pointer-events: none; }
      #${TOAST_ID} .wblock-toast-inner { max-width: 520px; padding: 12px 14px; border-radius: 12px; background: rgba(20, 20, 22, 0.82); color: #fff; font-size: 13px; box-shadow: 0 10px 30px rgba(0,0,0,0.35); text-align: center; }
    `.trim();

    const root = document.createElement('div');
    root.id = UI_ROOT_ID;
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-label', 'wBlock Element Zapper');

    const dragHint = document.createElement('div');
    dragHint.className = 'wblock-drag-hint';

    const bar = document.createElement('div');
    bar.className = 'wblock-bar';

    const status = document.createElement('div');
    status.className = 'wblock-status';
    status.textContent = 'Element Zapper: Tap an element to hide it.';

    const actions = document.createElement('div');
    actions.className = 'wblock-actions';

    const undoButton = document.createElement('button');
    undoButton.type = 'button';
    undoButton.textContent = 'Undo';
    undoButton.disabled = true;
    const onUndo = (e) => {
      if (e) {
        e.preventDefault();
        e.stopPropagation();
        if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();
      }
      undoLastZap().catch(() => {});
    };
    undoButton.addEventListener('click', onUndo);
    undoButton.addEventListener('pointerup', onUndo, true);
    undoButton.addEventListener('touchend', onUndo, { passive: false });

    const manualButton = document.createElement('button');
    manualButton.type = 'button';
    manualButton.textContent = 'Add Rule';
    const onManualRule = (e) => {
      if (e) {
        e.preventDefault();
        e.stopPropagation();
        if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();
      }
      addManualRuleFromPrompt().catch(() => {});
    };
    manualButton.addEventListener('click', onManualRule);
    manualButton.addEventListener('pointerup', onManualRule, true);
    manualButton.addEventListener('touchend', onManualRule, { passive: false });

    const doneButton = document.createElement('button');
    doneButton.type = 'button';
    doneButton.textContent = 'Done';
    const onDone = (e) => {
      if (e) {
        e.preventDefault();
        e.stopPropagation();
        if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();
      }
      // Delay teardown until after the current input/click sequence completes
      // so we don't accidentally retarget the synthetic click to the page.
      setTimeout(() => deactivateZapper({ removeUi: true }), 0);
    };
    doneButton.addEventListener('click', onDone);
    doneButton.addEventListener('pointerup', onDone, true);
    doneButton.addEventListener('touchend', onDone, { passive: false });

    const defaultGroup = document.createElement('span');
    defaultGroup.className = 'wblock-default';
    defaultGroup.style.display = 'flex';
    defaultGroup.style.gap = '10px';
    defaultGroup.appendChild(undoButton);
    defaultGroup.appendChild(manualButton);

    const navGroup = document.createElement('span');
    navGroup.className = 'wblock-nav';

    const parentButton = document.createElement('button');
    parentButton.type = 'button';
    parentButton.textContent = '\u25B2';
    parentButton.title = 'Select parent element';
    parentButton.disabled = true;
    const onParent = (e) => {
      if (e) { e.preventDefault(); e.stopPropagation(); if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation(); }
      navigateParent();
    };
    parentButton.addEventListener('click', onParent);
    parentButton.addEventListener('pointerup', onParent, true);
    parentButton.addEventListener('touchend', onParent, { passive: false });

    const childButton = document.createElement('button');
    childButton.type = 'button';
    childButton.textContent = '\u25BC';
    childButton.title = 'Select child element';
    childButton.disabled = true;
    const onChild = (e) => {
      if (e) { e.preventDefault(); e.stopPropagation(); if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation(); }
      navigateChild();
    };
    childButton.addEventListener('click', onChild);
    childButton.addEventListener('pointerup', onChild, true);
    childButton.addEventListener('touchend', onChild, { passive: false });

    const hideButton = document.createElement('button');
    hideButton.type = 'button';
    hideButton.textContent = '\u2713 Hide';
    const onHide = (e) => {
      if (e) { e.preventDefault(); e.stopPropagation(); if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation(); }
      confirmHide();
    };
    hideButton.addEventListener('click', onHide);
    hideButton.addEventListener('pointerup', onHide, true);
    hideButton.addEventListener('touchend', onHide, { passive: false });

    navGroup.appendChild(parentButton);
    navGroup.appendChild(childButton);
    navGroup.appendChild(hideButton);

    actions.appendChild(defaultGroup);
    actions.appendChild(navGroup);
    actions.appendChild(doneButton);
    bar.appendChild(status);
    bar.appendChild(actions);
    root.appendChild(dragHint);
    root.appendChild(bar);

    const highlight = document.createElement('div');
    highlight.id = HIGHLIGHT_ID;
    highlight.style.display = 'none';

    const toast = document.createElement('div');
    toast.id = TOAST_ID;
    const toastInner = document.createElement('div');
    toastInner.className = 'wblock-toast-inner';
    toast.appendChild(toastInner);

    state.ui.root = root;
    state.ui.highlight = highlight;
    state.ui.toast = toast;
    state.ui.statusText = status;
    state.ui.undoButton = undoButton;
    state.ui.manualButton = manualButton;
    state.ui.doneButton = doneButton;
    state.ui.parentButton = parentButton;
    state.ui.childButton = childButton;
    state.ui.hideButton = hideButton;
    state.ui.navGroup = navGroup;
    state.ui.defaultGroup = defaultGroup;

    // --- Drag-to-move logic ---
    let dragStartY = 0;
    let rootStartBottom = 0;
    let isDragging = false;

    function startDrag(clientY) {
      isDragging = true;
      dragStartY = clientY;
      const computed = parseFloat(getComputedStyle(root).bottom) || 12;
      rootStartBottom = computed;
      bar.classList.add('wblock-dragging');
    }

    function moveDrag(clientY) {
      if (!isDragging) return;
      const delta = dragStartY - clientY;
      const maxBottom = window.innerHeight - root.offsetHeight - 4;
      const newBottom = Math.max(4, Math.min(maxBottom, rootStartBottom + delta));
      root.style.bottom = `${newBottom}px`;
    }

    function endDrag() {
      if (!isDragging) return;
      isDragging = false;
      bar.classList.remove('wblock-dragging');
    }

    const onBarPointerDown = (e) => {
      if (e.target.closest('button')) return;
      e.preventDefault();
      startDrag(e.clientY);
    };
    const onBarTouchStart = (e) => {
      if (e.target.closest('button')) return;
      if (e.touches.length !== 1) return;
      startDrag(e.touches[0].clientY);
    };
    const onDocPointerMove = (e) => { if (isDragging) { e.preventDefault(); moveDrag(e.clientY); } };
    const onDocTouchMove = (e) => { if (isDragging && e.touches[0]) { e.preventDefault(); moveDrag(e.touches[0].clientY); } };
    const onDocPointerUp = () => endDrag();
    const onDocTouchEnd = () => endDrag();

    bar.addEventListener('pointerdown', onBarPointerDown);
    bar.addEventListener('touchstart', onBarTouchStart, { passive: false });
    document.addEventListener('pointermove', onDocPointerMove, { passive: false });
    document.addEventListener('touchmove', onDocTouchMove, { passive: false });
    document.addEventListener('pointerup', onDocPointerUp);
    document.addEventListener('touchend', onDocTouchEnd);

    state.cleanupFns.push(
      () => bar.removeEventListener('pointerdown', onBarPointerDown),
      () => bar.removeEventListener('touchstart', onBarTouchStart, { passive: false }),
      () => document.removeEventListener('pointermove', onDocPointerMove, { passive: false }),
      () => document.removeEventListener('touchmove', onDocTouchMove, { passive: false }),
      () => document.removeEventListener('pointerup', onDocPointerUp),
      () => document.removeEventListener('touchend', onDocTouchEnd),
    );

    root.appendChild(toast);
    (document.documentElement || document).appendChild(highlight);
    (document.documentElement || document).appendChild(root);
  }

  function showToast(message) {
    ensureUi();
    const toast = state.ui.toast;
    if (!toast) return;
    const inner = toast.querySelector('.wblock-toast-inner');
    if (inner) inner.textContent = message;
    toast.style.display = 'flex';
    clearTimeout(showToast._timer);
    showToast._timer = setTimeout(() => {
      toast.style.display = 'none';
    }, 1400);
  }

  function setHighlightForElement(element) {
    ensureUi();
    const highlight = state.ui.highlight;
    if (!highlight) return;
    if (!(element instanceof Element) || shouldIgnoreTarget(element)) {
      highlight.style.display = 'none';
      return;
    }
    const rect = element.getBoundingClientRect();
    if (!rect || rect.width <= 0 || rect.height <= 0) {
      highlight.style.display = 'none';
      return;
    }
    if (rect.bottom <= 0 || rect.top >= window.innerHeight ||
        rect.right <= 0 || rect.left >= window.innerWidth) {
      highlight.style.display = 'none';
      return;
    }
    highlight.style.display = 'block';
    highlight.style.top = `${Math.max(0, rect.top)}px`;
    highlight.style.left = `${Math.max(0, rect.left)}px`;
    highlight.style.width = `${Math.max(0, rect.width)}px`;
    highlight.style.height = `${Math.max(0, rect.height)}px`;
  }

  function clearHighlight() {
    if (state.ui.highlight) state.ui.highlight.style.display = 'none';
  }

  function getPointFromEvent(event) {
    if (event && typeof event.clientX === 'number' && typeof event.clientY === 'number') {
      return { x: event.clientX, y: event.clientY };
    }
    if (event && event.touches && event.touches[0]) {
      return { x: event.touches[0].clientX, y: event.touches[0].clientY };
    }
    return null;
  }

  function elementFromEvent(event) {
    const point = getPointFromEvent(event);
    if (!point) return null;
    try {
      return document.elementFromPoint(point.x, point.y);
    } catch {
      return null;
    }
  }

  function isValidCssSelector(selector) {
    try {
      document.createDocumentFragment().querySelector(selector);
      return true;
    } catch {
      return false;
    }
  }

  function parseManualRuleInput(input) {
    const raw = String(input || '').trim();
    if (!raw) {
      return { selector: '', error: 'Enter a CSS selector.' };
    }

    let selector = raw;
    if (raw.includes('{')) {
      const openIndex = raw.indexOf('{');
      const closeIndex = raw.lastIndexOf('}');
      if (closeIndex <= openIndex) {
        return { selector: '', error: 'CSS rule syntax is invalid.' };
      }
      if (raw.slice(closeIndex + 1).trim().length > 0) {
        return { selector: '', error: 'CSS rule syntax is invalid.' };
      }
      selector = raw.slice(0, openIndex).trim();
    } else if (raw.includes('}')) {
      return { selector: '', error: 'CSS rule syntax is invalid.' };
    }

    if (!selector) {
      return { selector: '', error: 'Enter a CSS selector.' };
    }
    if (selector.length > 512) {
      return { selector: '', error: 'Selector is too long.' };
    }
    if (!isValidCssSelector(selector)) {
      return { selector: '', error: 'Selector syntax is invalid.' };
    }

    return { selector, error: '' };
  }

  async function addSelectorRule(selector, options = {}) {
    const normalized = (selector || '').trim();
    if (!normalized) return;
    if (state.rules.includes(normalized)) {
      showToast(options.manual ? 'Rule already exists.' : 'Already hidden.');
      return;
    }
    state.rules = state.rules.concat([normalized]).slice(0, MAX_RULES_PER_SITE);
    state.lastAddedSelector = normalized;
    await saveRulesForHost(state.host, state.rules);
    applyRulesToPage(state.rules);
    if (state.ui.undoButton) state.ui.undoButton.disabled = false;
    showToast(options.manual ? 'Rule saved for this site.' : 'Hidden. Rule saved for this site.');
  }

  async function addManualRuleFromPrompt() {
    const rawInput = window.prompt('Enter CSS selector for this site');
    if (rawInput === null) return;

    const parsed = parseManualRuleInput(rawInput);
    if (parsed.error) {
      showToast(parsed.error);
      return;
    }

    await addSelectorRule(parsed.selector, { manual: true });
  }

  async function undoLastZap() {
    if (!state.lastAddedSelector) return;
    const toRemove = state.lastAddedSelector;
    state.rules = state.rules.filter((r) => r !== toRemove);
    state.lastAddedSelector = null;
    await saveRulesForHost(state.host, state.rules);
    applyRulesToPage(state.rules);
    if (state.ui.undoButton) state.ui.undoButton.disabled = true;
    showToast('Undone.');
  }

  function addCleanup(fn) {
    state.cleanupFns.push(fn);
  }

  function teardownUi() {
    clearTimeout(showToast._timer);

    const root = state.ui.root;
    const highlight = state.ui.highlight;
    const toast = state.ui.toast;

    try {
      if (root && root.parentNode) root.parentNode.removeChild(root);
      if (highlight && highlight.parentNode) highlight.parentNode.removeChild(highlight);
      if (toast && toast.parentNode) toast.parentNode.removeChild(toast);
    } catch {}

    try {
      const uiStyle = document.getElementById(UI_STYLE_ID);
      if (uiStyle && uiStyle.parentNode) uiStyle.parentNode.removeChild(uiStyle);
    } catch {}

    // Fallback: remove any lingering nodes by ID (in case state references changed).
    try {
      const rootEl = document.getElementById(UI_ROOT_ID);
      if (rootEl) rootEl.remove();
      const highlightEl = document.getElementById(HIGHLIGHT_ID);
      if (highlightEl) highlightEl.remove();
      const toastEl = document.getElementById(TOAST_ID);
      if (toastEl) toastEl.remove();
      const uiStyleEl = document.getElementById(UI_STYLE_ID);
      if (uiStyleEl) uiStyleEl.remove();
    } catch {}

    state.ui.root = null;
    state.ui.highlight = null;
    state.ui.toast = null;
    state.ui.statusText = null;
    state.ui.undoButton = null;
    state.ui.manualButton = null;
    state.ui.doneButton = null;
    state.ui.parentButton = null;
    state.ui.childButton = null;
    state.ui.hideButton = null;
    state.ui.navGroup = null;
    state.ui.defaultGroup = null;
  }

  function clearCleanup() {
    const fns = state.cleanupFns.slice();
    state.cleanupFns = [];
    for (const fn of fns) {
      try {
        fn();
      } catch {}
    }
  }

  function interceptEvent(event) {
    if (!event) return;
    event.preventDefault();
    event.stopPropagation();
    if (typeof event.stopImmediatePropagation === 'function') {
      event.stopImmediatePropagation();
    }
  }

  function elementLabel(el) {
    if (!el || !(el instanceof Element)) return '';
    const tag = el.tagName.toLowerCase();
    if (el.id) return `<${tag}#${el.id}>`;
    const cls = Array.from(el.classList || []).filter(Boolean).slice(0, 2).join('.');
    return cls ? `<${tag}.${cls}>` : `<${tag}>`;
  }

  function enterRefineMode(element) {
    state.candidateElement = element;
    state.traversalPath = [];
    setHighlightForElement(element);
    if (state.ui.navGroup) state.ui.navGroup.classList.add('wblock-active');
    if (state.ui.defaultGroup) state.ui.defaultGroup.style.display = 'none';
    updateRefineStatus();
  }

  function exitRefineMode() {
    state.candidateElement = null;
    state.traversalPath = [];
    clearHighlight();
    if (state.ui.navGroup) state.ui.navGroup.classList.remove('wblock-active');
    if (state.ui.defaultGroup) state.ui.defaultGroup.style.display = 'flex';
    if (state.ui.statusText) state.ui.statusText.textContent = 'Element Zapper: Tap an element to hide it.';
  }

  function updateRefineStatus() {
    const el = state.candidateElement;
    if (!el) return;
    const label = elementLabel(el);
    if (state.ui.statusText) state.ui.statusText.textContent = `${label} — ▲▼ to adjust, ✓ to hide`;
    const parent = el.parentElement;
    const atTop = !parent || parent === document.body || parent === document.documentElement;
    if (state.ui.parentButton) state.ui.parentButton.disabled = atTop;
    if (state.ui.childButton) state.ui.childButton.disabled = state.traversalPath.length === 0;
  }

  function navigateParent() {
    const candidate = state.candidateElement;
    if (!candidate) return;
    const parent = candidate.parentElement;
    if (!parent || parent === document.body || parent === document.documentElement) return;
    state.traversalPath.push(candidate);
    state.candidateElement = parent;
    setHighlightForElement(parent);
    updateRefineStatus();
  }

  function navigateChild() {
    if (state.traversalPath.length === 0) return;
    const child = state.traversalPath.pop();
    state.candidateElement = child;
    setHighlightForElement(child);
    updateRefineStatus();
  }

  function confirmHide() {
    const el = state.candidateElement;
    if (!el) return;
    const selector = selectorForElement(el);
    if (!selector) {
      showToast('Unable to create a rule for that element.');
      exitRefineMode();
      return;
    }
    exitRefineMode();
    addSelectorRule(selector).catch(() => {});
  }

  function activateZapper() {
    if (state.active) return;
    ensureUi();
    state.active = true;
    state.lastAddedSelector = null;
    state.lastPickAt = 0;
    state.candidateElement = null;
    state.traversalPath = [];
    state.lastPointerX = -1;
    state.lastPointerY = -1;
    state.isScrolling = false;
    if (state.ui.undoButton) state.ui.undoButton.disabled = true;
    if (state.ui.navGroup) state.ui.navGroup.classList.remove('wblock-active');
    if (state.ui.defaultGroup) state.ui.defaultGroup.style.display = 'flex';
    if (state.ui.statusText) state.ui.statusText.textContent = 'Element Zapper: Tap an element to hide it.';
    showToast('Element Zapper enabled.');

    const onMove = (event) => {
      if (!state.active) return;
      if (state.candidateElement) return;
      if (state.ui.root && event && event.target && state.ui.root.contains(event.target)) return;
      const point = getPointFromEvent(event);
      if (point) {
        state.lastPointerX = point.x;
        state.lastPointerY = point.y;
      }
      const el = elementFromEvent(event);
      if (!el || shouldIgnoreTarget(el)) return;
      setHighlightForElement(el);
    };

    const pickFromEvent = (event) => {
      if (!state.active) return;
      if (state.isScrolling) return;
      if (state.ui.root && event && event.target && state.ui.root.contains(event.target)) return;
      const now = Date.now();
      if (now - state.lastPickAt < 120) return;
      const el = elementFromEvent(event);
      if (!el || shouldIgnoreTarget(el)) return;
      interceptEvent(event);
      state.lastPickAt = now;
      enterRefineMode(el);
    };

    // Prevent navigation/actions that fire on click (e.g. <a href=...>) while
    // the zapper is active. On iOS Safari, preventing pointer/touch events
    // alone does not always cancel the subsequent click.
    const onClick = (event) => {
      if (!state.active) return;
      if (state.ui.root && event && event.target && state.ui.root.contains(event.target)) return;
      interceptEvent(event);

      const now = Date.now();
      if (now - state.lastPickAt < 350) return;
      pickFromEvent(event);
    };

    const onKeyDown = (event) => {
      if (!state.active) return;
      if (!event) return;
      if (event.key === 'Escape') {
        interceptEvent(event);
        if (state.candidateElement) {
          exitRefineMode();
        } else {
          deactivateZapper();
        }
        return;
      }
      if (event.key === 'ArrowUp') {
        interceptEvent(event);
        navigateParent();
        return;
      }
      if (event.key === 'ArrowDown') {
        interceptEvent(event);
        navigateChild();
        return;
      }
      if (event.key === 'Enter' && state.candidateElement) {
        interceptEvent(event);
        confirmHide();
        return;
      }
      if ((event.ctrlKey || event.metaKey) && (event.key === 'z' || event.key === 'Z')) {
        interceptEvent(event);
        undoLastZap().catch(() => {});
      }
    };

    const moveEvent = 'PointerEvent' in window ? 'pointermove' : 'mousemove';
    const downEvent = 'PointerEvent' in window ? 'pointerdown' : 'mousedown';
    const touchOptions = { capture: true, passive: false };

    document.addEventListener(moveEvent, onMove, true);
    document.addEventListener(downEvent, pickFromEvent, true);
    document.addEventListener('click', onClick, true);
    // Ensure preventDefault works for touch-driven clicks.
    document.addEventListener('touchstart', pickFromEvent, touchOptions);
    document.addEventListener('keydown', onKeyDown, true);

    addCleanup(() => document.removeEventListener(moveEvent, onMove, true));
    addCleanup(() => document.removeEventListener(downEvent, pickFromEvent, true));
    addCleanup(() => document.removeEventListener('click', onClick, true));
    addCleanup(() => document.removeEventListener('touchstart', pickFromEvent, touchOptions));
    addCleanup(() => document.removeEventListener('keydown', onKeyDown, true));

    let scrollTimer = 0;
    const onScroll = () => {
      if (!state.active) return;
      state.isScrolling = true;
      clearTimeout(scrollTimer);
      scrollTimer = setTimeout(() => { state.isScrolling = false; }, 150);
      if (state.candidateElement) {
        setHighlightForElement(state.candidateElement);
      } else if (state.lastPointerX >= 0 && state.lastPointerY >= 0) {
        try {
          const el = document.elementFromPoint(state.lastPointerX, state.lastPointerY);
          if (el && !shouldIgnoreTarget(el)) {
            setHighlightForElement(el);
          }
        } catch {}
      }
    };

    window.addEventListener('scroll', onScroll, { capture: true, passive: true });
    addCleanup(() => {
      window.removeEventListener('scroll', onScroll, true);
      clearTimeout(scrollTimer);
      state.isScrolling = false;
    });
  }

  function deactivateZapper(options = {}) {
    const removeUi = Boolean(options.removeUi);
    if (!state.active && !removeUi) return;
    state.active = false;
    state.candidateElement = null;
    state.traversalPath = [];
    clearCleanup();
    clearHighlight();
    if (removeUi) {
      teardownUi();
      return;
    }

    showToast('Element Zapper disabled.');
    if (state.ui.statusText) state.ui.statusText.textContent = 'Element Zapper: Off';
  }

  async function reloadRulesAndApply() {
    state.host = safeHostname();
    state.rules = await loadRulesForHost(state.host);
    applyRulesToPage(state.rules);
  }

  browser.runtime.onMessage.addListener((message) => {
    if (!message || typeof message !== 'object') return;

    if (message.type === 'wblock:zapper:activate') {
      activateZapper();
      return;
    }
    if (message.type === 'wblock:zapper:deactivate') {
      deactivateZapper({ removeUi: true });
      return;
    }
    if (message.type === 'wblock:zapper:reloadRules') {
      reloadRulesAndApply().catch(() => {});
      return;
    }
  });

  // Initial load: apply existing rules for this host.
  reloadRulesAndApply().catch(() => {});
})();
