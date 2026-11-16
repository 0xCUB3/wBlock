// Behavior checks for the shipped background's page-style insertion, the path a
// bfcache restore and a page load both take. The rules go in as CSS_RULES_PER_INSERT
// chunks; the frame marker goes in last, only after every chunk succeeded, so a
// marker on the page means the whole set is applied.
//
// Loads the real bundle from "wBlock Scripts (iOS)/Resources/background.js" with a
// stubbed `browser` API and drives its onMessage listener. A failing insertCSS
// call is picked by the text it carries.
//
// Run: node scripts/test_background_frame_styles.mjs [path/to/background.js]

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { runtimeMessageListener } from "./helpers/runtime-message.mjs";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const bundlePath = process.argv[2]
  ?? path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "background.js");
const bundleSource = readFileSync(bundlePath, "utf8");

// Matches CSS_RULES_PER_INSERT in extension-src/background.js.
const CSS_RULES_PER_INSERT = 1000;
const PAGE = "https://example.test/page";
const MARKER_NEEDLE = "--wblock-frame-styles";

let failures = 0;
const check = (name, condition, detail = "") => {
  if (condition) {
    console.log(`PASS: ${name}`);
  } else {
    failures += 1;
    console.error(`FAIL: ${name}${detail ? ` [${detail}]` : ""}`);
  }
};

// One filler rule per chunk slot plus the two real hides, so the rule count is
// CSS_RULES_PER_INSERT + 1 and the second chunk holds only the last selector.
const selectors = [
  ...Array.from({ length: CSS_RULES_PER_INSERT - 1 }, (_, i) => `.filler-${i}`),
  ".ad-slot-0",
  ".ad-slot-1"
];
const FIRST_CHUNK_NEEDLE = ".filler-0 {";
const SECOND_CHUNK_NEEDLE = ".ad-slot-1 {";

const configuration = (overrides = {}) => ({
  css: selectors,
  styles: [],
  procedural: [],
  scriptlets: [],
  engineTimestamp: 1,
  disabled: false,
  paused: false,
  ...overrides
});

