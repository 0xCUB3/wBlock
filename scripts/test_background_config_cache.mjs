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
const canonicalSource = readFileSync(path.join(repoRoot, "extension-src", "background.js"), "utf8");

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

const makeConfig = (css, engineTimestamp, js = [], scriptlets = [], state = {}) => ({
  css,
  extendedCss: [],
  js,
  scriptlets,
  engineTimestamp,
  ...state
});

// Loads the bundle with a fresh browser stub.
// nativeHandler receives every sendNativeMessage payload and returns the
// response (or a never-resolving promise to simulate a hung native host).
const loadBackground = ({
  storage = {},
  nativeHandler,
  executeScript = async () => [{}],
  fetchImpl = globalThis.fetch,
  source = bundleSource,
  dynamicRules = [],
  sessionRules = [],
  dnrLimit = 30000,
  dnrUpdateHandler = async () => {},
  removeParamHandler = null,
  tabMessageHandler = async () => ({}),
}) => {
  const state = {
    storage,
    nativeMessages: [],
    cssInserted: [],
    executed: [],
    onMessage: null,
    nativePortMessage: null,
    tabQueries: 0,
    tabMessages: [],
    dnrUpdates: []
  };

  const defaultNative = async message => {
    if (message && message.action === "getRemoveParamDNRRules") {
      if (removeParamHandler) return removeParamHandler(message);
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
      connectNative: () => ({
        onMessage: { addListener: fn => { state.nativePortMessage = fn; } },
        onDisconnect: { addListener: () => {} }
      }),
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
      query: async () => { state.tabQueries += 1; return [{ id: 7 }]; },
      get: async () => ({}),
      sendMessage: async (tabId, message) => {
        state.tabMessages.push({ tabId, message });
        return tabMessageHandler(tabId, message);
      },
      onUpdated: { addListener: fn => { state.onTabUpdated = fn; } },
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
      ...(dnrLimit == null ? {} : { MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES: dnrLimit }),
      getDynamicRules: async () => dynamicRules,
      getSessionRules: async () => sessionRules,
      updateDynamicRules: async update => {
        state.dnrUpdates.push(update);
        return dnrUpdateHandler(update);
      }
    },
    i18n: { getMessage: () => "" }
  };

  const run = new Function("browser", "window", "self", "fetch", source);
  run(browser, globalThis, globalThis, fetchImpl);
  if (typeof state.onMessage !== "function") {
    throw new Error("background bundle did not register an onMessage listener");
  }
  return state;
};

const topFrameSender = url => ({ url, frameId: 0, tab: { id: 7, url } });
const frameSender = (url, topUrl, frameId = 1) => ({ url, frameId, tab: { id: 7, url: topUrl } });

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
      if (message && message.action === "getBlockingState") {
        return { disabled: false, paused: false };
      }
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
      if (message && message.action === "getBlockingState") {
        return { disabled: false, paused: false };
      }
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
  check(
    "cache miss keeps the single native configuration request",
    state.nativeMessages.filter(message => message && message.payload && message.payload.url === pageUrl).length === 1
      && !state.nativeMessages.some(message => message && message.action === "getBlockingState")
  );
}

// Scenario E: concurrent configuration misses share one native request, while a
// detached cache refresh cannot create an unhandled rejection.
{
  const pageUrl = "https://coalesce.example/";
  let configurationRequests = 0;
  const state = loadBackground({
    storage: {},
    nativeHandler: async message => {
      const url = message && message.payload ? message.payload.url : "";
      if (url === pageUrl) {
        configurationRequests += 1;
        await sleep(25);
        return { payload: makeConfig(["#coalesced"], 7) };
      }
      if (url === WARMUP_URL) {
        return { payload: makeConfig([], 7) };
      }
      return { payload: makeConfig([], 7) };
    }
  });
  await sleep(20);
  await Promise.all([
    state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl)),
    state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl))
  ]);
  check("concurrent configuration misses share one native request", configurationRequests === 1);

  const unhandled = [];
  const onUnhandledRejection = reason => unhandled.push(reason);
  process.on("unhandledRejection", onUnhandledRejection);
  const refreshState = loadBackground({
    storage: {
      [CACHE_KEY]: {
        engineTimestamp: 8,
        entries: [[`${pageUrl}#`, makeConfig(["#cached"], 8)]]
      }
    },
    nativeHandler: async message => {
      if (message && message.action === "getBlockingState") {
        return { disabled: false, paused: false };
      }
      const url = message && message.payload ? message.payload.url : "";
      if (url === WARMUP_URL) return { payload: makeConfig([], 8) };
      if (url === pageUrl) throw new Error("refresh failed");
      return { payload: makeConfig([], 8) };
    }
  });
  await sleep(20);
  await refreshState.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  await sleep(20);
  process.removeListener("unhandledRejection", onUnhandledRejection);
  check("failed background configuration refresh is safely consumed", unhandled.length === 0);

  let disabledRequests = 0;
  const disabledState = loadBackground({
    storage: {},
    nativeHandler: async message => {
      if (message && message.action === "getSiteDisabledState") {
        disabledRequests += 1;
        await sleep(25);
        return { disabled: true };
      }
      if (message && message.payload && message.payload.url === WARMUP_URL) {
        return { payload: makeConfig([], 9) };
      }
      return { payload: makeConfig([], 9) };
    }
  });
  const disabledResponses = await Promise.all([
    disabledState.onMessage({ action: "wblock:getSiteDisabledState", host: " Example.COM " }, topFrameSender(pageUrl)),
    disabledState.onMessage({ action: "wblock:getSiteDisabledState", host: "example.com" }, topFrameSender(pageUrl))
  ]);
  check("concurrent site-disabled requests share one normalized-host lookup", disabledRequests === 1);
  const disabledNativeRequest = disabledState.nativeMessages.find(message => message && message.action === "getSiteDisabledState");
  check("site-disabled lookup sends the normalized host", disabledNativeRequest && disabledNativeRequest.host === "example.com");
  check("coalesced site-disabled responses preserve the result", disabledResponses.every(response => response && response.disabled === true));
}

