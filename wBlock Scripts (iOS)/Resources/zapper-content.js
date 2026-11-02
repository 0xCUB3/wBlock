// wBlock Element Zapper (WebExtension content script)
//
// - Persists per-site CSS selectors in browser.storage.local
// - Applies saved selectors on every page load
// - Provides an in-page picker UI when activated from the extension popup

(function () {
  'use strict';

  if (typeof browser === 'undefined' || !browser.runtime || !browser.runtime.sendMessage || !browser.runtime.onMessage) {
    return;
  }

  // One copy per document. A second copy would build its own panel and its
  // own click interceptor, which swallows clicks meant for the first panel.
  if (window.__wblockZapperLoaded) return;
  window.__wblockZapperLoaded = true;

  const STORAGE_PREFIX = 'wblock.zapperRules.v1:';
  const META_PREFIX = 'wblock.zapperMeta.v1:';
  const STYLE_ID = 'wblock-zapper-style';
  const UI_STYLE_ID = 'wblock-zapper-ui-style';
  const UI_ROOT_ID = 'wblock-zapper-root';
  const HIGHLIGHT_ID = 'wblock-zapper-highlight';
  const TOAST_ID = 'wblock-zapper-toast';
  const TEMP_STYLE_ID = 'wblock-zapper-temp-style';
  const MAX_RULES_PER_SITE = 200;
  // Native state changes are pushed through the background port. Keep only a
  // coarse top-frame fallback for Safari sessions where that port is lost.
  const RULE_SYNC_FALLBACK_INTERVAL_MS = 5 * 60 * 1000;
  const NATIVE_MESSAGE_TIMEOUT_MS = 3500;

  function t(key, substitutions, fallback = '') {
    const message = browser.i18n.getMessage(key, substitutions);
    if (typeof message === 'string' && message.length > 0) {
      return message;
    }
    return fallback;
  }

  function withTimeout(promise, timeoutMs, message = 'Operation timed out.') {
    let timer = null;
    return Promise.race([
      Promise.resolve(promise).finally(() => {
        if (timer !== null) clearTimeout(timer);
      }),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(message)), timeoutMs);
      }),
    ]);
  }

  const state = {
    active: false,
    host: '',
    rules: [],
    inheritedRules: [],
    tempRules: [],
    undoStack: [],
    lastPickAt: 0,
    candidateElement: null,
    traversalPath: [],
    cleanupFns: [],
    ui: {
      root: null,
      highlight: null,
      toast: null,
      undoButton: null,
      addRuleButton: null,
      hideOnceButton: null,
    },
    rulesDisabled: false,
  };

  let ruleSyncIntervalId = null;
  let ruleSyncInFlight = false;
  let ruleReloadPromise = null;
  let ruleReloadPending = false;
  let ruleReloadActive = false;
  let isFinalizingSession = false;
  const pendingSaveOperations = new Set();

  function trackPendingSave(operationPromise) {
    let trackedPromise;
    trackedPromise = Promise.resolve(operationPromise)
      .catch(() => {})
      .finally(() => {
        pendingSaveOperations.delete(trackedPromise);
      });
    pendingSaveOperations.add(trackedPromise);
    return trackedPromise;
  }

  async function waitForPendingSaves(timeoutMs = 1500) {
    if (pendingSaveOperations.size === 0) return;
    const pending = Array.from(pendingSaveOperations);
    await Promise.race([
      Promise.allSettled(pending),
      new Promise((resolve) => setTimeout(resolve, timeoutMs))
    ]);
  }

  async function finalizeSession() {
    if (isFinalizingSession) return;
    isFinalizingSession = true;

    try {
      await waitForPendingSaves();
      // Delay teardown until after the current input/click sequence completes
      // so we don't accidentally retarget the synthetic click to the page.
      await new Promise((resolve) => setTimeout(resolve, 0));
      // The hide stylesheet stays in place, so no page reload is needed;
      // the native content blocker rules take over on the next navigation.
      deactivateZapper({ removeUi: true });
    } catch {
      deactivateZapper({ removeUi: true });
    } finally {
      isFinalizingSession = false;
    }
  }

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

  function metaKey(host) {
    return `${META_PREFIX}${host}`;
  }

  async function setSiteZapperDisabled(host, disabled) {
    if (!host) return null;
    try {
      return await withTimeout(browser.runtime.sendMessage({
        action: 'wblock:zapper:setDisabled',
        hostname: host,
        disabled: Boolean(disabled)
      }), NATIVE_MESSAGE_TIMEOUT_MS, 'Zapper state update timed out.');
    } catch {
      return null;
    }
  }

  async function migrateLegacyZapperRulesDisabled(host, rules = null) {
    if (!host) return false;
    const key = `wblock.zapperRulesDisabled.v1:${host}`;
    try {
      const result = await browser.storage.local.get(key);
      if (result[key] !== true) {
        return false;
      }
      if (Array.isArray(rules) && rules.length > 0) {
        await syncRulesToNative(host, rules);
      }
      const response = await setSiteZapperDisabled(host, true);
      await browser.storage.local.remove(key);
      return Boolean(response && response.disabled);
    } catch {
      return false;
    }
  }

  async function getSiteDisabledState(host) {
    if (!host) return false;
    try {
      const response = await withTimeout(browser.runtime.sendMessage({
        action: 'wblock:getSiteDisabledState',
        host
      }), NATIVE_MESSAGE_TIMEOUT_MS, 'Site state lookup timed out.');
      if (!response || response.ok !== true || typeof response.disabled !== 'boolean') {
        return null;
      }
      return Boolean(response && response.disabled);
    } catch {
      return null;
    }
  }

  async function shouldSuppressZapperRules(host) {
    if (state.rulesDisabled === true) return true;
    const siteDisabled = await getSiteDisabledState(host);
    // Unknown must not reactivate rules on a site that may be globally disabled.
    return siteDisabled !== false;
  }

  function normalizeRules(rules) {
    return Array.from(new Set(
      (rules || [])
        .filter((s) => typeof s === 'string')
        .map((s) => s.trim())
        .filter((s) => s.length > 0)
    ));
  }

  function rulesSignature(rules) {
    return normalizeRules(rules).join('\u001f');
  }

  function normalizeMeta(raw) {
    if (!raw || typeof raw !== 'object') {
      return { pendingSync: false, lastLocalEditAt: 0, lastSyncAt: 0, disabled: false };
    }
    const lastLocalEditAt = Number(raw.lastLocalEditAt);
    const lastSyncAt = Number(raw.lastSyncAt);
    return {
      pendingSync: Boolean(raw.pendingSync),
      lastLocalEditAt: Number.isFinite(lastLocalEditAt) ? lastLocalEditAt : 0,
      lastSyncAt: Number.isFinite(lastSyncAt) ? lastSyncAt : 0,
      disabled: raw.disabled === true
    };
  }

  async function getSyncMeta(host) {
    if (!host) return { pendingSync: false, lastLocalEditAt: 0, lastSyncAt: 0, disabled: false };
    try {
      const key = metaKey(host);
      const result = await browser.storage.local.get(key);
      return normalizeMeta(result[key]);
    } catch {
      return { pendingSync: false, lastLocalEditAt: 0, lastSyncAt: 0, disabled: false };
    }
  }

  async function loadCachedRulesDisabled(host) {
    if (!host) return false;
    return (await getSyncMeta(host)).disabled === true;
  }

  async function cacheZapperState(host, rules, disabled) {
    if (!host) return;
    const key = storageKey(host);
    await browser.storage.local.set({ [key]: normalizeRules(rules) });
    await setSyncMeta(host, {
      pendingSync: false,
      lastSyncAt: Date.now(),
      disabled: disabled === true
    });
  }

  function normalizeNativeZapperState(response) {
    if (!response || !Array.isArray(response.rules)) {
      return null;
    }
    return {
      rules: normalizeRules(response.rules),
      inheritedRules: normalizeRules(response.inheritedRules),
      disabled: response.disabled === true
    };
  }

  async function setSyncMeta(host, patch) {
    if (!host) return;
    const key = metaKey(host);
    const current = await getSyncMeta(host);
    const next = normalizeMeta({
      ...current,
      ...patch
    });
    await browser.storage.local.set({ [key]: next });
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

  async function syncRulesToNative(host, rules) {
    if (!host) return null;
    const normalizedRules = normalizeRules(rules);
    try {
      const response = await withTimeout(browser.runtime.sendMessage({
        action: 'wblock:zapper:syncRules',
        hostname: host,
        rules: normalizedRules
      }), NATIVE_MESSAGE_TIMEOUT_MS, 'Zapper sync timed out.');
      // If the native side returned an authoritative rules list (e.g. after
      // filtering out app-deleted rules), update browser.storage.local to match.
      if (response && Array.isArray(response.rules)) {
        const key = storageKey(host);
        const normalized = normalizeRules(response.rules);
        await browser.storage.local.set({ [key]: normalized });
        await setSyncMeta(host, { pendingSync: false, lastSyncAt: Date.now() });
        return normalized;
      }
      return null;
    } catch {
      return null;
    }
  }

  async function fetchRulesFromNative(host) {
    if (!host) return null;
    try {
      const response = await withTimeout(browser.runtime.sendMessage({
        action: 'wblock:zapper:getRules',
        hostname: host
      }), NATIVE_MESSAGE_TIMEOUT_MS, 'Zapper fetch timed out.');
      const nativeState = normalizeNativeZapperState(response);
      if (!nativeState) {
        return null;
      }
      const localRules = await loadRulesForHost(host);
      const localSig = rulesSignature(localRules);
      const nativeSig = rulesSignature(nativeState.rules);
      const meta = await getSyncMeta(host);
      if (meta.pendingSync && localSig !== nativeSig) {
        const reconciled = await syncRulesToNative(host, localRules);
        const rules = Array.isArray(reconciled) ? reconciled : localRules;
        const disabled = nativeState.disabled || await migrateLegacyZapperRulesDisabled(host, rules);
        await setSyncMeta(host, { disabled });
        return { rules, disabled, inheritedRules: nativeState.inheritedRules };
      }
      const disabled = nativeState.disabled || await migrateLegacyZapperRulesDisabled(host, nativeState.rules.length === 0 ? localRules : null);
      await cacheZapperState(host, nativeState.rules, disabled);
      return { rules: nativeState.rules, disabled, inheritedRules: nativeState.inheritedRules };
    } catch {
      return null;
    }
  }

  async function saveRulesForHost(host, rules) {
    if (!host) return;
    const key = storageKey(host);
    const unique = normalizeRules(rules).slice(0, MAX_RULES_PER_SITE);
    await browser.storage.local.set({ [key]: unique });
    await setSyncMeta(host, { pendingSync: true, lastLocalEditAt: Date.now() });
    const reconciled = await syncRulesToNative(host, unique);
    if (!Array.isArray(reconciled)) {
      return;
    }
    if (rulesSignature(reconciled) !== rulesSignature(unique)) {
      await browser.storage.local.set({ [key]: reconciled });
    }
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

  async function applyRulesToPage(rules) {
    const selectors = normalizeRules([...rules, ...state.inheritedRules]);
    if (selectors.length === 0 && state.tempRules.length === 0) {
      // Clearing needs no permission lookup, and empty frames need no styles.
      for (const id of [STYLE_ID, TEMP_STYLE_ID]) {
        const style = document.getElementById(id);
        if (style && style.textContent) style.textContent = '';
      }
      return;
    }
    const style = ensureStyleElement(STYLE_ID);
    const tempStyle = ensureStyleElement(TEMP_STYLE_ID);
    const suppressed = await shouldSuppressZapperRules(state.host || safeHostname());
    style.textContent = suppressed ? '' : buildHideCss(selectors);
    tempStyle.textContent = suppressed ? '' : buildHideCss(state.tempRules);
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

  function uiButton(label, className, onActivate) {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = label;
    if (className) button.className = className;
    button.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      onActivate();
    });
    return button;
  }

  function ensureUi() {
    if (state.ui.root) return;

    const uiStyle = ensureStyleElement(UI_STYLE_ID);
    uiStyle.textContent = `
      #${UI_ROOT_ID} { all: initial; --wb-text: #1d1d1f; --wb-danger: rgb(229,72,77); --wb-danger-fill: rgba(229,72,77,0.16); --wb-panel: rgba(255,255,255,0.55); --wb-fill: rgba(120,120,128,0.14); --wb-menu: rgba(255,255,255,0.8); --wb-line: rgba(0,0,0,0.08); --wb-shadow: rgba(0,0,0,0.18); --wb-highlight: rgba(255,255,255,0.7); position: fixed; top: 50%; right: calc(10px + env(safe-area-inset-right, 0px)); transform: translateY(-50%); z-index: 2147483647; box-sizing: border-box; width: 108px; padding: 8px; border-radius: 22px; display: flex; flex-direction: column; gap: 6px; font-family: -apple-system, system-ui, sans-serif; font-size: 13px; line-height: 1.15; color: var(--wb-text) !important; background: var(--wb-panel); backdrop-filter: blur(24px) saturate(180%); -webkit-backdrop-filter: blur(24px) saturate(180%); border: 1px solid var(--wb-line); box-shadow: inset 0 1px 0 var(--wb-highlight), 0 10px 30px var(--wb-shadow); cursor: grab; touch-action: none; }
      @media (prefers-color-scheme: dark) {
        #${UI_ROOT_ID} { --wb-text: #f5f5f7; --wb-panel: rgba(36,36,40,0.82); --wb-fill: rgba(120,120,128,0.3); --wb-menu: rgba(44,44,48,0.94); --wb-line: rgba(255,255,255,0.12); --wb-shadow: rgba(0,0,0,0.4); --wb-highlight: rgba(255,255,255,0.14); --wb-danger: rgb(255,105,97); --wb-danger-fill: rgba(255,105,97,0.2); }
      }
      #${UI_ROOT_ID}.wblock-dragging { cursor: grabbing; }
      #${UI_ROOT_ID}:focus { outline: none; }
      #${UI_ROOT_ID} button { all: initial; appearance: none; cursor: pointer; display: flex; align-items: center; justify-content: center; box-sizing: border-box; min-width: 0; min-height: 34px; margin: 0; border: 0; border-radius: 12px; padding: 7px 6px; background: var(--wb-fill); color: var(--wb-text) !important; font: inherit; font-size: 13px; font-weight: 600; line-height: 1.15; text-align: center; overflow-wrap: anywhere; touch-action: manipulation; -webkit-tap-highlight-color: transparent; }
      #${UI_ROOT_ID} button:active { filter: brightness(0.9); }
      #${UI_ROOT_ID} button:disabled { opacity: 0.4; }
      #${UI_ROOT_ID} .wblock-grip { width: 28px; height: 4px; margin: 0 auto 2px; border-radius: 2px; background: rgba(120,120,128,0.45); }
      #${UI_ROOT_ID} .wblock-hide { color: var(--wb-danger) !important; }
      #${UI_ROOT_ID} .wblock-hide.wblock-ready { background: var(--wb-danger-fill); }
      #${UI_ROOT_ID} .wblock-footer { position: relative; display: flex; justify-content: center; }
      #${UI_ROOT_ID} .wblock-more { min-height: 22px; padding: 0 8px; background: transparent; font-size: 15px; line-height: 1; letter-spacing: 1px; }
      #${UI_ROOT_ID} .wblock-overflow { position: absolute; right: calc(100% + 8px); bottom: 0; min-width: 170px; padding: 4px; border-radius: 14px; background: var(--wb-menu); backdrop-filter: blur(24px) saturate(180%); -webkit-backdrop-filter: blur(24px) saturate(180%); box-shadow: 0 8px 24px var(--wb-shadow); opacity: 0; transform: scale(0.97); transition: opacity 0.15s ease, transform 0.15s ease; pointer-events: none; }
      #${UI_ROOT_ID} .wblock-overflow.wblock-open { opacity: 1; transform: scale(1); pointer-events: auto; }
      #${UI_ROOT_ID} .wblock-overflow button { width: 100%; justify-content: flex-start; text-align: left; min-height: 36px; padding: 8px 10px; border-radius: 9px; background: transparent; font-weight: 500; }
      #${UI_ROOT_ID} .wblock-overflow button:active { background: var(--wb-fill); }
      #${HIGHLIGHT_ID} { position: fixed; pointer-events: none; z-index: 2147483646; border: 2px solid rgb(229,72,77); border-radius: 8px; background: rgba(229,72,77,0.08); transform: translate3d(0,0,0); }
      #${TOAST_ID} { position: absolute; right: 0; bottom: calc(100% + 8px); display: none; pointer-events: none; }
      #${TOAST_ID} .wblock-toast-inner { width: max-content; max-width: 200px; padding: 8px 10px; border-radius: 12px; background: var(--wb-menu); color: var(--wb-text); font-size: 12px; line-height: 1.3; text-align: center; box-shadow: 0 8px 24px var(--wb-shadow); }
    `.trim();

    const root = document.createElement('div');
    root.id = UI_ROOT_ID;
    root.tabIndex = -1;
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-label', t('zapper_aria_label', undefined, 'wBlock Element Zapper'));

    const grip = document.createElement('div');
    grip.className = 'wblock-grip';

    const addRuleButton = uiButton(t('zapper_button_add_rule', undefined, 'Add Rule'), 'wblock-hide', () => confirmHide());
    addRuleButton.disabled = true;

    const hideOnceButton = uiButton(t('zapper_button_hide_once', undefined, 'Hide Once'), 'wblock-hide', () => confirmHide({ temporary: true }));
    hideOnceButton.disabled = true;

    const doneButton = uiButton(t('zapper_button_done', undefined, 'Done'), '', () => {
      doneButton.disabled = true;
      finalizeSession().catch(() => {});
    });

    const cancelButton = uiButton(t('zapper_button_cancel', undefined, 'Cancel'), '', () => cancelSession());

    // --- Overflow menu (···) holds Undo and the custom rule prompt; it opens to the left ---
    const overflowMenu = document.createElement('div');
    overflowMenu.className = 'wblock-overflow';

    const undoButton = uiButton(t('zapper_button_undo', undefined, 'Undo'), '', () => {
      overflowMenu.classList.remove('wblock-open');
      undoLastZap().catch(() => {});
    });
    undoButton.disabled = true;

    const manualButton = uiButton(t('zapper_button_add_custom_rule', undefined, 'Add custom CSS rule…'), '', () => {
      overflowMenu.classList.remove('wblock-open');
      addManualRuleFromPrompt().catch(() => {});
    });
    overflowMenu.append(undoButton, manualButton);

    const footer = document.createElement('div');
    footer.className = 'wblock-footer';
    const moreButton = uiButton('···', 'wblock-more', () => overflowMenu.classList.toggle('wblock-open'));
    moreButton.title = t('zapper_button_more', undefined, 'More options');
    footer.append(moreButton, overflowMenu);

    const onOverflowOutside = (event) => {
      if (!overflowMenu.classList.contains('wblock-open')) return;
      if (footer.contains(event.target)) return;
      overflowMenu.classList.remove('wblock-open');
    };
    document.addEventListener('pointerdown', onOverflowOutside, true);
    state.cleanupFns.push(() => document.removeEventListener('pointerdown', onOverflowOutside, true));

    const highlight = document.createElement('div');
    highlight.id = HIGHLIGHT_ID;
    highlight.style.display = 'none';

    const toast = document.createElement('div');
    toast.id = TOAST_ID;
    const toastInner = document.createElement('div');
    toastInner.className = 'wblock-toast-inner';
    toast.appendChild(toastInner);

    root.append(grip, addRuleButton, hideOnceButton, doneButton, cancelButton, footer, toast);

    state.ui.root = root;
    state.ui.highlight = highlight;
    state.ui.toast = toast;
    state.ui.undoButton = undoButton;
    state.ui.addRuleButton = addRuleButton;
    state.ui.hideOnceButton = hideOnceButton;

    // --- Vertical drag-to-move logic ---
    // A press on the panel body only arms a drag. The panel moves once the
    // pointer has travelled DRAG_THRESHOLD_PX, so taps and small jitters on
    // the panel never move it, and buttons never arm a drag at all.
    const DRAG_THRESHOLD_PX = 6;
    let offsetY = 0;
    let pressY = null;
    let dragStartY = 0;
    let dragStartOffset = 0;
    let isDragging = false;

    function moveDrag(clientY) {
      if (pressY === null) return false;
      if (!isDragging) {
        if (Math.abs(clientY - pressY) < DRAG_THRESHOLD_PX) return false;
        isDragging = true;
        dragStartY = pressY;
        dragStartOffset = offsetY;
        root.classList.add('wblock-dragging');
      }
      // Keep room above the panel for the toast, which sits there.
      const room = window.innerHeight / 2 - root.offsetHeight / 2;
      offsetY = Math.max(-(room - 56), Math.min(room - 4, dragStartOffset + clientY - dragStartY));
      root.style.transform = `translateY(calc(-50% + ${offsetY}px))`;
      return true;
    }

    function endDrag() {
      pressY = null;
      isDragging = false;
      root.classList.remove('wblock-dragging');
    }

    const onPanelPointerDown = (e) => {
      if (e.target.closest('button, .wblock-overflow')) return;
      pressY = e.clientY;
    };
    const onPanelTouchStart = (e) => {
      if (e.target.closest('button, .wblock-overflow')) return;
      if (e.touches.length !== 1) return;
      pressY = e.touches[0].clientY;
    };
    const onDocPointerMove = (e) => { if (moveDrag(e.clientY)) e.preventDefault(); };
    const onDocTouchMove = (e) => { if (e.touches[0] && moveDrag(e.touches[0].clientY)) e.preventDefault(); };
    const onDocPointerEnd = () => endDrag();

    root.addEventListener('pointerdown', onPanelPointerDown);
    root.addEventListener('touchstart', onPanelTouchStart, { passive: true });
    document.addEventListener('pointermove', onDocPointerMove, { passive: false });
    document.addEventListener('touchmove', onDocTouchMove, { passive: false });
    document.addEventListener('pointerup', onDocPointerEnd);
    document.addEventListener('pointercancel', onDocPointerEnd);
    document.addEventListener('touchend', onDocPointerEnd);
    document.addEventListener('touchcancel', onDocPointerEnd);

    state.cleanupFns.push(
      () => root.removeEventListener('pointerdown', onPanelPointerDown),
      () => root.removeEventListener('touchstart', onPanelTouchStart),
      () => document.removeEventListener('pointermove', onDocPointerMove, { passive: false }),
      () => document.removeEventListener('touchmove', onDocTouchMove, { passive: false }),
      () => document.removeEventListener('pointerup', onDocPointerEnd),
      () => document.removeEventListener('pointercancel', onDocPointerEnd),
      () => document.removeEventListener('touchend', onDocPointerEnd),
      () => document.removeEventListener('touchcancel', onDocPointerEnd),
    );

    (document.documentElement || document).appendChild(highlight);
    (document.documentElement || document).appendChild(root);
  }

  function showToast(message) {
    if (!state.active) return;
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
      return { selector: '', error: t('zapper_error_enter_selector', undefined, 'Enter a CSS selector.') };
    }

    let selector = raw;
    if (raw.includes('{')) {
      const openIndex = raw.indexOf('{');
      const closeIndex = raw.lastIndexOf('}');
      if (closeIndex <= openIndex) {
        return { selector: '', error: t('zapper_error_rule_syntax_invalid', undefined, 'CSS rule syntax is invalid.') };
      }
      if (raw.slice(closeIndex + 1).trim().length > 0) {
        return { selector: '', error: t('zapper_error_rule_syntax_invalid', undefined, 'CSS rule syntax is invalid.') };
      }
      selector = raw.slice(0, openIndex).trim();
    } else if (raw.includes('}')) {
      return { selector: '', error: t('zapper_error_rule_syntax_invalid', undefined, 'CSS rule syntax is invalid.') };
    }

    if (!selector) {
      return { selector: '', error: t('zapper_error_enter_selector', undefined, 'Enter a CSS selector.') };
    }
    if (selector.length > 512) {
      return { selector: '', error: t('zapper_error_selector_too_long', undefined, 'Selector is too long.') };
    }
    if (!isValidCssSelector(selector)) {
      return { selector: '', error: t('zapper_error_selector_syntax_invalid', undefined, 'Selector syntax is invalid.') };
    }

    return { selector, error: '' };
  }

  async function addSelectorRule(selector, options = {}) {
    const normalized = (selector || '').trim();
    if (!normalized) return;
    if (state.rules.includes(normalized) || state.tempRules.includes(normalized)) {
      showToast(options.manual
        ? t('zapper_toast_rule_exists', undefined, 'Rule already exists.')
        : t('zapper_toast_already_hidden', undefined, 'Already hidden.'));
      return;
    }
    const temporary = options.temporary === true;
    state.undoStack.push({ selector: normalized, temporary });
    if (temporary) {
      state.tempRules = state.tempRules.concat([normalized]).slice(0, MAX_RULES_PER_SITE);
    } else {
      state.rules = state.rules.concat([normalized]).slice(0, MAX_RULES_PER_SITE);
      await trackPendingSave(saveRulesForHost(state.host, state.rules));
    }
    await applyRulesToPage(state.rules);
    if (!state.active) return;
    if (state.ui.undoButton) state.ui.undoButton.disabled = false;
    showToast(temporary
      ? t('zapper_toast_hidden_until_reload', undefined, 'Hidden until reload.')
      : options.manual
        ? t('zapper_toast_rule_saved', undefined, 'Rule saved for this site.')
        : t('zapper_toast_hidden_and_saved', undefined, 'Hidden. Rule saved for this site.'));
  }

  async function addManualRuleFromPrompt() {
    const rawInput = window.prompt(t('zapper_prompt_enter_selector', undefined, 'Enter CSS selector for this site'));
    if (rawInput === null) return;

    const parsed = parseManualRuleInput(rawInput);
    if (parsed.error) {
      showToast(parsed.error);
      return;
    }

    await addSelectorRule(parsed.selector, { manual: true });
  }

  // Drops the newest hide, or every hide from this session when `all` is set.
  // Permanent hides leave the saved rules (synced like any edit); temporary
  // hides only leave the in-memory list.
  async function revertZaps(all = false) {
    const entries = all ? state.undoStack.splice(0) : state.undoStack.splice(-1);
    if (entries.length === 0) return false;
    const temporary = new Set(entries.filter((e) => e.temporary).map((e) => e.selector));
    const permanent = new Set(entries.filter((e) => !e.temporary).map((e) => e.selector));
    state.tempRules = state.tempRules.filter((r) => !temporary.has(r));
    if (permanent.size > 0) {
      state.rules = state.rules.filter((r) => !permanent.has(r));
      await trackPendingSave(saveRulesForHost(state.host, state.rules));
    }
    await applyRulesToPage(state.rules);
    return true;
  }

  async function undoLastZap() {
    if (!(await revertZaps())) return;
    if (!state.active) return;
    if (state.ui.undoButton) state.ui.undoButton.disabled = state.undoStack.length === 0;
    showToast(t('zapper_toast_undone', undefined, 'Undone.'));
  }

  // Cancel closes the panel and reverts every hide made in this session.
  function cancelSession() {
    deactivateZapper({ removeUi: true });
    return revertZaps(true).catch(() => {});
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

    for (const key of Object.keys(state.ui)) state.ui[key] = null;
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

  function isTextEntryTarget(target) {
    if (!(target instanceof Element)) return false;
    if (target.isContentEditable) return true;
    return target.matches('textarea, select, input:not([type=button]):not([type=checkbox]):not([type=radio]):not([type=submit]):not([type=reset]):not([type=range]):not([type=color]):not([type=file]):not([type=image])');
  }

  function isZapperBoundary(el) {
    return !el || el === document.body || el === document.documentElement;
  }

  function syncPanelState() {
    const ready = Boolean(state.candidateElement);
    for (const button of [state.ui.addRuleButton, state.ui.hideOnceButton]) {
      if (!button) continue;
      button.disabled = !ready;
      button.classList.toggle('wblock-ready', ready);
    }
  }

  function enterRefineMode(element) {
    state.candidateElement = element;
    state.traversalPath = [];
    setHighlightForElement(element);
    syncPanelState();
  }

  function clearSelection() {
    state.candidateElement = null;
    state.traversalPath = [];
    clearHighlight();
    syncPanelState();
  }

  function navigateParent() {
    const candidate = state.candidateElement;
    if (!candidate) return;
    const parent = candidate.parentElement;
    if (isZapperBoundary(parent)) return;
    state.traversalPath.push(candidate);
    state.candidateElement = parent;
    setHighlightForElement(parent);
  }

  function navigateChild() {
    if (state.traversalPath.length === 0) return;
    state.candidateElement = state.traversalPath.pop();
    setHighlightForElement(state.candidateElement);
  }

  // Add Rule saves a permanent rule; Hide Once (temporary) lasts until reload.
  function confirmHide(options = {}) {
    const el = state.candidateElement;
    if (!el) return;
    const selector = selectorForElement(el);
    clearSelection();
    if (!selector) {
      showToast(t('zapper_toast_unable_create_rule', undefined, 'Unable to create a rule for that element.'));
      return;
    }
    addSelectorRule(selector, { temporary: options.temporary === true }).catch(() => {});
  }

  // Element under the last right click, used by the "Zap Element" context
  // menu to preselect its target. Cleared as soon as it is consumed.
  let lastContextMenuTarget = null;

  function preselectContextMenuTarget() {
    const el = lastContextMenuTarget;
    lastContextMenuTarget = null;
    if (!el || !el.isConnected || shouldIgnoreTarget(el)) return;
    enterRefineMode(el);
  }

  async function activateZapper(options = {}) {
    if (state.active) {
      if (options.fromContextMenu === true) preselectContextMenuTarget();
      return true;
    }
    state.host = safeHostname();
    if (await shouldSuppressZapperRules(state.host)) {
      return false;
    }
    ensureUi();
    state.active = true;
    state.undoStack = [];
    state.lastPickAt = 0;
    clearSelection();
    state.lastPointerX = -1;
    state.lastPointerY = -1;
    state.isScrolling = false;
    if (state.ui.undoButton) state.ui.undoButton.disabled = true;
    showToast(t('zapper_toast_enabled', undefined, 'Element Zapper enabled.'));
    if (options.fromContextMenu === true) preselectContextMenuTarget();

    // After the popup closes, keyboard focus stays on Safari's chrome.
    // Without explicit focus, keydown events (like Escape) never reach our
    // listeners. Retry briefly so Activate works even if the first focus is stolen.
    const focusZapperRoot = () => {
      if (!state.active) return;
      const rootEl = state.ui.root;
      if (rootEl && typeof rootEl.focus === 'function') {
        try {
          rootEl.focus({ preventScroll: true });
        } catch {
          rootEl.focus();
        }
      }
    };
    focusZapperRoot();
    setTimeout(focusZapperRoot, 0);
    setTimeout(focusZapperRoot, 50);
    setTimeout(focusZapperRoot, 150);

    const onMove = (event) => {
      if (!state.active) return;
      if (state.candidateElement) return;
      if (shouldIgnoreTarget(event && event.target)) return;
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
      if (shouldIgnoreTarget(event && event.target)) return;
      const now = Date.now();
      if (now - state.lastPickAt < 120) return;
      const el = elementFromEvent(event);
      if (!el || shouldIgnoreTarget(el)) return;
      interceptEvent(event);
      focusZapperRoot();
      state.lastPickAt = now;
      const current = state.candidateElement;
      if (current && current.contains(el)) {
        navigateParent();
      } else {
        enterRefineMode(el);
      }
    };

    // Prevent navigation/actions that fire on click (e.g. <a href=...>) while
    // the zapper is active. On iOS Safari, preventing pointer/touch events
    // alone does not always cancel the subsequent click.
    const onClick = (event) => {
      if (!state.active) return;
      if (shouldIgnoreTarget(event && event.target)) return;
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
          clearSelection();
        } else {
          deactivateZapper({ removeUi: true });
        }
        return;
      }
      // ArrowUp selects the parent, ArrowDown returns to the child picked last.
      // Arrows typed into page fields keep their normal caret movement.
      if ((event.key === 'ArrowUp' || event.key === 'ArrowDown') && !isTextEntryTarget(event.target)) {
        interceptEvent(event);
        if (event.key === 'ArrowUp') navigateParent();
        else navigateChild();
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
    window.addEventListener('keydown', onKeyDown, true);

    addCleanup(() => document.removeEventListener(moveEvent, onMove, true));
    addCleanup(() => document.removeEventListener(downEvent, pickFromEvent, true));
    addCleanup(() => document.removeEventListener('click', onClick, true));
    addCleanup(() => document.removeEventListener('touchstart', pickFromEvent, touchOptions));
    addCleanup(() => document.removeEventListener('keydown', onKeyDown, true));
    addCleanup(() => window.removeEventListener('keydown', onKeyDown, true));

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
    return true;
  }

  function deactivateZapper(options = {}) {
    const removeUi = Boolean(options.removeUi);
    if (!state.active && !removeUi) return;
    state.active = false;
    clearSelection();
    clearCleanup();
    if (removeUi) {
      teardownUi();
      return;
    }

    showToast(t('zapper_toast_disabled', undefined, 'Element Zapper disabled.'));
  }

  function startRuleSyncLoop() {
    if (ruleSyncIntervalId !== null) return;
    if (window.top !== window) return;
    ruleSyncIntervalId = window.setInterval(() => {
      if (document.visibilityState === 'hidden') return;
      if (ruleSyncInFlight) return;
      ruleSyncInFlight = true;
      browser.runtime.sendMessage({ action: 'wblock:zapper:broadcastReload' })
        .catch(() => {})
        .finally(() => {
          ruleSyncInFlight = false;
        });
    }, RULE_SYNC_FALLBACK_INTERVAL_MS);
    window.addEventListener('pagehide', () => {
      if (ruleSyncIntervalId !== null) {
        clearInterval(ruleSyncIntervalId);
        ruleSyncIntervalId = null;
      }
    }, { once: true });
  }

  async function reloadRulesAndApply() {
    state.inheritedRules = [];
    state.host = safeHostname();
    state.rules = await loadRulesForHost(state.host);
    state.rulesDisabled = await loadCachedRulesDisabled(state.host);
    if (await migrateLegacyZapperRulesDisabled(state.host, state.rules)) {
      state.rulesDisabled = true;
      await setSyncMeta(state.host, { disabled: true });
    }
    await applyRulesToPage(state.rules);

    const nativeState = await fetchRulesFromNative(state.host);
    if (nativeState && Array.isArray(nativeState.rules)) {
      state.inheritedRules = nativeState.inheritedRules;
      state.rulesDisabled = nativeState.disabled === true;
      if (rulesSignature(nativeState.rules) !== rulesSignature(state.rules)) {
        state.rules = nativeState.rules;
      }
      await applyRulesToPage(state.rules);
      return;
    }

    if (state.rules.length > 0) {
      syncRulesToNative(state.host, state.rules).catch(() => {});
    }
  }

  function reloadRulesAndApplyCoalesced() {
    if (ruleReloadPromise) {
      // A native invalidation racing an older read must not be swallowed. Fold
      // any burst into exactly one follow-up pass after the current pass ends.
      if (ruleReloadActive) ruleReloadPending = true;
      return ruleReloadPromise;
    }
    // Start on the next microtask so same-tick invalidation bursts collapse into
    // one pass before any native read has actually begun.
    ruleReloadPromise = Promise.resolve().then(async () => {
      ruleReloadActive = true;
      do {
        ruleReloadPending = false;
        await reloadRulesAndApply();
      } while (ruleReloadPending);
    }).finally(() => {
      ruleReloadActive = false;
      ruleReloadPromise = null;
    });
    return ruleReloadPromise;
  }

  // iOS Safari keeps a frame alive while an extension event still holds its
  // listener, so detach on pagehide or iframe-heavy pages run out of memory (#861).
  const listenWhileShown = (event, listener) => {
      event.addListener(listener);
      window.addEventListener('pagehide', () => event.removeListener(listener));
      window.addEventListener('pageshow', (e) => { if (e.persisted) event.addListener(listener); });
  };
  document.addEventListener('contextmenu', (event) => {
    lastContextMenuTarget = event.target instanceof Element ? event.target : null;
  }, true);
  listenWhileShown(browser.runtime.onMessage, (message) => {
    if (!message || typeof message !== 'object') return;

    if (message.type === 'wblock:pageSupportProbe') {
      return Promise.resolve({
        ok: true,
        host: safeHostname(),
        protocol: typeof location !== 'undefined' ? location.protocol : '',
      });
    }
    if (message.type === 'wblock:zapper:activate') {
      // Activation may reach every frame of the tab. Only the top frame builds
      // the panel; a context-menu activation targets the frame that was clicked.
      if (message.fromContextMenu !== true && window.top !== window) return;
      return activateZapper({
        fromContextMenu: message.fromContextMenu === true,
      }).then((activated) => ({
        ok: activated !== false,
        handledBy: 'zapper-content'
      }));
    }
    if (message.type === 'wblock:zapper:deactivate') {
      deactivateZapper({ removeUi: true });
      return Promise.resolve({ ok: true, handledBy: 'zapper-content' });
    }
    if (message.type === 'wblock:zapper:reloadRules') {
      return reloadRulesAndApplyCoalesced()
        .then(() => ({ ok: true, handledBy: 'zapper-content' }))
        .catch(() => ({ ok: false, handledBy: 'zapper-content' }));
    }
  });

  // Initial load: apply existing rules for this host.
  reloadRulesAndApplyCoalesced().catch(() => {});
  startRuleSyncLoop();
})();
