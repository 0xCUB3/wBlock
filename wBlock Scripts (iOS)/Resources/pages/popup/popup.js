const NATIVE_HOST_ID = 'application.id';
const ZAPPER_STORAGE_PREFIX = 'wblock.zapperRules.v1:';

async function syncRulesToNative(host, rules) {
    if (!host) return;
    try {
        await browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
            action: 'syncZapperRules',
            hostname: host,
            rules: Array.isArray(rules) ? rules : []
        });
    } catch {
        // Best-effort sync
    }
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
    const normalized = Array.from(new Set((rules || []).map((r) => String(r).trim()).filter(Boolean)));
    await browser.storage.local.set({ [key]: normalized });
    await syncRulesToNative(host, normalized);
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
    await browser.runtime.sendNativeMessage(NATIVE_HOST_ID, {
        action: 'setSiteDisabledState',
        host,
        disabled: Boolean(disabled),
    });
}

async function reloadActiveTab(tabId) {
    if (!tabId) return;
    try {
        await browser.tabs.reload(tabId);
    } catch (error) {
        console.warn('[wBlock] Failed to reload tab:', error);
    }
}

async function refreshUi() {
    setError('');

    const hostEl = document.getElementById('site-host');
    const disableToggle = document.getElementById('disable-toggle');
    const zapperActivate = document.getElementById('zapper-activate');
    const rulesToggle = document.getElementById('zapper-rules-toggle');

    const tab = await getActiveTab();
    const host = tab && tab.url ? hostnameFromUrl(tab.url) : '';

    if (hostEl) hostEl.textContent = host || '—';

    if (!tab || !tab.id || !host) {
        setStatus('Unavailable', 'neutral');
        if (disableToggle) disableToggle.disabled = true;
        if (zapperActivate) zapperActivate.disabled = true;
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

    await updateZapperCount(host);

    if (rulesToggle) {
        rulesToggle.disabled = false;
        rulesToggle.addEventListener('click', async () => {
            try {
                setError('');
                setRulesExpanded(!zapperRulesExpanded);
                if (!zapperRulesExpanded) return;
                currentZapperRules = await loadZapperRules(host);
                renderZapperRules(currentZapperRules);
            } catch (error) {
                console.error('[wBlock] Failed to toggle rules:', error);
                setError('Failed to load rules.');
            }
        });
    }

    const rulesContainer = document.getElementById('zapper-rules');
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
                currentZapperRules = await loadZapperRules(host);
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
                await setSiteDisabledState(host, next);
                try {
                    await browser.runtime.sendMessage({ action: 'wblock:clearCache' });
                } catch (error) {
                    console.warn('[wBlock] Failed to clear configuration cache:', error);
                }
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

    const zapperClear = document.getElementById('zapper-clear');
    if (zapperClear) {
        zapperClear.addEventListener('click', async () => {
            try {
                setError('');
                const key = zapperStorageKey(host);
                await browser.storage.local.remove(key);
                await syncRulesToNative(host, []);
                await updateZapperCount(host);
                currentZapperRules = [];
                if (zapperRulesExpanded) renderZapperRules(currentZapperRules);
                await notifyZapperRulesChanged(tab.id);
            } catch (error) {
                console.error('[wBlock] Failed to clear zaps:', error);
                setError('Failed to clear zapper rules.');
            }
        });
    }
}

document.addEventListener('DOMContentLoaded', () => {
    refreshUi().catch((error) => {
        console.error('[wBlock] Popup init failed:', error);
        setError('Failed to load popup.');
    });
});
