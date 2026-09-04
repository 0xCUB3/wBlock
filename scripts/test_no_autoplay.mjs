// Behavioral test for the No Autoplay content script
// ("wBlock Scripts (iOS)/Resources/no-autoplay.js").
//
// Runs the shipped script in a vm sandbox with stubbed DOM and WebExtension
// APIs and verifies the controller/gate contract:
// - the warm hint arms the gate synchronously at document_start;
// - extension storage is authoritative and corrects the hint both ways;
// - locked media rejects play() with NotAllowedError and loses autoplay;
// - user gestures (direct or via a single-media player) unlock media;
// - per-site allow, the native disabled-sites state, live storage changes,
//   and a foreground return after a native-only change stand the gate down
//   (and re-arm it) without a reload;
// - a CSP that blocks inline scripts falls back to the isolated world where
//   DOM-level enforcement (autoplay stripping, pause-on-play) still works.
//
// Run: node scripts/test_no_autoplay.mjs [path/to/no-autoplay.js]

import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const scriptPath = process.argv[2]
  ?? path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "no-autoplay.js");
const source = readFileSync(scriptPath, "utf8");

const ENABLED_KEY = "wblock.noAutoplay.enabled.v1";
const ALLOW_PREFIX = "wblock.noAutoplayAllow.v1:";
const NATIVE_MIGRATED_KEY = "wblock.noAutoplay.nativeMigrated.v1";
const HINT_KEY = "__wblock_no_autoplay_arm_v1";
const HOST = "example.com";

let failures = 0;
const check = (name, cond) => {
  console.log(`${cond ? "PASS" : "FAIL"}: ${name}`);
  if (!cond) failures += 1;
};
const settle = () => new Promise((resolve) => setTimeout(resolve, 25));