// Scenario F: a request started before clearCache cannot repopulate the cache;
// the next lookup must wait for a new native request.
{
  const pageUrl = "https://clear-race.example/";
  let configurationRequests = 0;
  let resolveStale;
  let resolveFresh;
  const staleResponse = new Promise(resolve => { resolveStale = resolve; });
  const freshResponse = new Promise(resolve => { resolveFresh = resolve; });
  const state = loadBackground({
    storage: {},
    nativeHandler: message => {
      const url = message && message.payload ? message.payload.url : "";
      if (url === WARMUP_URL) return { payload: makeConfig([], 1) };
      if (url === pageUrl) {
        configurationRequests += 1;
        return configurationRequests === 1
          ? staleResponse
          : freshResponse;
      }
      return { payload: makeConfig([], 1) };
    }
  });
  await sleep(20);
  const staleLookup = state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  await sleep(20);
  const clearLookup = state.onMessage({ action: "wblock:clearCache" }, topFrameSender(pageUrl));
  await sleep(20);
  check("pre-clear configuration request is in flight", configurationRequests === 1);
  resolveStale({ payload: makeConfig(["#stale"], 11) });
  await Promise.all([staleLookup, clearLookup]);

  let postClearResolved = false;
  const postClearLookup = state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl))
    .then(() => { postClearResolved = true; });
  await sleep(20);
  check("post-clear lookup does not use stale cached completion", !postClearResolved);
  check("post-clear lookup starts a fresh native request", configurationRequests === 2);
  resolveFresh({ payload: makeConfig(["#fresh"], 22) });
  await postClearLookup;
  check(
    "post-clear lookup applies fresh configuration",
    state.cssInserted.some(injection => String(injection.css).includes("#fresh"))
  );
}

// Scenario G: clearing configuration after a site toggle also drops the
// pending site-disabled request, so the next lookup gets current state.
{
  const pageUrl = "https://site-race.example/";
  let siteRequests = 0;
  let resolveStale;
  const staleResponse = new Promise(resolve => { resolveStale = resolve; });
  const state = loadBackground({
    storage: {},
    nativeHandler: message => {
      if (message && message.action === "getBlockingState") {
        return { disabled: false, paused: false };
      }
      if (message && message.payload && message.payload.url === WARMUP_URL) {
        return { payload: makeConfig([], 1) };
      }
      if (message && message.action === "getSiteDisabledState") {
        siteRequests += 1;
        return siteRequests === 1 ? staleResponse : { disabled: false };
      }
      return { payload: makeConfig([], 1) };
    }
  });
  await sleep(20);
  const staleLookup = state.onMessage(
    { action: "wblock:getSiteDisabledState", host: "example.com" },
    topFrameSender(pageUrl)
  );
  await sleep(20);
  const clearLookup = state.onMessage({ action: "wblock:clearCache" }, topFrameSender(pageUrl));
  await sleep(20);
  const postToggleLookup = state.onMessage(
    { action: "wblock:getSiteDisabledState", host: "example.com" },
    topFrameSender(pageUrl)
  );
  let postToggleResolved = false;
  postToggleLookup.then(() => { postToggleResolved = true; });
  await sleep(20);
  check("post-toggle site lookup does not use pending pre-toggle work", !postToggleResolved);
  resolveStale({ disabled: true });
  const [staleResult, postToggleResult] = await Promise.all([staleLookup, postToggleLookup]);
  await clearLookup;
  check("post-toggle site lookup starts a fresh native request", siteRequests === 2);
  check("post-toggle site lookup returns current state", staleResult.disabled === true && postToggleResult.disabled === false);
}

