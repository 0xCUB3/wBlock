// MV3 background service worker (module)
//
// Goals:
// - Network filtering via DNR (static ruleset + optional dynamic overrides)
// - Exact toolbar badge count on macOS using DNR action count
// - Per-site disable implemented via DNR allow rules (no native/UserDefaults)

const webext = globalThis.browser ?? globalThis.chrome;
const dnr = webext?.declarativeNetRequest;

const STORAGE_KEYS = {
  allowlistMap: 'wblock.allowlist.v1', // { [host: string]: baseRuleId:number }
  allowlistNextId: 'wblock.allowlist.nextId.v1',
  corePackAppliedAt: 'wblock.corePack.appliedAt.v1', // ISO timestamp from latest.json
};

// Keep allowlist rules well away from generated filter rule ids.
const ALLOWLIST_RULE_ID_START = 60000;
const ALLOWLIST_RULE_ID_STEP = 2;

const CORE_RULE_ID_MAX_EXCLUSIVE = ALLOWLIST_RULE_ID_START;

// Remote pack endpoint (hosted in this repo on a dedicated branch).
// CI can update these files without requiring an App Store update.
const PACKS_BASE_URL = 'https://raw.githubusercontent.com/0xCUB3/wBlock/dnr-packs/packs';
const PACKS_LATEST_URL = `${PACKS_BASE_URL}/latest.json`;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function normalizeHost(host) {
  if (typeof host !== 'string') return '';
  return host.trim().toLowerCase();
}

function findMatchingAllowlistKey(host, allowlistMap) {
  // Returns the stored key which matches `host` by suffix.
  // This mirrors the legacy behavior in native code: `example.com` applies to `www.example.com`.
  let cur = normalizeHost(host);
  while (cur) {
    if (Object.prototype.hasOwnProperty.call(allowlistMap, cur)) return cur;
    const dot = cur.indexOf('.');
    if (dot === -1) break;
    cur = cur.slice(dot + 1);
  }
  return '';
}

function allowRulesForHost(hostKey, baseRuleId) {
  const host = normalizeHost(hostKey);
  // Safari has had bugs with single-entry requestDomains; urlFilter is reliable.
  const hostFilter = `||${host}^`;

  return [
    {
      id: baseRuleId,
      priority: 1000,
      action: { type: 'allowAllRequests' },
      condition: {
        resourceTypes: ['main_frame'],
        urlFilter: hostFilter,
      },
    },
    // Workaround for allowAllRequests not always exempting scripts in Safari/Chromium.
    // (Mirrors uBO Lite's approach.)
    {
      id: baseRuleId + 1,
      priority: 1000,
      action: { type: 'allow' },
      condition: {
        resourceTypes: ['script'],
        initiatorDomains: [host],
      },
    },
  ];
}

let dynamicRulesUpdateQueue = Promise.resolve();

async function safeUpdateDynamicRules(updateOptions) {
  if (!dnr?.updateDynamicRules) return;
  const run = async () => {
    try {
      await dnr.updateDynamicRules(updateOptions);
      return;
    } catch (err) {
      // Some implementations error if asked to remove unknown ids.
      try {
        const existing = await dnr.getDynamicRules();
        const existingIds = new Set((existing || []).map((r) => r && r.id).filter((id) => typeof id === 'number'));
        const removeRuleIds = (updateOptions.removeRuleIds || []).filter((id) => existingIds.has(id));
        const retry = {};
        if (removeRuleIds.length) retry.removeRuleIds = removeRuleIds;
        if (Array.isArray(updateOptions.addRules) && updateOptions.addRules.length) retry.addRules = updateOptions.addRules;
        if (retry.removeRuleIds || retry.addRules) {
          await dnr.updateDynamicRules(retry);
        }
      } catch {
        // Ignore; we will surface issues in the popup if needed later.
      }
    }
  };

  const next = dynamicRulesUpdateQueue.then(run, run);
  dynamicRulesUpdateQueue = next.catch(() => {});
  return next;
}

async function enableStaticBaseRuleset() {
  if (!dnr?.updateEnabledRulesets) return;
  try {
    await dnr.updateEnabledRulesets({ enableRulesetIds: ['base'] });
  } catch {
    // ignore
  }
}

