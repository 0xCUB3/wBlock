const NATIVE_HOST_ID = 'application.id';
const ZAPPER_STORAGE_PREFIX = 'wblock.zapperRules.v1:';
const ZAPPER_META_PREFIX = 'wblock.zapperMeta.v1:';

function normalizeRules(rules) {
    return Array.from(new Set((rules || [])
        .filter((r) => typeof r === 'string')
        .map((r) => r.trim())
        .filter(Boolean)));
}

function rulesSignature(rules) {
    return normalizeRules(rules).join('\u001f');
}

function zapperMetaKey(host) {
    return `${ZAPPER_META_PREFIX}${host}`;
}

function normalizeSyncMeta(raw) {
    if (!raw || typeof raw !== 'object') {
        return { pendingSync: false, lastLocalEditAt: 0, lastSyncAt: 0 };
    }
    const lastLocalEditAt = Number(raw.lastLocalEditAt);
    const lastSyncAt = Number(raw.lastSyncAt);
    return {
        pendingSync: Boolean(raw.pendingSync),
        lastLocalEditAt: Number.isFinite(lastLocalEditAt) ? lastLocalEditAt : 0,
        lastSyncAt: Number.isFinite(lastSyncAt) ? lastSyncAt : 0,
    };
}

async function getSyncMeta(host) {
    if (!host) return { pendingSync: false, lastLocalEditAt: 0, lastSyncAt: 0 };
    try {
        const key = zapperMetaKey(host);
        const result = await browser.storage.local.get(key);
        return normalizeSyncMeta(result[key]);
    } catch {
        return { pendingSync: false, lastLocalEditAt: 0, lastSyncAt: 0 };
    }
}

async function setSyncMeta(host, patch) {
    if (!host) return;
    const key = zapperMetaKey(host);
    const current = await getSyncMeta(host);
    const next = normalizeSyncMeta({
        ...current,
        ...patch,
    });
    await browser.storage.local.set({ [key]: next });
}

async function syncRulesToNative(host, rules) {
    if (!host) return null;
    const normalizedRules = normalizeRules(rules);
    try {
        const response = await browser.runtime.sendMessage({
            action: 'wblock:zapper:syncRules',
            hostname: host,
            rules: normalizedRules
        });
        if (response && Array.isArray(response.rules)) {
            const key = zapperStorageKey(host);
            const normalized = normalizeRules(response.rules);
            await browser.storage.local.set({ [key]: normalized });
            await setSyncMeta(host, { pendingSync: false, lastSyncAt: Date.now() });
            return normalized;
        }
        return null;
    } catch {
        try {
            const response = await browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
                action: 'syncZapperRules',
                hostname: host,
                rules: normalizedRules
            });
            if (response && Array.isArray(response.rules)) {
                const key = zapperStorageKey(host);
                const normalized = normalizeRules(response.rules);
                await browser.storage.local.set({ [key]: normalized });
                await setSyncMeta(host, { pendingSync: false, lastSyncAt: Date.now() });
                return normalized;
            }
        } catch {
            return null;
        }
        return null;
    }
}

async function fetchRulesFromNative(host) {
    if (!host) return null;
    try {
        const response = await browser.runtime.sendMessage({
            action: 'wblock:zapper:getRules',
            hostname: host,
        });
        if (!response || !Array.isArray(response.rules)) {
            return null;
        }
        const normalized = normalizeRules(response.rules);
        const localRules = await loadZapperRules(host);
        const localSig = rulesSignature(localRules);
        const nativeSig = rulesSignature(normalized);
        const meta = await getSyncMeta(host);
        if (meta.pendingSync && localSig !== nativeSig) {
            const reconciled = await syncRulesToNative(host, localRules);
            return Array.isArray(reconciled) ? reconciled : localRules;
        }
        const key = zapperStorageKey(host);
        await browser.storage.local.set({ [key]: normalized });
        await setSyncMeta(host, { pendingSync: false, lastSyncAt: Date.now() });
        return normalized;
    } catch {
        try {
            const response = await browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
                action: 'getZapperRules',
                hostname: host,
            });
            if (!response || !Array.isArray(response.rules)) {
                return null;
            }
            const normalized = normalizeRules(response.rules);
            const localRules = await loadZapperRules(host);
            const localSig = rulesSignature(localRules);
            const nativeSig = rulesSignature(normalized);
            const meta = await getSyncMeta(host);
            if (meta.pendingSync && localSig !== nativeSig) {
                const reconciled = await syncRulesToNative(host, localRules);
                return Array.isArray(reconciled) ? reconciled : localRules;
            }
            const key = zapperStorageKey(host);
            await browser.storage.local.set({ [key]: normalized });
            await setSyncMeta(host, { pendingSync: false, lastSyncAt: Date.now() });
            return normalized;
        } catch {
            return null;
        }
    }
}

async function getAuthoritativeZapperRules(host) {
    if (!host) return [];
    const nativeRules = await fetchRulesFromNative(host);
    if (Array.isArray(nativeRules)) {
        return nativeRules;
    }
    const localRules = await loadZapperRules(host);
    const reconciled = await syncRulesToNative(host, localRules);
    return Array.isArray(reconciled) ? reconciled : localRules;
}

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

