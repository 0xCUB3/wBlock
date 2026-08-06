// Behavioral check for the shipped (minified) content script: it must expose
// window.adguard.contentScript and assemble runnable scriptlet / raw-JS-rule
// code for the blank-frame fallback path (scriptlets.invoke -> IIFE wrapping
// of fn.toString()). Guards the esbuild minification step in
// scripts/minify-extension-js.sh.
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
const contentSource = readFileSync(path.join(repoRoot, "extension-src", "content.js"), "utf8");
const backgroundSource = readFileSync(path.join(repoRoot, "extension-src", "background.js"), "utf8");
const backgroundBundle = readFileSync(path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "background.js"), "utf8");

let failures = 0;
const check = (name, cond) => {
  console.log(`${cond ? "PASS" : "FAIL"}: ${name}`);
  if (!cond) failures += 1;
};
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

check("content source keeps Extended CSS", contentSource.includes("class ExtendedCss"));
check("content source keeps ContentScript", contentSource.includes("class ContentScript"));
check("content source omits generated scriptlet registry", !contentSource.includes("scriptletsMap") && !contentSource.includes("getScriptletFunction") && !contentSource.includes("scriptlets.invoke"));
check("shipped content omits generated scriptlet registry", !source.includes("scriptletsMap") && !source.includes("getScriptletFunction"));
check("background source retains generated scriptlet registry", backgroundSource.includes("var scriptletsMap = {") && backgroundSource.includes("getScriptletFunction") && backgroundSource.includes("var scriptlets = {"));
check("background source compiles fallback scriptlets", backgroundSource.includes("compileScriptletsForContent") && backgroundSource.includes("code: scriptlets.invoke(source)"));
check("shipped background retains scriptlet compiler", backgroundBundle.includes("getScriptletFunction") && backgroundBundle.includes("invoke"));
check("shipped content size stays below regression ceiling", statSync(bundlePath).size < 100 * 1024);

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

const browserStub = {
  runtime: {
    sendMessage: async () => ({}),
    onMessage: { addListener() {} },
  },
};

try {
  const run = new Function("browser", "window", "self", source);
  run(browserStub, windowStub, windowStub);

  check("window.adguard.contentScript exposed", !!(windowStub.adguard && windowStub.adguard.contentScript));

  const cs = windowStub.adguard.contentScript;
  appended.length = 0;
  cs.runScriptlets([{
    name: "set-constant",
    args: ["wblockSmokeTest", "1"],
    code: '(function(source,args){ window.__wblockSmokeTest = source.name; })( {"name":"set-constant"}, []);'
  }], false);

  const scriptEls = appended.filter(el => el.tagName === "script");
  check("scriptlet injection appended a script element", scriptEls.length === 1);

  const code = scriptEls[0] ? scriptEls[0].textContent : "";
  check("assembled code carries precompiled source", code.includes("__wblockSmokeTest"));
  check("assembled code is an IIFE invocation", code.trim().startsWith("("));

  let parses = true;
  try { new Function(code); } catch { parses = false; }
  check("assembled scriptlet code parses", parses);

  appended.length = 0;
  cs.runScriptlets([
    { name: "bad", code: "throw new Error('first scriptlet failed');" },
    { name: "good", code: "window.__wblockSecondScriptlet = true;" }
  ]);
  check("fallback keeps per-scriptlet injection isolation", appended.filter(el => el.tagName === "script").length === 2);

  // Raw #%# JS rule path used by the blank-frame fallback.
  appended.length = 0;
  cs.runScripts(["window.__wblockRawRule = 42;"]);
  const rawEls = appended.filter(el => el.tagName === "script");
  check("raw js rule injection appended a script element", rawEls.length === 1);
  check("raw js rule code preserved", (rawEls[0]?.textContent || "").includes("__wblockRawRule"));
} finally {
  for (const [k, desc] of Object.entries(saved)) {
    if (desc === undefined) delete globalThis[k];
    else Object.defineProperty(globalThis, k, desc);
  }
}

// --- Bundle source: shipped dispatcher uses the 3000ms timeout ---
// Guards against the timeout value silently regressing (it caps how long
// YouTube scriptlets wait before DOMContentLoaded is force-flushed).
const dispatcherUsesThreeSeconds =
  /setupDelayedEventDispatcher\(3000\)/.test(source) || /\b\w+\(3e3\);let\b/.test(source);
