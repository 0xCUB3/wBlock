// Tests for the background script's persistent configuration cache and
// native host warm-up (cold-start fix for first-load-unprotected reports).
//
// Loads the real bundle from "wBlock Scripts (iOS)/Resources/background.js"
// with a stubbed `browser` API and drives the registered onMessage listener.
//
// Run: node scripts/test_background_config_cache.mjs

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const bundlePath = path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "background.js");
const bundleSource = readFileSync(bundlePath, "utf8");

const CACHE_KEY = "wblockConfigCacheV1";
const DOCUMENT_START_SCRIPT_CACHE_KEY = "wblockDocumentStartScriptCacheV1";
const WARMUP_URL = "https://warmup.wblock.invalid/";

let failures = 0;
const check = (name, condition) => {
  if (condition) {
    console.log(`PASS: ${name}`);
  } else {
    failures += 1;
    console.error(`FAIL: ${name}`);
  }
};

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

const makeConfig = (css, engineTimestamp, js = []) => ({
  css,
  extendedCss: [],
  js,
  scriptlets: [],
  engineTimestamp
});

// Loads the bundle with a fresh browser stub.
// nativeHandler receives every sendNativeMessage payload and returns the
// response (or a never-resolving promise to simulate a hung native host).
const loadBackground = ({ storage = {}, nativeHandler, executeScript = async () => [{}] }) => {
  const state = {
    storage,
    nativeMessages: [],
    cssInserted: [],
    executed: [],
    onMessage: null
  };

  const defaultNative = async message => {
    if (message && message.action === "getRemoveParamDNRRules") {
      return { ok: true, version: "test", count: 0, rules: [], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
    }
    return nativeHandler(message);
  };

  const listenerStub = { addListener: () => {} };
  const browser = {
    runtime: {
      sendNativeMessage: (_appId, message) => {
        state.nativeMessages.push(message);
        return defaultNative(message);
      },
      onMessage: { addListener: fn => { state.onMessage = fn; } },
      onInstalled: listenerStub,
      onStartup: listenerStub
    },
    storage: {
      local: {
        get: async key => {
          if (typeof key === "string") {
            return Object.hasOwn(state.storage, key) ? { [key]: state.storage[key] } : {};
          }
          return { ...state.storage };
        },
        set: async items => { Object.assign(state.storage, items); },
        remove: async key => { delete state.storage[key]; }
      }
    },
    tabs: {
      query: async () => [],
      get: async () => ({}),
      sendMessage: async () => ({}),
      onUpdated: listenerStub,
      onActivated: listenerStub,
      onCreated: listenerStub,
      onRemoved: listenerStub
    },
    scripting: {
      executeScript: async injection => {
        state.executed.push(injection);
        return executeScript(injection);
      },
      insertCSS: async injection => { state.cssInserted.push(injection); }
    },
    declarativeNetRequest: {
      getDynamicRules: async () => [],
      updateDynamicRules: async () => {}
    },
    i18n: { getMessage: () => "" }
  };

  const run = new Function("browser", "window", "self", bundleSource);
  run(browser, globalThis, globalThis);
  if (typeof state.onMessage !== "function") {
    throw new Error("background bundle did not register an onMessage listener");
  }
  return state;
};

const topFrameSender = url => ({ url, frameId: 0, tab: { id: 7, url } });

// Scenario A: persisted cache serves a top-frame config instantly while the
// native host hangs (cold start after Safari relaunch).
{
  const pageUrl = "https://example.com/";
  const state = loadBackground({
    storage: {
      [CACHE_KEY]: {
        engineTimestamp: 111,
        entries: [[`${pageUrl}#`, makeConfig(["#ad-banner"], 111)]]
      }
    },
    nativeHandler: message => {
      const url = message && message.payload ? message.payload.url : "";
      if (url === WARMUP_URL) {
        return { payload: makeConfig([], 111) };
      }
      return new Promise(() => {}); // hang: native host never answers
    }
  });

  await sleep(50); // let hydration + warm-up settle

  const warmupSeen = state.nativeMessages.some(m => m && m.payload && m.payload.url === WARMUP_URL);
  check("warm-up lookup is sent to the native host at startup", warmupSeen);

  let resolved = false;
  const dispatch = Promise.resolve(
    state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl))
  ).then(() => { resolved = true; });
  await Promise.race([dispatch, sleep(500)]);
  check("hydrated cache answers while the native host hangs", resolved);
  check(
    "cached CSS is applied to the tab",
    state.cssInserted.some(injection => String(injection.css).includes("#ad-banner"))
  );
}

