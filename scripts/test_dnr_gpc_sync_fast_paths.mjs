// Tests for DNR (60s) version-first fast path and GPC (5s) sync fast path.
//
// Loads both extension-src/background.js and the generated artifact
// wBlock Scripts (iOS)/Resources/background.js with a stubbed browser API.
//
// Run: node scripts/test_dnr_gpc_sync_fast_paths.mjs

import { readFileSync } from "node:fs";
import { runtimeMessageListener } from "./helpers/runtime-message.mjs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const canonicalSource = readFileSync(path.join(repoRoot, "extension-src", "background.js"), "utf8");
const bundleSource = readFileSync(path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "background.js"), "utf8");

let failures = 0;
const check = (name, condition) => {
  if (condition) {
    console.log(`PASS: ${name}`);
  } else {
    failures += 1;
    console.error(`FAIL: ${name}`);
  }
};

const flush = () => new Promise(resolve => setTimeout(resolve, 25));

const withMockEnv = async (fn) => {
  const origNow = Date.now;
  const origNav = Object.getOwnPropertyDescriptor(globalThis, "navigator");
  let now = 1_700_000_000_000;
  Date.now = () => now;
  const setUserAgent = ua => {
    Object.defineProperty(globalThis, "navigator", {
      value: { userAgent: ua },
      configurable: true,
      writable: true
    });
  };
  setUserAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15");
  try {
    await fn({
      getNow: () => now,
      advanceMs: ms => { now += ms; },
      setUserAgent
    });
  } finally {
    Date.now = origNow;
    if (origNav) Object.defineProperty(globalThis, "navigator", origNav);
    else delete globalThis.navigator;
  }
};

