const NATIVE_HOST_ACTIONS = {
    GET_SITE_DISABLED_STATE: 'getSiteDisabledState',
    SET_SITE_DISABLED_STATE: 'setSiteDisabledState',
    ZAPPER: 'zapperController',
};

const state = {
    tabId: null,
    tabUrl: '',
    host: '',
    rules: [],
    rulesExpanded: false,
};

function setError(message) {
    const el = document.getElementById('error');
    if (!el) return;
    if (!message) {
        el.hidden = true;
        el.textContent = '';
        return;
    }
    el.hidden = false;
    el.textContent = message;
}

function setStatus(text, kind = 'neutral') {
    const statusEl = document.getElementById('blocking-status');
    if (!statusEl) return;
    statusEl.textContent = text;
    statusEl.classList.remove('is-active', 'is-disabled', 'is-neutral');
    if (kind === 'active') statusEl.classList.add('is-active');
    else if (kind === 'disabled') statusEl.classList.add('is-disabled');
    else statusEl.classList.add('is-neutral');
}

function hostnameFromUrl(urlString) {
    try {
        const url = new URL(urlString);
        return url.hostname || '';
    } catch {
        return '';
    }
}

async function getActiveTab() {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    return tabs && tabs.length ? tabs[0] : null;
}

async function sendNative(action, payload = {}) {
    return browser.runtime.sendMessage({ action, ...payload });
}

async function refreshBadgeCounterState() {
    try {
        await sendNative('wblock:refreshBadgeCounter');
    } catch (error) {
        console.error('[wBlock] Failed to refresh badge counter state:', error);
    }
}

async function getSiteDisabledState(host) {
    if (!host) return false;
    const response = await sendNative(NATIVE_HOST_ACTIONS.GET_SITE_DISABLED_STATE, { host });
    return Boolean(response && response.disabled);
}

async function setSiteDisabledState(host, disabled) {
    if (!host) return;
    await sendNative(NATIVE_HOST_ACTIONS.SET_SITE_DISABLED_STATE, {
        host,
        disabled: Boolean(disabled),
    });
}

async function loadZapperRules(host) {
    if (!host) return [];
    const response = await sendNative(NATIVE_HOST_ACTIONS.ZAPPER, {
        payload: {
            action: 'loadRules',
            hostname: host,
        },
    });
    const rules = Array.isArray(response && response.rules) ? response.rules : [];
    return rules
        .filter((rule) => typeof rule === 'string')
        .map((rule) => rule.trim())
        .filter(Boolean);
}

async function removeZapperRule(host, selector) {
    if (!host || !selector) return;
    await sendNative(NATIVE_HOST_ACTIONS.ZAPPER, {
        payload: {
            action: 'removeRule',
            hostname: host,
            selector,
        },
    });
}

async function reloadActiveTab(tabId, tabUrl) {
    if (!tabId) return;
    const url = typeof tabUrl === 'string' ? tabUrl : '';

    // In Safari, `tabs.reload()` can behave like a soft refresh. Navigating to the current
    // URL is a closer match to "reload from origin" behavior and applies updated blockers
    // more reliably after toggling per-site disable.
    if (/^https?:\/\//i.test(url)) {
        try {
            await browser.tabs.update(tabId, { url });
            return;
        } catch (error) {
            console.warn('[wBlock] Failed to hard-navigate tab, falling back to reload:', error);
        }
    }

    await browser.tabs.reload(tabId);
}

async function notifyZapperRulesChanged(tabId) {
    if (!tabId) return;
    try {
        await browser.tabs.sendMessage(tabId, { type: 'wblock:zapper:reloadRules' });
    } catch {
        // Content script may not be reachable on special pages.
    }
}

function renderRules() {
    const countEl = document.getElementById('zapper-count');
    const clearBtn = document.getElementById('zapper-clear');
    const rulesContainer = document.getElementById('zapper-rules');

    if (countEl) countEl.textContent = String(state.rules.length);
    if (clearBtn) clearBtn.disabled = state.rules.length === 0;
    if (!rulesContainer) return;

    rulesContainer.innerHTML = '';

    if (state.rules.length === 0) {
        const empty = document.createElement('div');
        empty.className = 'rule-empty';
        empty.textContent = 'No rules';
        rulesContainer.appendChild(empty);
        return;
    }

    state.rules.forEach((rule, index) => {
        const row = document.createElement('div');
        row.className = 'rule-row';

        const text = document.createElement('div');
        text.className = 'rule-text';
        text.textContent = rule;

        const del = document.createElement('button');
        del.type = 'button';
        del.className = 'rule-delete';
        del.setAttribute('data-index', String(index));
        del.setAttribute('aria-label', 'Delete rule');
        del.textContent = '✕';

        row.appendChild(text);
        row.appendChild(del);
        rulesContainer.appendChild(row);
    });
}

function setRulesExpanded(expanded) {
    state.rulesExpanded = expanded;
    const toggle = document.getElementById('zapper-rules-toggle');
    const container = document.getElementById('zapper-rules');
    if (toggle) toggle.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    if (container) container.hidden = !expanded;
}

