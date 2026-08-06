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

// Scenario L: timing-critical page-world userscripts bypass a blocked native
// configuration queue and are persisted for the next cold document start.
{
  const pageUrl = "https://discord.com/app";
  const vencord = {
    id: "vencord",
    name: "Vencord",
    isLocal: false,
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
  const state = loadBackground({
    storage: {},
    nativeHandler: message => {
      if (message && message.action === "getUserScripts") {
        return { userScripts: [vencord, storageScript] };
      }
      if (message && message.action === "getDocumentStartUserScriptCatalog") {
        return {
          userScripts: [vencord, storageScript, fullTinyShield, groupedTinyShield],
          disabledHosts: [],
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
  const persistedScripts = persisted && persisted.catalog;
  check("safe page-world document-start script is persisted", persistedScripts && persistedScripts.some(script => script.id === "vencord"));
  check("script with synchronous GM storage is not persisted", persistedScripts && !persistedScripts.some(script => script.id === "storage-script"));
  check(
    "storage snapshots are excluded from the early cache",
    persistedScripts && !Object.hasOwn(persistedScripts.find(script => script.id === "vencord"), "storageSnapshot")
  );

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