function createEnvironment(options = {}) {
  const env = {
    inlineExecutions: 0,
    runtimeMessages: [],
    observers: [],
    storageListeners: [],
    documentListeners: new Map(),
    mediaInDom: [],
    localStore: new Map(),
    nativeCalls: [],
    storageWrites: [],
  };

  if (options.hint) env.localStore.set(HINT_KEY, "1");
  const storageData = options.storage || {};

  function attrsMixin(target) {
    const attrs = new Map();
    target.getAttribute = (k) => (attrs.has(k) ? attrs.get(k) : null);
    target.setAttribute = (k, v) => { attrs.set(k, String(v)); };
    target.removeAttribute = (k) => { attrs.delete(k); };
    target.hasAttribute = (k) => attrs.has(k);
    return target;
  }

  function HTMLMediaElement() {}
  HTMLMediaElement.prototype.play = function () {
    this.playedNatively = true;
    this.paused = false;
    return Promise.resolve();
  };
  Object.defineProperty(HTMLMediaElement.prototype, "autoplay", {
    configurable: true,
    enumerable: true,
    get() { return this._autoplay === true; },
    set(value) {
      this._autoplay = value === true;
      if (this._autoplay) this.setAttribute("autoplay", "");
      else this.removeAttribute("autoplay");
    },
  });

  env.makeMedia = (localName = "video") => {
    const media = Object.create(HTMLMediaElement.prototype);
    attrsMixin(media);
    media.localName = localName;
    media.paused = true;
    media.pauseCalls = 0;
    media.playedNatively = false;
    media.pause = () => { media.pauseCalls += 1; media.paused = true; };
    media.querySelectorAll = () => [];
    media.addEventListener = () => {};
    return media;
  };

  const documentElement = attrsMixin({
    querySelectorAll: (selector) => (selector === "video, audio" ? env.mediaInDom : []),
    appendChild(el) {
      if (typeof el.textContent === "string" && el.textContent.length > 0 && !options.cspBlocksInline) {
        env.inlineExecutions += 1;
        vm.runInContext(el.textContent, context);
      }
      return el;
    },
  });

  const bodyElement = attrsMixin({
    localName: "body",
    querySelectorAll: (selector) => (selector === "video, audio" ? env.mediaInDom : []),
    parentElement: documentElement,
  });

  const documentStub = {
    documentElement: options.deferRoot ? null : documentElement,
    body: bodyElement,
    head: null,
    addEventListener(type, fn) {
      if (!env.documentListeners.has(type)) env.documentListeners.set(type, []);
      env.documentListeners.get(type).push(fn);
    },
    removeEventListener() {},
    dispatchEvent(event) {
      for (const fn of env.documentListeners.get(event.type) || []) fn(event);
      return true;
    },
    createElement(tag) {
      const el = attrsMixin({ tagName: String(tag).toUpperCase(), textContent: "", remove() {} });
      return el;
    },
    querySelector: () => null,
    querySelectorAll: () => [],
    visibilityState: options.visibilityState ?? "visible",
  };

  env.dispatch = (type, event) => {
    event.type = type;
    documentStub.dispatchEvent(event);
  };
  env.body = bodyElement;
  env.setVisibility = (state) => { documentStub.visibilityState = state; };

  function MutationObserver(callback) {
    this.callback = callback;
    this.roots = [];
    env.observers.push(this);
  }
  MutationObserver.prototype.observe = function (root) { this.roots.push(root); };
  MutationObserver.prototype.disconnect = function () {};
  env.triggerMutations = (mutations) => {
    for (const observer of env.observers) observer.callback(mutations);
  };

  class DOMExceptionStub extends Error {
    constructor(message, name) {
      super(message);
      this.name = name || "Error";
    }
  }

  class EventStub {
    constructor(type) { this.type = type; }
  }

  function DocumentStubCtor() {}
  DocumentStubCtor.prototype.createElement = documentStub.createElement;
  function ElementStubCtor() {}

  const sandbox = {
    console,
    setTimeout,
    clearTimeout,
    HTMLMediaElement,
    Document: DocumentStubCtor,
    Element: ElementStubCtor,
    MutationObserver,
    DOMException: DOMExceptionStub,
    Event: EventStub,
    document: documentStub,
    location: { hostname: options.hostname ?? HOST },
    localStorage: {
      getItem: (k) => (env.localStore.has(k) ? env.localStore.get(k) : null),
      setItem: (k, v) => { env.localStore.set(k, String(v)); },
      removeItem: (k) => { env.localStore.delete(k); },
    },
    crypto: {
      getRandomValues(arr) {
        for (let i = 0; i < arr.length; i += 1) arr[i] = (i * 37 + 11) % 256;
        return arr;
      },
    },
    browser: {
      runtime: {
        sendMessage(message) {
          env.runtimeMessages.push(message);
          return Promise.resolve({ ok: true });
        },
        sendNativeMessage(_id, message) {
          env.nativeCalls.push(message);
          if (message && message.action === "getSiteDisabledState") {
            if (options.siteDisabledUnknown === true) {
              return Promise.reject(new Error("native unavailable"));
            }
            if (options.siteDisabledMalformed === true) {
              return Promise.resolve({});
            }
            return Promise.resolve({ disabled: options.nativeDisabled === true });
          }
          if (message && message.action === "getNoAutoplayState"
              && options.nativeNoAutoplayState !== undefined) {
            return Promise.resolve(options.nativeNoAutoplayState);
          }
          return Promise.resolve({});
        },
      },
      storage: {
        local: {
          get: async (keys) => {
            const out = {};
            for (const key of Array.isArray(keys) ? keys : [keys]) {
              if (key in storageData) out[key] = storageData[key];
            }
            return out;
          },
          set: async (patch) => {
            env.storageWrites.push(patch || {});
            for (const [key, value] of Object.entries(patch || {})) {
              storageData[key] = value;
            }
          },
          remove: async (keys) => {
            for (const key of Array.isArray(keys) ? keys : [keys]) {
              delete storageData[key];
            }
          },
        },
        onChanged: {
          addListener: (fn) => { env.storageListeners.push(fn); },
        },
      },
    },
  };
  sandbox.window = sandbox;
  const context = vm.createContext(sandbox);
  env.sandbox = sandbox;
  env.storage = storageData;
  env.run = () => vm.runInContext(source, context);
  env.gateMarker = () => documentElement.getAttribute("data-wblock-no-autoplay-gate") === "1";
  env.notifyStorageChange = (changes) => {
    for (const fn of env.storageListeners) fn(changes, "local");
  };
  env.attachRoot = () => {
    documentStub.documentElement = documentElement;
    env.triggerMutations([{ type: "childList", addedNodes: [] }]);
  };
  return env;
}

async function playResult(media) {
  try {
    await media.play();
    return "ok";
  } catch (error) {
    return error && error.name ? error.name : "error";
  }
}