async function getActiveTab() {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    return tabs && tabs.length ? tabs[0] : null;
}

function hostnameFromUrl(urlString) {
    try {
        const url = new URL(urlString);
        return url.hostname || '';
    } catch {
        return '';
    }
}

function zapperStorageKey(host) {
    return `${ZAPPER_STORAGE_PREFIX}${host}`;
}

async function updateZapperCount(host) {
    const countEl = document.getElementById('zapper-count');
    const clearBtn = document.getElementById('zapper-clear');
    if (!host) {
        if (countEl) countEl.textContent = '—';
        if (clearBtn) clearBtn.disabled = true;
        return 0;
    }
    const key = zapperStorageKey(host);
    const result = await browser.storage.local.get(key);
    const rules = Array.isArray(result[key]) ? result[key] : [];
    const count = rules.length;
    if (countEl) countEl.textContent = String(count);
    if (clearBtn) clearBtn.disabled = count === 0;
    return count;
}

async function loadZapperRules(host) {
    if (!host) return [];
    try {
        const key = zapperStorageKey(host);
        const result = await browser.storage.local.get(key);
        const rules = Array.isArray(result[key]) ? result[key] : [];
        return rules
            .filter((r) => typeof r === 'string')
            .map((r) => r.trim())
            .filter(Boolean);
    } catch (error) {
        console.warn('[wBlock] Failed to load zapper rules:', error);
        return [];
    }
}

async function saveZapperRules(host, rules) {
    if (!host) return;
    const key = zapperStorageKey(host);
    const normalized = normalizeRules(rules);
    await browser.storage.local.set({ [key]: normalized });
    await setSyncMeta(host, { pendingSync: true, lastLocalEditAt: Date.now() });
    const reconciled = await syncRulesToNative(host, normalized);
    if (!Array.isArray(reconciled)) {
        return;
    }
    if (rulesSignature(reconciled) !== rulesSignature(normalized)) {
        await browser.storage.local.set({ [key]: reconciled });
    }
}

async function notifyZapperRulesChanged(tabId) {
    if (!tabId) return;
    try {
        await browser.tabs.sendMessage(tabId, { type: 'wblock:zapper:reloadRules' });
    } catch {
        // Content script may not be reachable on certain pages; ignore.
    }
}

let zapperRulesExpanded = false;
let currentZapperRules = [];
let host = '';
let tab = null;

function setRulesExpanded(expanded) {
    zapperRulesExpanded = expanded;
    const toggle = document.getElementById('zapper-rules-toggle');
    const container = document.getElementById('zapper-rules');
    if (toggle) toggle.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    if (container) container.hidden = !expanded;
}

function renderZapperRules(rules) {
    const container = document.getElementById('zapper-rules');
    if (!container) return;
    container.innerHTML = '';

    if (!rules.length) {
        const empty = document.createElement('div');
        empty.className = 'rule-empty';
        empty.textContent = 'No rules';
        container.appendChild(empty);
        return;
    }

    for (let index = 0; index < rules.length; index += 1) {
        const rule = rules[index];
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
        container.appendChild(row);
    }
}

async function getSiteDisabledState(host) {
    if (!host) return false;
    try {
        const response = await browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
            action: 'getSiteDisabledState',
            host,
        });
        return Boolean(response && response.disabled);
    } catch (error) {
        console.error('[wBlock] Failed to get disabled state:', error);
        return false;
    }
}

async function setSiteDisabledState(host, disabled) {
    if (!host) return;
    return browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
        action: 'setSiteDisabledState',
        host,
        disabled: Boolean(disabled),
    });
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function reloadActiveTab(tabId) {
    if (!tabId) return;
    try {
        await browser.tabs.reload(tabId, { bypassCache: true });
    } catch (error) {
        try {
            await browser.tabs.reload(tabId);
        } catch (fallbackError) {
            console.warn('[wBlock] Failed to reload tab:', fallbackError);
        }
    }
}