// Scenario B: a newer engineTimestamp from the warm-up drops stale persisted
// entries, fresh config is fetched natively and re-persisted (without the
// warm-up key, capped LRU slice).
{
  const pageUrl = "https://example.com/";
  const state = loadBackground({
    storage: {
      [CACHE_KEY]: {
        engineTimestamp: 111,
        entries: [[`${pageUrl}#`, makeConfig(["#stale"], 111)]]
      }
    },
    nativeHandler: message => {
      const url = message && message.payload ? message.payload.url : "";
      if (url === WARMUP_URL) {
        return { payload: makeConfig([], 222) };
      }
      if (url === pageUrl) {
        return { payload: makeConfig(["#fresh"], 222) };
      }
      return { payload: makeConfig([], 222) };
    }
  });

  await sleep(50);
  await state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));

  const lookedUpPage = state.nativeMessages.some(m => m && m.payload && m.payload.url === pageUrl);
  check("engine update invalidates persisted entries (native lookup happens)", lookedUpPage);
  check(
    "fresh CSS is applied after invalidation",
    state.cssInserted.some(injection => String(injection.css).includes("#fresh"))
  );
  check(
    "stale CSS is not applied after invalidation",
    !state.cssInserted.some(injection => String(injection.css).includes("#stale"))
  );

  await sleep(1200); // wait for the debounced persist
  const persisted = state.storage[CACHE_KEY];
  check("cache is re-persisted with the new engineTimestamp", persisted && persisted.engineTimestamp === 222);
  check(
    "persisted entries contain the fresh top-frame config",
    persisted && persisted.entries.some(([key]) => key === `${pageUrl}#`)
  );
  check(
    "warm-up lookup is not persisted",
    persisted && !persisted.entries.some(([key]) => key.startsWith(WARMUP_URL))
  );
  check(
    "persisted slice respects the entry cap",
    persisted && persisted.entries.length <= 40
  );

  // Scenario C: wblock:clearCache also clears the persisted cache.
  const response = await state.onMessage({ action: "wblock:clearCache" }, topFrameSender(pageUrl));
  check("clearCache acknowledges", response && response.ok === true);
  check("clearCache removes the persisted cache", !Object.hasOwn(state.storage, CACHE_KEY));
}

// Scenario D: empty storage (first run) — lookup falls through to native.
{
  const pageUrl = "https://example.org/";
  const state = loadBackground({
    storage: {},
    nativeHandler: message => {
      const url = message && message.payload ? message.payload.url : "";
      if (url === pageUrl) {
        return { payload: makeConfig(["#first-run"], 5) };
      }
      return { payload: makeConfig([], 5) };
    }
  });

  await sleep(50);
  await state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  check(
    "first run without persisted cache still applies native config",
    state.cssInserted.some(injection => String(injection.css).includes("#first-run"))
  );
}

// Scenario E: executeScript treats unavailable targets and permission denials as
// expected skips, while unexpected failures remain visible as errors.
const runScriptInjectionScenario = async executeScript => {
  const pageUrl = "https://injection.example/";
  const state = loadBackground({
    storage: {},
    nativeHandler: () => ({ payload: makeConfig([], 9, ["test script"]) }),
    executeScript
  });
  const errors = [];
  const originalConsoleError = console.error;
  let rejected = false;
  console.error = (...args) => { errors.push(args); };
  try {
    await state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  } catch {
    rejected = true;
  } finally {
    console.error = originalConsoleError;
  }
  return { errors, rejected };
};

{
  const outcome = await runScriptInjectionScenario(async () => []);
  check("empty executeScript results are skipped without an error", !outcome.rejected && outcome.errors.length === 0);
}

{
  const outcome = await runScriptInjectionScenario(async () => {
    throw new Error("The extension does not have permission to access this page");
  });
  check("permission-denied executeScript rejection is skipped without an error", !outcome.rejected && outcome.errors.length === 0);
}

{
  const outcome = await runScriptInjectionScenario(async () => {
    throw new Error("Unexpected script injection failure");
  });
  check(
    "unexpected executeScript rejection is logged as an error",
    !outcome.rejected && outcome.errors.some(args => args.some(value => String(value).includes("Failed to execute script in target")))
  );
}

{
  const outcome = await runScriptInjectionScenario(async () => [{ error: "Unexpected script injection result" }]);
  check(
    "unexpected executeScript result error is logged",
    !outcome.rejected && outcome.errors.some(args => args.some(value => String(value).includes("Failed to execute script in target")))
  );
}