// Scenario H: executeScript treats unavailable targets and permission denials as
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

// Scenario I: blank-frame fallback receives background-compiled scriptlet source,
// while normal HTTP frames retain MAIN-world function injection.
{
  const pageUrl = "https://example.com/";
  const scriptlet = { name: "set-constant", args: ["__wblockBlankProbe", "1"] };
  const fallbackScriptlets = [
    { name: "missing-scriptlet", args: [] },
    scriptlet,
    { name: "another-missing-scriptlet", args: [] }
  ];
  const state = loadBackground({
    nativeHandler: message => {
      if (message && message.action === "getBlockingState") {
        return { disabled: false, paused: false };
      }
      if (message && message.payload && message.payload.url === pageUrl) {
        return { payload: makeConfig([], 17, [], fallbackScriptlets) };
      }
      return { payload: makeConfig([], 17) };
    }
  });
  for (const frameUrl of [
    "about:blank",
    "about:srcdoc",
    "data:text/html,<p>data frame</p>",
    "blob:https://example.com/00000000-0000-0000-0000-000000000000"
  ]) {
    const response = await state.onMessage(
      { type: "InitContentScript" },
      frameSender(frameUrl, pageUrl)
    );
    const scriptlets = response && response.payload && response.payload.scriptlets;
    const compiled = scriptlets && scriptlets[1];
    check(`${frameUrl} routes through the content fallback`, !!(response && response.payload) && state.executed.length === 0);
    check(`${frameUrl} carries precompiled scriptlet source`, compiled && compiled.code.includes("__wblockBlankProbe"));
    check(`${frameUrl} preserves thrown/unknown ordering`, scriptlets && scriptlets[0].code === "" && scriptlets[2].code === "");
    check(`${frameUrl} preserves blank-frame verbose=false metadata`, compiled
      && compiled.code.includes('"engine":"safari-extension"')
      && compiled.code.includes('"name":"set-constant"')
      && compiled.code.includes('"verbose":false'));
  }

  const httpState = loadBackground({
    nativeHandler: () => ({ payload: makeConfig([], 18, [], [scriptlet]) })
  });
  await httpState.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  check("HTTP frame still uses MAIN-world scriptlet injection", httpState.executed.some(injection => injection.world === "MAIN" && typeof injection.func === "function"));
  check("HTTP frame does not receive fallback payload", httpState.executed.every(injection => injection.world !== "ISOLATED" || injection.args === undefined || !injection.args.some(arg => arg && arg.code)));
}

// Scenario J: disabled/paused cache misses remain uncached, and the first
// navigation after re-enable/resume obtains a fresh active configuration.
for (const [label, inertState, activeCSS] of [
  ["disabled", { disabled: true, paused: false }, "#re-enabled"],
  ["paused", { disabled: false, paused: true }, "#resumed"]
]) {
  const pageUrl = `https://${label}-miss.example/`;
  let stateValue = inertState;
  const state = loadBackground({
    nativeHandler: message => {
      if (message && message.payload && message.payload.url === pageUrl) {
        const css = stateValue.disabled || stateValue.paused ? ["#must-not-run"] : [activeCSS];
        return { payload: makeConfig(css, 23, [], [], stateValue) };
      }
      return { payload: makeConfig([], 23) };
    }
  });
  const inertResponse = await state.onMessage(
    { type: "InitContentScript" },
    topFrameSender(pageUrl)
  );
  check(`${label} miss returns authoritative inert state`,
    inertResponse && inertResponse.disabled === inertState.disabled
      && inertResponse.paused === inertState.paused);
  check(`${label} miss does not apply native inert rules`, state.cssInserted.length === 0);
  await sleep(1100);
  check(`${label} miss does not persist inert configuration`,
    !state.storage[CACHE_KEY] || !state.storage[CACHE_KEY].entries.some(([key]) => key === `${pageUrl}#`));

  stateValue = { disabled: false, paused: false };
  await state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  check(`${label} re-enable/resume fetches active configuration`,
    state.cssInserted.some(injection => String(injection.css).includes(activeCSS)));
  await sleep(1100);
  check(`${label} re-enable/resume persists active configuration`,
    state.storage[CACHE_KEY] && state.storage[CACHE_KEY].entries.some(([, configuration]) =>
      configuration.css.some(css => String(css).includes(activeCSS))
    ));
}

