const NATIVE_HOST_ID = 'application.id';
const ZAPPER_STORAGE_PREFIX = 'wblock.zapperRules.v1:';
const ZAPPER_META_PREFIX = 'wblock.zapperMeta.v1:';
const NO_AUTOPLAY_ENABLED_KEY = 'wblock.noAutoplay.enabled.v1';
const NO_AUTOPLAY_ALLOW_PREFIX = 'wblock.noAutoplayAllow.v1:';
const NO_AUTOPLAY_NATIVE_MIGRATED_KEY = 'wblock.noAutoplay.nativeMigrated.v1';
const SUPPORT_PROBE_TIMEOUT_MS = 1200;
const SUPPORT_PROBE_ATTEMPTS = 5;
const SUPPORT_PROBE_RETRY_DELAY_MS = 200;
const TOP_FRAME_ID = 0;
const NATIVE_MESSAGE_TIMEOUT_MS = 3500;
const FILTER_UPDATE_POLL_INTERVAL_MS = 500;
const FILTER_UPDATE_POLL_ATTEMPTS = 120;
let resumeInFlight = false;

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

function sendNativeMessageWithTimeout(message, timeoutMs = NATIVE_MESSAGE_TIMEOUT_MS) {
    return withTimeout(
        browser.runtime.sendNativeMessage(NATIVE_HOST_ID, message),
        timeoutMs,
        `Native message timed out: ${message && message.action ? message.action : 'unknown'}`
    );
}

async function logExtensionDiagnostic(fields) {
    const normalizedFields = normalizeDiagnosticFields(fields);
    console.info('[wBlock] Support diagnostic', normalizedFields);
    try {
        await sendNativeMessageWithTimeout({
            action: 'logExtensionDiagnostic',
            fields: normalizedFields,
        }, 1200);
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
        return { pendingSync: false, lastLocalEditAt: 0, lastSyncAt: 0, disabled: false };
    }
    const lastLocalEditAt = Number(raw.lastLocalEditAt);
    const lastSyncAt = Number(raw.lastSyncAt);
    return {
        pendingSync: Boolean(raw.pendingSync),
        lastLocalEditAt: Number.isFinite(lastLocalEditAt) ? lastLocalEditAt : 0,
        lastSyncAt: Number.isFinite(lastSyncAt) ? lastSyncAt : 0,
        disabled: raw.disabled === true,
    };
}

