const NATIVE_HOST_ID = 'application.id';
const ZAPPER_STORAGE_PREFIX = 'wblock.zapperRules.v1:';

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

async function refreshUi() {
    setError('');

    const hostEl = document.getElementById('site-host');
    const statusEl = document.getElementById('blocking-status');
    const disableToggle = document.getElementById('disable-toggle');
    const zapperActivate = document.getElementById('zapper-activate');

    const tab = await getActiveTab();
    const host = tab && tab.url ? hostnameFromUrl(tab.url) : '';

    if (hostEl) hostEl.textContent = host || '—';

    if (!tab || !tab.id || !host) {
        if (statusEl) statusEl.textContent = 'Unavailable on this page';
        if (disableToggle) disableToggle.disabled = true;
        if (zapperActivate) zapperActivate.disabled = true;
        await updateZapperCount('');
        return;
    }

    if (statusEl) statusEl.textContent = 'Checking…';

    const disabled = await getSiteDisabledState(host);
    if (disableToggle) {
        disableToggle.checked = disabled;
        disableToggle.disabled = false;
    }
    if (statusEl) statusEl.textContent = disabled ? 'Disabled on this site' : 'Active';

    await updateZapperCount(host);

    if (disableToggle) {
        disableToggle.addEventListener('change', async () => {
            try {
                setError('');
                disableToggle.disabled = true;
                const next = disableToggle.checked;
                if (statusEl) statusEl.textContent = next ? 'Disabling…' : 'Enabling…';
                await setSiteDisabledState(host, next);
                if (statusEl) statusEl.textContent = next ? 'Disabled on this site' : 'Active';
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
                await updateZapperCount(host);
                try {
                    await browser.tabs.sendMessage(tab.id, { type: 'wblock:zapper:reloadRules' });
                } catch {
                    // Content script may not be reachable on certain pages; ignore.
                }
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
