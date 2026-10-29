// Behavioral checks for the shipped (minified) content script. It applies the
// per-page payload in frames the background page hands back (blank frames):
// selectors as a style element, procedural filters through wbeProcedural, and
// no page-context scripts (scriptlets need the background). It also covers the wBlock lifecycle,
// Init-handoff, and tracking-cleanup behavior that must not change.
//
// Run: node scripts/test_content_scriptlet_injection.mjs [path/to/content.js]
// Defaults to "wBlock Scripts (iOS)/Resources/content.js".

import { readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const bundlePath = process.argv[2]
  ?? path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "content.js");
const source = readFileSync(bundlePath, "utf8");

let failures = 0;
const check = (name, cond) => {
  console.log(`${cond ? "PASS" : "FAIL"}: ${name}`);
  if (!cond) failures += 1;
};
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// --- DOM stubs ---
const appended = [];
const makeEl = tag => ({
  tagName: tag,
  attributes: {},
  textContent: "",
  setAttribute(k, v) { this.attributes[k] = v; },
  appendChild(c) { (this.children ||= []).push(c); return c; },
  removeChild() {},
  remove() {},
  addEventListener() {},
  style: {},
  sheet: null,
  parentNode: null,
});
const documentStub = {
  readyState: "loading",
  documentElement: {
    appendChild(el) {
      appended.push(el);
      // Real script tags execute synchronously on append and remove
      // themselves (the bundle detects success via parentNode === null).
      el.parentNode = null;
      return el;
    },
    removeChild() {},
    addEventListener() {},
  },
  head: null,
  createElement: tag => makeEl(tag),
  createTextNode: text => ({ text }),
  addEventListener() {},
  removeEventListener() {},
  getElementsByTagName: () => [],
  querySelectorAll: () => [],
};

const windowStub = {
  addEventListener() {},
  removeEventListener() {},
  dispatchEvent() { return true; },
};
const saved = {};
const globals = {
  document: documentStub,
  Node: class Node {},
  Element: class Element {},
  HTMLElement: class HTMLElement {},
  MutationObserver: class { observe() {} disconnect() {} },
  getComputedStyle: () => ({}),
  navigator: { userAgent: "test" },
  location: { href: "https://example.com/", hostname: "example.com" },
  Event: class Event { constructor(name) { this.name = name; } },
  CustomEvent: class CustomEvent { constructor(name) { this.name = name; } },
  CSS: { supports: () => false },
  requestAnimationFrame: cb => setTimeout(cb, 0),
};
for (const [k, v] of Object.entries(globals)) {
  saved[k] = Object.getOwnPropertyDescriptor(globalThis, k);
  Object.defineProperty(globalThis, k, { value: v, configurable: true, writable: true });
}

const withGlobals = async (globals, fn) => {
  const saved = {};
  for (const [k, v] of Object.entries(globals)) {
    saved[k] = Object.getOwnPropertyDescriptor(globalThis, k);
    Object.defineProperty(globalThis, k, { value: v, configurable: true, writable: true });
  }
  try {
    return await fn();
  } finally {
    for (const [k, desc] of Object.entries(saved)) {
      if (desc === undefined) delete globalThis[k];
      else Object.defineProperty(globalThis, k, desc);
    }
  }
};
const frameGlobals = document => ({
  document,
  Node: class Node {},
  Element: class Element {},
  HTMLElement: class HTMLElement {},
  MutationObserver: class { observe() {} disconnect() {} },
  getComputedStyle: () => ({}),
  navigator: { userAgent: "test" },
  location: { href: "about:blank", hostname: "" },
  Event: class Event { constructor(name) { this.name = name; } },
  CustomEvent: class CustomEvent { constructor(name) { this.name = name; } },
  CSS: { supports: () => false },
  requestAnimationFrame: cb => setTimeout(cb, 0),
});