check(
  "shipped bundle uses a 3000ms dispatcher timeout",
  dispatcherUsesThreeSeconds,
);

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
        // InitContentScript: return a real configuration payload so scriptlet
        // machinery is observable downstream.
        if (msg.type === "InitContentScript") {
          return Promise.resolve({
            disabled: false,
            paused: false,
            payload: {
              css: [],
              extendedCss: [],
              scriptlets: [{
                name: "set-constant",
                args: ["__wblockRaceProbe", "1"],
                code: '(function(source,args){ window.__wblockRaceProbe = source.name; })( {"name":"set-constant"}, []);'
              }],
              js: [],
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

    check(
      "contentScript exposed after authoritative state handoff",
      !!(raceWindow.adguard && raceWindow.adguard.contentScript),
    );

    const raceScriptEls = raceAppended.filter(el => el.tagName === "script");
    check(
      "scriptlet from authoritative Init response is applied",
      raceScriptEls.length >= 1 && raceScriptEls.some(el => (el.textContent || "").includes("__wblockRaceProbe")),
    );

    const compatibilityMessages = [];
    const compatibilityBrowser = {
      runtime: {
        onMessage: { addListener() {} },
        sendMessage(message) {
          compatibilityMessages.push(message);
          if (message.action === "wblock:getBlockingState") {
            return Promise.resolve({ disabled: true, paused: false });
          }
          if (message.type === "InitContentScript") {
            return Promise.resolve({ payload: { css: [], extendedCss: [], scriptlets: [], js: [] } });
          }
          return Promise.resolve({});
        },
      },
    };
    const compatibilityRun = new Function("browser", "window", "self", source);
    compatibilityRun(compatibilityBrowser, raceWindow, raceWindow);
    await new Promise(resolve => setTimeout(resolve, 20));
    const compatibilityStateMessages = compatibilityMessages.filter(message => message && message.action === "wblock:getBlockingState");
    check(
      "legacy Init response uses one combined compatibility lookup",
      compatibilityStateMessages.length === 1 && compatibilityStateMessages[0].host === "youtube.com",
    );
    check(
      "legacy Init response does not route an unrouted pause action",
      !compatibilityMessages.some(message => message && (
        message.action === "wblock:getSiteDisabledState" || message.action === "getBlockingPausedState"
      )),
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

// --- Lifecycle interception timing ---
// Frame-level document-start scriptlets depend on lifecycle interception, while
// events that already fired must not get stale listeners.
const runLifecycleScenario = async ({ href, readyState, topLevel = true, title = "" }) => {
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
  const loading = await runLifecycleScenario({ href: "https://example.com/", readyState: "loading" });
  check("top-level HTTP(S) document intercepts both lifecycle events", loading.documentListeners.includes("DOMContentLoaded") && loading.windowListeners.includes("load"));

  const subframe = await runLifecycleScenario({ href: "https://example.com/frame", readyState: "loading", topLevel: false });
  check("loading subframes intercept both lifecycle events", subframe.documentListeners.includes("DOMContentLoaded") && subframe.windowListeners.includes("load"));

  const blankFrame = await runLifecycleScenario({ href: "about:blank", readyState: "loading", topLevel: false });
  check("loading blank frames intercept both lifecycle events", blankFrame.documentListeners.includes("DOMContentLoaded") && blankFrame.windowListeners.includes("load"));

  const interactive = await runLifecycleScenario({ href: "https://example.com/interactive", readyState: "interactive" });
  check("interactive documents do not add a stale DOMContentLoaded listener", !interactive.documentListeners.includes("DOMContentLoaded") && interactive.windowListeners.includes("load"));

  const complete = await runLifecycleScenario({ href: "https://example.com/complete", readyState: "complete" });
  check("complete documents do not add lifecycle listeners", complete.documentListeners.length === 0 && complete.windowListeners.length === 0);

  const cloudflareFrame = await runLifecycleScenario({ href: "https://challenges.cloudflare.com/turnstile", readyState: "loading", topLevel: false });
  check("Cloudflare frames still skip initialization", !cloudflareFrame.sentMessages.some(message => message && message.type === "InitContentScript"));
} catch (error) {
  check("lifecycle interception scope checks ran without throwing", false);
  console.error(error);
}

if (failures > 0) {
  console.error(`\n${failures} content scriptlet injection check(s) failed`);
  process.exit(1);
}
console.log("\nAll content scriptlet injection checks passed");
process.exit(0);
