// Behavioral check for the shipped (minified) content script: it must expose
// window.adguard.contentScript and assemble runnable scriptlet / raw-JS-rule
// code for the blank-frame fallback path (scriptlets.invoke -> IIFE wrapping
// of fn.toString()). Guards the esbuild minification step in
// scripts/minify-extension-js.sh.
//
// Run: node scripts/test_content_scriptlet_injection.mjs [path/to/content.js]
// Defaults to "wBlock Scripts (iOS)/Resources/content.js".

import { readFileSync } from "node:fs";
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
  cs.runScriptlets([{ name: "set-constant", args: ["wblockSmokeTest", "1"] }], false);

  const scriptEls = appended.filter(el => el.tagName === "script");
  check("scriptlet injection appended a script element", scriptEls.length === 1);

  const code = scriptEls[0] ? scriptEls[0].textContent : "";
  check("assembled code carries scriptlet source JSON", code.includes('"name":"set-constant"'));
  check("assembled code is an IIFE invocation", code.trim().startsWith("("));

  let parses = true;
  try { new Function(code); } catch { parses = false; }
  check("assembled scriptlet code parses", parses);

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

// --- Scriptlet timing race (issue #445 regression) ---
// Contract: when the per-site disabled-state lookup never resolves (native
// host latency / dropped message), the content script must NOT block the
// InitContentScript request on it. The Init request must be sent eagerly and
// its response must apply scriptlet machinery, even while siteDisabledPromise
// stays pending. Under the old sequential `await siteDisabledPromise` gate the
// InitContentScript message would never be sent, so this check fails there and
// passes only after the concurrent race fix.
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
  // A never-settling promise simulating a hung native-host disabled-state lookup.
  const pendingForever = new Promise(() => {});
  const raceBrowser = {
    runtime: {
      onMessage: { addListener() {} },
      sendMessage(msg) {
        sentMessages.push(msg);
        if (msg.action === "wblock:getSiteDisabledState") {
          return pendingForever;
        }
        // InitContentScript: return a real configuration payload so scriptlet
        // machinery is observable downstream.
        if (msg.type === "InitContentScript") {
          return Promise.resolve({
            payload: {
              css: [],
              extendedCss: [],
              scriptlets: [{ name: "set-constant", args: ["__wblockRaceProbe", "1"] }],
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

    // Flush microtasks so main()'s async race + applyConfiguration settle.
    // Disabled-state never resolves; only the config branch can complete.
    await new Promise(resolve => setTimeout(resolve, 50));

    const initSent = sentMessages.some(m => m && m.type === "InitContentScript");
    check(
      "InitContentScript sent despite unresolved disabled-state lookup",
      initSent,
    );

    // Ordering: the Init request must be dispatched without waiting on the
    // disabled-state promise. Under a sequential await-disabled-first gate the
    // Init message is never sent at all, so a present Init suffices to fail the
    // old behavior; we additionally assert the disabled-state request was made
    // (so the hang is real and the race is genuine, not a skipped branch).
    const disabledRequested = sentMessages.some(m => m && m.action === "wblock:getSiteDisabledState");
    check(
      "disabled-state lookup was actually initiated (race is genuine)",
      disabledRequested,
    );

    check(
      "contentScript exposed while disabled-state hangs",
      !!(raceWindow.adguard && raceWindow.adguard.contentScript),
    );

    const raceScriptEls = raceAppended.filter(el => el.tagName === "script");
    check(
      "scriptlet from Init response applied before disabled-state resolves",
      raceScriptEls.length >= 1 && raceScriptEls.some(el => (el.textContent || "").includes("__wblockRaceProbe")),
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

if (failures > 0) {
  console.error(`\n${failures} content scriptlet injection check(s) failed`);
  process.exit(1);
}
console.log("\nAll content scriptlet injection checks passed");
process.exit(0);