async function getSyncMeta(host) {
    if (!host) return { pendingSync: false, lastLocalEditAt: 0, lastSyncAt: 0, disabled: false };
    try {
        const key = zapperMetaKey(host);
        const result = await browser.storage.local.get(key);
        return normalizeSyncMeta(result[key]);
    } catch {
        return { pendingSync: false, lastLocalEditAt: 0, lastSyncAt: 0, disabled: false };
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

async function cacheZapperState(host, rules, disabled) {
    if (!host) return;
    const key = zapperStorageKey(host);
    await browser.storage.local.set({ [key]: normalizeRules(rules) });
    await setSyncMeta(host, {
        pendingSync: false,
        lastSyncAt: Date.now(),
        disabled: disabled === true,
    });
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
    } catch (error) {
        console.warn('[wBlock] Failed to migrate legacy Zapper state:', error);
        return false;
    }
}

function normalizeNativeZapperState(response) {
    if (!response || !Array.isArray(response.rules)) {
        return null;
    }
    return {
        rules: normalizeRules(response.rules),
        disabled: response.disabled === true,
    };
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
            const response = await sendNativeMessageWithTimeout({
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
        const response = await withTimeout(browser.runtime.sendMessage({
            action: 'wblock:zapper:getRules',
            hostname: host,
        }), NATIVE_MESSAGE_TIMEOUT_MS, 'Zapper fetch timed out.');
        const state = normalizeNativeZapperState(response);
        if (!state) {
            return null;
        }
        const localRules = await loadZapperRules(host);
        const localSig = rulesSignature(localRules);
        const nativeSig = rulesSignature(state.rules);
        const meta = await getSyncMeta(host);
        if (meta.pendingSync && localSig !== nativeSig) {
            const reconciled = await syncRulesToNative(host, localRules);
            const rules = Array.isArray(reconciled) ? reconciled : localRules;
            const disabled = state.disabled || await migrateLegacyZapperRulesDisabled(host, rules);
            await setSyncMeta(host, { disabled });
            return { rules, disabled };
        }
        const disabled = state.disabled || await migrateLegacyZapperRulesDisabled(host, state.rules.length === 0 ? localRules : null);
        await cacheZapperState(host, state.rules, disabled);
        return { rules: state.rules, disabled };
    } catch {
        try {
            const response = await sendNativeMessageWithTimeout({
                action: 'getZapperRules',
                hostname: host,
            });
            const state = normalizeNativeZapperState(response);
            if (!state) {
                return null;
            }
            const localRules = await loadZapperRules(host);
            const localSig = rulesSignature(localRules);
            const nativeSig = rulesSignature(state.rules);
            const meta = await getSyncMeta(host);
            if (meta.pendingSync && localSig !== nativeSig) {
                const reconciled = await syncRulesToNative(host, localRules);
                const rules = Array.isArray(reconciled) ? reconciled : localRules;
                const disabled = state.disabled || await migrateLegacyZapperRulesDisabled(host, rules);
                await setSyncMeta(host, { disabled });
                return { rules, disabled };
            }
            const disabled = state.disabled || await migrateLegacyZapperRulesDisabled(host, state.rules.length === 0 ? localRules : null);
            await cacheZapperState(host, state.rules, disabled);
            return { rules: state.rules, disabled };
        } catch {
            return null;
        }
    }
}

async function getAuthoritativeZapperState(host) {
    if (!host) return { rules: [], disabled: false };
    const nativeState = await fetchRulesFromNative(host);
    if (nativeState && Array.isArray(nativeState.rules)) {
        return nativeState;
    }
    const localRules = await loadZapperRules(host);
    if (localRules.length > 0) {
        syncRulesToNative(host, localRules).catch(() => {});
    }
    return {
        rules: localRules,
        disabled: (await getSyncMeta(host)).disabled === true,
    };
}

async function getAuthoritativeZapperRules(host) {
    return (await getAuthoritativeZapperState(host)).rules;
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
    const popupBody = document.querySelector('.popup-body');
    if (popupBody) popupBody.scrollTop = 0;
}

function setStatus(text, kind = 'neutral') {
    const statusEl = document.getElementById('blocking-status');
    if (!statusEl) return;
    statusEl.textContent = text;
    statusEl.classList.remove('is-active', 'is-disabled', 'is-neutral', 'is-error');
    if (kind === 'active') statusEl.classList.add('is-active');
    else if (kind === 'disabled') statusEl.classList.add('is-disabled');
    else if (kind === 'error') statusEl.classList.add('is-error');
    else statusEl.classList.add('is-neutral');
}

let filterUpdatePollPromise = null;
let filterUpdatePollToken = 0;

function renderFilterUpdateStatus(snapshot) {
    const button = document.getElementById('update-filters');
    const statusEl = document.getElementById('filter-update-status');
    if (!button || !statusEl) return;

    const state = snapshot && typeof snapshot.state === 'string' ? snapshot.state : 'idle';
    statusEl.classList.remove('is-running', 'is-success', 'is-error');
    statusEl.hidden = state === 'idle';
    button.disabled = state === 'running';
    if (state === 'running') {
        button.setAttribute('aria-busy', 'true');
        statusEl.classList.add('is-running');
        statusEl.textContent = t('popup_status_updating_filters', undefined, 'Updating filters…');
        return;
    }
    button.removeAttribute('aria-busy');
    if (state === 'succeeded') {
        statusEl.classList.add('is-success');
        const count = Number(snapshot.updatedFilters);
        statusEl.textContent = count > 0
            ? t('popup_status_filters_updated', [String(count)], `Filters updated (${count}).`)
            : t('popup_status_filters_updated', undefined, 'Filters updated.');
    } else if (state === 'no_change') {
        statusEl.classList.add('is-success');
        statusEl.textContent = t('popup_status_filters_no_change', undefined, 'Filters are up to date.');
    } else if (state === 'failed') {
        statusEl.classList.add('is-error');
        statusEl.textContent = snapshot.error || t('popup_error_filter_update', undefined, 'Filter update failed.');
    }
}

async function getFilterUpdateStatus() {
    const response = await withTimeout(
        browser.runtime.sendMessage({ action: 'wblock:filterUpdate:getStatus' }),
        NATIVE_MESSAGE_TIMEOUT_MS,
        'Filter update status timed out.'
    );
    if (!response || response.ok !== true || typeof response.state !== 'string') {
        throw new Error((response && response.error) || 'Invalid filter update status.');
    }
    return response;
}

async function pollFilterUpdateStatus() {
    if (filterUpdatePollPromise) return filterUpdatePollPromise;
    const token = ++filterUpdatePollToken;
    filterUpdatePollPromise = (async () => {
        let waitingForStart = 5;
        for (let attempt = 0; attempt < FILTER_UPDATE_POLL_ATTEMPTS; attempt += 1) {
            if (token !== filterUpdatePollToken) return null;
            const snapshot = await getFilterUpdateStatus();
            if (snapshot.state === 'running') {
                waitingForStart = 0;
                renderFilterUpdateStatus(snapshot);
            } else if (snapshot.state === 'idle' && waitingForStart > 0) {
                // The XPC acknowledgement can arrive just before the shared status write.
                waitingForStart -= 1;
                renderFilterUpdateStatus({ state: 'running' });
            } else {
                renderFilterUpdateStatus(snapshot);
                return snapshot;
            }
            await sleep(FILTER_UPDATE_POLL_INTERVAL_MS);
        }
        throw new Error(t('popup_error_filter_update', undefined, 'Filter update status is unavailable.'));
    })().finally(() => {
        filterUpdatePollPromise = null;
    });
    return filterUpdatePollPromise;
}

async function refreshFilterUpdateStatus() {
    try {
        const snapshot = await getFilterUpdateStatus();
        renderFilterUpdateStatus(snapshot);
        if (snapshot.state === 'running') {
            await pollFilterUpdateStatus();
        }
    } catch (error) {
        console.warn('[wBlock] Filter update status unavailable:', error);
    }
}

async function startFilterUpdate() {
    const button = document.getElementById('update-filters');
    if (!button || button.disabled) return;
    setError('');
    renderFilterUpdateStatus({ state: 'running' });
    try {
        const response = await withTimeout(
            browser.runtime.sendMessage({ action: 'wblock:filterUpdate:start' }),
            NATIVE_MESSAGE_TIMEOUT_MS,
            'Filter update start timed out.'
        );
        if (!response || response.ok !== true || response.state !== 'running') {
            throw new Error((response && response.error) || t('popup_error_filter_update_start', undefined, 'Could not start filter update.'));
        }
        await pollFilterUpdateStatus();
    } catch (error) {
        console.error('[wBlock] Filter update failed:', error);
        renderFilterUpdateStatus({
            state: 'failed',
            error: (error && error.message) || t('popup_error_filter_update', undefined, 'Filter update failed.'),
        });
    }
}

async function getActiveTab() {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    return tabs && tabs.length ? tabs[0] : null;
}

async function getActiveTabWithRetry() {
    for (let attempt = 0; attempt < SUPPORT_PROBE_ATTEMPTS; attempt += 1) {
        const activeTab = await getActiveTab();
        if (activeTab && typeof activeTab.url === 'string' && activeTab.url.length > 0) {
            return activeTab;
        }
        if (attempt + 1 < SUPPORT_PROBE_ATTEMPTS) {
            await sleep(SUPPORT_PROBE_RETRY_DELAY_MS);
        }
    }

    return getActiveTab();
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

function isSuccessfulTabMessageResponse(response) {
    return Boolean(response && response.ok === true);
}

function isSupportedProbeResponse(response) {
    return Boolean(
        isSuccessfulTabMessageResponse(response) &&
        (response.protocol === 'http:' || response.protocol === 'https:') &&
        typeof response.host === 'string' &&
        response.host.length > 0
    );
}

function isZapperCommandResponse(response) {
    return Boolean(
        isSuccessfulTabMessageResponse(response) &&
        response.handledBy === 'zapper-content'
    );
}

async function sendTabMessageWithRetry(tabId, message, { timeoutMs = null, validateResponse = isSuccessfulTabMessageResponse, frameId = TOP_FRAME_ID } = {}) {
    if (!tabId) throw new Error('Missing tab');
    let lastError = null;

    for (let attempt = 0; attempt < SUPPORT_PROBE_ATTEMPTS; attempt += 1) {
        try {
            const messageOptions = typeof frameId === 'number' ? { frameId } : undefined;
            const messagePromise = messageOptions
                ? browser.tabs.sendMessage(tabId, message, messageOptions)
                : browser.tabs.sendMessage(tabId, message);
            const response = timeoutMs === null
                ? await messagePromise
                : await withTimeout(messagePromise, timeoutMs, 'Tab message timed out.');

            if (!validateResponse || validateResponse(response)) {
                return response;
            }

            lastError = new Error('Unexpected tab message response.');
        } catch (error) {
            lastError = error;
        }

        if (attempt + 1 < SUPPORT_PROBE_ATTEMPTS) {
            await sleep(SUPPORT_PROBE_RETRY_DELAY_MS);
        }
    }

    throw lastError || new Error('Failed to deliver tab message.');
}

async function probeTabSupport(tabId) {
    if (!tabId) return false;

    try {
        await sendTabMessageWithRetry(tabId, { type: 'wblock:pageSupportProbe' }, {
            timeoutMs: SUPPORT_PROBE_TIMEOUT_MS,
            validateResponse: isSupportedProbeResponse,
        });
        return true;
    } catch {
        return false;
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
        await browser.tabs.sendMessage(tabId, { type: 'wblock:zapper:reloadRules' }, { frameId: TOP_FRAME_ID });
    } catch {
        // Content script may not be reachable on certain pages; ignore.
    }
}

let zapperRulesExpanded = false;
let userscriptsExpanded = false;
let currentZapperRules = [];
let currentPageUserScripts = [];
let host = '';
let tab = null;
let siteToggleGeneration = 0;
let siteToggleInFlight = false;

const DISCLOSURE_DURATION_MS = 200;

function prefersReducedMotion() {
    try {
        return Boolean(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    } catch {
        return false;
    }
}

function setDisclosureInert(panel, inert) {
    if ('inert' in panel) {
        panel.inert = inert;
        if (!inert) panel.removeAttribute('aria-hidden');
        return;
    }
    if (inert) {
        panel.setAttribute('aria-hidden', 'true');
    } else {
        panel.removeAttribute('aria-hidden');
    }
}

function setDisclosureOpen(panel, open, toggle) {
    if (!panel) return;

    const alreadyOpen = !panel.hidden && panel.classList.contains('is-open');
    const alreadyClosed = panel.hidden && !panel.classList.contains('is-open');
    if (open && alreadyOpen) return;
    if (!open && alreadyClosed) return;

    const token = (Number(panel.dataset.disclosureToken) || 0) + 1;
    panel.dataset.disclosureToken = String(token);

    if (panel._disclosureOnEnd) {
        panel.removeEventListener('transitionend', panel._disclosureOnEnd);
        panel._disclosureOnEnd = null;
    }
    if (panel._disclosureTimer) {
        clearTimeout(panel._disclosureTimer);
        panel._disclosureTimer = 0;
    }

    const reduced = prefersReducedMotion();

    if (open) {
        setDisclosureInert(panel, false);
        panel.hidden = false;
        if (reduced) {
            panel.classList.add('is-open');
            return;
        }
        panel.classList.remove('is-open');
        requestAnimationFrame(() => {
            if (Number(panel.dataset.disclosureToken) !== token) return;
            requestAnimationFrame(() => {
                if (Number(panel.dataset.disclosureToken) !== token) return;
                panel.classList.add('is-open');
            });
        });
        return;
    }

    setDisclosureInert(panel, true);
    if (toggle && panel.contains(document.activeElement)) {
        toggle.focus();
    }

    const hide = () => {
        if (Number(panel.dataset.disclosureToken) !== token) return;
        if (panel._disclosureOnEnd) {
            panel.removeEventListener('transitionend', panel._disclosureOnEnd);
            panel._disclosureOnEnd = null;
        }
        if (panel._disclosureTimer) {
            clearTimeout(panel._disclosureTimer);
            panel._disclosureTimer = 0;
        }
        panel.hidden = true;
        panel.classList.remove('is-open');
    };

    if (reduced) {
        hide();
        return;
    }

    panel.classList.remove('is-open');
    panel._disclosureOnEnd = (event) => {
        if (event.target !== panel) return;
        hide();
    };
    panel.addEventListener('transitionend', panel._disclosureOnEnd);
    panel._disclosureTimer = setTimeout(hide, DISCLOSURE_DURATION_MS + 50);
}

function setRulesExpanded(expanded) {
    zapperRulesExpanded = expanded;
    const toggle = document.getElementById('zapper-rules-toggle');
    if (toggle) toggle.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    setDisclosureOpen(document.getElementById('zapper-rules-panel'), expanded, toggle);
}

function setUserscriptsExpanded(expanded) {
    userscriptsExpanded = expanded;
    const toggle = document.getElementById('userscripts-toggle');
    const list = document.getElementById('userscripts-list');
    const empty = document.getElementById('userscripts-empty');
    const hasScripts = currentPageUserScripts.length > 0;
    if (toggle) toggle.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    if (list) list.hidden = !hasScripts;
    if (empty) empty.hidden = hasScripts;
    setDisclosureOpen(document.getElementById('userscripts-panel'), expanded, toggle);
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

async function getBlockingPausedState() {
    try {
        const response = await sendNativeMessageWithTimeout({
            action: 'getBlockingPausedState',
        });
        if (!response || typeof response.paused !== 'boolean' ||
            typeof response.filtersPaused !== 'boolean' ||
            typeof response.userScriptsPaused !== 'boolean' ||
            typeof response.elementZapperPaused !== 'boolean' ||
            typeof response.resumeAvailable !== 'boolean') {
            throw new Error('Invalid pause state response');
        }
        return response;
    } catch (error) {
        console.error('[wBlock] Failed to get pause state:', error);
        return null;
    }
}

async function getResumeRequestStatus() {
    try {
        const response = await sendNativeMessageWithTimeout({
            action: 'getResumeRequestStatus',
        });
        if (!response || response.ok !== true || typeof response.status !== 'string') {
            return null;
        }
        return response;
    } catch (error) {
        console.warn('[wBlock] Resume status unavailable:', error);
        return null;
    }
}

async function resumeBlocking() {
    let response;
    try {
        response = await sendNativeMessageWithTimeout({
            action: 'resumeBlocking',
        }, 10000);
    } catch (error) {
        console.warn('[wBlock] Containing app did not answer resume request:', error);
        return { status: 'unavailable' };
    }
    if (!response || response.ok !== true) {
        throw new Error((response && response.error) || 'Resume request failed');
    }
    if (response.status === 'succeeded' && response.paused === false) {
        return { status: 'succeeded' };
    }
    // A wake failure only means the app was not launched by this request. Keep polling
    // briefly because a resident containing app can still consume the Darwin request.
    if (typeof response.status !== 'string') {
        return { status: 'unavailable' };
    }

    for (let attempt = 0; attempt < 20; attempt += 1) {
        await sleep(300);
        const status = await getResumeRequestStatus();
        if (!status) continue;
        if (status.status === 'succeeded' && status.paused === false) {
            return { status: 'succeeded' };
        }
        if (status.status === 'failed') {
            throw new Error(status.error || 'Resume request failed');
        }
    }
    // A pending request means the extension bridge is alive, but the containing app
    // may be terminated. Do not claim Active; leave the paused UI authoritative.
    return { status: 'unavailable' };
}

async function getSiteDisabledState(host) {
    if (!host) return false;
    try {
        const response = await sendNativeMessageWithTimeout({
            action: 'getSiteDisabledState',
            host,
        });
        return Boolean(response && response.disabled);
    } catch (error) {
        console.error('[wBlock] Failed to get disabled state:', error);
        return null;
    }
}

async function readSiteDisabledStateAfterTimeout(targetHost) {
    let actuallyDisabled = await getSiteDisabledState(targetHost);
    for (let attempt = 0; attempt < 2 && typeof actuallyDisabled !== 'boolean'; attempt += 1) {
        await sleep(300);
        actuallyDisabled = await getSiteDisabledState(targetHost);
    }
    return actuallyDisabled;
}

async function setSiteDisabledState(host, disabled) {
    if (!host) return;
    return sendNativeMessageWithTimeout({
        action: 'setSiteDisabledState',
        host,
        disabled: Boolean(disabled),
    }, 10000);
}

async function setSiteZapperDisabled(host, disabled) {
    if (!host) return { ok: false, disabled: false };
    const response = await sendNativeMessageWithTimeout({
        action: 'setSiteZapperDisabled',
        hostname: host,
        disabled: Boolean(disabled),
    }, 10000);
    const nextDisabled = Boolean(response && response.disabled);
    await setSyncMeta(host, { disabled: nextDisabled });
    return response;
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

async function isMacPlatform() {
    try {
        const info = await browser.runtime.getPlatformInfo();
        return typeof info?.os === 'string' && info.os === 'mac';
    } catch (error) {
        console.warn('[wBlock] Failed to get platform info:', error);
        return false;
    }
}
function getClosestTarget(event, selector) {
    if (!event || !event.target || !event.target.closest) return null;
    return event.target.closest(selector);
}

function renderUserscriptCommands(commands) {
    const container = document.getElementById('userscript-commands');
    if (!container) return;
    container.innerHTML = '';

    if (!Array.isArray(commands) || commands.length === 0) {
        container.hidden = true;
        return;
    }

    const list = document.createElement('div');
    list.className = 'command-list';

    for (const command of commands) {
        if (!command || typeof command.caption !== 'string' || !command.caption.trim()) continue;

        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'btn command-btn';
        button.setAttribute('data-bridge-id', command.bridgeId);
        button.setAttribute('data-command-id', command.commandId);
        button.setAttribute('data-frame-id', String(typeof command.frameId === 'number' ? command.frameId : 0));

        const label = document.createElement('span');
        label.className = 'command-label';
        label.textContent = command.caption;
        button.appendChild(label);

        const metaParts = [];
        if (typeof command.scriptName === 'string' && command.scriptName.trim()) metaParts.push(command.scriptName.trim());
        if (typeof command.frameId === 'number' && command.frameId !== 0) metaParts.push(`#${command.frameId}`);
        if (typeof command.title === 'string' && command.title.trim()) metaParts.push(command.title.trim());
        if (metaParts.length > 0) {
            const meta = document.createElement('span');
            meta.className = 'command-meta';
            meta.textContent = metaParts.join(', ');
            button.appendChild(meta);
        }

        list.appendChild(button);
    }

    if (list.childElementCount === 0) {
        container.hidden = true;
        return;
    }

    container.appendChild(list);
    container.hidden = false;
}

async function fetchUserscriptCommands(tabId) {
    if (!tabId) return [];
    try {
        const response = await browser.runtime.sendMessage({
            action: 'wblock:menu:getCommands',
            tabId,
        });
        if (!response || !Array.isArray(response.commands)) {
            return [];
        }
        return response.commands.filter((command) => (
            command
            && typeof command.bridgeId === 'string'
            && typeof command.commandId === 'string'
            && typeof command.caption === 'string'
            && command.caption.trim().length > 0
        ));
    } catch (error) {
        console.warn('[wBlock] Failed to fetch userscript commands:', error);
        return [];
    }
}

async function fetchPageUserScripts(url) {
    if (!url) return [];
    try {
        const response = await sendNativeMessageWithTimeout({
            action: 'getPageUserScripts',
            url,
        });
        if (!response || !Array.isArray(response.userScripts)) {
            return [];
        }
        return response.userScripts.filter((script) => (
            script
            && typeof script.id === 'string'
            && typeof script.name === 'string'
            && script.name.trim().length > 0
        ));
    } catch (error) {
        console.warn('[wBlock] Failed to fetch page userscripts:', error);
        return [];
    }
}

async function setUserscriptSiteDisabled(scriptId, disabled) {
    if (!scriptId || !host) {
        return { ok: false, error: 'Invalid userscript site setting request' };
    }
    try {
        const response = await sendNativeMessageWithTimeout({
            action: 'setUserScriptSiteDisabledState',
            scriptId,
            host,
            disabled: Boolean(disabled),
        }, 5000);
        return response || { ok: false, error: 'Userscript setting returned no response' };
    } catch (error) {
        return { ok: false, error: error && error.message ? error.message : String(error) };
    }
}

function renderPageUserScripts(scripts, disabled = false) {
    const section = document.getElementById('userscripts-section');
    const list = document.getElementById('userscripts-list');
    const empty = document.getElementById('userscripts-empty');
    const count = document.getElementById('userscripts-count');
    if (!section || !list) return;

    const normalizedScripts = Array.isArray(scripts) ? scripts : [];
    currentPageUserScripts = normalizedScripts;
    list.innerHTML = '';
    if (count) count.textContent = String(normalizedScripts.filter((script) => script && script.running !== false).length);

    if (normalizedScripts.length === 0) {
        section.hidden = true;
        setUserscriptsExpanded(false);
        return;
    }

    section.hidden = false;
    if (empty) empty.hidden = true;

    for (const script of normalizedScripts) {
        const idSuffix = String(script.id).replace(/[^A-Za-z0-9_-]/g, '_');
        const toggleId = `userscript-toggle-${idSuffix}`;
        const nameId = `userscript-name-${idSuffix}`;

        const row = document.createElement('div');
        row.className = 'userscript-row';

        const text = document.createElement('span');
        text.className = 'userscript-text';

        const name = document.createElement('span');
        name.className = 'userscript-name';
        name.id = nameId;
        name.textContent = script.name;
        text.appendChild(name);

        const control = document.createElement('label');
        control.className = 'switch';
        control.htmlFor = toggleId;

        const input = document.createElement('input');
        input.type = 'checkbox';
        input.id = toggleId;
        input.className = 'userscript-toggle';
        input.setAttribute('data-script-id', script.id);
        input.setAttribute('aria-labelledby', nameId);
        input.setAttribute('aria-label', script.name);
        input.checked = !script.disabledForSite;
        input.disabled = disabled;

        const slider = document.createElement('span');
        slider.className = 'slider';
        slider.setAttribute('aria-hidden', 'true');

        control.appendChild(input);
        control.appendChild(slider);
        row.appendChild(text);
        row.appendChild(control);
        list.appendChild(row);
    }

    setUserscriptsExpanded(userscriptsExpanded);
}

async function invokeUserscriptCommand(tabId, frameId, bridgeId, commandId) {
    if (!tabId || !bridgeId || !commandId) {
        return { ok: false, error: 'Invalid menu command request' };
    }
    try {
        const response = await browser.runtime.sendMessage({
            action: 'wblock:menu:invokeCommand',
            tabId,
            frameId,
            bridgeId,
            commandId,
        });
        return response || { ok: false, error: 'Menu command invocation returned no response' };
    } catch (error) {
        return { ok: false, error: error && error.message ? error.message : String(error) };
    }
}

let noAutoplaySiteDisabled = false;

function noAutoplayAllowKey(siteHost) {
    return `${NO_AUTOPLAY_ALLOW_PREFIX}${siteHost}`;
}

function isNativeNoAutoplayState(response) {
    return Boolean(
        response
        && typeof response.enabled === 'boolean'
        && typeof response.siteAllowed === 'boolean'
    );
}

async function readNoAutoplayLocalCache(siteHost) {
    const keys = [NO_AUTOPLAY_ENABLED_KEY];
    if (siteHost) keys.push(noAutoplayAllowKey(siteHost));
    try {
        const result = await browser.storage.local.get(keys);
        return {
            enabled: result[NO_AUTOPLAY_ENABLED_KEY] === true,
            siteAllowed: siteHost ? result[noAutoplayAllowKey(siteHost)] === true : false,
        };
    } catch (error) {
        console.warn('[wBlock] Failed to read No Autoplay local cache:', error);
        return null;
    }
}

async function mirrorNoAutoplayLocalCache(enabled, siteHost, siteAllowed) {
    try {
        await browser.storage.local.set({ [NO_AUTOPLAY_ENABLED_KEY]: enabled === true });
        if (siteHost) {
            const allowKey = noAutoplayAllowKey(siteHost);
            if (siteAllowed === true) {
                await browser.storage.local.set({ [allowKey]: true });
            } else {
                await browser.storage.local.remove(allowKey);
            }
        }
    } catch (error) {
        console.warn('[wBlock] Failed to mirror No Autoplay cache:', error);
    }
}

async function fetchNativeNoAutoplayState(siteHost) {
    try {
        const message = { action: 'getNoAutoplayState' };
        if (siteHost) message.host = siteHost;
        const response = await sendNativeMessageWithTimeout(message);
        return isNativeNoAutoplayState(response) ? response : null;
    } catch (error) {
        console.warn('[wBlock] Failed to read native No Autoplay state:', error);
        return null;
    }
}

async function hasMigratedNoAutoplayToNative() {
    try {
        const result = await browser.storage.local.get(NO_AUTOPLAY_NATIVE_MIGRATED_KEY);
        return result[NO_AUTOPLAY_NATIVE_MIGRATED_KEY] === true;
    } catch {
        return false;
    }
}

async function markNoAutoplayNativeMigrated() {
    try {
        await browser.storage.local.set({ [NO_AUTOPLAY_NATIVE_MIGRATED_KEY]: true });
    } catch (error) {
        console.warn('[wBlock] Failed to persist No Autoplay native migration flag:', error);
    }
}

function normalizedLegacyNoAutoplayAllowHost(rawHost) {
    let host = String(rawHost || '').trim().toLowerCase();
    if (!host) return null;
    const schemeIndex = host.indexOf('://');
    if (schemeIndex !== -1) host = host.slice(schemeIndex + 3);
    const separatorIndex = host.search(/[/?#]/);
    if (separatorIndex !== -1) host = host.slice(0, separatorIndex);
    const credentialsIndex = host.lastIndexOf('@');
    if (credentialsIndex !== -1) host = host.slice(credentialsIndex + 1);
    const portIndex = host.indexOf(':');
    if (portIndex !== -1) host = host.slice(0, portIndex);
    return /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/.test(host) ? host : null;
}

async function collectLegacyNoAutoplayAllowHosts(siteHost, localSiteAllowed) {
    const hosts = new Set();
    const addHost = (candidate) => {
        const host = normalizedLegacyNoAutoplayAllowHost(candidate);
        if (host) hosts.add(host);
    };
    if (localSiteAllowed === true) addHost(siteHost);
    let all;
    try {
        all = await browser.storage.local.get(null);
    } catch (error) {
        console.warn('[wBlock] Failed to enumerate legacy No Autoplay allows:', error);
        throw error;
    }
    for (const [key, value] of Object.entries(all || {})) {
        if (!key.startsWith(NO_AUTOPLAY_ALLOW_PREFIX) || value !== true) continue;
        addHost(key.slice(NO_AUTOPLAY_ALLOW_PREFIX.length));
    }
    return [...hosts];
}

async function migrateLegacyNoAutoplayToNative(local, siteHost) {
    if (await hasMigratedNoAutoplayToNative()) {
        return true;
    }
    try {
        const hosts = await collectLegacyNoAutoplayAllowHosts(siteHost, local.siteAllowed);
        for (const host of hosts) {
            const siteResponse = await sendNativeMessageWithTimeout({
                action: 'setNoAutoplaySiteAllowed',
                host,
                allowed: true,
            });
            if (siteResponse && siteResponse.error === 'Invalid host') {
                continue;
            }
            if (!siteResponse || siteResponse.ok !== true
                || typeof siteResponse.enabled !== 'boolean'
                || typeof siteResponse.siteAllowed !== 'boolean') {
                return false;
            }
        }
        if (local.enabled === true) {
            const enabledResponse = await sendNativeMessageWithTimeout({
                action: 'setNoAutoplayEnabled',
                enabled: true,
            });
            if (!enabledResponse || enabledResponse.ok !== true || typeof enabledResponse.enabled !== 'boolean') {
                return false;
            }
        }
        await markNoAutoplayNativeMigrated();
        return true;
    } catch (error) {
        console.warn('[wBlock] Failed to migrate No Autoplay state to native:', error);
        return false;
    }
}

async function getNoAutoplayState(siteHost) {
    const local = await readNoAutoplayLocalCache(siteHost);
    const localForMigrate = local ?? { enabled: false, siteAllowed: false };
    let native = await fetchNativeNoAutoplayState(siteHost);
    if (!native) {
        return local ?? { enabled: false, siteAllowed: false };
    }

    const migrated = await migrateLegacyNoAutoplayToNative(localForMigrate, siteHost);
    if (!migrated) {
        if (local !== null) {
            return local;
        }
        return { enabled: native.enabled, siteAllowed: native.siteAllowed };
    }

    native = await fetchNativeNoAutoplayState(siteHost) || native;
    await mirrorNoAutoplayLocalCache(native.enabled, siteHost, native.siteAllowed);
    return { enabled: native.enabled, siteAllowed: native.siteAllowed };
}

async function setNoAutoplayEnabled(enabled) {
    const nextEnabled = enabled === true;
    const response = await sendNativeMessageWithTimeout({
        action: 'setNoAutoplayEnabled',
        enabled: nextEnabled,
    });
    if (!response || response.ok !== true || typeof response.enabled !== 'boolean') {
        throw new Error('Native No Autoplay enabled write did not persist');
    }
    await mirrorNoAutoplayLocalCache(response.enabled, null, false);
}

async function setNoAutoplaySiteAllowed(siteHost, allowed) {
    if (!siteHost) return;
    const nextAllowed = allowed === true;
    const response = await sendNativeMessageWithTimeout({
        action: 'setNoAutoplaySiteAllowed',
        host: siteHost,
        allowed: nextAllowed,
    });
    if (!response || response.ok !== true
        || typeof response.enabled !== 'boolean'
        || typeof response.siteAllowed !== 'boolean') {
        throw new Error('Native No Autoplay site allow write did not persist');
    }
    await mirrorNoAutoplayLocalCache(response.enabled, siteHost, response.siteAllowed);
}

function updateNoAutoplayControls(state, options = {}) {
    const enabledToggle = document.getElementById('no-autoplay-enabled-toggle');
    const siteRow = document.getElementById('no-autoplay-site-row');
    const siteToggle = document.getElementById('no-autoplay-site-toggle');
    const locked = options.locked === true;
    if (enabledToggle) {
        enabledToggle.checked = state.enabled;
        enabledToggle.disabled = locked;
    }
    if (siteRow) siteRow.hidden = !state.enabled || !options.host;
    if (siteToggle) {
        siteToggle.checked = state.siteAllowed;
        siteToggle.disabled = locked || options.siteDisabled === true;
    }
}

function setupListeners() {
    const rulesToggle = document.getElementById('zapper-rules-toggle');
    const rulesContainer = document.getElementById('zapper-rules');
    const disableToggle = document.getElementById('enable-toggle');
    const zapperEnabledToggle = document.getElementById('zapper-enabled-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const zapperClear = document.getElementById('zapper-clear');
    const userscriptCommands = document.getElementById('userscript-commands');
    const userscriptsList = document.getElementById('userscripts-list');
    const userscriptsToggle = document.getElementById('userscripts-toggle');
    const openAppButton = document.getElementById('open-app');
    const resumeButton = document.getElementById('resume-blocking');
    const updateFiltersButton = document.getElementById('update-filters');

    if (updateFiltersButton) {
        updateFiltersButton.addEventListener('click', () => {
            startFilterUpdate().catch((error) => {
                console.error('[wBlock] Filter update action failed:', error);
            });
        });
    }

    if (userscriptsToggle) {
        userscriptsToggle.addEventListener('click', () => {
            setUserscriptsExpanded(!userscriptsExpanded);
        });
    }

    if (rulesToggle) {
        rulesToggle.addEventListener('click', async () => {
            try {
                setError('');
                setRulesExpanded(!zapperRulesExpanded);
                if (!zapperRulesExpanded) return;
                renderZapperRules(currentZapperRules);
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
            const element = getClosestTarget(event, 'button.rule-delete');
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
            const generation = ++siteToggleGeneration;
            siteToggleInFlight = true;
            const next = !disableToggle.checked;
            const previousChecked = !disableToggle.checked;
            const targetHost = host;
            const targetTab = tab;
            try {
                if (!targetHost) {
                    disableToggle.checked = previousChecked;
                    return;
                }

                setError('');
                disableToggle.disabled = true;
                setStatus(next
                    ? t('popup_status_disabling', undefined, 'Disabling…')
                    : t('popup_status_enabling', undefined, 'Enabling…'), 'neutral');
                const updateResult = await setSiteDisabledState(targetHost, next);
                try {
                    await browser.runtime.sendMessage({ action: 'wblock:clearCache' });
                } catch (error) {
                    console.warn('[wBlock] Failed to clear configuration cache:', error);
                }
                const failedTargets = Number(updateResult && updateResult.failedTargets) || 0;
                const requiresFullApply = Boolean(updateResult && updateResult.requiresFullApply);
                if (requiresFullApply) {
                    setError(t(
                        'popup_warning_open_app_to_apply',
                        undefined,
                        'Open wBlock to finish applying filters.'
                    ));
                } else if (failedTargets > 0) {
                    setError(t('popup_error_update_site_setting', undefined, 'Failed to update site setting.'));
                }
                disableToggle.checked = !next;
                setStatus(next
                    ? t('popup_status_disabled', undefined, 'Disabled')
                    : t('popup_status_active', undefined, 'Active'),
                next ? 'disabled' : 'active');
                await reloadActiveTab(targetTab && targetTab.id);
            } catch (error) {
                console.error('[wBlock] Failed to update disabled state:', error);
                // The native write can finish after the popup times out. Re-read
                // the authoritative state before treating this as a hard failure.
                let actuallyDisabled = null;
                try {
                    actuallyDisabled = await readSiteDisabledStateAfterTimeout(targetHost);
                } catch (reconcileError) {
                    console.warn('[wBlock] Failed to reconcile site setting after error:', reconcileError);
                    actuallyDisabled = null;
                }
                if (typeof actuallyDisabled === 'boolean') {
                    disableToggle.checked = !actuallyDisabled;
                    if (actuallyDisabled === next) {
                        setStatus(next
                            ? t('popup_status_disabled', undefined, 'Disabled')
                            : t('popup_status_active', undefined, 'Active'),
                        next ? 'disabled' : 'active');
                        await reloadActiveTab(targetTab && targetTab.id);
                        return;
                    }
                } else {
                    disableToggle.checked = previousChecked;
                }
                setError(t('popup_error_update_site_setting', undefined, 'Failed to update site setting.'));
                setStatus(t('popup_status_error', undefined, 'Error'), 'error');
            } finally {
                if (generation === siteToggleGeneration) {
                    siteToggleInFlight = false;
                    disableToggle.disabled = false;
                }
            }
        });
    }

    if (zapperEnabledToggle) {
        zapperEnabledToggle.addEventListener('change', async () => {
            const nextEnabled = zapperEnabledToggle.checked;
            try {
                setError('');
                zapperEnabledToggle.disabled = true;
                const response = await setSiteZapperDisabled(host, !nextEnabled);
                const disabled = Boolean(response && response.disabled);
                zapperEnabledToggle.checked = !disabled;
                if (zapperActivate) {
                    zapperActivate.disabled = (disableToggle ? !disableToggle.checked : false) || disabled;
                }
                await notifyZapperRulesChanged(tab.id);
                await reloadActiveTab(tab.id);
            } catch (error) {
                console.error('[wBlock] Failed to update Zapper state:', error);
                setError(t('popup_error_update_site_setting', undefined, 'Failed to update site setting.'));
                zapperEnabledToggle.checked = !nextEnabled;
            } finally {
                zapperEnabledToggle.disabled = false;
            }
        });
    }

    const noAutoplayEnabledToggle = document.getElementById('no-autoplay-enabled-toggle');
    const noAutoplaySiteToggle = document.getElementById('no-autoplay-site-toggle');

    if (noAutoplayEnabledToggle) {
        noAutoplayEnabledToggle.addEventListener('change', async () => {
            const nextEnabled = noAutoplayEnabledToggle.checked;
            try {
                setError('');
                noAutoplayEnabledToggle.disabled = true;
                await setNoAutoplayEnabled(nextEnabled);
                const state = await getNoAutoplayState(host);
                updateNoAutoplayControls(state, { host, siteDisabled: noAutoplaySiteDisabled });
            } catch (error) {
                console.error('[wBlock] Failed to update No Autoplay state:', error);
                setError(t('popup_error_update_site_setting', undefined, 'Failed to update site setting.'));
                noAutoplayEnabledToggle.checked = !nextEnabled;
            } finally {
                noAutoplayEnabledToggle.disabled = false;
            }
        });
    }

    if (noAutoplaySiteToggle) {
        noAutoplaySiteToggle.addEventListener('change', async () => {
            const nextAllowed = noAutoplaySiteToggle.checked;
            try {
                setError('');
                noAutoplaySiteToggle.disabled = true;
                await setNoAutoplaySiteAllowed(host, nextAllowed);
            } catch (error) {
                console.error('[wBlock] Failed to update No Autoplay site setting:', error);
                setError(t('popup_error_update_site_setting', undefined, 'Failed to update site setting.'));
                noAutoplaySiteToggle.checked = !nextAllowed;
            } finally {
                noAutoplaySiteToggle.disabled = noAutoplaySiteDisabled;
            }
        });
    }

    if (zapperActivate) {
        zapperActivate.addEventListener('click', async () => {
            try {
                setError('');
                await sendTabMessageWithRetry(tab.id, { type: 'wblock:zapper:activate' }, {
                    validateResponse: isZapperCommandResponse,
                });
                window.close();
            } catch (error) {
                console.error('[wBlock] Failed to activate zapper:', error);
                setError(t('popup_error_zapper_unavailable', undefined, 'Element Zapper is unavailable on this page.'));
            }
        });
    }

    if (userscriptsList) {
        userscriptsList.addEventListener('change', async (event) => {
            const input = getClosestTarget(event, 'input.userscript-toggle');
            if (!input || !tab || !tab.id) return;

            const scriptId = input.getAttribute('data-script-id') || '';
            const disabledForSite = !input.checked;
            try {
                setError('');
                input.disabled = true;
                const response = await setUserscriptSiteDisabled(scriptId, disabledForSite);
                if (!response || response.ok === false) {
                    throw new Error((response && response.error) || t('popup_error_update_userscript', undefined, 'Failed to update userscript setting.'));
                }
                currentPageUserScripts = currentPageUserScripts.map((script) => (
                    script.id === scriptId
                        ? { ...script, disabledForSite, running: !disabledForSite }
                        : script
                ));
                renderPageUserScripts(currentPageUserScripts, false);
                await reloadActiveTab(tab.id);
            } catch (error) {
                console.error('[wBlock] Failed to update userscript site setting:', error);
                setError((error && error.message) || t('popup_error_update_userscript', undefined, 'Failed to update userscript setting.'));
                input.checked = !input.checked;
                input.disabled = false;
            }
        });
    }

    if (userscriptCommands) {
        userscriptCommands.addEventListener('click', async (event) => {
            const button = getClosestTarget(event, 'button.command-btn');
            if (!button || !tab || !tab.id) return;

            const bridgeId = button.getAttribute('data-bridge-id') || '';
            const commandId = button.getAttribute('data-command-id') || '';
            const frameId = Number(button.getAttribute('data-frame-id'));
            if (!bridgeId || !commandId || !Number.isFinite(frameId)) return;

            try {
                setError('');
                button.disabled = true;
                const response = await invokeUserscriptCommand(tab.id, frameId, bridgeId, commandId);
                if (!response || response.ok === false) {
                    throw new Error((response && response.error) || t('popup_error_load_popup', undefined, 'Failed to load popup.'));
                }
                await refreshUi();
            } catch (error) {
                console.error('[wBlock] Failed to invoke userscript menu command:', error);
                setError((error && error.message) || t('popup_error_load_popup', undefined, 'Failed to load popup.'));
                button.disabled = false;
            }
        });
    }

    if (resumeButton) {
        resumeButton.addEventListener('click', async () => {
            if (resumeInFlight) return;
            resumeInFlight = true;
            try {
                setError('');
                resumeButton.disabled = true;
                resumeButton.setAttribute('aria-busy', 'true');
                setStatus(t('popup_status_resuming', undefined, 'Resuming…'), 'neutral');
                const result = await resumeBlocking();
                if (result.status === 'unavailable') {
                    setError(t(
                        'popup_error_resume_unavailable',
                        undefined,
                        'Open wBlock to resume blocking.'
                    ));
                    resumeButton.disabled = false;
                    resumeButton.removeAttribute('aria-busy');
                    setStatus(t('popup_status_paused', undefined, 'Paused'), 'disabled');
                    return;
                }
                await refreshUi();
            } catch (error) {
                console.error('[wBlock] Failed to resume blocking:', error);
                setError(t('popup_error_resume_blocking', undefined, 'Failed to resume blocking.'));
                resumeButton.disabled = false;
                resumeButton.removeAttribute('aria-busy');
                setStatus(t('popup_status_paused', undefined, 'Paused'), 'disabled');
            } finally {
                resumeInFlight = false;
            }
        });
    }

    if (openAppButton) {
        openAppButton.addEventListener('click', async () => {
            try {
                setError('');
                openAppButton.disabled = true;
                const response = await sendNativeMessageWithTimeout({
                    action: 'openContainingApp',
                }, 5000);
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
    const generationAtStart = siteToggleGeneration;
    if (!siteToggleInFlight) {
        setError('');
    }
    const isMac = await isMacPlatform();
    const updateFiltersButton = document.getElementById('update-filters');
    if (updateFiltersButton) updateFiltersButton.hidden = !isMac;
    if (isMac) {
        refreshFilterUpdateStatus().catch((error) => {
            console.warn('[wBlock] Failed to restore filter update status:', error);
        });
    }
    browser.runtime.sendMessage({ action: 'wblock:installRemoveParamDNRRules' }).catch((error) => {
        console.warn('[wBlock] Failed to refresh removeparam DNR rules:', error);
    });

    const hostEl = document.getElementById('site-host');
    const disableToggle = document.getElementById('enable-toggle');
    const zapperEnabledToggle = document.getElementById('zapper-enabled-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const rulesToggle = document.getElementById('zapper-rules-toggle');
    const openAppButton = document.getElementById('open-app');
    const userscriptsSection = document.getElementById('userscripts-section');
    const pausedPrompt = document.getElementById('paused-prompt');
    const pausedPromptTitle = document.getElementById('paused-prompt-title');
    const pausedPromptMessage = document.getElementById('paused-prompt-message');
    const resumeButton = document.getElementById('resume-blocking');

    if (openAppButton) {
        openAppButton.hidden = !isMac;
    }
    tab = await getActiveTabWithRetry();
    const pageSupport = getPageSupport(tab);
    host = pageSupport.host;

    if (hostEl) hostEl.textContent = host || '—';

    if (!pageSupport.supported) {
        setStatus(t('popup_status_unsupported', undefined, 'Unsupported'), 'neutral');
        if (disableToggle) disableToggle.disabled = true;
        if (zapperEnabledToggle) zapperEnabledToggle.disabled = true;
        if (pausedPrompt) pausedPrompt.hidden = true;
        if (resumeButton) resumeButton.hidden = true;
        if (zapperActivate) zapperActivate.disabled = true;
        if (rulesToggle) rulesToggle.disabled = true;
        currentPageUserScripts = [];
        userscriptsExpanded = false;
        renderPageUserScripts([], true);
        if (userscriptsSection) userscriptsSection.hidden = true;
        renderUserscriptCommands([]);
        await logExtensionDiagnostic({
            event: 'popup_support_fallback',
            source: 'popup',
            outcome: 'unsupported',
            reason: 'url_unsupported',
            tabId: tab && tab.id ? tab.id : '',
            url: tab && typeof tab.url === 'string' ? tab.url : '',
            host: pageSupport.host,
        });
        await updateZapperCount('');
        setRulesExpanded(false);
        updateNoAutoplayControls(await getNoAutoplayState(''), { host: '', locked: true });
        return;
    }

    const blockingPausedPromise = getBlockingPausedState();
    const pageUserScriptsPromise = fetchPageUserScripts(tab.url);
    let pageUserScriptsRenderedDisabled = null;
    const renderPageUserScriptsPromise = pageUserScriptsPromise.then((scripts) => {
        pageUserScriptsRenderedDisabled = disableToggle ? !disableToggle.checked : false;
        renderPageUserScripts(scripts, pageUserScriptsRenderedDisabled);
        return scripts;
    });
    const disabledPromise = getSiteDisabledState(host);
    const contentScriptReachablePromise = probeTabSupport(tab.id);
    const zapperStatePromise = getAuthoritativeZapperState(host);
    const zapperCountPromise = updateZapperCount(host);
    const noAutoplayStatePromise = getNoAutoplayState(host);

    setStatus(t('popup_status_checking', undefined, 'Checking…'), 'neutral');

    const [pauseState, disabled, zapperState, contentScriptReachable, noAutoplayState] = await Promise.all([
        blockingPausedPromise,
        disabledPromise,
        zapperStatePromise,
        contentScriptReachablePromise,
        noAutoplayStatePromise,
    ]);
    if (pauseState === null) {
        setStatus(t('popup_status_error', undefined, 'Error'), 'disabled');
        setError(t('popup_error_load_popup', undefined, 'Failed to load popup.'));
        if (disableToggle) disableToggle.disabled = true;
        if (zapperEnabledToggle) zapperEnabledToggle.disabled = true;
        if (zapperActivate) zapperActivate.disabled = true;
        if (resumeButton) resumeButton.disabled = true;
        if (pausedPrompt) pausedPrompt.hidden = true;
        if (resumeButton) resumeButton.hidden = true;
        updateNoAutoplayControls(noAutoplayState, { host, locked: true });
        return;
    }

    const blockingPaused = pauseState.paused;
    const resumeAvailable = pauseState.resumeAvailable;
    const filtersPaused = pauseState.filtersPaused;
    const userScriptsPaused = pauseState.userScriptsPaused;
    const zapperPaused = pauseState.elementZapperPaused;
    const partiallyPaused = blockingPaused && !(
        filtersPaused && userScriptsPaused && zapperPaused
    );
    const siteDisabled = disabled === true;
    const siteDisabledUnknown = disabled === null;
    const skipSiteToggleCommit = siteToggleInFlight || generationAtStart !== siteToggleGeneration;
    const zapperRulesDisabled = zapperState.disabled === true;
    if (disableToggle) {
        if (siteDisabledUnknown) {
            disableToggle.disabled = true;
        } else if (!skipSiteToggleCommit) {
            disableToggle.checked = !siteDisabled;
            disableToggle.disabled = filtersPaused;
        }
    }
    if (pausedPrompt) pausedPrompt.hidden = !blockingPaused;
    if (resumeButton) resumeButton.hidden = !(blockingPaused && resumeAvailable);
    if (pausedPromptTitle) {
        pausedPromptTitle.textContent = partiallyPaused
            ? t('popup_paused_partial_prompt_title', undefined, 'Some blocking components are paused')
            : t('popup_paused_prompt_title', undefined, 'Blocking is paused');
    }
    if (pausedPromptMessage) {
        pausedPromptMessage.textContent = t(
            'popup_paused_prompt_message',
            undefined,
            'Resume restores all components.'
        );
    }
    if (resumeButton) {
        resumeButton.disabled = !(blockingPaused && resumeAvailable);
        resumeButton.removeAttribute('aria-busy');
    }
    if (zapperEnabledToggle) {
        zapperEnabledToggle.checked = !zapperRulesDisabled;
        zapperEnabledToggle.disabled = siteDisabled || zapperPaused;
    }
    noAutoplaySiteDisabled = siteDisabled;
    updateNoAutoplayControls(noAutoplayState, { host, siteDisabled });
    const shouldCommitSiteStatus = !skipSiteToggleCommit || blockingPaused;
    if (shouldCommitSiteStatus) {
        if (siteDisabledUnknown && !blockingPaused) {
            setStatus(t('popup_status_unavailable', undefined, 'Unavailable'), 'neutral');
        } else {
            setStatus(
                blockingPaused && !partiallyPaused
                    ? t('popup_status_paused', undefined, 'Paused')
                    : blockingPaused
                        ? t('popup_status_partially_paused', undefined, 'Partially Paused')
                        : siteDisabled
                            ? t('popup_status_disabled', undefined, 'Disabled')
                            : t('popup_status_active', undefined, 'Active'),
                blockingPaused || siteDisabled ? 'disabled' : 'active'
            );
        }
    }

    if (zapperActivate) {
        zapperActivate.disabled = siteDisabled || zapperPaused || zapperRulesDisabled;
    }
    if (rulesToggle) {
        rulesToggle.disabled = zapperPaused;
    }
    await renderPageUserScriptsPromise;
    if (pageUserScriptsRenderedDisabled !== disabled) {
        renderPageUserScripts(await pageUserScriptsPromise, disabled);
    }
    currentZapperRules = zapperState.rules;
    const zapperCount = await zapperCountPromise;
    const zapperClear = document.getElementById('zapper-clear');
    if (zapperClear) zapperClear.disabled = zapperPaused || zapperCount === 0;
    renderUserscriptCommands(contentScriptReachable ? await fetchUserscriptCommands(tab.id) : []);
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