// Blank frames: the background page returns the payload and this script applies it.
const runBlankFrameWithPayload = async payload => {
  appended.length = 0;
  const applied = [];
  const win = {
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() { return true; },
    location: { href: "about:blank", hostname: "" },
    wbeProcedural: { apply: filters => applied.push(filters) },
  };
  const browserPayload = {
    runtime: {
      onMessage: { addListener() {} },
      sendMessage(message) {
        if (message && message.type === "InitContentScript") {
          return Promise.resolve({ type: "InitContentScript", disabled: false, paused: false, payload });
        }
        return Promise.resolve({});
      },
    },
  };
  await withGlobals(frameGlobals(documentStub), async () => {
    new Function("browser", "window", "self", source)(browserPayload, win, win);
    await sleep(20);
  });
  return { applied, styles: appended.filter(el => el.tagName === "style"), scripts: appended.filter(el => el.tagName === "script") };
};

{
  const selectorsOnly = await runBlankFrameWithPayload({
    css: ["#blank-probe", "div.ad"],
    procedural: ['{"selector":[{"type":"css","arg":"div"}]}'],
    scriptlets: [["set-constant", "payloadProbe", "1"]],
  });
  check(
    "blank frame hides each selector as its own rule",
    selectorsOnly.styles.length === 1
      && selectorsOnly.styles[0].textContent === "#blank-probe { display: none !important; }\ndiv.ad { display: none !important; }"
  );
  check(
    "blank frame hands procedural filters to wbeProcedural",
    selectorsOnly.applied.length === 1 && selectorsOnly.applied[0][0] === '{"selector":[{"type":"css","arg":"div"}]}'
  );
  check(
    "blank frame adds no page script (scriptlets need the background's injection)",
    selectorsOnly.scripts.length === 0
  );

  const empty = await runBlankFrameWithPayload({ css: [], procedural: [], scriptlets: [] });
  check(
    "empty blank-frame payload injects nothing",
    empty.styles.length === 0 && empty.scripts.length === 0 && empty.applied.length === 0
  );
}