async function disableStaticBaseRuleset() {
  if (!dnr?.updateEnabledRulesets) return;
  try {
    await dnr.updateEnabledRulesets({ disableRulesetIds: ['base'] });
  } catch {
    // ignore
  }
}

function validateCoreRules(rules) {
  if (!Array.isArray(rules) || rules.length === 0) {
    throw new Error('Core pack contained no rules');
  }
  for (const rule of rules) {
    if (!rule || typeof rule.id !== 'number') {
      throw new Error('Core pack contained invalid rule entries');
    }
    if (rule.id <= 0 || rule.id >= CORE_RULE_ID_MAX_EXCLUSIVE) {
      throw new Error(`Core rule id out of range: ${rule.id}`);
    }
  }
}

async function getExistingCoreDynamicRuleIds() {
  if (!dnr?.getDynamicRules) return [];
  const existing = await dnr.getDynamicRules();
  return (existing || [])
    .map((r) => r && r.id)
    .filter((id) => typeof id === 'number' && id > 0 && id < CORE_RULE_ID_MAX_EXCLUSIVE);
}

async function applyCoreDynamicRules(rules) {
  validateCoreRules(rules);

  // Ensure we're protected during the update.
  await enableStaticBaseRuleset();

  const removeRuleIds = await getExistingCoreDynamicRuleIds();

  // Remove old core rules first (chunked to avoid per-call limits).
  const REMOVE_CHUNK = 5000;
  for (let i = 0; i < removeRuleIds.length; i += REMOVE_CHUNK) {
    await safeUpdateDynamicRules({ removeRuleIds: removeRuleIds.slice(i, i + REMOVE_CHUNK) });
  }

  // Add new core rules (chunked to avoid per-call limits).
  const ADD_CHUNK = 2000;
  for (let i = 0; i < rules.length; i += ADD_CHUNK) {
    await safeUpdateDynamicRules({ addRules: rules.slice(i, i + ADD_CHUNK) });
  }

  // Prefer dynamic core once installed to avoid double-counting.
  await disableStaticBaseRuleset();
}

async function loadJson(url) {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`Fetch failed: ${url} (${res.status})`);
  return await res.json();
}

async function bootstrapCoreRulesFromBuiltinIfNeeded() {
  if (!dnr?.updateDynamicRules) return;

  const existingCoreIds = await getExistingCoreDynamicRuleIds();
  if (existingCoreIds.length > 0) return;

  try {
    const builtinRules = await loadJson(webext.runtime.getURL('rulesets/base.json'));
    if (!Array.isArray(builtinRules) || builtinRules.length === 0) return;
    await applyCoreDynamicRules(builtinRules);
  } catch {
    // ignore
  }
}

async function maybeUpdateCoreRulesFromRemote() {
  if (!dnr?.updateDynamicRules) return;

  let latest;
  try {
    latest = await loadJson(PACKS_LATEST_URL);
  } catch {
    return;
  }

  const applied = await webext.storage.local.get([STORAGE_KEYS.corePackAppliedAt]);
  const appliedAt = typeof applied?.[STORAGE_KEYS.corePackAppliedAt] === 'string'
    ? applied[STORAGE_KEYS.corePackAppliedAt]
    : '';
  const latestAt = typeof latest?.updatedAt === 'string' ? latest.updatedAt : '';
  const packFile = typeof latest?.packFile === 'string' ? latest.packFile : '';
  if (!latestAt || !packFile) return;
  if (appliedAt === latestAt) return;

  let pack;
  try {
    pack = await loadJson(`${PACKS_BASE_URL}/${packFile}`);
  } catch {
    return;
  }

  const rules = Array.isArray(pack) ? pack : pack?.rules;
  if (!Array.isArray(rules) || rules.length === 0) return;

  try {
    await applyCoreDynamicRules(rules);
    await webext.storage.local.set({ [STORAGE_KEYS.corePackAppliedAt]: latestAt });
  } catch {
    // ignore
  }
}

async function ensureCoreRules() {
  // Prefer remote pack (fresh + small CPU). Fallback to bundled rules if offline.
  await maybeUpdateCoreRulesFromRemote();
  await bootstrapCoreRulesFromBuiltinIfNeeded();
}

