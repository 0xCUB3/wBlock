const NATIVE_HOST_ID = 'application.id';
const ZAPPER_STORAGE_PREFIX = 'wblock.zapperRules.v1:';
const ZAPPER_META_PREFIX = 'wblock.zapperMeta.v1:';
const SUPPORT_PROBE_TIMEOUT_MS = 800;

function t(key, substitutions, fallback = '') {
    const message = browser.i18n.getMessage(key, substitutions);
    if (typeof message === 'string' && message.length > 0) {
        return message;
    }
    return fallback;
}

function localizeStaticPopupText() {
    const nodes = document.querySelectorAll('[data-i18n]');
    for (const node of nodes) {
        const key = node.getAttribute('data-i18n');
        if (!key) continue;
        const localized = t(key, undefined, '');
        if (!localized) continue;
        node.textContent = localized;
    }
}

function normalizeDiagnosticFields(fields) {
    return Object.fromEntries(
        Object.entries(fields)
            .filter(([, value]) => value !== undefined && value !== null && value !== '')
            .map(([key, value]) => [key, String(value)])
    );
}

async function logExtensionDiagnostic(fields) {
    const normalizedFields = normalizeDiagnosticFields(fields);
    console.info('[wBlock] Support diagnostic', normalizedFields);
    try {
        await browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
            action: 'logExtensionDiagnostic',
            fields: normalizedFields,
        });
    } catch (error) {
        console.warn('[wBlock] Failed to forward support diagnostic to native log:', error, normalizedFields);
    }
}

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

function getPageSupport(tab) {
    if (!tab || !tab.id || typeof tab.url !== 'string' || tab.url.length === 0) {
        return { supported: false, host: '' };
    }

    try {
        const url = new URL(tab.url);
        const supported = (url.protocol === 'http:' || url.protocol === 'https:') && Boolean(url.hostname);
        return {
            supported,
            host: supported ? url.hostname : '',
        };
    } catch {
        return { supported: false, host: '' };
    }
}

async function probeTabSupport(tabId) {
    if (!tabId) return false;

    const probePromise = browser.tabs.sendMessage(tabId, {
        type: 'wblock:pageSupportProbe',
    })
        .then((response) => Boolean(
            response &&
            response.ok === true &&
            (response.protocol === 'http:' || response.protocol === 'https:') &&
            typeof response.host === 'string' &&
            response.host.length > 0
        ))
        .catch(() => false);

    const timeoutPromise = new Promise((resolve) => {
        setTimeout(() => resolve(false), SUPPORT_PROBE_TIMEOUT_MS);
    });

    return Promise.race([probePromise, timeoutPromise]);
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
        empty.textContent = t('popup_rules_empty', undefined, 'No rules');
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
        del.setAttribute('aria-label', t('popup_rule_delete_aria', undefined, 'Delete rule'));
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

async function shouldShowOpenAppButton() {
    try {
        const info = await browser.runtime.getPlatformInfo();
        return typeof info?.os === 'string' && info.os === 'mac';
    } catch (error) {
        console.warn('[wBlock] Failed to get platform info:', error);
        return false;
    }
}

function setupListeners() {
    const rulesToggle = document.getElementById('zapper-rules-toggle');
    const rulesContainer = document.getElementById('zapper-rules');
    const disableToggle = document.getElementById('disable-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const zapperClear = document.getElementById('zapper-clear');
    const openAppButton = document.getElementById('open-app');

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
                setError(t('popup_error_load_rules', undefined, 'Failed to load rules.'));
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
                setError(t('popup_error_delete_rule', undefined, 'Failed to delete rule.'));
            }
        });
    }

    if (disableToggle) {
        disableToggle.addEventListener('change', async () => {
            try {
                setError('');
                disableToggle.disabled = true;
                const next = disableToggle.checked;
                setStatus(next
                    ? t('popup_status_disabling', undefined, 'Disabling…')
                    : t('popup_status_enabling', undefined, 'Enabling…'), 'neutral');
                const updateResult = await setSiteDisabledState(host, next);
                try {
                    await browser.runtime.sendMessage({ action: 'wblock:clearCache' });
                } catch (error) {
                    console.warn('[wBlock] Failed to clear configuration cache:', error);
                }
                const settleMs = updateResult && updateResult.failedTargets > 0 ? 1200 : 350;
                await sleep(settleMs);
                setStatus(next
                    ? t('popup_status_disabled', undefined, 'Disabled')
                    : t('popup_status_active', undefined, 'Active'),
                next ? 'disabled' : 'active');
                await reloadActiveTab(tab.id);
            } catch (error) {
                console.error('[wBlock] Failed to update disabled state:', error);
                setError(t('popup_error_update_site_setting', undefined, 'Failed to update site setting.'));
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
                setError(t('popup_error_zapper_unavailable', undefined, 'Element Zapper is unavailable on this page.'));
            }
        });
    }

    if (openAppButton) {
        openAppButton.addEventListener('click', async () => {
            try {
                setError('');
                openAppButton.disabled = true;
                const response = await browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
                    action: 'openContainingApp',
                });
                if (response && response.opened) {
                    window.close();
                    return;
                }

                setError((response && response.error) || t('popup_error_open_app', undefined, 'Failed to open the app.'));
            } catch (error) {
                console.error('[wBlock] Failed to open app:', error);
                setError(t('popup_error_open_app', undefined, 'Failed to open the app.'));
            } finally {
                openAppButton.disabled = false;
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
                await reloadActiveTab(tab.id);
            } catch (error) {
                console.error('[wBlock] Failed to clear zaps:', error);
                setError(t('popup_error_clear_rules', undefined, 'Failed to clear zapper rules.'));
            }
        });
    }
}