// --- InitContentScript state handoff ---
// Contract: authoritative native state in the Init response removes the
// redundant per-frame disabled-state lookup, while old responses still use the
// compatibility lookup.
try {
  const raceAppended = [];
  const raceMakeEl = tag => ({
    tagName: tag,
    attributes: {},
    textContent: "",
    setAttribute(k, v) { this.attributes[k] = v; },
    appendChild(c) { (this.children ||= []).push(c); return c; },
    removeChild() {},
    remove() {},
    addEventListener() {},
    style: {},
    sheet: null,
    parentNode: null,
  });
  const raceDoc = {
    readyState: "loading",
    documentElement: {
      appendChild(el) {
        raceAppended.push(el);
        el.parentNode = null;
        return el;
      },
      removeChild() {},
      addEventListener() {},
    },
    head: null,
    createElement: tag => raceMakeEl(tag),
    createTextNode: text => ({ text }),
    addEventListener() {},
    removeEventListener() {},
    getElementsByTagName: () => [],
    querySelectorAll: () => [],
  };
  const raceLocation = { href: "https://youtube.com/", hostname: "youtube.com" };
  const raceWindow = {
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() { return true; },
    location: raceLocation,
  };
  const raceGlobals = {
    document: raceDoc,
    Node: class Node {},
    Element: class Element {},
    HTMLElement: class HTMLElement {},
    MutationObserver: class { observe() {} disconnect() {} },
    getComputedStyle: () => ({}),
    navigator: { userAgent: "test" },
    location: raceLocation,
    Event: class Event { constructor(name) { this.name = name; } },
    CustomEvent: class CustomEvent { constructor(name) { this.name = name; } },
    CSS: { supports: () => false },
    requestAnimationFrame: cb => setTimeout(cb, 0),
  };
  const raceSaved = {};
  for (const [k, v] of Object.entries(raceGlobals)) {
    raceSaved[k] = Object.getOwnPropertyDescriptor(globalThis, k);
    Object.defineProperty(globalThis, k, { value: v, configurable: true, writable: true });
  }

  // Recorded sendMessage calls so we can assert the Init request happened.
  const sentMessages = [];
  let fallbackRequested = false;
  const raceBrowser = {
    runtime: {
      onMessage: { addListener() {} },
      sendMessage(msg) {
        sentMessages.push(msg);
        if (msg.action === "wblock:getBlockingState") {
          fallbackRequested = true;
          return Promise.resolve({ disabled: true, paused: false });
        }
        // InitContentScript: return a real payload so scriptlet injection is
        // observable downstream.
        if (msg.type === "InitContentScript") {
          return Promise.resolve({
            disabled: false,
            paused: false,
            payload: {
              css: ["#race-probe"],
              procedural: [],
              scriptlets: [],
            },
          });
        }
        return Promise.resolve({});
      },
    },
  };

  try {
    const run = new Function("browser", "window", "self", source);
    run(raceBrowser, raceWindow, raceWindow);

    // Flush microtasks so the Init response and applyConfiguration settle.
    await new Promise(resolve => setTimeout(resolve, 50));

    const initSent = sentMessages.some(m => m && m.type === "InitContentScript");
    check(
      "InitContentScript sent with authoritative state response",
      initSent,
    );

    const disabledRequested = sentMessages.some(m => m && m.action === "wblock:getSiteDisabledState");
    check(
      "authoritative Init response avoids disabled-state lookup",
      !disabledRequested && !fallbackRequested,
    );

    const raceStyleEls = raceAppended.filter(el => el.tagName === "style");
    check(
      "payload from authoritative Init response is applied",
      raceStyleEls.some(el => (el.textContent || "").includes("#race-probe")),
    );

    const errorMessages = [];
    const errorBrowser = {
      runtime: {
        onMessage: { addListener() {} },
        sendMessage(message) {
          errorMessages.push(message);
          if (message.type === "InitContentScript") {
            return Promise.resolve({ type: "InitContentScript", state: "error", error: "native failed" });
          }
          return Promise.resolve({ ok: true, cleanUrl: "https://youtube.com/?utm_source=test" });
        },
      },
    };
    const errorRun = new Function("browser", "window", "self", source);
    errorRun(errorBrowser, raceWindow, raceWindow);
    await new Promise(resolve => setTimeout(resolve, 20));
    check(
      "native Init error suppresses removeparam cleanup",
      !errorMessages.some(message => message && message.action === "wblock:getCleanURL"),
    );
  } finally {
    for (const [k, desc] of Object.entries(raceSaved)) {
      if (desc === undefined) delete globalThis[k];
      else Object.defineProperty(globalThis, k, desc);
    }
  }
} catch (err) {
  check("timing-race block ran without throwing", false);
  console.error(err);
}

// --- Lifecycle event fidelity ---
// Configuration latency must not install listeners that replace native events.
const runLifecycleScenario = async ({ href, readyState, topLevel = true, title = "", pendingInit = false }) => {
  const documentListeners = [];
  const windowListeners = [];
  const sentMessages = [];
  const url = new URL(href);
  const documentScenario = {
    readyState,
    title,
    documentElement: {
      appendChild() {},
      removeChild() {}
    },
    addEventListener: name => documentListeners.push(name),
    removeEventListener() {},
    createElement: () => ({
      setAttribute() {},
      appendChild() {},
      remove() {},
      parentNode: null,
      style: {}
    }),
    createTextNode: text => ({ text }),
    querySelector: () => null,
    querySelectorAll: () => [],
    getElementsByTagName: () => [],
    head: null
  };
  const windowScenario = {
    location: { href, hostname: url.hostname, pathname: url.pathname },
    frameElement: topLevel ? null : {},
    addEventListener: name => windowListeners.push(name),
    removeEventListener() {},
    dispatchEvent: () => true
  };
  windowScenario.top = topLevel ? windowScenario : {};
  const saved = {};
  const globals = {
    document: documentScenario,
    window: windowScenario,
    location: windowScenario.location,
    Node: class Node {},
    Element: class Element {},
    HTMLElement: class HTMLElement {},
    MutationObserver: class { observe() {} disconnect() {} },
    getComputedStyle: () => ({}),
    navigator: { userAgent: "test" },
    Event: class Event { constructor(name) { this.name = name; } },
    CustomEvent: class CustomEvent { constructor(name) { this.name = name; } },
    CSS: { supports: () => false },
    requestAnimationFrame: cb => setTimeout(cb, 0)
  };
  for (const [key, value] of Object.entries(globals)) {
    saved[key] = Object.getOwnPropertyDescriptor(globalThis, key);
    Object.defineProperty(globalThis, key, { value, configurable: true, writable: true });
  }
  try {
    const browserScenario = {
      runtime: {
        sendMessage(message) {
          sentMessages.push(message);
          if (pendingInit && message && message.type === "InitContentScript") {
            return new Promise(() => {});
          }
          return Promise.resolve({});
        },
        onMessage: { addListener() {} }
      }
    };
    const run = new Function("browser", "window", "self", source);
    run(browserScenario, windowScenario, windowScenario);
    await sleep(10);
    return { documentListeners, windowListeners, sentMessages };
  } finally {
    for (const [key, descriptor] of Object.entries(saved)) {
      if (descriptor === undefined) delete globalThis[key];
      else Object.defineProperty(globalThis, key, descriptor);
    }
  }
};