// --- 1. Warm hint arms the gate synchronously at document_start ---
{
  const env = createEnvironment({ hint: true, storage: { [ENABLED_KEY]: true } });
  env.run();
  check("warm hint injects the page gate synchronously (before any await)", env.gateMarker());
  check("page-world injection used the inline script path", env.inlineExecutions === 1);

  const video = env.makeMedia("video");
  const blocked = await playResult(video);
  check("locked media rejects play() with NotAllowedError", blocked === "NotAllowedError");
  check("blocked media is marked and stays paused", video.getAttribute("data-wblock-no-autoplay") === "1" && video.paused);

  video.autoplay = true;
  check("autoplay setter is ignored while locked", video.autoplay === false && !video.hasAttribute("autoplay"));

  env.dispatch("click", { target: video, composedPath: () => [video] });
  check("a direct click unlocks that media", video.getAttribute("data-wblock-no-autoplay-unlocked") === "1");
  check("unlocked media plays natively", (await playResult(video)) === "ok" && video.playedNatively);

  const other = env.makeMedia("video");
  check("unlocking one media does not unlock others", (await playResult(other)) === "NotAllowedError");

  await settle();
  check("authoritative check keeps the hint set while enabled", env.localStore.get(HINT_KEY) === "1");
}

// --- 2. A play button beside a single video unlocks that player ---
{
  const env = createEnvironment({ hint: true, storage: { [ENABLED_KEY]: true } });
  env.run();
  const video = env.makeMedia("video");
  const player = { querySelectorAll: (sel) => (sel === "video, audio" ? [video] : []) };
  const button = { querySelectorAll: () => [], parentElement: player };
  env.dispatch("click", { target: button, composedPath: () => [button, player] });
  check("sibling play button unlocks the only video in the player", (await playResult(video)) === "ok");

  const keyedVideo = env.makeMedia("video");
  env.dispatch("keydown", { key: "k", target: keyedVideo, composedPath: () => [keyedVideo] });
  check("playback key unlocks the focused media", (await playResult(keyedVideo)) === "ok");
  const arrowVideo = env.makeMedia("video");
  env.dispatch("keydown", { key: "ArrowDown", target: arrowVideo, composedPath: () => [arrowVideo] });
  check("non-playback key does not unlock media", (await playResult(arrowVideo)) === "NotAllowedError");
}

// --- 2b. Page-level gestures never unlock a page's only video ---
{
  const env = createEnvironment({ hint: true, storage: { [ENABLED_KEY]: true } });
  env.run();
  const only = env.makeMedia("video");
  only.parentElement = env.body;
  env.mediaInDom.push(only);

  env.dispatch("click", { target: env.body, composedPath: () => [env.body] });
  check("a click on the body does not unlock the page's only video",
    (await playResult(only)) === "NotAllowedError");

  env.dispatch("keydown", { key: " ", target: env.body, composedPath: () => [env.body] });
  check("pressing space on the page does not unlock the only video",
    (await playResult(only)) === "NotAllowedError");

  const unrelated = { localName: "div", querySelectorAll: () => [], parentElement: env.body };
  env.dispatch("pointerdown", { target: unrelated, composedPath: () => [unrelated, env.body] });
  check("a gesture in unrelated UI walks up but stops before the body",
    (await playResult(only)) === "NotAllowedError");

  env.dispatch("click", { target: only, composedPath: () => [only, env.body] });
  check("a direct gesture on the only video still unlocks it",
    (await playResult(only)) === "ok");
}

// --- 3. Boot scan and mutation observer disarm autoplaying media ---
{
  const env = createEnvironment({ hint: true, storage: { [ENABLED_KEY]: true } });
  const preexisting = env.makeMedia("video");
  preexisting._autoplay = true;
  preexisting.setAttribute("autoplay", "");
  preexisting.paused = false;
  env.mediaInDom.push(preexisting);
  env.run();
  check("boot scan pauses and disarms media that was already autoplaying",
    preexisting.pauseCalls > 0 && preexisting.paused && !preexisting.hasAttribute("autoplay"));

  const late = env.makeMedia("audio");
  late._autoplay = true;
  late.setAttribute("autoplay", "");
  late.paused = false;
  env.triggerMutations([{ type: "childList", addedNodes: [late] }]);
  check("mutation observer disarms media added later",
    late.pauseCalls > 0 && !late.hasAttribute("autoplay") && late.getAttribute("data-wblock-no-autoplay") === "1");

  const rearmed = env.makeMedia("video");
  rearmed.setAttribute("autoplay", "");
  env.triggerMutations([{ type: "attributes", addedNodes: [], target: rearmed }]);
  check("mutation observer strips a re-added autoplay attribute", !rearmed.hasAttribute("autoplay"));

  check("pause-on-play event catches media that slipped through", (() => {
    const slipped = env.makeMedia("video");
    slipped.paused = false;
    env.dispatch("play", { target: slipped });
    return slipped.pauseCalls > 0 && slipped.paused;
  })());
}