// Scenario K: the background compatibility route is one combined lookup with
// the normalized host, not a generic configuration request.
{
  const state = loadBackground({
    nativeHandler: message => message && message.action === "getBlockingState"
      ? { disabled: true, paused: false }
      : { payload: makeConfig([], 24) }
  });
  const response = await state.onMessage(
    { action: "wblock:getBlockingState", host: " Example.COM " },
    topFrameSender("https://example.com/")
  );
  const nativeRequest = state.nativeMessages.find(message => message && message.action === "getBlockingState");
  check("combined compatibility route returns both state fields",
    response && response.disabled === true && response.paused === false);
  check("combined compatibility route sends normalized host",
    nativeRequest && nativeRequest.host === "example.com");
  check("combined compatibility route does not request configuration",
    !state.nativeMessages.some(message => message && message.payload
      && message.payload.url === "https://example.com/"));
}

// Scenario L: native configuration failures return an explicit error state and
// never create a cache entry.
{
  const pageUrl = "https://native-error.example/";
  const state = loadBackground({ nativeHandler: message => {
    if (message && message.payload && message.payload.url === pageUrl) {
      return { payload: message.payload, state: "error", error: "native configuration failed" };
    }
    return { payload: makeConfig([], 25) };
  }});
  const response = await state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  check("native configuration failure returns an error state",
    response && response.state === "error" && String(response.error).includes("native configuration failed"));
  await sleep(1100);
  check("native configuration failure does not persist a cache entry",
    !state.storage[CACHE_KEY] || !state.storage[CACHE_KEY].entries.some(([key]) => key === `${pageUrl}#`));
}

// Scenario M: cache hits resolve current state before applying rules across
// pause and site-disable transitions.
{
  const pageUrl = "https://cache-state.example/";
  let stateValue = { disabled: false, paused: false };
  let blockingStateRequests = 0;
  const state = loadBackground({
    nativeHandler: message => {
      if (message && message.action === "getBlockingState") {
        blockingStateRequests += 1;
        return new Promise(resolve => setTimeout(() => resolve({ ...stateValue }), 10));
      }
      const url = message && message.payload ? message.payload.url : "";
      if (url === WARMUP_URL) return { payload: makeConfig([], 31) };
      return { payload: makeConfig(["#cached-state"], 31, [], [], { disabled: false, paused: false }) };
    }
  });

  await sleep(20);
  await state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  const beforeCoalescedState = blockingStateRequests;
  await Promise.all([
    state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl)),
    state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl))
  ]);
  check(
    "concurrent cached lookups coalesce the priority state request",
    blockingStateRequests === beforeCoalescedState + 1
  );
  const initialApplications = state.cssInserted.length;
  stateValue = { disabled: false, paused: true };
  await state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  check(
    "enabled-to-paused cache transition does not apply cached rules",
    state.cssInserted.length === initialApplications
  );

  stateValue = { disabled: false, paused: false };
  await state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  check(
    "paused-to-enabled cache transition reapplies current rules",
    state.cssInserted.length === initialApplications + 1
  );

  stateValue = { disabled: true, paused: false };
  await state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl));
  check(
    "enabled-to-site-disabled cache transition does not apply cached rules",
    state.cssInserted.length === initialApplications + 1
  );
}

// Scenario L: the permanently-disabled native document-start catalog/cache
// contract is absent, while ordinary userscript payloads remain authoritative.
{
  const forbidden = [
    "getDocumentStartUserScriptCatalog",
    "getCachedDocumentStartUserScripts",
    "documentStartCacheAllowed",
    "cacheRevision",
    "cacheCategory",
    "documentStartScriptCatalog"
  ];
  for (const symbol of forbidden) {
    check(`canonical source removes ${symbol}`, !canonicalSource.includes(symbol));
    check(`bundle removes ${symbol}`, !bundleSource.includes(symbol));
  }

  const pageUrl = "https://example.com/";
  const state = loadBackground({
    nativeHandler: message => message && message.action === "getUserScripts"
      ? { userScripts: [{ id: "live", runAt: "document-start", content: "window.__live = true;" }] }
      : { payload: makeConfig([], 1) }
  });
  const response = await state.onMessage({ action: "getUserScripts", url: pageUrl, includeContent: true }, topFrameSender(pageUrl));
  check("ordinary userscript lookup returns native scripts", response.userScripts.length === 1);
  check("ordinary userscript response has no cache fields", !Object.hasOwn(response, "cacheRevision") && !Object.hasOwn(response, "documentStartCacheAllowed"));
  check("catalog route is never sent", !state.nativeMessages.some(message => message && message.action === "getDocumentStartUserScriptCatalog"));
}

