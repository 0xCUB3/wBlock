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
const MANUAL_BADGE_STRONG_ERROR_PATTERNS = [
  'blocked',
  'denied',
  'by_client',
  'content blocker',
  'contentblocker',
  'policy',
];
const MANUAL_BADGE_WEAK_ERROR_PATTERNS = ['abort', 'cancel'];
const MANUAL_BADGE_TRACKED_RESOURCE_TYPES = new Set([
  'sub_frame',
  'script',
  'image',
  'stylesheet',
  'object',
  'xmlhttprequest',
  'media',
  'font',
  'ping',
  'other',
]);
const MANUAL_BADGE_TRACK_RETENTION_MS = 30000;
const MANUAL_BADGE_MAX_TRACKED_REQUESTS = 4096;

let isMacPlatform = false;
let manualBadgeFallbackEnabled = false;
const blockedCountByTab = new Map();
const trackedRequestById = new Map();

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

async function hasDnrRulesConfigured() {
  const dnr = browser && browser.declarativeNetRequest;
  if (!dnr) {
    return false;
  }

  let ruleCount = 0;
  try {
    if (typeof dnr.getEnabledRulesets === 'function') {
      const enabledRulesets = await dnr.getEnabledRulesets();
      if (Array.isArray(enabledRulesets)) {
        ruleCount += enabledRulesets.length;
      }
    }
  } catch {
    // Ignore API-specific failures; we still try other rule sources.
  }

  try {
    if (typeof dnr.getDynamicRules === 'function') {
      const dynamicRules = await dnr.getDynamicRules();
      if (Array.isArray(dynamicRules)) {
        ruleCount += dynamicRules.length;
      }
    }
  } catch {
    // Ignore API-specific failures; we still try other rule sources.
  }

  try {
    if (typeof dnr.getSessionRules === 'function') {
      const sessionRules = await dnr.getSessionRules();
      if (Array.isArray(sessionRules)) {
        ruleCount += sessionRules.length;
      }
    }
  } catch {
    // Ignore API-specific failures.
  }

  return ruleCount > 0;
}

async function clearGlobalBadgeText() {
  const action = browser && browser.action;
  if (!action || typeof action.setBadgeText !== 'function') {
    return;
  }
  try {
    await action.setBadgeText({ text: '' });
  } catch {
    // Ignore global badge clear failures.
  }
}

function isTrackableResourceType(type) {
  return MANUAL_BADGE_TRACKED_RESOURCE_TYPES.has(String(type || '').toLowerCase());
}

function pruneTrackedRequests(nowMs = Date.now()) {
  if (trackedRequestById.size === 0) {
    return;
  }

  if (trackedRequestById.size > MANUAL_BADGE_MAX_TRACKED_REQUESTS) {
    const overflow = trackedRequestById.size - MANUAL_BADGE_MAX_TRACKED_REQUESTS;
    let removed = 0;
    for (const requestId of trackedRequestById.keys()) {
      trackedRequestById.delete(requestId);
      removed += 1;
      if (removed >= overflow) {
        break;
      }
    }
  }

  for (const [requestId, meta] of trackedRequestById.entries()) {
    if (!meta || typeof meta.startedAt !== 'number') {
      trackedRequestById.delete(requestId);
      continue;
    }
    if (nowMs - meta.startedAt > MANUAL_BADGE_TRACK_RETENTION_MS) {
      trackedRequestById.delete(requestId);
    }
  }
}

function rememberRequest(details) {
  if (!manualBadgeFallbackEnabled) {
    return;
  }
  if (!details || typeof details.requestId === 'undefined') {
    return;
  }
  if (typeof details.tabId !== 'number' || details.tabId < 0) {
    return;
  }
  if (!isTrackableResourceType(details.type)) {
    return;
  }
  const url = String(details.url || '');
  if (!/^https?:\/\//i.test(url)) {
    return;
  }

  trackedRequestById.set(String(details.requestId), {
    tabId: details.tabId,
    startedAt: Date.now(),
    type: String(details.type || '').toLowerCase(),
    url,
  });
  pruneTrackedRequests();
}