// Loads the bundle with a fresh browser stub. `config` is what the native host
// returns for every InitContentScript lookup, or an Error to throw.
// `failWhen` decides whether an insertCSS call rejects, from its injection.
const loadBackground = ({ config = configuration(), failWhen = () => null, tabUrl = PAGE } = {}) => {
  const state = {
    attempts: [],
    applied: [],
    onMessage: null,
    nativeMessages: []
  };
  const listenerStub = { addListener: () => {} };
  const defaultNative = async message => {
    if (message && message.action === "getRemoveParamDNRRules") {
      return { ok: true, version: "test", count: 0, rules: [], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
    }
    if (message && message.type === "InitContentScript") {
      if (config instanceof Error) throw config;
      return { payload: config };
    }
    return { ok: true };
  };
  const browser = {
    runtime: {
      getURL: relative => `safari-web-extension://test/${relative}`,
      sendNativeMessage: (_appId, message) => {
        state.nativeMessages.push(message);
        return defaultNative(message);
      },
      onMessage: { addListener: fn => { state.onMessage = runtimeMessageListener(fn); } },
      connectNative: () => ({
        onMessage: { addListener: () => {} },
        onDisconnect: { addListener: () => {} }
      }),
      onInstalled: listenerStub,
      onStartup: listenerStub
    },
    storage: {
      local: {
        get: async () => ({}),
        set: async () => {},
        remove: async () => {}
      }
    },
    tabs: {
      query: async () => [{ id: 7 }],
      get: async id => ({ id, url: tabUrl }),
      sendMessage: async () => ({}),
      onUpdated: listenerStub,
      onActivated: listenerStub,
      onCreated: listenerStub,
      onRemoved: listenerStub
    },
    scripting: {
      executeScript: async () => [{}],
      insertCSS: async injection => {
        state.attempts.push(injection);
        const failure = failWhen(injection);
        if (failure) throw new Error(failure);
        state.applied.push(injection);
      },
      removeCSS: async () => {}
    },
    declarativeNetRequest: {
      isRegexSupported: async () => ({ isSupported: true }),
      getDynamicRules: async () => [],
      getSessionRules: async () => [],
      updateDynamicRules: async () => {}
    },
    i18n: { getMessage: () => "" }
  };
  new Function("browser", "window", "self", "fetch", bundleSource)(browser, globalThis, globalThis, globalThis.fetch);
  if (typeof state.onMessage !== "function") {
    throw new Error("background bundle did not register an onMessage listener");
  }
  return state;
};

const topFrameSender = { url: PAGE, frameId: 0, tab: { id: 7, url: PAGE } };
const restore = (state, sender = topFrameSender) => state.onMessage({ action: "wblock:restoreFrameStyles" }, sender);
const hasMarker = injection => injection.css.includes(MARKER_NEEDLE);
const markerCalls = calls => calls.filter(hasMarker);
const failOn = needle => injection => (injection.css.includes(needle) ? "chunk rejected by engine" : null);

console.log("first chunk rejects during a restore");
{
  const state = loadBackground({ failWhen: failOn(FIRST_CHUNK_NEEDLE) });
  const response = await restore(state);
  check("restore reports an error so the content script retries", response.state === "error", JSON.stringify(response));
  check("no frame marker is applied after a failed chunk", markerCalls(state.applied).length === 0);
}

console.log("second chunk rejects during a restore");
{
  const state = loadBackground({ failWhen: failOn(SECOND_CHUNK_NEEDLE) });
  const response = await restore(state);
  check("restore reports an error so the content script retries", response.state === "error", JSON.stringify(response));
  check("no frame marker is applied after a failed chunk", markerCalls(state.applied).length === 0);
}

console.log("retry after a failed chunk");
{
  let failing = true;
  const state = loadBackground({ failWhen: injection => (failing && injection.css.includes(SECOND_CHUNK_NEEDLE) ? "chunk rejected by engine" : null) });
  await restore(state);
  failing = false;
  const response = await restore(state);
  check("the retry completes", response.restored === true && response.state === "applied", JSON.stringify(response));
  const last = state.applied[state.applied.length - 1];
  check("the retry ends with the marker", last !== undefined && hasMarker(last));
  check("the retry applies the second chunk", state.applied.some(injection => injection.css.includes(SECOND_CHUNK_NEEDLE)));
}

console.log("marker placement on a successful restore");
{
  const state = loadBackground();
  const response = await restore(state);
  check("success reports applied", response.state === "applied", JSON.stringify(response));
  check("two chunks: a full one, then the last rule with the marker", state.applied.length === 2, `calls=${state.applied.length}`);
  check("the marker rides in the last chunk, once", markerCalls(state.applied).length === 1 && hasMarker(state.applied[state.applied.length - 1]));
  check("no call exceeds CSS_RULES_PER_INSERT rules", state.applied.every(injection => injection.css.split("\n").length <= CSS_RULES_PER_INSERT));
}

console.log("exactly CSS_RULES_PER_INSERT rules: the marker must not overflow a full chunk");
{
  const state = loadBackground({ config: configuration({ css: selectors.slice(0, CSS_RULES_PER_INSERT) }) });
  const response = await restore(state);
  check("success reports applied", response.state === "applied", JSON.stringify(response));
  check("the marker goes in a call of its own", state.applied.length === 2 && !state.applied[1].css.includes("display: none"), `calls=${state.applied.length}`);
  check("no call exceeds CSS_RULES_PER_INSERT rules", state.applied.every(injection => injection.css.split("\n").length <= CSS_RULES_PER_INSERT));
}

console.log("page load with a failed chunk, then a restore");
{
  let failing = true;
  const state = loadBackground({ failWhen: injection => (failing && injection.css.includes(SECOND_CHUNK_NEEDLE) ? "chunk rejected by engine" : null) });
  const loadReply = await state.onMessage({ type: "InitContentScript", includeUserScripts: false }, topFrameSender);
  check("page load does not report a restore error to the page", loadReply && loadReply.state !== "error", JSON.stringify(loadReply));
  check("page load with a failed chunk applies no marker", markerCalls(state.applied).length === 0);
  failing = false;
  const response = await restore(state);
  check("the next restore fills the missing chunk and sets the marker", response.state === "applied" && markerCalls(state.applied).length === 1, JSON.stringify(response));
}

console.log("target skipped during a restore (tab navigated away)");
{
  const state = loadBackground({ failWhen: () => "Tab not found" });
  const response = await restore(state);
  check("a skipped target is not reported as applied", response.restored !== true, JSON.stringify(response));
  check("a skipped target reports skipped, with no retry", response.state === "skipped", JSON.stringify(response));
  check("a skipped target sets no marker", markerCalls(state.applied).length === 0);
}

console.log("no CSS configuration");
{
  const state = loadBackground({ config: configuration({ css: [], styles: [] }) });
  const response = await restore(state);
  check("no insertion when there is no CSS", state.attempts.length === 0);
  check("no CSS reports empty, which the content script does not retry", response.state === "empty", JSON.stringify(response));
}

console.log("site disabled while the page was cached");
{
  const state = loadBackground({ config: configuration({ disabled: true }) });
  const response = await restore(state);
  check("no insertion while disabled", state.attempts.length === 0);
  check("disabled is not an error", response.state !== "error", JSON.stringify(response));
}

console.log("native lookup fails during a restore");
{
  const state = loadBackground({ config: new Error("native unavailable") });
  const response = await restore(state);
  check("a lookup failure is an error the content script retries", response.state === "error", JSON.stringify(response));
  check("no insertion after a lookup failure", state.attempts.length === 0);
}

console.log("top-level URL changed while the lookup was in flight");
{
  const state = loadBackground({ tabUrl: "https://example.test/other" });
  const response = await restore(state);
  check("a stale top-level document gets no styles", state.attempts.length === 0);
  check("a stale top-level document is reported stale, with no retry", response.state === "stale", JSON.stringify(response));
}

console.log(failures === 0 ? "All tests passed!" : `${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
