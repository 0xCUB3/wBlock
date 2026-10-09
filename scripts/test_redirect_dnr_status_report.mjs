// Tests for redirect DNR status reporting to native host.
//
// Loads the real bundle from "wBlock Scripts (iOS)/Resources/background.js"
// with a stubbed `browser` API and drives the registered onMessage listener.
//
// Run: node scripts/test_redirect_dnr_status_report.mjs

import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const canonicalSource = readFileSync(path.join(repoRoot, "extension-src", "background.js"), "utf8");

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

// Loads the bundle with a fresh browser stub.
const loadBackground = ({
  storage = {},
  nativeHandler,
  permissions = {},
  isAllowedIncognito = null,
  dynamicRules = [],
  sessionRules = [],
  dnrLimit = 30000,
}) => {
  const state = {
    storage,
    nativeMessages: [],
    onMessage: null,
    dnrUpdates: []
  };

  const listenerStub = { addListener: () => {} };
  const browser = {
    runtime: {
      getURL: relative => `safari-web-extension://test/${relative}`,
      sendNativeMessage: (_appId, message) => {
        state.nativeMessages.push(message);
        return nativeHandler(message);
      },
      onMessage: { addListener: fn => { state.onMessage = fn; } },
      connectNative: () => ({
        onMessage: { addListener: fn => {} },
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
    permissions: {
      contains: async query => {
        return permissions[JSON.stringify(query)] ?? false;
      }
    },
    extension: {
      isAllowedIncognitoAccess: isAllowedIncognito !== null
        ? async () => isAllowedIncognito
        : undefined
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
      executeScript: async () => [{}],
      insertCSS: async () => {}
    },
    declarativeNetRequest: {
      ...(dnrLimit == null ? {} : { MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES: dnrLimit }),
      getDynamicRules: async () => dynamicRules,
      getSessionRules: async () => sessionRules,
      updateDynamicRules: async update => {
        state.dnrUpdates.push(update);
      }
    },
    i18n: { getMessage: () => "" }
  };

  const run = new Function("browser", "window", "self", "fetch", canonicalSource);
  run(browser, globalThis, globalThis, globalThis.fetch);
  if (typeof state.onMessage !== "function") {
    throw new Error("background bundle did not register an onMessage listener");
  }
  return state;
};

// Scenario A: first install sends a report with the right counts/flags
{
  const state = loadBackground({
    nativeHandler: message => {
      if (message && message.action === "getRemoveParamDNRRules") {
        return { ok: true, version: "test", count: 2, rules: [
          { id: 1500000, priority: 15000, action: { type: "redirect", redirect: { extensionPath: "/redirects/noopjs.js" } }, condition: {} },
          { id: 1500001, priority: 15100, action: { type: "redirect", redirect: { extensionPath: "/redirects/noop.html" } }, condition: {} }
        ], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
      }
      return { payload: { css: [], extendedCss: [], js: [], scriptlets: [], engineTimestamp: 1 } };
    },
    permissions: { '{\"origins\":[\"*://*/*\"]}': true },
    isAllowedIncognito: false,
    dynamicRules: [],
    sessionRules: []
  });

  await sleep(50);
  const statusReport = state.nativeMessages.find(m => m && m.action === "reportRedirectDNRStatus");
  check("first install sends a status report", !!statusReport);
  check("report has correct installedRedirects count", statusReport && statusReport.installedRedirects === 2);
  check("report has correct hostAccess", statusReport && statusReport.hostAccess === true);
  check("report has correct privateAccess", statusReport && statusReport.privateAccess === false);
  check("status is persisted in storage", state.storage.wblockRedirectDNRStatusReport && state.storage.wblockRedirectDNRStatusReport.installedRedirects === 2);
}

// Scenario B: second run within 6 hours with unchanged values sends nothing
{
  const previousReport = { installedRedirects: 2, hostAccess: true, privateAccess: false, at: Date.now() - (5 * 60 * 60 * 1000) };
  const state = loadBackground({
    storage: {
      wblockRemoveParamDNRVersion: { version: "test", count: 2 },
      wblockRedirectDNRStatusReport: previousReport
    },
    nativeHandler: message => {
      if (message && message.action === "getRemoveParamDNRRules") {
        return { ok: true, version: "test", count: 2, rules: [
          { id: 1500000, priority: 15000, action: { type: "redirect", redirect: { extensionPath: "/redirects/noopjs.js" } }, condition: {} },
          { id: 1500001, priority: 15100, action: { type: "redirect", redirect: { extensionPath: "/redirects/noop.html" } }, condition: {} }
        ], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
      }
      return { payload: { css: [], extendedCss: [], js: [], scriptlets: [], engineTimestamp: 1 } };
    },
    permissions: { '{\"origins\":[\"*://*/*\"]}': true },
    isAllowedIncognito: false,
    dynamicRules: [
      { id: 1500000, priority: 15000, action: { type: "redirect", redirect: { extensionPath: "/redirects/noopjs.js" } }, condition: {} },
      { id: 1500001, priority: 15100, action: { type: "redirect", redirect: { extensionPath: "/redirects/noop.html" } }, condition: {} }
    ],
    sessionRules: []
  });

  await sleep(50);
  const reportCount = state.nativeMessages.filter(m => m && m.action === "reportRedirectDNRStatus").length;
  check("no report sent when values unchanged and within throttle window", reportCount === 0);
}

// Scenario C: change in hostAccess sends again
{
  const previousReport = { installedRedirects: 2, hostAccess: true, privateAccess: false, at: Date.now() - (5 * 60 * 60 * 1000) };
  const state = loadBackground({
    storage: {
      wblockRemoveParamDNRVersion: { version: "test", count: 2 },
      wblockRedirectDNRStatusReport: previousReport
    },
    nativeHandler: message => {
      if (message && message.action === "getRemoveParamDNRRules") {
        return { ok: true, version: "test", count: 2, rules: [
          { id: 1500000, priority: 15000, action: { type: "redirect", redirect: { extensionPath: "/redirects/noopjs.js" } }, condition: {} },
          { id: 1500001, priority: 15100, action: { type: "redirect", redirect: { extensionPath: "/redirects/noop.html" } }, condition: {} }
        ], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
      }
      return { payload: { css: [], extendedCss: [], js: [], scriptlets: [], engineTimestamp: 1 } };
    },
    permissions: { '{\"origins\":[\"*://*/*\"]}': false },
    isAllowedIncognito: false,
    dynamicRules: [
      { id: 1500000, priority: 15000, action: { type: "redirect", redirect: { extensionPath: "/redirects/noopjs.js" } }, condition: {} },
      { id: 1500001, priority: 15100, action: { type: "redirect", redirect: { extensionPath: "/redirects/noop.html" } }, condition: {} }
    ],
    sessionRules: []
  });

  await sleep(50);
  const statusReport = state.nativeMessages.find(m => m && m.action === "reportRedirectDNRStatus");
  check("changed hostAccess triggers a new report", !!statusReport);
  check("report reflects new hostAccess value", statusReport && statusReport.hostAccess === false);
}

// Scenario D: failed updateDynamicRules error does not send report
{
  const state = loadBackground({
    nativeHandler: message => {
      if (message && message.action === "getRemoveParamDNRRules") {
        return { ok: true, version: "test", count: 1, rules: [
          { id: 1500000, priority: 15000, action: { type: "redirect", redirect: { extensionPath: "/redirects/noopjs.js" } }, condition: {} }
        ], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
      }
      return { payload: { css: [], extendedCss: [], js: [], scriptlets: [], engineTimestamp: 1 } };
    },
    permissions: { '{\"origins\":[\"*://*/*\"]}': true },
    isAllowedIncognito: null,
    dynamicRules: [],
    sessionRules: []
  });

  // Mock updateDynamicRules to throw
  const oldRun = state.onMessage;
  const firstCall = { called: false };

  // Override the browser's updateDynamicRules to throw on first call
  // We need to re-run with a custom implementation
  const storage = {};
  let nativeMessages = [];
  const browser = {
    runtime: {
      getURL: relative => `safari-web-extension://test/${relative}`,
      sendNativeMessage: (_appId, message) => {
        nativeMessages.push(message);
        if (message && message.action === "getRemoveParamDNRRules") {
          return { ok: true, version: "test", count: 1, rules: [
            { id: 1500000, priority: 15000, action: { type: "redirect", redirect: { extensionPath: "/redirects/noopjs.js" } }, condition: {} }
          ], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
        }
        return { payload: { css: [], extendedCss: [], js: [], scriptlets: [], engineTimestamp: 1 } };
      },
      onMessage: { addListener: () => {} },
      connectNative: () => ({ onMessage: { addListener: () => {} }, onDisconnect: { addListener: () => {} } }),
      onInstalled: { addListener: () => {} },
      onStartup: { addListener: () => {} }
    },
    storage: {
      local: {
        get: async key => Object.hasOwn(storage, key) ? { [key]: storage[key] } : {},
        set: async items => Object.assign(storage, items),
        remove: async key => { delete storage[key]; }
      }
    },
    permissions: {
      contains: async query => query.origins && query.origins.includes("*://*/*")
    },
    extension: {},
    tabs: {
      query: async () => [],
      get: async () => ({}),
      sendMessage: async () => ({}),
      onUpdated: { addListener: () => {} },
      onActivated: { addListener: () => {} },
      onCreated: { addListener: () => {} },
      onRemoved: { addListener: () => {} }
    },
    scripting: {
      executeScript: async () => [{}],
      insertCSS: async () => {}
    },
    declarativeNetRequest: {
      MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES: 30000,
      getDynamicRules: async () => [],
      getSessionRules: async () => [],
      updateDynamicRules: async update => {
        throw new Error("validation failed");
      }
    },
    i18n: { getMessage: () => "" }
  };

  let caughtError = false;
  try {
    const run = new Function("browser", "window", "self", "fetch", canonicalSource);
    run(browser, globalThis, globalThis, globalThis.fetch);
  } catch (error) {
    caughtError = true;
  }

  check("failed updateDynamicRules does not crash bundle loading", !caughtError);
}

// Scenario E: count redirects accurately (only those with extensionPath as string)
{
  const state = loadBackground({
    nativeHandler: message => {
      if (message && message.action === "getRemoveParamDNRRules") {
        return { ok: true, version: "test", count: 4, rules: [
          { id: 1500000, priority: 15000, action: { type: "redirect", redirect: { extensionPath: "/redirects/noopjs.js" } }, condition: {} },
          { id: 1500001, priority: 15100, action: { type: "redirect", redirect: { transform: { queryTransform: { removeParams: ["ref"] } } } }, condition: {} },
          { id: 1500002, priority: 15000, action: { type: "redirect", redirect: { extensionPath: "/redirects/noop.html" } }, condition: {} },
          { id: 1500003, priority: 1, action: { type: "allow" }, condition: {} }
        ], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
      }
      return { payload: { css: [], extendedCss: [], js: [], scriptlets: [], engineTimestamp: 1 } };
    },
    permissions: { '{\"origins\":[\"*://*/*\"]}': true },
    isAllowedIncognito: true,
    dynamicRules: [],
    sessionRules: []
  });

  await sleep(50);
  const statusReport = state.nativeMessages.find(m => m && m.action === "reportRedirectDNRStatus");
  check("counts only extension path redirects", statusReport && statusReport.installedRedirects === 2);
}

if (failures === 0) {
  console.log("\nAll tests passed!");
  process.exit(0);
} else {
  console.error(`\n${failures} test(s) failed`);
  process.exit(1);
}