function forgetTrackedRequest(details) {
  if (!details || typeof details.requestId === 'undefined') {
    return;
  }
  trackedRequestById.delete(String(details.requestId));
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
  const os = platformInfo && typeof platformInfo.os === 'string' ? platformInfo.os.toLowerCase() : '';
  if (!os || (os !== 'mac' && os !== 'macos')) {
    isMacPlatform = false;
    manualBadgeFallbackEnabled = false;
    trackedRequestById.clear();
    blockedCountByTab.clear();
    await clearGlobalBadgeText();
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

  let hasDnrRules = false;
  if (enabled) {
    hasDnrRules = await hasDnrRulesConfigured();
  }
  manualBadgeFallbackEnabled = Boolean(enabled) && !hasDnrRules;

  try {
    await applyBadgeCounterState(Boolean(enabled) && hasDnrRules);
  } catch (error) {
    console.warn('[wBlock] Failed to apply badge counter setting:', error);
  }

  if (!manualBadgeFallbackEnabled) {
    trackedRequestById.clear();
    blockedCountByTab.clear();
    await clearGlobalBadgeText();
  }
}

function shouldCountBlockedRequest(details) {
  const normalized = String(details && details.error ? details.error : '').toLowerCase();
  if (!normalized) {
    return false;
  }
  if (MANUAL_BADGE_STRONG_ERROR_PATTERNS.some((pattern) => normalized.includes(pattern))) {
    return true;
  }
  if (!MANUAL_BADGE_WEAK_ERROR_PATTERNS.some((pattern) => normalized.includes(pattern))) {
    return false;
  }
  if (!details || !isTrackableResourceType(details.type)) {
    return false;
  }
  if (typeof details.tabId !== 'number' || details.tabId < 0) {
    return false;
  }
  const url = String(details.url || '');
  if (!/^https?:\/\//i.test(url)) {
    return false;
  }

  const tracked = trackedRequestById.get(String(details.requestId));
  if (tracked && typeof tracked.startedAt === 'number') {
    if (Date.now() - tracked.startedAt > MANUAL_BADGE_TRACK_RETENTION_MS) {
      return false;
    }
  }
  return true;
}

async function updateBadgeForTab(tabId) {
  if (!isMacPlatform || !manualBadgeFallbackEnabled || typeof tabId !== 'number' || tabId < 0) {
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
  if (!manualBadgeFallbackEnabled || typeof tabId !== 'number' || tabId < 0) {
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

if (browser.webRequest && browser.webRequest.onBeforeRequest) {
  browser.webRequest.onBeforeRequest.addListener(
    (details) => {
      if (!isMacPlatform || !manualBadgeFallbackEnabled) {
        return;
      }
      rememberRequest(details);
    },
    { urls: ['<all_urls>'] }
  );
}

if (browser.webRequest && browser.webRequest.onCompleted) {
  browser.webRequest.onCompleted.addListener(
    (details) => {
      forgetTrackedRequest(details);
    },
    { urls: ['<all_urls>'] }
  );
}

if (browser.webRequest && browser.webRequest.onBeforeRedirect) {
  browser.webRequest.onBeforeRedirect.addListener(
    (details) => {
      forgetTrackedRequest(details);
    },
    { urls: ['<all_urls>'] }
  );
}

if (browser.webRequest && browser.webRequest.onErrorOccurred) {
  browser.webRequest.onErrorOccurred.addListener(
    (details) => {
      if (!isMacPlatform || !manualBadgeFallbackEnabled) {
        return;
      }
      if (!details || typeof details.tabId !== 'number' || details.tabId < 0) {
        forgetTrackedRequest(details);
        return;
      }
      if (!shouldCountBlockedRequest(details)) {
        forgetTrackedRequest(details);
        return;
      }

      const current = blockedCountByTab.get(details.tabId) || 0;
      blockedCountByTab.set(details.tabId, current + 1);
      updateBadgeForTab(details.tabId).catch(() => {});
      forgetTrackedRequest(details);
    },
    { urls: ['<all_urls>'] }
  );
}

refreshBadgeCounterState();