// Scenario M: userscript mutation invalidates live document-start sessions by
// broadcasting the native session-cache clear, without any catalog refresh.
{
  const state = loadBackground({ nativeHandler: () => ({ payload: makeConfig([], 1) }) });
  state.nativePortMessage({ action: "wblock:userscriptsChanged" });
  await sleep(20);
  check("userscriptsChanged broadcasts live session invalidation", state.tabMessages.some(({ message }) => message && message.type === "wblock:clearDocumentStartSessionCache"));
  check("userscriptsChanged does not request a catalog", !state.nativeMessages.some(message => message && message.action === "getDocumentStartUserScriptCatalog"));
}


// Page rules must stay responsive while either maintenance download is pending.
for (const maintenanceAction of ["maybeUpdateUserScripts", "maybeStageFilterUpdates"]) {
  let releaseMaintenance;
  let markMaintenanceStarted;
  let releasePage;
  const heldMaintenance = new Promise(resolve => { releaseMaintenance = resolve; });
  const maintenanceStarted = new Promise(resolve => { markMaintenanceStarted = resolve; });
  const heldPage = new Promise(resolve => { releasePage = resolve; });
  const pageUrl = "https://fresh-page.example/";
  const state = loadBackground({ nativeHandler: message => {
    if (message.action === maintenanceAction) {
      markMaintenanceStarted();
      return heldMaintenance;
    }
    if (message.action === "maybeUpdateUserScripts" || message.action === "maybeStageFilterUpdates") {
      return { updated: 0, staged: 0 };
    }
    if (message.action === "getBlockingState") return { disabled: false, paused: false };
    if (message.payload?.url === pageUrl) return heldPage;
    return { payload: makeConfig([], 1) };
  }});

  await sleep(20);
  state.onTabUpdated(7, { status: "complete" }, { id: 7, url: "https://previous-page.example/" });
  let maintenanceRunning = false;
  await Promise.race([
    maintenanceStarted.then(() => { maintenanceRunning = true; }),
    sleep(500)
  ]);
  check(`${maintenanceAction} starts through tab completion`, maintenanceRunning);

  let completed = false;
  const requests = Promise.all([
    state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl)),
    state.onMessage({ type: "InitContentScript" }, topFrameSender(pageUrl))
  ]).then(() => { completed = true; });
  await sleep(50);
  check(`page lookup bypasses ${maintenanceAction} and still coalesces`,
    state.nativeMessages.filter(message => message.payload?.url === pageUrl).length === 1);
  if (maintenanceAction === "maybeUpdateUserScripts") {
    check("filter staging still waits behind userscript maintenance",
      !state.nativeMessages.some(message => message.action === "maybeStageFilterUpdates"));
  }
  releasePage({ payload: makeConfig(["#fresh-page-ad"], 1) });
  await Promise.race([requests, sleep(500)]);
  check(`page rules apply before ${maintenanceAction} finishes`, completed &&
    state.cssInserted.some(injection => injection.css.includes("#fresh-page-ad")));

  releaseMaintenance({ updated: 0, staged: 0 });
  await requests;
}


