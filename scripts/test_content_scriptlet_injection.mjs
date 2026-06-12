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

if (failures > 0) {
  console.error(`\n${failures} content scriptlet injection check(s) failed`);
  process.exit(1);
}
console.log("\nAll content scriptlet injection checks passed");
process.exit(0);