function setupListeners() {
    const rulesToggle = document.getElementById('zapper-rules-toggle');
    const rulesContainer = document.getElementById('zapper-rules');
    const disableToggle = document.getElementById('disable-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const zapperRefresh = document.getElementById('zapper-refresh');
    const zapperClear = document.getElementById('zapper-clear');

    if (rulesToggle) {
        rulesToggle.addEventListener('click', async () => {
            try {
                setError('');
                setRulesExpanded(!zapperRulesExpanded);
                if (!zapperRulesExpanded) return;
                currentZapperRules = await getAuthoritativeZapperRules(host);
                renderZapperRules(currentZapperRules);
            } catch (error) {
                console.error('[wBlock] Failed to toggle rules:', error);
                setError('Failed to load rules.');
            }
        });
    }

    if (rulesContainer) {
        rulesContainer.addEventListener('click', async (event) => {
            const element = event && event.target && event.target.closest ? event.target.closest('button.rule-delete') : null;
            if (!element) return;
            const idx = Number(element.getAttribute('data-index'));
            if (!Number.isFinite(idx) || idx < 0 || idx >= currentZapperRules.length) return;

            try {
                setError('');
                const next = currentZapperRules.slice();
                next.splice(idx, 1);
                await saveZapperRules(host, next);
                currentZapperRules = await getAuthoritativeZapperRules(host);
                renderZapperRules(currentZapperRules);
                await updateZapperCount(host);
                await notifyZapperRulesChanged(tab.id);
            } catch (error) {
                console.error('[wBlock] Failed to delete rule:', error);
                setError('Failed to delete rule.');
            }
        });
    }

    if (disableToggle) {
        disableToggle.addEventListener('change', async () => {
            try {
                setError('');
                disableToggle.disabled = true;
                const next = disableToggle.checked;
                setStatus(next ? 'Disabling…' : 'Enabling…', 'neutral');
                const updateResult = await setSiteDisabledState(host, next);
                try {
                    await browser.runtime.sendMessage({ action: 'wblock:clearCache' });
                } catch (error) {
                    console.warn('[wBlock] Failed to clear configuration cache:', error);
                }
                const settleMs = updateResult && updateResult.failedTargets > 0 ? 1200 : 350;
                await sleep(settleMs);
                setStatus(next ? 'Disabled' : 'Active', next ? 'disabled' : 'active');
                await reloadActiveTab(tab.id);
            } catch (error) {
                console.error('[wBlock] Failed to update disabled state:', error);
                setError('Failed to update site setting.');
                disableToggle.checked = !disableToggle.checked;
            } finally {
                disableToggle.disabled = false;
            }
        });
    }

    if (zapperActivate) {
        zapperActivate.addEventListener('click', async () => {
            try {
                setError('');
                await browser.tabs.sendMessage(tab.id, { type: 'wblock:zapper:activate' });
                window.close();
            } catch (error) {
                console.error('[wBlock] Failed to activate zapper:', error);
                setError('Element Zapper is unavailable on this page.');
            }
        });
    }

    if (zapperRefresh) {
        zapperRefresh.addEventListener('click', async () => {
            try {
                setError('');
                zapperRefresh.disabled = true;
                currentZapperRules = await getAuthoritativeZapperRules(host);
                await updateZapperCount(host);
                if (zapperRulesExpanded) renderZapperRules(currentZapperRules);
                await notifyZapperRulesChanged(tab.id);
            } catch (error) {
                console.error('[wBlock] Failed to refresh zapper rules:', error);
                setError('Failed to refresh zapper rules.');
            } finally {
                zapperRefresh.disabled = false;
            }
        });
    }

    if (zapperClear) {
        zapperClear.addEventListener('click', async () => {
            try {
                setError('');
                const key = zapperStorageKey(host);
                await browser.storage.local.remove(key);
                const syncedRules = await syncRulesToNative(host, []);
                currentZapperRules = Array.isArray(syncedRules) ? syncedRules : [];
                await updateZapperCount(host);
                if (zapperRulesExpanded) renderZapperRules(currentZapperRules);
                await notifyZapperRulesChanged(tab.id);
            } catch (error) {
                console.error('[wBlock] Failed to clear zaps:', error);
                setError('Failed to clear zapper rules.');
            }
        });
    }
}

async function refreshUi() {
    setError('');

    const hostEl = document.getElementById('site-host');
    const disableToggle = document.getElementById('disable-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const zapperRefresh = document.getElementById('zapper-refresh');
    const rulesToggle = document.getElementById('zapper-rules-toggle');

    tab = await getActiveTab();
    host = tab && tab.url ? hostnameFromUrl(tab.url) : '';

    if (hostEl) hostEl.textContent = host || '—';

    if (!tab || !tab.id || !host) {
        setStatus('Unavailable', 'neutral');
        if (disableToggle) disableToggle.disabled = true;
        if (zapperActivate) zapperActivate.disabled = true;
        if (zapperRefresh) zapperRefresh.disabled = true;
        if (rulesToggle) rulesToggle.disabled = true;
        await updateZapperCount('');
        setRulesExpanded(false);
        return;
    }

    setStatus('Checking…', 'neutral');

    const disabled = await getSiteDisabledState(host);
    if (disableToggle) {
        disableToggle.checked = disabled;
        disableToggle.disabled = false;
    }
    setStatus(disabled ? 'Disabled' : 'Active', disabled ? 'disabled' : 'active');

    if (rulesToggle) {
        rulesToggle.disabled = false;
    }
    if (zapperRefresh) {
        zapperRefresh.disabled = false;
    }

    currentZapperRules = await getAuthoritativeZapperRules(host);
    await updateZapperCount(host);

    if (zapperRulesExpanded) {
        renderZapperRules(currentZapperRules);
    }
}

document.addEventListener('DOMContentLoaded', () => {
    setupListeners();
    refreshUi().catch((error) => {
        console.error('[wBlock] Popup init failed:', error);
        setError('Failed to load popup.');
    });
});