// Requests use native metadata and the browser-supplied frame URL, not page payloads.
{
  let entries = ["self"];
  let authorized = true;
  const calls = [];
  let respond = async () => new Response("ok");
  const state = loadBackground({
    nativeHandler: message => {
      if (message.action === "getUserScriptRequestPolicy") return { ok: authorized, connect: entries };
      if (message.action === "gmXmlhttpRequestNative") return { responseText: "native-ok" };
      return { payload: makeConfig([], 1) };
    },
    fetchImpl: async (url, options) => { calls.push({ url, options }); return respond(url, options); }
  });
  const sender = { tab: { id: 7 }, frameId: 0, url: "https://page.invalid/" };
  const request = url => state.onMessage({ action: "gmXmlhttpRequest", scriptId: "script-1", url, connect: ["*"], pageURL: "https://forged.invalid/" }, sender);
  for (const action of ["gmXmlhttpRequestNative", "getUserScriptRequestPolicy"]) {
    const count = () => state.nativeMessages.filter(message => message.action === action).length;
    const before = count();
    check(`raw ${action} cannot bypass GM authorization`, !!(await state.onMessage({ action, scriptId: "script-1", pageURL: sender.url, url: sender.url }, sender)).error && count() === before);
  }
  check("missing script identity cannot fetch", !!(await state.onMessage({ action: "gmXmlhttpRequest", url: sender.url }, sender)).error && calls.length === 0);
  check("missing sender URL cannot borrow payload URL", !!(await state.onMessage({ action: "gmXmlhttpRequest", scriptId: "script-1", url: sender.url, pageURL: sender.url }, { frameId: 0 })).error && calls.length === 0);
  check("caller cannot forge connect wildcard", !!(await request("https://outside.invalid/")).error && calls.length === 0);
  check("self request succeeds", (await request(sender.url)).responseText === "ok");
  const policyRequest = state.nativeMessages.find(message => message.action === "getUserScriptRequestPolicy");
  check("policy uses sender identity and frame", policyRequest.pageURL === sender.url && policyRequest.isTopFrame === true);
  for (const [rules, url, allowed] of [
    [["example.org"], "https://sub.example.org/", true],
    [["example.org"], "https://evil-example.org/", false],
    [["example.org"], "https://example.org.evil/", false],
    [["localhost"], "http://localhost:8080/", true],
    [["*"], "file:///etc/passwd", false],
    [["*"], "https://user:secret@example.org/", false],
    [["*"], "https://anywhere.invalid/", true],
    [["https://example.org"], "https://example.org/", false],
    [[], sender.url, false]
  ]) {
    entries = rules;
    const before = calls.length;
    const result = await request(url);
    check(`connect ${JSON.stringify(rules)} for ${url}`, allowed ? result.responseText === "ok" : !!result.error && calls.length === before);
  }
  entries = ["page.invalid"];
  respond = async () => new Response(null, { status: 302, headers: { location: "https://outside.invalid/" } });
  let before = calls.length;
  check("unapproved redirect never fetches target", !!(await request(sender.url)).error && calls.length === before + 1);
  entries = ["page.invalid", "allowed.invalid"];
  respond = async url => url === sender.url ? new Response(null, { status: 302, headers: { location: "https://allowed.invalid/" } }) : new Response("redirect-ok");
  check("approved redirect succeeds", (await request(sender.url)).responseText === "redirect-ok");
  check("fetch always uses manual redirects", calls.every(call => call.options.redirect === "manual"));
  respond = async () => ({ type: "opaqueredirect" });
  check("opaque redirects fail closed", !!(await request(sender.url)).error);
  authorized = false;
  before = calls.length;
  check("disabled scripts lose network access", !!(await request(sender.url)).error && calls.length === before);
  authorized = true;
  entries = ["self"];
  const nativeCount = () => state.nativeMessages.filter(message => message.action === "gmXmlhttpRequestNative").length;
  const restricted = await state.onMessage({ action: "gmXmlhttpRequest", scriptId: "script-1", url: "https://outside.invalid/", headers: { "User-Agent": "test" } }, sender);
  check("native-header path cannot bypass connect", !!restricted.error && nativeCount() === 0);
  await state.onMessage({ action: "gmXmlhttpRequest", scriptId: "script-1", url: sender.url, headers: { "User-Agent": "test" } }, sender);
  const nativeRequest = state.nativeMessages.find(message => message.action === "gmXmlhttpRequestNative");
  check("native path carries trusted identity for revalidation", nativeRequest?.scriptId === "script-1" && nativeRequest?.pageURL === sender.url);
}

// RemoveParam runtime compatibility/capacity and atomic replacement use the
// canonical source so these checks do not depend on when the generated bundle
// is refreshed.
{
  const rules = [
    { id: 1500000, priority: 20000, action: { type: "allow" }, condition: { requestDomains: ["disabled.example"], resourceTypes: ["main_frame"] } },
    { id: 1500001, priority: 1, action: { type: "redirect", redirect: { transform: { queryTransform: { removeParams: ["utm"] } } } }, condition: { initiatorDomains: ["page.example"], urlFilter: "^utm=" } },
    { id: 1500002, priority: 1, action: { type: "redirect", redirect: { transform: { queryTransform: { removeParams: ["id"] } } } }, condition: { requestDomains: ["target.example"], urlFilter: "^id=" } },
  ];
  const state = loadBackground({
    source: canonicalSource,
    dnrLimit: null,
    removeParamHandler: message => ({
      ok: true, version: "legacy", count: rules.length,
      rules: message.offset === 0 ? rules : [], ruleIdBase: 1500000, ruleIdLimit: 1650000
    }),
    nativeHandler: () => ({ payload: makeConfig([], 1) }),
  });
  await sleep(50);
  const update = state.dnrUpdates[0];
  check("old Safari DNR uses one atomic replacement", state.dnrUpdates.length === 1 && Array.isArray(update?.removeRuleIds) && Array.isArray(update?.addRules));
  check("old Safari request-domain allow downgrades to exact host URL filter",
    update?.addRules?.some(rule => rule.id === 1500000 && rule.condition.urlFilter === "||disabled.example^" && !rule.condition.requestDomains));
  check("old Safari initiatorDomains downgrades to legacy domains",
    update?.addRules?.some(rule => rule.id === 1500001 && rule.condition.domains?.[0] === "page.example" && !rule.condition.initiatorDomains));
  check("old Safari skips unrepresentable request-domain redirect instead of widening it",
    !update?.addRules?.some(rule => rule.id === 1500002));
}