async function refreshUi() {
    setError('');

    const hostEl = document.getElementById('site-host');
    const disableToggle = document.getElementById('disable-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const rulesToggle = document.getElementById('zapper-rules-toggle');
    const openAppButton = document.getElementById('open-app');

    if (openAppButton) {
        openAppButton.hidden = !(await shouldShowOpenAppButton());
    }
    tab = await getActiveTab();
    const pageSupport = getPageSupport(tab);
    const contentScriptReachable = pageSupport.supported ? await probeTabSupport(tab.id) : false;
    host = contentScriptReachable ? pageSupport.host : '';

    if (hostEl) hostEl.textContent = host || '—';

    if (!pageSupport.supported || !contentScriptReachable) {
        setStatus(t('popup_status_unsupported', undefined, 'Unsupported'), 'neutral');
        if (disableToggle) disableToggle.disabled = true;
        if (zapperActivate) zapperActivate.disabled = true;
        if (rulesToggle) rulesToggle.disabled = true;
        await logExtensionDiagnostic({
            event: 'popup_support_fallback',
            source: 'popup',
            outcome: 'unsupported',
            reason: !pageSupport.supported ? 'url_unsupported' : 'probe_unreachable',
            tabId: tab && tab.id ? tab.id : '',
            url: tab && typeof tab.url === 'string' ? tab.url : '',
            host: pageSupport.host,
        });
        await updateZapperCount('');
        setRulesExpanded(false);
        return;
    }

    setStatus(t('popup_status_checking', undefined, 'Checking…'), 'neutral');

    const disabled = await getSiteDisabledState(host);
    if (disableToggle) {
        disableToggle.checked = disabled;
        disableToggle.disabled = false;
    }
    setStatus(disabled
        ? t('popup_status_disabled', undefined, 'Disabled')
        : t('popup_status_active', undefined, 'Active'),
    disabled ? 'disabled' : 'active');

    if (rulesToggle) {
        rulesToggle.disabled = false;
    }
    currentZapperRules = await getAuthoritativeZapperRules(host);
    await updateZapperCount(host);

    if (zapperRulesExpanded) {
        renderZapperRules(currentZapperRules);
    }
}

document.addEventListener('DOMContentLoaded', () => {
    localizeStaticPopupText();
    setupListeners();
    refreshUi().catch((error) => {
        console.error('[wBlock] Popup init failed:', error);
        setError(t('popup_error_load_popup', undefined, 'Failed to load popup.'));
    });
});