async function readAllowlistState() {
  const result = await webext.storage.local.get([STORAGE_KEYS.allowlistMap, STORAGE_KEYS.allowlistNextId]);
  const map = (result && result[STORAGE_KEYS.allowlistMap]) || {};
  const nextId = typeof result?.[STORAGE_KEYS.allowlistNextId] === 'number'
    ? result[STORAGE_KEYS.allowlistNextId]
    : ALLOWLIST_RULE_ID_START;

  return {
    map: map && typeof map === 'object' ? map : {},
    nextId,
  };
}

async function writeAllowlistState(map, nextId) {
  await webext.storage.local.set({
    [STORAGE_KEYS.allowlistMap]: map,
    [STORAGE_KEYS.allowlistNextId]: nextId,
  });
}

async function setHostDisabled(host, disabled) {
  const normalized = normalizeHost(host);
  if (!normalized) return { disabled: false };

  const { map, nextId: storedNextId } = await readAllowlistState();
  const matchingKey = findMatchingAllowlistKey(normalized, map);

  if (disabled) {
    if (matchingKey) return { disabled: true };

    const baseRuleId = storedNextId;
    const addRules = allowRulesForHost(normalized, baseRuleId);

    await safeUpdateDynamicRules({
      removeRuleIds: [baseRuleId, baseRuleId + 1],
      addRules,
    });

    map[normalized] = baseRuleId;
    await writeAllowlistState(map, baseRuleId + ALLOWLIST_RULE_ID_STEP);
    return { disabled: true };
  }

  if (!matchingKey) return { disabled: false };

  const baseRuleId = map[matchingKey];
  delete map[matchingKey];

  await safeUpdateDynamicRules({
    removeRuleIds: [baseRuleId, baseRuleId + 1],
  });

  await writeAllowlistState(map, storedNextId);
  return { disabled: false };
}

async function getHostDisabled(host) {
  const normalized = normalizeHost(host);
  if (!normalized) return { disabled: false };
  const { map } = await readAllowlistState();
  const matchingKey = findMatchingAllowlistKey(normalized, map);
  return { disabled: Boolean(matchingKey) };
}

async function reloadTab(tabId, url) {
  if (typeof tabId !== 'number') return;

  // Give DNR a moment to commit changes before reload.
  await sleep(250);

  try {
    await webext.tabs.reload(tabId, { bypassCache: true });
    return;
  } catch {
    // ignore
  }

  try {
    if (typeof url === 'string' && url) {
      await webext.tabs.update(tabId, { url });
      return;
    }
  } catch {
    // ignore
  }

  try {
    await webext.tabs.reload(tabId);
  } catch {
    // ignore
  }
}

async function ensureBadgeCountEnabled() {
  if (!dnr?.setExtensionActionOptions) return;
  try {
    await dnr.setExtensionActionOptions({
      displayActionCountAsBadgeText: true,
    });
  } catch {
    // Ignore: not supported on some platforms.
  }
}

webext.runtime.onInstalled.addListener(() => {
  ensureBadgeCountEnabled();

  // Keep update checks wired even if we don't implement packs yet.
  try {
    webext.alarms.create('wblock:updates', { periodInMinutes: 24 * 60 });
  } catch {
    // ignore
  }

  ensureCoreRules();
});

webext.runtime.onStartup?.addListener(() => {
  ensureBadgeCountEnabled();
  ensureCoreRules();
});

webext.alarms?.onAlarm?.addListener((alarm) => {
  if (!alarm || alarm.name !== 'wblock:updates') return;
  ensureCoreRules();
});

webext.runtime.onMessage.addListener(async (message, sender) => {
  if (!message || typeof message !== 'object') return;

  const action = message.action;

  // Popup per-site disable
  if (action === 'getSiteDisabledState') {
    return await getHostDisabled(message.host);
  }

  if (action === 'setSiteDisabledState') {
    const result = await setHostDisabled(message.host, Boolean(message.disabled));
    if (typeof message.tabId === 'number') {
      await reloadTab(message.tabId, message.url);
    }
    return result;
  }

  // Userscripts (placeholder): respond with empty results so the injector is quiet.
  if (action === 'getUserScripts') {
    return { userScripts: [] };
  }
  if (action === 'getUserScriptContentChunk') {
    return { totalChunks: 0, chunk: '' };
  }
  if (action === 'getUserScriptResourceChunk') {
    return { totalChunks: 0, chunk: '' };
  }

  return;
});

// Run once on initial load as well (service worker may not fire onStartup on iOS).
ensureBadgeCountEnabled();
ensureCoreRules();
