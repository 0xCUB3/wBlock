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
    cleanupFns: [],
    ui: {
      root: null,
      highlight: null,
      toast: null,
      statusText: null,
      undoButton: null,
      doneButton: null,
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
      #${UI_ROOT_ID} { position: fixed; left: 12px; right: 12px; bottom: 12px; z-index: 2147483647; font-family: -apple-system, system-ui, sans-serif; }
      #${UI_ROOT_ID} .wblock-bar { display: flex; gap: 8px; align-items: center; justify-content: space-between; padding: 10px 12px; border-radius: 14px; backdrop-filter: blur(16px); background: rgba(20, 20, 22, 0.78); color: #fff; box-shadow: 0 10px 30px rgba(0,0,0,0.35); }
      #${UI_ROOT_ID} .wblock-status { font-size: 12px; line-height: 1.2; flex: 1; min-width: 0; }
      #${UI_ROOT_ID} .wblock-actions { display: flex; gap: 8px; }
      #${UI_ROOT_ID} button { appearance: none; border: 0; border-radius: 10px; padding: 8px 10px; font-size: 12px; font-weight: 600; color: #fff; background: rgba(255,255,255,0.14); }
      #${UI_ROOT_ID} button:disabled { opacity: 0.5; }
      #${HIGHLIGHT_ID} { position: fixed; pointer-events: none; z-index: 2147483646; border: 2px solid rgba(249,115,22,0.95); background: rgba(249,115,22,0.12); border-radius: 6px; }
      #${TOAST_ID} { position: fixed; left: 12px; right: 12px; bottom: 72px; z-index: 2147483647; display: none; justify-content: center; pointer-events: none; }
      #${TOAST_ID} .wblock-toast-inner { max-width: 520px; padding: 10px 12px; border-radius: 12px; background: rgba(20, 20, 22, 0.82); color: #fff; font-size: 12px; box-shadow: 0 10px 30px rgba(0,0,0,0.35); text-align: center; }
    `.trim();

    const root = document.createElement('div');
    root.id = UI_ROOT_ID;
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-label', 'wBlock Element Zapper');

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
    undoButton.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      undoLastZap().catch(() => {});
    });

    const doneButton = document.createElement('button');
    doneButton.type = 'button';
    doneButton.textContent = 'Done';
    doneButton.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      deactivateZapper();
    });

    actions.appendChild(undoButton);
    actions.appendChild(doneButton);
    bar.appendChild(status);
    bar.appendChild(actions);
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
    state.ui.doneButton = doneButton;

    (document.documentElement || document).appendChild(highlight);
    (document.documentElement || document).appendChild(toast);
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

  async function addSelectorRule(selector) {
    const normalized = (selector || '').trim();
    if (!normalized) return;
    if (state.rules.includes(normalized)) {
      showToast('Already hidden.');
      return;
    }
    state.rules = state.rules.concat([normalized]).slice(0, MAX_RULES_PER_SITE);
    state.lastAddedSelector = normalized;
    await saveRulesForHost(state.host, state.rules);
    applyRulesToPage(state.rules);
    if (state.ui.undoButton) state.ui.undoButton.disabled = false;
    showToast('Hidden. Rule saved for this site.');
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

  function activateZapper() {
    if (state.active) return;
    ensureUi();
    state.active = true;
    state.lastAddedSelector = null;
    if (state.ui.undoButton) state.ui.undoButton.disabled = true;
    if (state.ui.statusText) state.ui.statusText.textContent = 'Element Zapper: Tap an element to hide it.';
    showToast('Element Zapper enabled.');

    const onMove = (event) => {
      if (!state.active) return;
      if (state.ui.root && event && event.target && state.ui.root.contains(event.target)) return;
      const el = elementFromEvent(event);
      if (!el || shouldIgnoreTarget(el)) return;
      setHighlightForElement(el);
    };

    const onDown = (event) => {
      if (!state.active) return;
      if (state.ui.root && event && event.target && state.ui.root.contains(event.target)) return;
      const el = elementFromEvent(event);
      if (!el || shouldIgnoreTarget(el)) return;
      interceptEvent(event);
      const selector = selectorForElement(el);
      if (!selector) {
        showToast('Unable to create a rule for that element.');
        return;
      }
      addSelectorRule(selector).catch(() => {});
    };

    const onKeyDown = (event) => {
      if (!state.active) return;
      if (!event) return;
      if (event.key === 'Escape') {
        interceptEvent(event);
        deactivateZapper();
        return;
      }
      if ((event.ctrlKey || event.metaKey) && (event.key === 'z' || event.key === 'Z')) {
        interceptEvent(event);
        undoLastZap().catch(() => {});
      }
    };

    const moveEvent = 'PointerEvent' in window ? 'pointermove' : 'mousemove';
    const downEvent = 'PointerEvent' in window ? 'pointerdown' : 'mousedown';

    document.addEventListener(moveEvent, onMove, true);
    document.addEventListener(downEvent, onDown, true);
    document.addEventListener('keydown', onKeyDown, true);

    addCleanup(() => document.removeEventListener(moveEvent, onMove, true));
    addCleanup(() => document.removeEventListener(downEvent, onDown, true));
    addCleanup(() => document.removeEventListener('keydown', onKeyDown, true));
  }

  function deactivateZapper() {
    if (!state.active) return;
    state.active = false;
    clearCleanup();
    clearHighlight();
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
      deactivateZapper();
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

