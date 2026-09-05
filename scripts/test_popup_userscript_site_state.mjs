// Exercises popup initialization and refresh behavior for userscript site state.
// Run: node scripts/test_popup_userscript_site_state.mjs

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const popupPath = path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "pages", "popup", "popup.js");
let popupSource = readFileSync(popupPath, "utf8");
popupSource = popupSource.replace(
  "refreshUi().catch((error) => {",
  "globalThis.__popupInitPromise = refreshUi().catch((error) => {"
);

let failures = 0;
const check = (name, condition) => {
  console.log(`${condition ? "PASS" : "FAIL"}: ${name}`);
  if (!condition) failures += 1;
};

function makeClassList() {
  const classes = new Set();
  return {
    add(...names) { for (const name of names) classes.add(name); },
    remove(...names) { for (const name of names) classes.delete(name); },
    contains(name) { return classes.has(name); },
    toggle(name, force) {
      const enabled = force === undefined ? !classes.has(name) : Boolean(force);
      if (enabled) classes.add(name);
      else classes.delete(name);
      return enabled;
    },
    toString() { return [...classes].join(" "); },
  };
}

function makeElement(tagName = "div", id = "") {
  const listeners = new Map();
  const attributes = new Map();
  const element = {
    id,
    tagName: tagName.toUpperCase(),
    localName: tagName.toLowerCase(),
    hidden: false,
    disabled: false,
    checked: false,
    textContent: "",
    className: "",
    type: "",
    href: "",
    htmlFor: "",
    children: [],
    parentNode: null,
    dataset: {},
    style: {},
    scrollTop: 0,
    classList: makeClassList(),
    appendChild(child) {
      child.parentNode = this;
      this.children.push(child);
      return child;
    },
    setAttribute(name, value) {
      attributes.set(name, String(value));
      if (name === "id") this.id = String(value);
      if (name === "class") this.className = String(value);
      if (name.startsWith("data-")) {
        const key = name.slice(5).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
        this.dataset[key] = String(value);
      }
    },
    getAttribute(name) {
      if (name === "id") return this.id || null;
      if (name === "class") return this.className || null;
      return attributes.get(name) ?? null;
    },
    removeAttribute(name) {
      attributes.delete(name);
      if (name === "aria-busy") delete this.dataset.ariaBusy;
    },
    addEventListener(type, listener) {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(listener);
    },
    removeEventListener(type, listener) {
      listeners.set(type, (listeners.get(type) || []).filter((candidate) => candidate !== listener));
    },
    dispatchEvent(event) {
      event.target ??= this;
      event.currentTarget = this;
      for (const listener of listeners.get(event.type) || []) listener.call(this, event);
      if (event.bubbles !== false && this.parentNode) this.parentNode.dispatchEvent(event);
      return true;
    },
    contains(candidate) {
      for (let node = candidate; node; node = node.parentNode) {
        if (node === this) return true;
      }
      return false;
    },
    closest(selector) {
      for (let node = this; node; node = node.parentNode) {
        if (selector === "input.userscript-toggle") {
          const classes = String(node.className || "").split(/\s+/);
          if (node.localName === "input" && classes.includes("userscript-toggle")) return node;
        }
        if (selector === "button.rule-delete") {
          const classes = String(node.className || "").split(/\s+/);
          if (node.localName === "button" && classes.includes("rule-delete")) return node;
        }
        if (selector === "button.command-btn") {
          const classes = String(node.className || "").split(/\s+/);
          if (node.localName === "button" && classes.includes("command-btn")) return node;
        }
      }
      return null;
    },
    focus() {},
  };
  Object.defineProperty(element, "innerHTML", {
    set() { element.children = []; },
    get() { return ""; },
  });
  return element;
}

const documentListeners = new Map();
const elements = new Map();
const requiredIds = [
  "blocking-status",
  "enable-toggle",
  "error",
  "filter-update-status",
  "no-autoplay-enabled-toggle",
  "no-autoplay-site-row",
  "no-autoplay-site-toggle",
  "open-app",
  "paused-prompt",
  "paused-prompt-message",
  "paused-prompt-title",
  "resume-blocking",
  "site-host",
  "update-filters",
  "userscript-commands",
  "userscripts-count",
  "userscripts-empty",
  "userscripts-list",
  "userscripts-panel",
  "userscripts-section",
  "userscripts-toggle",
  "zapper-activate",
  "zapper-clear",
  "zapper-count",
  "zapper-enabled-toggle",
  "zapper-rules",
  "zapper-rules-panel",
  "zapper-rules-toggle",
];
for (const id of requiredIds) elements.set(id, makeElement("div", id));
for (const id of ["enable-toggle", "no-autoplay-enabled-toggle", "no-autoplay-site-toggle", "userscripts-toggle", "zapper-enabled-toggle"]) {
  elements.get(id).localName = "input";
  elements.get(id).tagName = "INPUT";
}
for (const id of ["open-app", "resume-blocking", "update-filters", "zapper-activate", "zapper-clear", "zapper-rules-toggle"]) {
  elements.get(id).localName = "button";
  elements.get(id).tagName = "BUTTON";
}
elements.get("userscripts-panel").hidden = true;
elements.get("zapper-rules-panel").hidden = true;

const storage = new Map();
const nativeMessages = [];
const runtimeMessages = [];
const tabMessages = [];
const reloads = [];
const siteScripts = [
  { id: "script-enabled", name: "Enabled Script", disabledForSite: false, running: true },
  { id: "script-disabled", name: "Disabled Script", disabledForSite: true, running: false },
];

