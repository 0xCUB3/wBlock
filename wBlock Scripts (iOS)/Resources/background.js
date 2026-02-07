/**
 * Unified wBlock WebExtension background bridge.
 *
 * Keeps web-extension-specific plumbing minimal and proxies native actions
 * through Safari's native messaging host.
 */

const NATIVE_HOST_ID = 'application.id';
const CACHE_CLEAR_ACTION = 'wblock:clearCache';
const REFRESH_BADGE_ACTION = 'wblock:refreshBadgeCounter';
const MANUAL_BADGE_COLOR = '#1f6fff';
const MANUAL_BADGE_ERROR_PATTERNS = [
  'blocked',
  'denied',
  'by_client',
  'content blocker',
  'contentblocker',
  'policy',
];
const MANUAL_BADGE_IGNORED_ERROR_PATTERNS = ['abort', 'cancel'];

let isMacPlatform = false;
const blockedCountByTab = new Map();

async function applyBadgeCounterState(enabled) {
  const dnr = browser && browser.declarativeNetRequest;
  if (!dnr || typeof dnr.setExtensionActionOptions !== 'function') {
    return;
  }

  await dnr.setExtensionActionOptions({
    // Matches uBOL's MV3 approach for exact DNR-backed blocked counts.
    displayActionCountAsBadgeText: Boolean(enabled),
  });
}

async function refreshBadgeCounterState() {
  if (
    !browser.runtime ||
    typeof browser.runtime.getPlatformInfo !== 'function' ||
    typeof browser.runtime.sendNativeMessage !== 'function'
  ) {
    return;
  }

  let platformInfo;
  try {
    platformInfo = await browser.runtime.getPlatformInfo();
  } catch (error) {
    console.warn('[wBlock] Failed to get platform info for badge counter:', error);
    return;
  }

  // iOS should behave identically except no toolbar blocked-item badge.
  if (!platformInfo || platformInfo.os !== 'mac') {
    isMacPlatform = false;
    return;
  }
  isMacPlatform = true;

  let enabled = true;
  try {
    const response = await sendToNative({ action: 'getBadgeCounterState' });
    enabled = Boolean(response && response.enabled);
  } catch (error) {
    console.warn('[wBlock] Failed to read badge counter setting:', error);
  }

  try {
    await applyBadgeCounterState(enabled);
  } catch (error) {
    console.warn('[wBlock] Failed to apply badge counter setting:', error);
  }
}

function shouldCountBlockedRequest(errorString) {
  const normalized = String(errorString || '').toLowerCase();
  if (!normalized) {
    return false;
  }
  if (MANUAL_BADGE_IGNORED_ERROR_PATTERNS.some((pattern) => normalized.includes(pattern))) {
    return false;
  }
  return MANUAL_BADGE_ERROR_PATTERNS.some((pattern) => normalized.includes(pattern));
}

async function updateBadgeForTab(tabId) {
  if (!isMacPlatform || typeof tabId !== 'number' || tabId < 0) {
    return;
  }

  const action = browser && browser.action;
  if (!action || typeof action.setBadgeText !== 'function') {
    return;
  }

  const count = blockedCountByTab.get(tabId) || 0;
  const text = count > 0 ? String(count) : '';

  try {
    await action.setBadgeText({ tabId, text });
    if (count > 0 && typeof action.setBadgeBackgroundColor === 'function') {
      await action.setBadgeBackgroundColor({ tabId, color: MANUAL_BADGE_COLOR });
    }
  } catch {
    // Ignore tab-scoped badge failures (for example restricted tabs).
  }
}

async function resetBadgeForTab(tabId) {
  if (typeof tabId !== 'number' || tabId < 0) {
    return;
  }
  blockedCountByTab.set(tabId, 0);
  await updateBadgeForTab(tabId);
}

function extractRequestPayload(request) {
  if (request && typeof request.payload === 'object' && request.payload !== null) {
    return request.payload;
  }
  return request || {};
}

async function sendToNative(message) {
  return browser.runtime.sendNativeMessage(NATIVE_HOST_ID, message);
}

async function requestConfiguration(url, topUrl) {
  const nativeRequest = {
    action: 'requestRules',
    payload: {
      url,
      topUrl,
    },
  };

  const nativeResponse = await sendToNative(nativeRequest);
  const payload = nativeResponse && nativeResponse.payload ? nativeResponse.payload : null;
  return payload || null;
}

function shouldProxyAction(action) {
  return [
    'getUserScripts',
    'getUserScriptContentChunk',
    'getUserScriptResourceChunk',
    'getSiteDisabledState',
    'setSiteDisabledState',
    'zapperController',
  ].includes(action);
}

async function handleRequestRules(request) {
  const payload = extractRequestPayload(request);
  const requestId = payload.requestId || '';
  const url = payload.url || '';
  const topUrl = payload.topUrl || null;

  if (!url) {
    return {
      requestId,
      payload: {
        css: [],
        extendedCss: [],
        js: [],
        scriptlets: [],
        userScripts: [],
      },
      verbose: false,
    };
  }

  const configuration = await requestConfiguration(url, topUrl);
  return {
    requestId,
    payload: configuration || {
      css: [],
      extendedCss: [],
      js: [],
      scriptlets: [],
      userScripts: [],
    },
    verbose: false,
  };
}

async function handleMessage(request) {
  const action = request && request.action;

  if (!action) {
    return {};
  }

  if (action === CACHE_CLEAR_ACTION) {
    // Kept for compatibility; no cached page config is retained in the bridge.
    return { ok: true };
  }

  if (action === REFRESH_BADGE_ACTION) {
    await refreshBadgeCounterState();
    return { ok: true };
  }

  if (action === 'requestRules') {
    return handleRequestRules(request);
  }

  if (shouldProxyAction(action)) {
    return sendToNative(request);
  }

  return {};
}

browser.runtime.onMessage.addListener((request) => {
  return handleMessage(request).catch((error) => {
    console.error('[wBlock] background bridge error:', error);
    return { error: String(error && error.message ? error.message : error) };
  });
});

if (browser.tabs && browser.tabs.onActivated) {
  browser.tabs.onActivated.addListener((activeInfo) => {
    if (activeInfo && typeof activeInfo.tabId === 'number') {
      updateBadgeForTab(activeInfo.tabId).catch(() => {});
    }
    refreshBadgeCounterState().catch(() => {});
  });
}

if (browser.tabs && browser.tabs.onUpdated) {
  browser.tabs.onUpdated.addListener((_tabId, changeInfo) => {
    if (typeof _tabId === 'number' && changeInfo && changeInfo.status === 'loading') {
      resetBadgeForTab(_tabId).catch(() => {});
    }
    if (changeInfo && changeInfo.status === 'loading') {
      refreshBadgeCounterState().catch(() => {});
    }
  });
}

if (browser.tabs && browser.tabs.onRemoved) {
  browser.tabs.onRemoved.addListener((tabId) => {
    blockedCountByTab.delete(tabId);
  });
}

if (browser.webRequest && browser.webRequest.onErrorOccurred) {
  browser.webRequest.onErrorOccurred.addListener(
    (details) => {
      if (!isMacPlatform) {
        return;
      }
      if (!details || typeof details.tabId !== 'number' || details.tabId < 0) {
        return;
      }
      if (!shouldCountBlockedRequest(details.error)) {
        return;
      }

      const current = blockedCountByTab.get(details.tabId) || 0;
      blockedCountByTab.set(details.tabId, current + 1);
      updateBadgeForTab(details.tabId).catch(() => {});
    },
    { urls: ['<all_urls>'] }
  );
}

refreshBadgeCounterState();