try {
  const loading = await runLifecycleScenario({ href: "https://example.com/", readyState: "loading", pendingInit: true });
  check("top-level HTTP(S) documents preserve native lifecycle events", loading.documentListeners.length === 0 && loading.windowListeners.length === 0);

  const subframe = await runLifecycleScenario({ href: "https://example.com/frame", readyState: "loading", topLevel: false, pendingInit: true });
  check("HTTP(S) subframes preserve native lifecycle events", subframe.documentListeners.length === 0 && subframe.windowListeners.length === 0);

  const blankTop = await runLifecycleScenario({ href: "about:blank", readyState: "loading" });
  check("top-level blank documents preserve native lifecycle events", blankTop.documentListeners.length === 0 && blankTop.windowListeners.length === 0);

  const blankFrame = await runLifecycleScenario({ href: "about:blank", readyState: "loading", topLevel: false, pendingInit: true });
  check("blank frames preserve native lifecycle events", blankFrame.documentListeners.length === 0 && blankFrame.windowListeners.length === 0);

  const dataFrame = await runLifecycleScenario({ href: "data:text/html,frame", readyState: "loading", topLevel: false });
  check("data frames preserve native lifecycle events", dataFrame.documentListeners.length === 0 && dataFrame.windowListeners.length === 0);

  const interactive = await runLifecycleScenario({ href: "https://example.com/interactive", readyState: "interactive" });
  check("interactive HTTP(S) documents do not add lifecycle listeners", interactive.documentListeners.length === 0 && interactive.windowListeners.length === 0);

  const complete = await runLifecycleScenario({ href: "https://example.com/complete", readyState: "complete" });
  check("complete documents do not add lifecycle listeners", complete.documentListeners.length === 0 && complete.windowListeners.length === 0);

  const cloudflareFrame = await runLifecycleScenario({ href: "https://challenges.cloudflare.com/turnstile", readyState: "loading", topLevel: false });
  check("Cloudflare frames still skip initialization", !cloudflareFrame.sentMessages.some(message => message && message.type === "InitContentScript"));
} catch (error) {
  check("lifecycle interception scope checks ran without throwing", false);
  console.error(error);
}