const createHarness = ({
  source,
  storage = {},
  dynamicRules = [],
  sessionRules = [],
  dnrLimit = 30000,
  supportsActionCount = true,
  throwOnFilteredGetDynamic = false,
  throwOnNextUpdateDynamic = false,
  onGetDynamicRules = null,
  onGetRegisteredScripts = null,
  onNativeMessage
}) => {
  let installedRules = dynamicRules.slice();
  let registeredScripts = [];
  const state = {
    storage: { ...storage },
    nativeMessages: [],
    getDynamicRulesCalls: [],
    getRegisteredScriptsCalls: [],
    isRegexSupportedCalls: 0,
    updateDynamicRulesCalls: [],
    dnrLimit,
    throwOnNextUpdateDynamic,
    getInstalledRules: () => installedRules.slice(),
    setInstalledRules: rules => { installedRules = rules.slice(); },
    onMessage: null,
    onInstalledListeners: [],
    onStartupListeners: []
  };

  const makeListener = list => ({ addListener: fn => { list.push(fn); } });
  const noopListener = { addListener: () => {} };

  const browser = {
    runtime: {
      getURL: rel => `safari-web-extension://test/${rel}`,
      sendNativeMessage: async (_appId, message) => {
        state.nativeMessages.push(message);
        return onNativeMessage(message);
      },
      onMessage: { addListener: fn => { state.onMessage = runtimeMessageListener(fn); } },
      connectNative: () => ({ onMessage: noopListener, onDisconnect: noopListener }),
      onInstalled: makeListener(state.onInstalledListeners),
      onStartup: makeListener(state.onStartupListeners)
    },
    storage: {
      local: {
        get: async key => {
          if (typeof key === "string") {
            return Object.hasOwn(state.storage, key) ? { [key]: state.storage[key] } : {};
          }
          if (Array.isArray(key)) {
            const out = {};
            for (const k of key) if (Object.hasOwn(state.storage, k)) out[k] = state.storage[k];
            return out;
          }
          return { ...state.storage };
        },
        set: async items => { Object.assign(state.storage, items); },
        remove: async key => { delete state.storage[key]; }
      }
    },
    permissions: { contains: async () => true },
    extension: { isAllowedIncognitoAccess: async () => false },
    tabs: {
      query: async () => [],
      get: async () => ({}),
      sendMessage: async () => ({}),
      onUpdated: noopListener,
      onActivated: noopListener,
      onCreated: noopListener,
      onRemoved: noopListener
    },
    scripting: {
      executeScript: async () => [{}],
      insertCSS: async () => {},
      registerContentScripts: async scripts => {
        for (const s of scripts) {
          if (!registeredScripts.some(x => x.id === s.id)) registeredScripts.push(s);
        }
      },
      unregisterContentScripts: async ({ ids }) => {
        registeredScripts = registeredScripts.filter(x => !ids.includes(x.id));
      },
      getRegisteredContentScripts: async filter => {
        state.getRegisteredScriptsCalls.push(filter);
        if (onGetRegisteredScripts) await onGetRegisteredScripts(filter);
        const ids = filter && Array.isArray(filter.ids) ? filter.ids : null;
        return ids ? registeredScripts.filter(s => ids.includes(s.id)) : registeredScripts.slice();
      }
    },
    action: { setBadgeText: async () => {}, setTitle: async () => {} },
    declarativeNetRequest: {
      ...(state.dnrLimit == null ? {} : {
        get MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES() { return state.dnrLimit; }
      }),
      ...(supportsActionCount ? { setExtensionActionOptions: async () => {} } : {}),
      getDynamicRules: async (...args) => {
        state.getDynamicRulesCalls.push(args);
        if (onGetDynamicRules) await onGetDynamicRules(args);
        if (throwOnFilteredGetDynamic && args.length > 0) {
          throw new Error("getDynamicRules filter unsupported");
        }
        const filter = args[0];
        if (filter && Array.isArray(filter.ruleIds)) {
          const wanted = new Set(filter.ruleIds);
          return installedRules.filter(r => wanted.has(r.id));
        }
        return installedRules.slice();
      },
      getSessionRules: async () => sessionRules.slice(),
      isRegexSupported: async () => {
        state.isRegexSupportedCalls += 1;
        return { isSupported: true };
      },
      updateDynamicRules: async update => {
        state.updateDynamicRulesCalls.push(update);
        if (state.throwOnNextUpdateDynamic) {
          state.throwOnNextUpdateDynamic = false;
          throw new Error("Simulated DNR update failure");
        }
        const removeIds = new Set(update.removeRuleIds || []);
        installedRules = installedRules.filter(r => !removeIds.has(r.id)).concat(update.addRules || []);
      }
    },
    i18n: { getMessage: () => "" }
  };

  const resetCounters = () => {
    state.nativeMessages.length = 0;
    state.getDynamicRulesCalls.length = 0;
    state.getRegisteredScriptsCalls.length = 0;
    state.isRegexSupportedCalls = 0;
    state.updateDynamicRulesCalls.length = 0;
  };

  new Function("browser", "window", "self", "fetch", source)(browser, globalThis, globalThis, globalThis.fetch);

  return {
    state,
    resetCounters,
    triggerMessage: async () => {
      await state.onMessage({ action: "wblock:noop" }, { tab: { id: 1 }, frameId: 0 });
      await flush();
    }
  };
};

const makeRule = id => ({
  id,
  priority: 10000,
  action: { type: "redirect", redirect: { regexSubstitution: "\\1" } },
  condition: { regexFilter: `^https://example${id}\\.com/(.*)`, resourceTypes: ["main_frame"] }
});

const makeCountRule = id => ({
  id,
  priority: 1,
  action: { type: "block" },
  condition: { requestDomains: [`ad-${id}.example`], resourceTypes: ["script"] }
});

const fallbackNativeReply = msg => {
  if (msg && msg.action === "reportRedirectDNRStatus") return { ok: true };
  if (msg && msg.action === "getBlockingState") return { disabled: false, paused: false };
  return { payload: { css: [], procedural: [], scriptlets: [], engineTimestamp: 1 } };
};