const sandbox = {
  browser: {
    i18n: { getMessage: () => "" },
    runtime: {
      getPlatformInfo: async () => ({ os: "mac" }),
      sendMessage: async (message) => {
        runtimeMessages.push(message);
        if (message?.action === "wblock:filterUpdate:getStatus") return { ok: true, state: "idle" };
        if (message?.action === "wblock:installRemoveParamDNRRules") return { ok: true };
        if (message?.action === "wblock:menu:getCommands") return { ok: true, commands: [] };
        if (message?.action === "wblock:zapper:getRules") return { ok: true, rules: [], disabled: false };
        if (message?.action === "wblock:clearCache") return { ok: true };
        return { ok: true };
      },
      sendNativeMessage: async (_hostId, message) => {
        nativeMessages.push(message);
        if (message?.action === "getBlockingPausedState") {
          return { paused: false, filtersPaused: false, userScriptsPaused: false, elementZapperPaused: false, resumeAvailable: false };
        }
        if (message?.action === "getSiteDisabledState") return { disabled: true };
        if (message?.action === "getPageUserScripts") return { userScripts: siteScripts.map((script) => ({ ...script })) };
        if (message?.action === "getZapperRules") return { ok: true, rules: [], disabled: false };
        if (message?.action === "getNoAutoplayState") return { enabled: true, siteAllowed: false };
        if (message?.action === "setUserScriptSiteDisabledState") return { ok: true };
        return { ok: true };
      },
    },
    tabs: {
      query: async () => [{ id: 9, url: "https://example.com/page", active: true }],
      get: async () => ({ id: 9, url: "https://example.com/page", active: true }),
      sendMessage: async (tabId, message, options) => {
        tabMessages.push({ tabId, message, options });
        if (message?.type === "wblock:pageSupportProbe") return { ok: true, protocol: "https:", host: "example.com" };
        return { ok: true };
      },
      reload: async (tabId, options) => { reloads.push({ tabId, options }); },
    },
    storage: {
      local: {
        get: async (keys) => {
          if (keys === null) return Object.fromEntries(storage.entries());
          const wanted = Array.isArray(keys) ? keys : [keys];
          return Object.fromEntries(wanted.map((key) => [key, storage.get(key)]));
        },
        set: async (values) => { for (const [key, value] of Object.entries(values)) storage.set(key, value); },
        remove: async (keys) => { for (const key of Array.isArray(keys) ? keys : [keys]) storage.delete(key); },
      },
    },
  },
  document: {
    hidden: false,
    activeElement: null,
    body: makeElement("body"),
    documentElement: makeElement("html"),
    getElementById: (id) => elements.get(id) ?? null,
    createElement: (tagName) => makeElement(tagName),
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener(type, listener) {
      if (!documentListeners.has(type)) documentListeners.set(type, []);
      documentListeners.get(type).push(listener);
    },
  },
  window: {
    innerHeight: 640,
    matchMedia: () => ({ matches: true, addEventListener() {} }),
    requestAnimationFrame: (fn) => fn(),
    addEventListener() {},
    close() {},
    location: { href: "" },
  },
  navigator: { userAgent: "Mac", platform: "MacIntel", maxTouchPoints: 0 },
  CSS: { supports: () => false },
  URL,
  console,
  setTimeout,
  clearTimeout,
  Promise,
  Array,
  Boolean,
  Date,
  Error,
  Map,
  Number,
  Object,
  RegExp,
  Set,
  String,
};
sandbox.globalThis = sandbox;
sandbox.requestAnimationFrame = sandbox.window.requestAnimationFrame;

vm.createContext(sandbox);
vm.runInContext(`${popupSource}\nglobalThis.__refreshPopupForTest = refreshUi;`, sandbox, { filename: "popup.js" });
for (const listener of documentListeners.get("DOMContentLoaded") || []) listener();
await sandbox.__popupInitPromise;

const rows = elements.get("userscripts-list").children;
const inputs = rows.map((row) => row.children[1].children[0]);
check("popup initialization requests page userscripts from native", nativeMessages.some((message) => message.action === "getPageUserScripts" && message.url === "https://example.com/page"));
check("userscript controls stay visible when the site is disabled", elements.get("userscripts-section").hidden === false && rows.length === 2);
check("userscript controls are configurable when site blocking is disabled", inputs.every((input) => input.disabled === false));
check("enabled per-script site state renders as checked", inputs[0].checked === true);
check("disabled per-script site state renders as unchecked", inputs[1].checked === false);
check("running count ignores scripts disabled for the site", elements.get("userscripts-count").textContent === "1");
check("main site toggle still reflects the disabled site", elements.get("enable-toggle").checked === false);

await sandbox.__refreshPopupForTest();
const refreshedInputs = elements.get("userscripts-list").children.map((row) => row.children[1].children[0]);
check("popup refresh keeps userscript controls configurable on disabled sites", refreshedInputs.every((input) => input.disabled === false));
check("popup refresh preserves per-script disabled state", refreshedInputs[0].checked === true && refreshedInputs[1].checked === false);

refreshedInputs[1].checked = true;
refreshedInputs[1].dispatchEvent({ type: "change" });
await new Promise((resolve) => setTimeout(resolve, 0));
await new Promise((resolve) => setTimeout(resolve, 0));

const toggleRequest = nativeMessages.find((message) => message.action === "setUserScriptSiteDisabledState");
check("userscript site toggle writes through native handler", toggleRequest?.scriptId === "script-disabled" && toggleRequest.host === "example.com" && toggleRequest.disabled === false);
check("successful userscript site toggle refreshes rendered state", elements.get("userscripts-list").children[1].children[1].children[0].checked === true);
check("userscript site toggle reloads the active tab", reloads.some((entry) => entry.tabId === 9));

if (failures > 0) process.exitCode = 1;
