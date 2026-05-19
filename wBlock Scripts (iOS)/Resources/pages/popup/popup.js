const NATIVE_HOST_ID = 'application.id';
const ZAPPER_STORAGE_PREFIX = 'wblock.zapperRules.v1:';
const ZAPPER_META_PREFIX = 'wblock.zapperMeta.v1:';
const ZAPPER_DISABLED_STORAGE_PREFIX = 'wblock.zapperRulesDisabled.v1:';
const SUPPORT_PROBE_TIMEOUT_MS = 800;
const SUPPORT_PROBE_ATTEMPTS = 3;
const SUPPORT_PROBE_RETRY_DELAY_MS = 150;

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

async function sendTabMessageWithRetry(tabId, message, { timeoutMs = null, validateResponse = isSuccessfulTabMessageResponse } = {}) {
    if (!tabId) throw new Error('Missing tab');
    let lastError = null;

    for (let attempt = 0; attempt < SUPPORT_PROBE_ATTEMPTS; attempt += 1) {
        try {
            const messagePromise = browser.tabs.sendMessage(tabId, message);
            const response = timeoutMs === null
                ? await messagePromise
                : await Promise.race([
                    messagePromise,
                    new Promise((_, reject) => {
                        setTimeout(() => reject(new Error('Tab message timed out.')), timeoutMs);
                    }),
                ]);

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
        await browser.tabs.sendMessage(tabId, { type: 'wblock:zapper:reloadRules' });
    } catch {
        // Content script may not be reachable on certain pages; ignore.
    }
}

let zapperRulesExpanded = false;
let currentZapperRules = [];
let currentPageUserScripts = [];
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

function zapperDisabledStorageKey(host) {
    return `${ZAPPER_DISABLED_STORAGE_PREFIX}${host}`;
}

async function getZapperRulesDisabled(host) {
    if (!host) return false;
    try {
        const key = zapperDisabledStorageKey(host);
        const result = await browser.storage.local.get(key);
        return result[key] === true;
    } catch (error) {
        console.warn('[wBlock] Failed to read Zapper state:', error);
        return false;
    }
}

async function setZapperRulesDisabled(host, disabled) {
    if (!host) return;
    const key = zapperDisabledStorageKey(host);
    if (disabled) {
        await browser.storage.local.set({ [key]: true });
    } else {
        await browser.storage.local.remove(key);
    }
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
        const response = await browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
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
        const response = await browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
            action: 'setUserScriptSiteDisabledState',
            scriptId,
            host,
            disabled: Boolean(disabled),
        });
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
    list.innerHTML = '';
    section.hidden = false;
    if (count) count.textContent = String(normalizedScripts.filter((script) => script && script.running !== false).length);

    if (normalizedScripts.length === 0) {
        if (empty) empty.hidden = false;
        return;
    }

    if (empty) empty.hidden = true;

    for (const script of normalizedScripts) {
        const row = document.createElement('label');
        row.className = 'userscript-row';

        const text = document.createElement('span');
        text.className = 'userscript-text';

        const name = document.createElement('span');
        name.className = 'userscript-name';
        name.textContent = script.name;
        text.appendChild(name);

        const metaParts = [];
        if (typeof script.version === 'string' && script.version.trim()) metaParts.push(`v${script.version.trim()}`);
        metaParts.push(script.disabledForSite ? t('popup_userscript_disabled_here', undefined, 'Disabled here') : t('popup_userscript_running', undefined, 'Running'));
        const meta = document.createElement('span');
        meta.className = 'userscript-meta';
        meta.textContent = metaParts.join(' · ');
        text.appendChild(meta);

        const control = document.createElement('span');
        control.className = 'switch';

        const input = document.createElement('input');
        input.type = 'checkbox';
        input.className = 'userscript-toggle';
        input.setAttribute('data-script-id', script.id);
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

function setupListeners() {
    const rulesToggle = document.getElementById('zapper-rules-toggle');
    const rulesContainer = document.getElementById('zapper-rules');
    const disableToggle = document.getElementById('disable-toggle');
    const zapperEnabledToggle = document.getElementById('zapper-enabled-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const zapperClear = document.getElementById('zapper-clear');
    const userscriptCommands = document.getElementById('userscript-commands');
    const userscriptsList = document.getElementById('userscripts-list');
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

    if (zapperEnabledToggle) {
        zapperEnabledToggle.addEventListener('change', async () => {
            const nextEnabled = zapperEnabledToggle.checked;
            try {
                setError('');
                zapperEnabledToggle.disabled = true;
                await setZapperRulesDisabled(host, !nextEnabled);
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
                await reloadActiveTab(tab.id);
                await refreshUi();
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
    const zapperEnabledToggle = document.getElementById('zapper-enabled-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const rulesToggle = document.getElementById('zapper-rules-toggle');
    const openAppButton = document.getElementById('open-app');
    const userscriptsSection = document.getElementById('userscripts-section');

    if (openAppButton) {
        openAppButton.hidden = !(await shouldShowOpenAppButton());
    }
    tab = await getActiveTabWithRetry();
    const pageSupport = getPageSupport(tab);
    host = pageSupport.host;

    if (hostEl) hostEl.textContent = host || '—';

    if (!pageSupport.supported) {
        setStatus(t('popup_status_unsupported', undefined, 'Unsupported'), 'neutral');
        if (disableToggle) disableToggle.disabled = true;
        if (zapperEnabledToggle) zapperEnabledToggle.disabled = true;
        if (zapperActivate) zapperActivate.disabled = true;
        if (rulesToggle) rulesToggle.disabled = true;
        currentPageUserScripts = [];
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
        return;
    }

    const contentScriptReachable = await probeTabSupport(tab.id);
    setStatus(t('popup_status_checking', undefined, 'Checking…'), 'neutral');

    const disabled = await getSiteDisabledState(host);
    const zapperRulesDisabled = await getZapperRulesDisabled(host);
    if (disableToggle) {
        disableToggle.checked = disabled;
        disableToggle.disabled = false;
    }
    if (zapperEnabledToggle) {
        zapperEnabledToggle.checked = !zapperRulesDisabled;
        zapperEnabledToggle.disabled = disabled;
    }
    setStatus(disabled
        ? t('popup_status_disabled', undefined, 'Disabled')
        : t('popup_status_active', undefined, 'Active'),
    disabled ? 'disabled' : 'active');

    if (zapperActivate) {
        zapperActivate.disabled = disabled || zapperRulesDisabled || !contentScriptReachable;
    }
    if (rulesToggle) {
        rulesToggle.disabled = false;
    }
    currentZapperRules = await getAuthoritativeZapperRules(host);
    await updateZapperCount(host);
    currentPageUserScripts = await fetchPageUserScripts(tab.url);
    renderPageUserScripts(currentPageUserScripts, disabled);
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