for (const source of [canonicalSource, bundleSource]) {
  const rules = [
    { id: 1500000, priority: 10000, action: { type: "allow" }, condition: { excludedRequestDomains: ["exception.example"], urlFilter: "^p=" } },
    { id: 1500001, priority: 1, action: { type: "redirect", redirect: { transform: { queryTransform: { removeParams: ["p"] } } } }, condition: { urlFilter: "^p=" } },
  ];
  const state = loadBackground({
    source,
    dnrLimit: null,
    removeParamHandler: message => ({
      ok: true, version: "legacy-unsupported-exception", count: rules.length,
      rules: message.offset === 0 ? rules : [], ruleIdBase: 1500000, ruleIdLimit: 1650000
    }),
    nativeHandler: () => ({ payload: makeConfig([], 1) }),
  });
  await sleep(50);
  check("old Safari never widens redirects by dropping an unsupported exception", state.dnrUpdates[0]?.addRules?.length === 0);
}

{
  const rules = Array.from({ length: 5100 }, (_, index) => ({
    id: 1500000 + index,
    priority: 1,
    action: { type: "redirect", redirect: { transform: { queryTransform: { removeParams: ["p"] } } } },
    condition: { urlFilter: "^p=", resourceTypes: ["main_frame"] }
  }));
  const legacy = loadBackground({
    source: canonicalSource,
    dnrLimit: null,
    removeParamHandler: message => ({
      ok: true, version: "legacy-cap", count: rules.length,
      rules: message.offset === 0 ? rules.slice(0, 250) : rules.slice(message.offset, message.offset + message.limit),
      ruleIdBase: 1500000, ruleIdLimit: 1650000
    }),
    nativeHandler: () => ({ payload: makeConfig([], 1) }),
  });
  await sleep(80);
  check("old Safari fallback capacity is bounded without lowering modern runtimes", legacy.dnrUpdates[0]?.addRules?.length === 5000);

  const modern = loadBackground({
    source: canonicalSource,
    dnrLimit: 30000,
    removeParamHandler: message => ({
      ok: true, version: "modern-cap", count: rules.length,
      rules: message.offset === 0 ? rules.slice(0, 250) : rules.slice(message.offset, message.offset + message.limit),
      ruleIdBase: 1500000, ruleIdLimit: 1650000
    }),
    nativeHandler: () => ({ payload: makeConfig([], 1) }),
  });
  await sleep(80);
  check("modern Safari preserves rules above the old fallback when runtime reports 30000", modern.dnrUpdates[0]?.addRules?.length === 5100);
}

{
  const redirects = Array.from({ length: 6 }, (_, index) => ({
    id: 1500100 + index,
    priority: 1,
    action: { type: "redirect", redirect: { transform: { queryTransform: { removeParams: ["p"] } } } },
    condition: { urlFilter: `^p${index}=`, resourceTypes: ["main_frame"] }
  }));
  const protective = [
    { id: 1500000, priority: 20000, action: { type: "allow" }, condition: { urlFilter: "||disabled.example^" } },
    { id: 1500001, priority: 10000, action: { type: "allow" }, condition: { urlFilter: "||exception.example^" } },
  ];
  const mixed = [...redirects, ...protective];
  const state = loadBackground({
    source: canonicalSource,
    dnrLimit: 5,
    removeParamHandler: message => ({
      ok: true, version: "protective-first", count: mixed.length,
      rules: message.offset === 0 ? mixed : [], ruleIdBase: 1500000, ruleIdLimit: 1650000
    }),
    nativeHandler: () => ({ payload: makeConfig([], 1) }),
  });
  await sleep(50);
  check("capacity keeps all allow/exception rules before redirect rules",
    state.dnrUpdates[0]?.addRules?.length === 5
      && state.dnrUpdates[0].addRules.slice(0, 2).every(rule => rule.action.type === "allow"));
}