for (const [label, source] of [["extension-src", canonicalSource], ["minified bundle", bundleSource]]) {
  // 1. GPC 5s sync optimization & edge cases
  await withMockEnv(async env => {
    let gpcEnabled = true;
    const h = createHarness({
      source,
      onNativeMessage: msg => {
        if (msg.action === "getGlobalPrivacyControlState") return { enabled: gpcEnabled };
        if (msg.action === "getRemoveParamDNRRules") return { ok: true, version: "v0", count: 0, rules: [], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
        if (msg.action === "getBlockedCountDNRRules") return { ok: true, enabled: false, version: "", count: 0, rules: [] };
        return fallbackNativeReply(msg);
      }
    });
    await flush();
    check(`[${label}] GPC startup queries only ruleIds [1700000]`,
      h.state.getDynamicRulesCalls.some(args => args.length === 1 && args[0]?.ruleIds?.[0] === 1700000));
    check(`[${label}] GPC startup installs rule 1700000`,
      h.state.getInstalledRules().some(r => r.id === 1700000));

    // Warm 5s ticks with unchanged enabled=true should do ZERO getDynamicRules / getRegisteredContentScripts
    h.resetCounters();
    env.advanceMs(6000);
    await h.triggerMessage();
    check(`[${label}] GPC warm unchanged tick skips getDynamicRules`, h.state.getDynamicRulesCalls.length === 0);
    check(`[${label}] GPC warm unchanged tick skips getRegisteredContentScripts`, h.state.getRegisteredScriptsCalls.length === 0);

    // Toggle enabled: true -> false
    gpcEnabled = false;
    h.resetCounters();
    env.advanceMs(6000);
    await h.triggerMessage();
    check(`[${label}] GPC toggle false removes rule 1700000`,
      !h.state.getInstalledRules().some(r => r.id === 1700000));

    // Subsequent warm 5s tick while false does zero getDynamicRules
    h.resetCounters();
    env.advanceMs(6000);
    await h.triggerMessage();
    check(`[${label}] GPC warm false tick skips getDynamicRules`, h.state.getDynamicRulesCalls.length === 0);

    // Update failure must NOT cache lastSyncedGPCEnabled so next 5s tick retries
    gpcEnabled = true;
    h.state.throwOnNextUpdateDynamic = true;
    env.advanceMs(6000);
    await h.triggerMessage();
    check(`[${label}] GPC failed update does not install rule`,
      !h.state.getInstalledRules().some(r => r.id === 1700000));

    h.resetCounters();
    env.advanceMs(6000);
    await h.triggerMessage();
    check(`[${label}] GPC retries after error and installs rule`,
      h.state.getInstalledRules().some(r => r.id === 1700000));

    // onInstalled resets GPC & DNR caches and re-verifies immediately
    h.resetCounters();
    for (const listener of h.state.onInstalledListeners) listener();
    await flush();
    check(`[${label}] GPC onInstalled triggers filtered getDynamicRules re-verification`,
      h.state.getDynamicRulesCalls.some(args => args.length === 1 && args[0]?.ruleIds?.[0] === 1700000));
  });

  // 2. Older Safari fallback when getDynamicRules({ ruleIds }) throws
  await withMockEnv(async () => {
    const h = createHarness({
      source,
      throwOnFilteredGetDynamic: true,
      onNativeMessage: msg => {
        if (msg.action === "getGlobalPrivacyControlState") return { enabled: true };
        if (msg.action === "getRemoveParamDNRRules") return { ok: true, version: "v0", count: 0, rules: [], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
        if (msg.action === "getBlockedCountDNRRules") return { ok: true, enabled: false, version: "", count: 0, rules: [] };
        return fallbackNativeReply(msg);
      }
    });
    await flush();
    check(`[${label}] GPC falls back to unfiltered getDynamicRules() when filter throws`,
      h.state.getDynamicRulesCalls.some(args => args.length === 0)
        && h.state.getInstalledRules().some(r => r.id === 1700000));
  });

  // 3. DNR 60s version-first fast paths (warm hit, cold wake hit, rule loss recovery, version change, runtimeKey change)
  await withMockEnv(async env => {
    const rpRulesV1 = Array.from({ length: 300 }, (_, i) => makeRule(1500000 + i));
    const bcRulesV1 = [makeCountRule(1660000), makeCountRule(1660001)];
    let rpVer = "rp-v1";
    let rpRules = rpRulesV1;
    let bcEnabled = true;
    let bcVer = "bc-v1";
    let bcRules = bcRulesV1;

    const nativeHandler = msg => {
      if (msg.action === "getGlobalPrivacyControlState") return { enabled: false };
      if (msg.action === "getRemoveParamDNRRules") {
        if (msg.offset === 0 && msg.knownVersion === rpVer) {
          return { ok: true, version: rpVer, count: rpRules.length, rules: [], unchanged: true, ruleIdBase: 1500000, ruleIdLimit: 1650000 };
        }
        return { ok: true, version: rpVer, count: rpRules.length, rules: rpRules.slice(msg.offset, msg.offset + msg.limit), ruleIdBase: 1500000, ruleIdLimit: 1650000 };
      }
      if (msg.action === "getBlockedCountDNRRules") {
        const currentCountVer = `${bcEnabled}:${bcVer}`;
        if (msg.offset === 0 && msg.knownVersion === currentCountVer) {
          return { ok: true, enabled: bcEnabled, version: bcVer, count: bcEnabled ? bcRules.length : 0, rules: [], unchanged: true };
        }
        const activeRules = bcEnabled ? bcRules : [];
        return { ok: true, enabled: bcEnabled, version: bcVer, count: activeRules.length, rules: activeRules.slice(msg.offset, msg.offset + msg.limit) };
      }
      return fallbackNativeReply(msg);
    };

    // Fresh install
    const h = createHarness({ source, onNativeMessage: nativeHandler });
    await flush();
    const persisted = h.state.storage.wblockRemoveParamDNRVersion;
    check(`[${label}] Initial DNR install persists runtimeKey and counts`,
      persisted && persisted.version === "rp-v1" && persisted.count === 300
        && persisted.countVersion === "true:bc-v1" && persisted.countCount === 2
        && persisted.runtimeKey === "30000:18.4");

    // Warm 60s steady-state check -> Fast Path 1: zero getDynamicRules(), zero isRegexSupported(), zero updateDynamicRules(), knownVersion sent
    h.resetCounters();
    env.advanceMs(61_000);
    await h.triggerMessage();
    const rpProbe = h.state.nativeMessages.filter(m => m.action === "getRemoveParamDNRRules");
    const bcProbe = h.state.nativeMessages.filter(m => m.action === "getBlockedCountDNRRules");
    check(`[${label}] Warm 60s check sends knownVersion for both rulesets with 1 probe each`,
      rpProbe.length === 1 && rpProbe[0].knownVersion === "rp-v1"
        && bcProbe.length === 1 && bcProbe[0].knownVersion === "true:bc-v1");
    check(`[${label}] Warm 60s unchanged skips getDynamicRules, isRegexSupported, and updates`,
      h.state.getDynamicRulesCalls.length === 0
        && h.state.isRegexSupportedCalls === 0
        && h.state.updateDynamicRulesCalls.length === 0);

    // Cold wake with matching storage + installed rules -> Fast Path 2: 1 getDynamicRules, 0 extra chunks, 0 isRegexSupported
    const hCold = createHarness({
      source,
      storage: h.state.storage,
      dynamicRules: h.state.getInstalledRules(),
      onNativeMessage: nativeHandler
    });
    await flush();
    const coldRpCalls = hCold.state.nativeMessages.filter(m => m.action === "getRemoveParamDNRRules");
    const coldBcCalls = hCold.state.nativeMessages.filter(m => m.action === "getBlockedCountDNRRules");
    check(`[${label}] Cold wake unchanged hits Fast Path 2 (1x getDynamicRules, 0 extra chunks, 0 regex checks)`,
      hCold.state.getDynamicRulesCalls.filter(a => a.length === 0).length === 1
        && coldRpCalls.length === 1 && coldRpCalls[0].knownVersion === "rp-v1"
        && coldBcCalls.length === 1 && coldBcCalls[0].knownVersion === "true:bc-v1"
        && hCold.state.isRegexSupportedCalls === 0
        && hCold.state.updateDynamicRulesCalls.length === 0);

    // Next warm 60s tick after cold wake hits Fast Path 1 (0 getDynamicRules)
    hCold.resetCounters();
    env.advanceMs(61_000);
    await hCold.triggerMessage();
    check(`[${label}] Warm 60s tick after cold wake hits Fast Path 1 (0 getDynamicRules)`,
      hCold.state.getDynamicRulesCalls.length === 0 && hCold.state.isRegexSupportedCalls === 0);

    // Cold wake where Safari lost installed rules while storage still matches version -> recovers and reinstalls
    const hLost = createHarness({
      source,
      storage: h.state.storage,
      dynamicRules: [],
      onNativeMessage: nativeHandler
    });
    await flush();
    const lostRpCalls = hLost.state.nativeMessages.filter(m => m.action === "getRemoveParamDNRRules");
    check(`[${label}] Cold wake recovers when Safari lost rules (re-fetches without knownVersion and reinstalls)`,
      lostRpCalls.some(m => m.offset === 0 && !m.knownVersion)
        && hLost.state.getInstalledRules().filter(r => r.id >= 1500000 && r.id < 1650000).length === 300
        && hLost.state.getInstalledRules().filter(r => r.id >= 1660000 && r.id < 1700000).length === 2);

    // Version change on warm 60s tick reuses probe chunk 0 without double-fetching offset 0
    rpVer = "rp-v2";
    rpRules = Array.from({ length: 260 }, (_, i) => makeRule(1500000 + i));
    bcEnabled = false;
    bcVer = "";
    hCold.resetCounters();
    env.advanceMs(61_000);
    await hCold.triggerMessage();
    const v2Offset0Calls = hCold.state.nativeMessages.filter(m => m.action === "getRemoveParamDNRRules" && m.offset === 0);
    const v2Offset250Calls = hCold.state.nativeMessages.filter(m => m.action === "getRemoveParamDNRRules" && m.offset === 250);
    check(`[${label}] Version change reuses chunk 0 from probe (only 1 offset=0 call + remaining chunks)`,
      v2Offset0Calls.length === 1 && v2Offset250Calls.length === 1
        && hCold.state.storage.wblockRemoveParamDNRVersion.version === "rp-v2"
        && hCold.state.storage.wblockRemoveParamDNRVersion.count === 260
        && hCold.state.storage.wblockRemoveParamDNRVersion.countVersion === "false:"
        && hCold.state.storage.wblockRemoveParamDNRVersion.countCount === 0);

    // Runtime capability change (e.g. Safari quota or version changed) bypasses Fast Path 2 and updates
    const hUpgrade = createHarness({
      source,
      storage: hCold.state.storage,
      dynamicRules: hCold.state.getInstalledRules(),
      dnrLimit: 25000,
      onNativeMessage: nativeHandler
    });
    await flush();
    check(`[${label}] Runtime capability change bypasses Fast Path 2 and updates runtimeKey`,
      hUpgrade.state.isRegexSupportedCalls > 0
        && hUpgrade.state.storage.wblockRemoveParamDNRVersion.runtimeKey === "25000:18.4");
  });

  // 4. Backwards compatibility with native mocks ignoring knownVersion
  await withMockEnv(async env => {
    const legacyRules = [makeRule(1500000), makeRule(1500001)];
    const h = createHarness({
      source,
      onNativeMessage: msg => {
        if (msg.action === "getGlobalPrivacyControlState") return { enabled: false };
        if (msg.action === "getRemoveParamDNRRules") {
          return { ok: true, version: "legacy-v1", count: 2, rules: legacyRules, ruleIdBase: 1500000, ruleIdLimit: 1650000 };
        }
        if (msg.action === "getBlockedCountDNRRules") {
          return { ok: true, enabled: false, version: "", count: 0, rules: [] };
        }
        return fallbackNativeReply(msg);
      }
    });
    await flush();
    h.resetCounters();
    env.advanceMs(61_000);
    await h.triggerMessage();
    check(`[${label}] Mock ignoring knownVersion still triggers Fast Path 1 when version matches`,
      h.state.getDynamicRulesCalls.length === 0 && h.state.isRegexSupportedCalls === 0);
  });

  // 5. Epoch guard: onInstalled firing mid-startup must prevent in-flight startup from poisoning fast-path caches
  await withMockEnv(async () => {
    let holdDnr = true;
    let holdGpc = true;
    let markDnrEntered, releaseDnr, markGpcEntered, releaseGpc;
    const dnrEnteredPromise = new Promise(resolve => { markDnrEntered = resolve; });
    const dnrReleasePromise = new Promise(resolve => { releaseDnr = resolve; });
    const gpcEnteredPromise = new Promise(resolve => { markGpcEntered = resolve; });
    const gpcReleasePromise = new Promise(resolve => { releaseGpc = resolve; });

    const h = createHarness({
      source,
      dynamicRules: [makeRule(1500000)],
      storage: {
        wblockRemoveParamDNRVersion: {
          version: "rp-race",
          count: 1,
          countVersion: "false:",
          countCount: 0,
          runtimeKey: "30000:18.4"
        }
      },
      onGetDynamicRules: async args => {
        if (holdDnr && args.length === 0) {
          holdDnr = false;
          markDnrEntered();
          await dnrReleasePromise;
        }
      },
      onGetRegisteredScripts: async () => {
        if (holdGpc) {
          holdGpc = false;
          markGpcEntered();
          await gpcReleasePromise;
        }
      },
      onNativeMessage: msg => {
        if (msg.action === "getGlobalPrivacyControlState") {
          return { enabled: true };
        }
        if (msg.action === "getRemoveParamDNRRules") {
          if (msg.offset === 0 && msg.knownVersion === "rp-race") {
            return { ok: true, version: "rp-race", count: 1, rules: [], unchanged: true, ruleIdBase: 1500000, ruleIdLimit: 1650000 };
          }
          return { ok: true, version: "rp-race", count: 1, rules: [makeRule(1500000)], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
        }
        if (msg.action === "getBlockedCountDNRRules") {
          return { ok: true, enabled: false, version: "", count: 0, rules: [] };
        }
        return fallbackNativeReply(msg);
      }
    });
    // Wait until both startup DNR and startup GPC are mid-flight BEFORE setting their caches
    await Promise.all([dnrEnteredPromise, gpcEnteredPromise]);
    for (const listener of h.state.onInstalledListeners) listener();
    h.resetCounters();
    releaseDnr();
    releaseGpc();
    await flush();
    check(`[${label}] onInstalled mid-flight forces fresh DNR getDynamicRules verification`,
      h.state.getDynamicRulesCalls.some(args => args.length === 0));
    check(`[${label}] onInstalled mid-flight forces fresh GPC filtered getDynamicRules verification`,
      h.state.getDynamicRulesCalls.some(args => args.length === 1 && args[0]?.ruleIds?.[0] === 1700000));
  });
}

if (failures === 0) {
  console.log("\nAll DNR/GPC fast path tests passed!");
  process.exit(0);
} else {
  console.error(`\n${failures} test(s) failed`);
  process.exit(1);
}