// --- 4. Authoritative state corrects a stale hint (per-site allow) ---
{
  const env = createEnvironment({
    hint: true,
    storage: { [ENABLED_KEY]: true, [ALLOW_PREFIX + HOST]: true },
  });
  env.run();
  check("stale hint still arms synchronously", env.gateMarker());
  await settle();
  check("per-site allow clears the hint", !env.localStore.has(HINT_KEY));
  const video = env.makeMedia("video");
  check("per-site allow stands the gate down (play passes through)", (await playResult(video)) === "ok");
  video.autoplay = true;
  check("per-site allow restores the autoplay setter", video.autoplay === true && video.hasAttribute("autoplay"));
}

// --- 5. Global toggle off: nothing arms ---
{
  const env = createEnvironment({ storage: {} });
  env.run();
  await settle();
  check("disabled feature never injects the gate", !env.gateMarker() && env.inlineExecutions === 0);
  check("disabled feature leaves no hint behind", !env.localStore.has(HINT_KEY));
  const video = env.makeMedia("video");
  check("disabled feature leaves play() untouched", (await playResult(video)) === "ok");
}

// --- 6. First visit with the feature enabled arms after the async check ---
{
  const env = createEnvironment({ storage: { [ENABLED_KEY]: true } });
  env.run();
  check("no hint means no synchronous arming", !env.gateMarker());
  await settle();
  check("authoritative check arms the gate on first visit", env.gateMarker());
  check("authoritative check records the hint for the next visit", env.localStore.get(HINT_KEY) === "1");
  check("native disabled-sites state was consulted",
    env.nativeCalls.some((m) => m && m.action === "getSiteDisabledState" && m.host === HOST));
}

// --- 7. Unmigrated legacy state wins over native protobuf defaults ---
{
  const env = createEnvironment({
    storage: { [ENABLED_KEY]: true },
    nativeNoAutoplayState: { enabled: false, siteAllowed: false },
  });
  env.run();
  await settle();
  check("unmigrated legacy enabled state stays armed despite native defaults", env.gateMarker());
  check("native default read does not write the legacy enabled key",
    !env.storageWrites.some((patch) => Object.hasOwn(patch, ENABLED_KEY)));
}

// --- 8. Native Site Settings allow is honored before legacy migration ---
{
  const env = createEnvironment({
    storage: { [ENABLED_KEY]: true },
    nativeNoAutoplayState: { enabled: false, siteAllowed: true },
  });
  env.run();
  await settle();
  check("unmigrated native site allow stands the gate down despite legacy enabled", !env.gateMarker());
}

// --- 9. Native state wins after legacy migration completes ---
{
  const env = createEnvironment({
    storage: { [ENABLED_KEY]: true, [NATIVE_MIGRATED_KEY]: true },
    nativeNoAutoplayState: { enabled: false, siteAllowed: false },
  });
  env.run();
  await settle();
  check("migrated native defaults stand the gate down", !env.gateMarker());
}

// --- 9. wBlock disabled on this site: gate stands down ---
{
  const env = createEnvironment({ hint: true, storage: { [ENABLED_KEY]: true }, nativeDisabled: true });
  env.run();
  await settle();
  check("site-disabled state clears the hint", !env.localStore.has(HINT_KEY));
  const video = env.makeMedia("video");
  check("site-disabled state stands the gate down", (await playResult(video)) === "ok");
}

// --- 9. Live storage changes disarm and re-arm without a reload ---
{
  const env = createEnvironment({ hint: true, storage: { [ENABLED_KEY]: true } });
  env.run();
  await settle();
  const video = env.makeMedia("video");
  check("gate is armed before the live change", (await playResult(video)) === "NotAllowedError");

  env.storage[ENABLED_KEY] = false;
  env.notifyStorageChange({ [ENABLED_KEY]: { newValue: false } });
  await settle();
  check("turning the global toggle off disarms live", (await playResult(video)) === "ok");
  check("live disarm clears the hint", !env.localStore.has(HINT_KEY));

  env.storage[ENABLED_KEY] = true;
  env.notifyStorageChange({ [ENABLED_KEY]: { newValue: true } });
  await settle();
  const fresh = env.makeMedia("video");
  check("turning the global toggle back on re-arms live", (await playResult(fresh)) === "NotAllowedError");
  check("re-arming does not inject a second gate", env.inlineExecutions === 1);
}