async function refreshState() {
    setError('');

    const hostEl = document.getElementById('site-host');
    const disableToggle = document.getElementById('disable-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const rulesToggle = document.getElementById('zapper-rules-toggle');

    const tab = await getActiveTab();
    const host = tab && tab.url ? hostnameFromUrl(tab.url) : '';

    state.tabId = tab && tab.id ? tab.id : null;
    state.tabUrl = tab && tab.url ? String(tab.url) : '';
    state.host = host;

    if (hostEl) hostEl.textContent = host || '—';

    if (!state.tabId || !host) {
        setStatus('Unavailable', 'neutral');
        if (disableToggle) disableToggle.disabled = true;
        if (zapperActivate) zapperActivate.disabled = true;
        if (rulesToggle) rulesToggle.disabled = true;
        state.rules = [];
        renderRules();
        setRulesExpanded(false);
        return;
    }

    setStatus('Checking…', 'neutral');

    const disabled = await getSiteDisabledState(host);
    if (disableToggle) {
        disableToggle.checked = disabled;
        disableToggle.disabled = false;
    }

    if (zapperActivate) zapperActivate.disabled = false;
    if (rulesToggle) rulesToggle.disabled = false;

    setStatus(disabled ? 'Disabled' : 'Active', disabled ? 'disabled' : 'active');

    state.rules = await loadZapperRules(host);
    renderRules();
}

async function handleToggleDisabled(event) {
    const disableToggle = event.target;
    if (!state.host || !state.tabId || !disableToggle) return;

    try {
        setError('');
        disableToggle.disabled = true;

        const disabled = Boolean(disableToggle.checked);
        setStatus(disabled ? 'Disabling…' : 'Enabling…', 'neutral');

        await setSiteDisabledState(state.host, disabled);
        await sendNative('wblock:clearCache');
        const tab = await getActiveTab();
        await reloadActiveTab(
            state.tabId,
            tab && tab.id === state.tabId ? tab.url : state.tabUrl
        );

        setStatus(disabled ? 'Disabled' : 'Active', disabled ? 'disabled' : 'active');
    } catch (error) {
        console.error('[wBlock] Failed to update disabled state:', error);
        setError('Failed to update site setting.');
        disableToggle.checked = !disableToggle.checked;
    } finally {
        disableToggle.disabled = false;
    }
}

async function handleActivateZapper() {
    if (!state.tabId) return;
    try {
        setError('');
        await browser.tabs.sendMessage(state.tabId, { type: 'wblock:zapper:activate' });
        window.close();
    } catch (error) {
        console.error('[wBlock] Failed to activate zapper:', error);
        setError('Element Zapper is unavailable on this page.');
    }
}

async function handleClearRules() {
    if (!state.host || !state.tabId) return;
    try {
        setError('');
        const existing = state.rules.slice();
        await Promise.all(existing.map((selector) => removeZapperRule(state.host, selector)));
        state.rules = [];
        renderRules();
        await notifyZapperRulesChanged(state.tabId);
    } catch (error) {
        console.error('[wBlock] Failed to clear zapper rules:', error);
        setError('Failed to clear zapper rules.');
    }
}

async function handleRulesClick(event) {
    const target = event && event.target && event.target.closest ? event.target.closest('button.rule-delete') : null;
    if (!target) return;

    const index = Number(target.getAttribute('data-index'));
    if (!Number.isFinite(index) || index < 0 || index >= state.rules.length) return;

    try {
        setError('');
        const selector = state.rules[index];
        await removeZapperRule(state.host, selector);
        state.rules.splice(index, 1);
        renderRules();
        if (state.tabId) {
            await notifyZapperRulesChanged(state.tabId);
        }
    } catch (error) {
        console.error('[wBlock] Failed to delete zapper rule:', error);
        setError('Failed to delete rule.');
    }
}

async function handleRulesToggle() {
    try {
        setError('');
        const nextExpanded = !state.rulesExpanded;
        setRulesExpanded(nextExpanded);
        if (!nextExpanded || !state.host) return;
        state.rules = await loadZapperRules(state.host);
        renderRules();
    } catch (error) {
        console.error('[wBlock] Failed to load zapper rules:', error);
        setError('Failed to load rules.');
    }
}

function setupEventHandlers() {
    const disableToggle = document.getElementById('disable-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const zapperClear = document.getElementById('zapper-clear');
    const rulesToggle = document.getElementById('zapper-rules-toggle');
    const rulesContainer = document.getElementById('zapper-rules');

    disableToggle?.addEventListener('change', handleToggleDisabled);
    zapperActivate?.addEventListener('click', handleActivateZapper);
    zapperClear?.addEventListener('click', handleClearRules);
    rulesToggle?.addEventListener('click', handleRulesToggle);
    rulesContainer?.addEventListener('click', handleRulesClick);
}

document.addEventListener('DOMContentLoaded', () => {
    setupEventHandlers();
    refreshBadgeCounterState();
    refreshState().catch((error) => {
        console.error('[wBlock] Popup init failed:', error);
        setError('Failed to load popup.');
    });
});