// Scenario F: timing-critical page-world userscripts bypass a blocked native
// configuration queue and are persisted for the next cold document start.
{
  const pageUrl = "https://discord.com/app";
  const vencord = {
    id: "vencord",
    name: "Vencord",
    runAt: "document-start",
    injectInto: "page",
    grant: ["GM_xmlhttpRequest", "unsafeWindow"],
    matches: ["*://*.discord.com/*"],
    excludeMatches: [],
    includes: [],
    excludes: [],
    resourceNames: [],
    content: "window.__vencordTest = true;",
    storageSnapshot: { shouldNotPersist: true }
  };
  const storageScript = {
    id: "storage-script",
    name: "Storage script",
    runAt: "document-start",
    injectInto: "page",
    grant: ["GM_getValue"],
    resourceNames: [],
    content: "window.__storageTest = GM_getValue('value');"
  };
  const state = loadBackground({
    storage: {},
    nativeHandler: message => {
      if (message && message.action === "getUserScripts") {
        return {
          userScripts: [vencord, storageScript],
          documentStartCacheAllowed: true
        };
      }
      if (message && message.payload && message.payload.url === WARMUP_URL) {
        return new Promise(() => {});
      }
      return { payload: makeConfig([], 1) };
    }
  });

  let response;
  let resolved = false;
  const request = Promise.resolve(state.onMessage({
    action: "getUserScripts",
    url: pageUrl,
    includeContent: true,
    maxInlineContentBytes: 128 * 1024
  }, topFrameSender(pageUrl))).then(value => {
    response = value;
    resolved = true;
  });
  await Promise.race([request, sleep(500)]);
  check("userscript lookup bypasses a blocked native configuration queue", resolved);
  check("priority userscript lookup returns the native scripts", response && response.userScripts.length === 2);
  await sleep(20);

  const persisted = state.storage[DOCUMENT_START_SCRIPT_CACHE_KEY];
  const persistedScripts = persisted && persisted.entries && persisted.entries[0] && persisted.entries[0][1];
  check("safe page-world document-start script is persisted", persistedScripts && persistedScripts.some(script => script.id === "vencord"));
  check("script with synchronous GM storage is not persisted", persistedScripts && !persistedScripts.some(script => script.id === "storage-script"));
  check(
    "storage snapshots are excluded from the early cache",
    persistedScripts && !Object.hasOwn(persistedScripts.find(script => script.id === "vencord"), "storageSnapshot")
  );

  persisted.catalog = [persistedScripts.find(script => script.id === "vencord")];
  persisted.disabledHosts = [];

  const fullTinyShield = {
    ...vencord,
    id: "tinyshield-full",
    name: "tinyShield",
    sourceURL: "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/tinyShield.user.js",
    matches: ["*://tinyshield.example/*"]
  };
  const groupedTinyShield = {
    ...vencord,
    id: "tinyshield-grouped",
    name: "tinyShield (example)",
    sourceURL: "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/grouped/e/tinyShield-example.user.js",
    matches: ["*://tinyshield.example/*"]
  };
  persisted.catalog.push(fullTinyShield, groupedTinyShield);

  const coldState = loadBackground({
    storage: { [DOCUMENT_START_SCRIPT_CACHE_KEY]: persisted },
    nativeHandler: message => {
      if (message && message.action === "getDocumentStartUserScriptCatalog") {
        return new Promise(() => {});
      }
      return { payload: makeConfig([], 1) };
    }
  });
  const cachedResponse = await coldState.onMessage({
    action: "getCachedDocumentStartUserScripts",
    url: pageUrl
  }, topFrameSender(pageUrl));
  check(
    "persisted document-start script is available after a cold background restart",
    cachedResponse && cachedResponse.userScripts.some(script => script.id === "vencord")
  );
  const catalogResponse = await coldState.onMessage({
    action: "getCachedDocumentStartUserScripts",
    url: "https://canary.discord.com/channels/@me"
  }, topFrameSender("https://canary.discord.com/channels/@me"));
  check(
    "catalog match metadata serves a script on another matching URL",
    catalogResponse && catalogResponse.userScripts.some(script => script.id === "vencord")
  );
  const unrelatedResponse = await coldState.onMessage({
    action: "getCachedDocumentStartUserScripts",
    url: "https://example.com/"
  }, topFrameSender("https://example.com/"));
  check("catalog scripts do not run on unrelated URLs", unrelatedResponse.userScripts.length === 0);

  const tinyShieldResponse = await coldState.onMessage({
    action: "getCachedDocumentStartUserScripts",
    url: "https://tinyshield.example/"
  }, topFrameSender("https://tinyshield.example/"));
  check(
    "catalog suppresses a grouped tinyShield variant when the full script runs",
    tinyShieldResponse.userScripts.length === 1 && tinyShieldResponse.userScripts[0].id === "tinyshield-full"
  );

  await coldState.onMessage({ action: "wblock:clearCache" }, topFrameSender(pageUrl));
  check(
    "clearCache removes the persisted document-start userscript cache",
    !Object.hasOwn(coldState.storage, DOCUMENT_START_SCRIPT_CACHE_KEY)
  );
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nAll background config cache checks passed");
process.exit(0);