// --- 10. A native-only site allow is refreshed when Safari becomes visible ---
{
  const nativeState = { enabled: true, siteAllowed: false };
  const env = createEnvironment({
    hint: true,
    storage: { [NATIVE_MIGRATED_KEY]: true },
    nativeNoAutoplayState: nativeState,
  });
  env.run();
  await settle();
  const video = env.makeMedia("video");
  check("gate is armed before the native-only change", (await playResult(video)) === "NotAllowedError");

  nativeState.siteAllowed = true;
  env.setVisibility("visible");
  env.dispatch("visibilitychange", {});
  await settle();
  check("visible return refreshes native site allow and stands the gate down",
    (await playResult(video)) === "ok");
}

// --- 11. CSP fallback: gate runs in the isolated world ---
{
  const env = createEnvironment({ hint: true, storage: { [ENABLED_KEY]: true }, cspBlocksInline: true });
  env.run();
  check("CSP fallback does not execute inline scripts", env.inlineExecutions === 0);
  check("CSP fallback still activates the gate", env.gateMarker());
  const gateRequests = env.runtimeMessages.filter(m => m && m.action === "wblock:noAutoplay:injectGate");
  check("CSP fallback asks the background for a page-world gate (#676)",
    gateRequests.length === 1 && typeof gateRequests[0].source === "string"
      && gateRequests[0].source.includes("__wblockNoAutoplayGateActive") && typeof gateRequests[0].token === "string");

  const video = env.makeMedia("video");
  video.paused = false;
  env.dispatch("play", { target: video });
  check("CSP fallback pauses locked media on play events", video.pauseCalls > 0 && video.paused);

  const late = env.makeMedia("video");
  late._autoplay = true;
  late.setAttribute("autoplay", "");
  env.triggerMutations([{ type: "childList", addedNodes: [late] }]);
  check("CSP fallback strips autoplay from added media", !late.hasAttribute("autoplay"));

  env.dispatch("click", { target: video, composedPath: () => [video] });
  check("CSP fallback records unlocks in the shared DOM",
    video.getAttribute("data-wblock-no-autoplay-unlocked") === "1");
}

// --- 11. document_start before the document element exists ---
{
  const env = createEnvironment({ hint: true, storage: { [ENABLED_KEY]: true }, deferRoot: true });
  env.run();
  check("arming defers while the document element is missing", !env.gateMarker() && env.inlineExecutions === 0);
  env.attachRoot();
  check("gate arms as soon as the document element appears", env.gateMarker() && env.inlineExecutions === 1);
  const video = env.makeMedia("video");
  check("deferred gate still blocks play()", (await playResult(video)) === "NotAllowedError");
}

// --- 12. Deferred arm is cancelled if the authoritative check says off ---
{
  const env = createEnvironment({ hint: true, storage: {}, deferRoot: true });
  env.run();
  await settle();
  env.attachRoot();
  check("deferred arm is cancelled when the feature turns out to be off",
    !env.gateMarker() && env.inlineExecutions === 0);
  check("cancelled deferred arm clears the hint", !env.localStore.has(HINT_KEY));
}

// --- 13. Frames without a hostname never arm ---
{
  const env = createEnvironment({ hint: true, storage: { [ENABLED_KEY]: true }, hostname: "" });
  env.run();
  await settle();
  check("hostname-less frames stand down after the authoritative check", !env.localStore.has(HINT_KEY));
}

// --- 14. Unknown site-disabled state: stand down (fail closed) ---
{
  const env = createEnvironment({
    hint: true,
    storage: { [ENABLED_KEY]: true },
    siteDisabledUnknown: true,
  });
  env.run();
  check("stale hint still arms before the site-disabled check settles", env.gateMarker());
  await settle();
  check("unknown site-disabled state clears the hint", !env.localStore.has(HINT_KEY));
  const video = env.makeMedia("video");
  check("unknown site-disabled state stands the gate down", (await playResult(video)) === "ok");
}

{
  const env = createEnvironment({
    hint: true,
    storage: { [ENABLED_KEY]: true },
    siteDisabledMalformed: true,
  });
  env.run();
  await settle();
  check("malformed site-disabled response stands down", (await playResult(env.makeMedia("video"))) === "ok");
  check("malformed site-disabled response clears the hint", !env.localStore.has(HINT_KEY));
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nAll No Autoplay checks passed");