{
  const protective = Array.from({ length: 6 }, (_, index) => ({
    id: 1500000 + index,
    priority: 10000,
    action: { type: "allow" },
    condition: { urlFilter: `||protect${index}.example^` }
  }));
  const state = loadBackground({
    source: canonicalSource,
    dnrLimit: 5,
    removeParamHandler: message => ({
      ok: true, version: "protective-overflow", count: protective.length,
      rules: message.offset === 0 ? protective : [], ruleIdBase: 1500000, ruleIdLimit: 1650000
    }),
    nativeHandler: () => ({ payload: makeConfig([], 1) }),
  });
  await sleep(50);
  check("protective rules exceeding capacity disables removeparam rather than widening",
    state.dnrUpdates[0]?.addRules?.length === 0);
}

{
  const first = Array.from({ length: 250 }, (_, index) => ({ id: 1500000 + index, action: { type: "allow" }, condition: {} }));
  const state = loadBackground({
    source: canonicalSource,
    removeParamHandler: message => message.offset === 0
      ? { ok: true, version: "v1", count: 251, rules: first, ruleIdBase: 1500000, ruleIdLimit: 1650000 }
      : { ok: true, version: "v2", count: 251, rules: [{ id: 1500250, action: { type: "allow" }, condition: {} }], ruleIdBase: 1500000, ruleIdLimit: 1650000 },
    nativeHandler: () => ({ payload: makeConfig([], 1) }),
  });
  await sleep(50);
  check("mixed-generation RemoveParam chunks are rejected before install", state.dnrUpdates.length === 0);
}

{
  const state = loadBackground({
    source: canonicalSource,
    removeParamHandler: () => ({ ok: true, version: "short", count: 2, rules: [{ id: 1500000, action: { type: "allow" }, condition: {} }], ruleIdBase: 1500000, ruleIdLimit: 1650000 }),
    nativeHandler: () => ({ payload: makeConfig([], 1) }),
  });
  await sleep(50);
  check("declared RemoveParam count mismatch is rejected before install", state.dnrUpdates.length === 0);
}

{
  const oldTracked = [{ id: 1500000, action: { type: "redirect" }, condition: {} }];
  const replacement = [{ id: 1500000, priority: 1, action: { type: "allow" }, condition: { urlFilter: "||new.example^" } }];
  const storage = {};
  const state = loadBackground({
    source: canonicalSource,
    storage,
    dynamicRules: oldTracked,
    dnrLimit: 30000,
    dnrUpdateHandler: async () => { throw new Error("validation failed"); },
    removeParamHandler: message => ({
      ok: true, version: "replacement", count: 1,
      rules: message.offset === 0 ? replacement : [], ruleIdBase: 1500000, ruleIdLimit: 1650000
    }),
    nativeHandler: () => ({ payload: makeConfig([], 1) }),
  });
  await sleep(50);
  check("failed RemoveParam replacement is attempted as one remove+add transaction",
    state.dnrUpdates.length === 1
      && state.dnrUpdates[0].removeRuleIds?.[0] === 1500000
      && state.dnrUpdates[0].addRules?.[0]?.id === 1500000);
  check("failed atomic replacement does not persist a success marker", storage.wblockRemoveParamDNRVersion === undefined);
}

// Content-script state/mutation requests terminate in the background; only the
// background owns native messaging on Safari.
{
  const state = loadBackground({
    source: canonicalSource,
    nativeHandler: message => {
      if (message.action === "getNoAutoplayState") return { enabled: true, siteAllowed: false };
      if (message.action === "setSiteZapperDisabled") return { ok: true, disabled: message.disabled === true };
      return { payload: makeConfig([], 1) };
    },
  });
  const sender = topFrameSender("https://example.com/");
  const autoplay = await state.onMessage({ action: "wblock:noAutoplay:getState", host: "Example.COM" }, sender);
  check("No Autoplay content relay returns validated native state",
    autoplay.ok === true && autoplay.enabled === true && autoplay.siteAllowed === false);
  check("No Autoplay relay normalizes host before native messaging",
    state.nativeMessages.some(message => message.action === "getNoAutoplayState" && message.host === "example.com"));

  const zapper = await state.onMessage({ action: "wblock:zapper:setDisabled", hostname: "example.com", disabled: true }, sender);
  check("Zapper content relay forwards per-site disable mutation",
    zapper.ok === true && zapper.disabled === true
      && state.nativeMessages.some(message => message.action === "setSiteZapperDisabled" && message.hostname === "example.com" && message.disabled === true));

  const broadcast = await state.onMessage({ action: "wblock:zapper:broadcastReload" }, sender);
  check("top-frame fallback relay broadcasts a reload to the sender tab",
    broadcast.ok === true
      && state.tabMessages.some(entry => entry.tabId === 7 && entry.message?.type === "wblock:zapper:reloadRules"));
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nAll background config cache checks passed");
process.exit(0);