// --- Tracking URL cleanup non-reload verification ---
// Removing tracking parameters in-place must use history.replaceState and must
// never invoke location.replace / location.reload to avoid infinite reload loops.
const runTrackingCleanupScenario = async ({ href, cleanUrlResponse, runtimeError = false }) => {
  let replaceStateCalls = [];
  let locationReplaceCalls = [];
  let locationReloadCalls = [];
  const url = new URL(href);
  const locationScenario = {
    href,
    hostname: url.hostname,
    pathname: url.pathname,
    search: url.search,
    replace: target => { locationReplaceCalls.push(target); },
    reload: () => { locationReloadCalls.push(true); }
  };
  const historyScenario = {
    state: { key: "initial" },
    replaceState: (state, title, url) => {
      replaceStateCalls.push({ state, title, url });
    }
  };
  const documentScenario = {
    readyState: "loading",
    title: "Example Page",
    documentElement: {
      appendChild() {},
      removeChild() {}
    },
    addEventListener() {},
    removeEventListener() {},
    createElement: () => ({
      setAttribute() {},
      appendChild() {},
      remove() {},
      parentNode: null,
      style: {}
    }),
    createTextNode: text => ({ text }),
    querySelector: () => null,
    querySelectorAll: () => [],
    getElementsByTagName: () => [],
    head: null
  };
  const windowScenario = {
    location: locationScenario,
    history: historyScenario,
    frameElement: null,
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent: () => true
  };
  windowScenario.top = windowScenario;

  const saved = {};
  const globals = {
    document: documentScenario,
    window: windowScenario,
    location: locationScenario,
    history: historyScenario,
    Node: class Node {},
    Element: class Element {},
    HTMLElement: class HTMLElement {},
    MutationObserver: class { observe() {} disconnect() {} },
    getComputedStyle: () => ({}),
    navigator: { userAgent: "test" },
    Event: class Event { constructor(name) { this.name = name; } },
    CustomEvent: class CustomEvent { constructor(name) { this.name = name; } },
    CSS: { supports: () => false },
    requestAnimationFrame: cb => setTimeout(cb, 0)
  };
  for (const [key, value] of Object.entries(globals)) {
    saved[key] = Object.getOwnPropertyDescriptor(globalThis, key);
    Object.defineProperty(globalThis, key, { value, configurable: true, writable: true });
  }

  try {
    const browserScenario = {
      runtime: {
        sendMessage(message) {
          if (message && message.type === "InitContentScript") {
            return Promise.resolve({ type: "InitContentScript", disabled: false, paused: false, payload: { css: [], procedural: [], scriptlets: [] } });
          }
          if (message && message.action === "wblock:getCleanURL") {
            if (runtimeError) {
              return Promise.reject(new Error("runtime disconnected"));
            }
            return Promise.resolve({ ok: true, cleanUrl: cleanUrlResponse });
          }
          return Promise.resolve({});
        },
        onMessage: { addListener() {} }
      }
    };
    const run = new Function("browser", "window", "self", source);
    run(browserScenario, windowScenario, windowScenario);
    await sleep(20);
    return { replaceStateCalls, locationReplaceCalls, locationReloadCalls };
  } finally {
    for (const [key, descriptor] of Object.entries(saved)) {
      if (descriptor === undefined) delete globalThis[key];
      else Object.defineProperty(globalThis, key, descriptor);
    }
  }
};

try {
  const cleanUrlResult = await runTrackingCleanupScenario({
    href: "https://example.com/page?utm_source=newsletter&utm_medium=email",
    cleanUrlResponse: "https://example.com/page"
  });
  check(
    "URL tracking cleanup uses history.replaceState",
    cleanUrlResult.replaceStateCalls.length === 1 && cleanUrlResult.replaceStateCalls[0].url === "https://example.com/page"
  );
  check(
    "URL tracking cleanup never triggers location.replace or reload",
    cleanUrlResult.locationReplaceCalls.length === 0 && cleanUrlResult.locationReloadCalls.length === 0
  );

  const unchangedResult = await runTrackingCleanupScenario({
    href: "https://example.com/landing?utm_source=keep&x=1",
    cleanUrlResponse: "https://example.com/landing?utm_source=keep&x=1"
  });
  check("unchanged filter result preserves tracking parameters", unchangedResult.replaceStateCalls.length === 0);

  const fallbackResult = await runTrackingCleanupScenario({
    href: "https://example.com/landing?fbclid=IwAR123456&gclid=789",
    runtimeError: true
  });
  check(
    "URL tracking cleanup fails closed when rules are unavailable",
    fallbackResult.replaceStateCalls.length === 0
  );
  check(
    "URL tracking fallback cleanup never triggers location.replace or reload",
    fallbackResult.locationReplaceCalls.length === 0 && fallbackResult.locationReloadCalls.length === 0
  );
} catch (error) {
  check("tracking cleanup non-reload checks ran without throwing", false);
  console.error(error);
}

if (failures > 0) {
  console.error(`\n${failures} content scriptlet injection check(s) failed`);
  process.exit(1);
}
console.log("\nAll content scriptlet injection checks passed");
process.exit(0);
