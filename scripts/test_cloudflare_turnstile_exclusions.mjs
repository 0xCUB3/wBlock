// Regression tests for Cloudflare Turnstile / challenge exclusions (#1167).
// Verifies manifest exclusions, static DNR allow rules, GPC, No Autoplay,
// warm scriptlets, content/zapper/userscript bail-outs, and background handlers.
//
// Run: node scripts/test_cloudflare_turnstile_exclusions.mjs

import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { runtimeMessageListener } from "./helpers/runtime-message.mjs";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const resDir = path.join(repoRoot, "wBlock Scripts (iOS)", "Resources");

const EXPECTED_EXCLUDES = [
  "*://challenges.cloudflare.com/*",
  "*://*.challenges.cloudflare.com/*",
  "*://*/cdn-cgi/challenge*",
];

let failures = 0;
const check = (name, cond) => {
  console.log(`${cond ? "PASS" : "FAIL"}: ${name}`);
  if (!cond) failures += 1;
};
const flush = () => new Promise(resolve => setTimeout(resolve, 25));

// 1. manifest.json excludes Cloudflare challenge frames from all <all_urls> content_scripts
{
  const manifest = JSON.parse(readFileSync(path.join(resDir, "manifest.json"), "utf8"));
  const allUrlScripts = (manifest.content_scripts || []).filter(entry =>
    Array.isArray(entry.matches) && entry.matches.includes("<all_urls>")
  );
  check("manifest has both <all_urls> content_scripts entries", allUrlScripts.length === 2);
  for (const entry of allUrlScripts) {
    const ok = EXPECTED_EXCLUDES.every(pattern => Array.isArray(entry.exclude_matches) && entry.exclude_matches.includes(pattern));
    check(`manifest exclude_matches covers Cloudflare challenges for [${entry.js.join(", ")}]`, ok);
  }
}

// 2. Static DNR rules allow challenges.cloudflare.com at priority 20000
{
  const rules = JSON.parse(readFileSync(path.join(resDir, "rules", "csp_strip_rules.json"), "utf8"));
  const allowRequest = rules.find(r =>
    r.priority === 20000 && r.action?.type === "allow"
    && Array.isArray(r.condition?.requestDomains) && r.condition.requestDomains.includes("challenges.cloudflare.com")
  );
  const allowDocument = rules.find(r =>
    r.priority === 20000 && r.action?.type === "allow"
    && Array.isArray(r.condition?.domains) && r.condition.domains.includes("challenges.cloudflare.com")
  );
  check("static DNR rules allow requests to challenges.cloudflare.com", !!allowRequest);
  check("static DNR rules allow subresources on challenges.cloudflare.com", !!allowDocument);
}

// 3. gpc.js skips Navigator.prototype mutation on Cloudflare challenge frames
{
  const gpcSource = readFileSync(path.join(resDir, "gpc.js"), "utf8");
  const runGpc = (hostname, pathname) => {
    function Navigator() {}
    const sandbox = { Navigator, location: { hostname, pathname } };
    vm.runInContext(gpcSource, vm.createContext(sandbox));
    return Object.getOwnPropertyDescriptor(Navigator.prototype, "globalPrivacyControl");
  };
  check("gpc.js skips challenges.cloudflare.com", runGpc("challenges.cloudflare.com", "/cdn-cgi/challenge-platform/h/b") === undefined);
  check("gpc.js skips debug.challenges.cloudflare.com", runGpc("debug.challenges.cloudflare.com", "/") === undefined);
  check("gpc.js skips /cdn-cgi/challenge paths on any host", runGpc("example.com", "/cdn-cgi/challenge-platform/foo") === undefined);
  const normal = runGpc("example.com", "/");
  check("gpc.js still defines globalPrivacyControl on normal pages", typeof normal?.get === "function" && normal.get() === true);
}

// 4. no-autoplay.js + no-autoplay-gate.js stay off Cloudflare challenges and avoid ShadowRoot/attachShadow expandos
{
  const gateSource = readFileSync(path.join(resDir, "no-autoplay-gate.js"), "utf8");
  const controllerSource = readFileSync(path.join(resDir, "no-autoplay.js"), "utf8");
  const combined = `${gateSource}\n${controllerSource}`;

  const runNoAutoplay = async ({ hostname, pathname = "/", hint = true, hasTurnstileScript = false }) => {
    const localStore = new Map(hint ? [["__wblock_no_autoplay_arm_v1", "1"]] : []);
    const runtimeMessages = [];
    let inlineExecutions = 0;
    const attrs = new Map();
    const documentElement = {
      getAttribute: k => (attrs.has(k) ? attrs.get(k) : null),
      setAttribute: (k, v) => { attrs.set(k, String(v)); },
      removeAttribute: k => { attrs.delete(k); },
      querySelectorAll: () => [],
      appendChild(el) {
        if (el.textContent) {
          inlineExecutions += 1;
          vm.runInContext(el.textContent, context);
        }
        return el;
      },
    };
    const documentStub = {
      documentElement,
      head: null,
      body: { localName: "body", querySelectorAll: () => [] },
      title: "",
      visibilityState: "visible",
      addEventListener() {},
      removeEventListener() {},
      dispatchEvent() { return true; },
      createElement: tag => ({ tagName: String(tag).toUpperCase(), textContent: "", setAttribute() {}, remove() {} }),
      querySelector: sel => (hasTurnstileScript && sel.includes("challenges.cloudflare.com") ? {} : null),
      querySelectorAll: () => [],
    };
    function HTMLMediaElement() {}
    HTMLMediaElement.prototype.play = () => Promise.resolve();
    function Document() {}
    const origCreateElement = documentStub.createElement;
    Document.prototype.createElement = origCreateElement;
    function Element() {}
    const origAttachShadow = function () { return { addEventListener() {} }; };
    Element.prototype.attachShadow = origAttachShadow;

    const sandbox = {
      console,
      setTimeout,
      clearTimeout,
      WeakSet,
      WeakRef,
      HTMLMediaElement,
      Document,
      Element,
      Event: class { constructor(type) { this.type = type; } },
      DOMException: class extends Error {},
      document: documentStub,
      location: { hostname, pathname },
      localStorage: {
        getItem: k => (localStore.has(k) ? localStore.get(k) : null),
        setItem: (k, v) => { localStore.set(k, String(v)); },
        removeItem: k => { localStore.delete(k); },
      },
      crypto: { getRandomValues: arr => arr },
      addEventListener() {},
      browser: {
        runtime: {
          sendMessage: msg => {
            runtimeMessages.push(msg);
            if (msg.action === "wblock:noAutoplay:getState") return Promise.resolve({ ok: true, enabled: true, siteAllowed: false });
            if (msg.action === "wblock:getSiteDisabledState") return Promise.resolve({ ok: true, disabled: false });
            return Promise.resolve({ ok: true });
          },
        },
        storage: {
          local: { get: async () => ({ "wblock.noAutoplay.enabled.v1": true }) },
          onChanged: { addListener() {}, removeListener() {} },
        },
      },
    };
    sandbox.window = sandbox;
    const context = vm.createContext(sandbox);
    vm.runInContext(combined, context);
    await flush();
    return {
      inlineExecutions,
      runtimeMessages,
      hintCleared: !localStore.has("__wblock_no_autoplay_arm_v1"),
      attachShadowUntouched: Element.prototype.attachShadow === origAttachShadow,
      createElementUntouched: Document.prototype.createElement === origCreateElement,
      Element,
    };
  };

  for (const [label, opts] of [
    ["challenges.cloudflare.com", { hostname: "challenges.cloudflare.com", pathname: "/turnstile" }],
    ["debug.challenges.cloudflare.com", { hostname: "debug.challenges.cloudflare.com", pathname: "/" }],
    ["/cdn-cgi/challenge path", { hostname: "example.com", pathname: "/cdn-cgi/challenge-platform/h/b" }],
  ]) {
    const res = await runNoAutoplay(opts);
    check(`no-autoplay skips ${label} even with warm hint`,
      res.inlineExecutions === 0 && res.runtimeMessages.length === 0 && res.hintCleared
      && res.attachShadowUntouched && res.createElementUntouched);
  }

  const hostWithTurnstile = await runNoAutoplay({ hostname: "example.com", pathname: "/login", hint: false, hasTurnstileScript: true });
  check("no-autoplay skips host page containing Turnstile script when unhinted",
    hostWithTurnstile.inlineExecutions === 0 && hostWithTurnstile.attachShadowUntouched);

  const normal = await runNoAutoplay({ hostname: "example.com", pathname: "/video", hint: true });
  const root = normal.Element.prototype.attachShadow.call({}, { mode: "closed" });
  check("no-autoplay-gate leaves no _wblockNoAutoplayPatched expando on attachShadow",
    !Object.prototype.hasOwnProperty.call(normal.Element.prototype.attachShadow, "_wblockNoAutoplayPatched"));
  check("no-autoplay-gate leaves no _wblockNoAutoplayObserved expando on ShadowRoot",
    !Object.prototype.hasOwnProperty.call(root, "_wblockNoAutoplayObserved"));
}

// 5. early/warm-scriptlets.js skips Cloudflare challenge frames
{
  const warmSource = readFileSync(path.join(resDir, "early", "warm-scriptlets.js"), "utf8");
  const runWarm = (hostname, pathname) => {
    const sandbox = {
      location: { hostname, pathname },
      localStorage: {
        getItem: () => JSON.stringify({ exp: Date.now() + 60_000, calls: [["set-constant", "foo", "true"]] }),
      },
    };
    sandbox.globalThis = sandbox;
    vm.runInContext(warmSource, vm.createContext(sandbox));
    return sandbox.__wbeScriptletCalls;
  };
  check("warm-scriptlets skips challenges.cloudflare.com", runWarm("challenges.cloudflare.com", "/") === undefined);
  check("warm-scriptlets skips debug.challenges.cloudflare.com", runWarm("debug.challenges.cloudflare.com", "/") === undefined);
  check("warm-scriptlets skips /cdn-cgi/challenge paths", runWarm("example.com", "/cdn-cgi/challenge-platform/x") === undefined);
  check("warm-scriptlets still queues calls on normal pages", Array.isArray(runWarm("example.com", "/")?.["set-constant"]));
}

// 6. userscript-injector.js, zapper-content.js, and content.js bail out on debug.challenges.cloudflare.com
{
  const runIsolatedScript = (filePath, hostname, pathname) => {
    const src = readFileSync(filePath, "utf8");
    const messages = [];
    const sandbox = {
      console: { log() {}, warn() {}, error() {}, info() {} },
      setTimeout,
      clearTimeout,
      location: { href: `https://${hostname}${pathname}`, hostname, pathname, protocol: "https:" },
      document: {
        readyState: "loading",
        title: "",
        documentElement: { appendChild() {}, removeChild() {} },
        addEventListener() {},
        removeEventListener() {},
        querySelector: () => null,
        querySelectorAll: () => [],
      },
      addEventListener() {},
      removeEventListener() {},
      browser: {
        runtime: {
          sendMessage: msg => { messages.push(msg); return Promise.resolve({}); },
          onMessage: { addListener() {}, removeListener() {} },
        },
        storage: { local: { get: async () => ({}) } },
        i18n: { getMessage: () => "" },
      },
    };
    sandbox.window = sandbox;
    sandbox.self = sandbox;
    sandbox.top = sandbox;
    vm.runInContext(src, vm.createContext(sandbox));
    return { sandbox, messages };
  };

  for (const [label, relPath] of [
    ["userscript-injector.js", "userscript-injector.js"],
    ["zapper-content.js", "zapper-content.js"],
    ["content.js (minified)", "content.js"],
  ]) {
    const file = path.join(resDir, relPath);
    const res = runIsolatedScript(file, "debug.challenges.cloudflare.com", "/");
    check(`${label} sends no messages on debug.challenges.cloudflare.com`, res.messages.length === 0);
  }
}

// 7. background.js (extension-src & minified): GPC/No Autoplay exclusions, upgrade path, shut-out tab, and message guards
for (const [label, filePath] of [
  ["extension-src", path.join(repoRoot, "extension-src", "background.js")],
  ["minified bundle", path.join(resDir, "background.js")],
]) {
  const source = readFileSync(filePath, "utf8");
  let installedRules = [{
    id: 1700000,
    priority: 2,
    action: { type: "modifyHeaders", requestHeaders: [{ header: "Sec-GPC", operation: "set", value: "1" }] },
    condition: { resourceTypes: ["main_frame"] },
  }];
  let registeredScripts = [
    { id: "wblock-gpc", js: ["gpc.js"], matches: ["<all_urls>"], allFrames: true, runAt: "document_start", world: "MAIN" },
    { id: "wblock-no-autoplay", js: ["no-autoplay-gate.js", "no-autoplay.js"], matches: ["<all_urls>"], allFrames: true, runAt: "document_start" },
  ];
  const executeScriptCalls = [];
  const tabsCreated = [];
  const onUpdatedListeners = [];
  let onMessage = null;

  const browser = {
    runtime: {
      getURL: rel => `safari-web-extension://test/${rel}`,
      sendNativeMessage: async (_appId, msg) => {
        if (msg.action === "getGlobalPrivacyControlState") return { enabled: true };
        if (msg.action === "getNoAutoplayState") return { active: true };
        if (msg.action === "getRemoveParamDNRRules") return { ok: true, version: "v0", count: 0, rules: [], ruleIdBase: 1500000, ruleIdLimit: 1650000 };
        if (msg.action === "getBlockedCountDNRRules") return { ok: true, enabled: false, version: "", count: 0, rules: [] };
        if (msg.action === "reportRedirectDNRStatus") return { ok: true };
        if (msg.action === "getBlockingState") return { disabled: false, paused: false };
        if (msg.action === "getBlockingPausedState") return { paused: false };
        return { payload: { css: [], procedural: [], scriptlets: [], engineTimestamp: 1, disabled: false, paused: false } };
      },
      onMessage: { addListener: fn => { onMessage = runtimeMessageListener(fn); } },
      connectNative: () => ({ onMessage: { addListener() {} }, onDisconnect: { addListener() {} } }),
      onInstalled: { addListener() {} },
      onStartup: { addListener() {} },
    },
    storage: {
      local: { get: async () => ({}), set: async () => {}, remove: async () => {} },
    },
    permissions: { contains: async () => true },
    extension: { isAllowedIncognitoAccess: async () => true },
    tabs: {
      query: async () => [],
      get: async id => ({ id, url: "https://debug.challenges.cloudflare.com/" }),
      sendMessage: async () => { throw new Error("no content script"); },
      create: async props => { tabsCreated.push(props); return { id: 99, ...props }; },
      remove: async () => {},
      onUpdated: { addListener: fn => onUpdatedListeners.push(fn) },
      onActivated: { addListener() {} },
      onCreated: { addListener() {} },
      onRemoved: { addListener() {} },
    },
    scripting: {
      executeScript: async injection => { executeScriptCalls.push(injection); return [{}]; },
      insertCSS: async () => {},
      registerContentScripts: async scripts => {
        for (const s of scripts) {
          registeredScripts = registeredScripts.filter(x => x.id !== s.id).concat([s]);
        }
      },
      unregisterContentScripts: async ({ ids }) => {
        registeredScripts = registeredScripts.filter(x => !ids.includes(x.id));
      },
      getRegisteredContentScripts: async filter => {
        const ids = filter && Array.isArray(filter.ids) ? filter.ids : null;
        return ids ? registeredScripts.filter(s => ids.includes(s.id)) : registeredScripts.slice();
      },
    },
    declarativeNetRequest: {
      MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES: 30000,
      setExtensionActionOptions: async () => {},
      getDynamicRules: async filter => {
        if (filter && Array.isArray(filter.ruleIds)) {
          const wanted = new Set(filter.ruleIds);
          return installedRules.filter(r => wanted.has(r.id));
        }
        return installedRules.slice();
      },
      getSessionRules: async () => [],
      isRegexSupported: async () => ({ isSupported: true }),
      updateDynamicRules: async update => {
        const removeIds = new Set(update.removeRuleIds || []);
        installedRules = installedRules.filter(r => !removeIds.has(r.id)).concat(update.addRules || []);
      },
    },
    action: {
      enable: async () => {}, disable: async () => {}, setIcon: async () => {}, setPopup: async () => {},
      setTitle: async () => {}, setBadgeText: async () => {}, setBadgeBackgroundColor: async () => {},
    },
    i18n: { getMessage: () => "" },
  };

  new Function("browser", "window", "self", "fetch", source)(browser, globalThis, globalThis, globalThis.fetch);
  await flush();

  const gpcRule = installedRules.find(r => r.id === 1700000);
  check(`[${label}] GPC rule upgrades with Cloudflare challenge domain exclusions`,
    gpcRule?.condition?.excludedRequestDomains?.includes("challenges.cloudflare.com")
    && gpcRule?.condition?.excludedDomains?.includes("challenges.cloudflare.com"));

  const gpcScript = registeredScripts.find(s => s.id === "wblock-gpc");
  check(`[${label}] GPC script upgrades with Cloudflare excludeMatches`,
    EXPECTED_EXCLUDES.every(p => gpcScript?.excludeMatches?.includes(p)));

  const autoplayScript = registeredScripts.find(s => s.id === "wblock-no-autoplay");
  check(`[${label}] No Autoplay script upgrades with Cloudflare excludeMatches`,
    EXPECTED_EXCLUDES.every(p => autoplayScript?.excludeMatches?.includes(p)));

  executeScriptCalls.length = 0;
  for (const listener of onUpdatedListeners) {
    listener(7, { status: "complete" }, { id: 7, index: 0, active: true, windowId: 1, url: "https://debug.challenges.cloudflare.com/" });
  }
  await flush();
  check(`[${label}] replaceShutOutTab skips debug.challenges.cloudflare.com`,
    executeScriptCalls.length === 0 && tabsCreated.length === 0);

  const gateReply = await onMessage(
    { action: "wblock:noAutoplay:injectGate", token: "abc" },
    { tab: { id: 7, url: "https://debug.challenges.cloudflare.com/" }, frameId: 2, url: "https://challenges.cloudflare.com/turnstile" }
  );
  check(`[${label}] wblock:noAutoplay:injectGate refuses Cloudflare challenge frames`,
    gateReply?.ok === false && executeScriptCalls.length === 0);

  const blankInitReply = await onMessage(
    { type: "InitContentScript" },
    { tab: { id: 7, url: "https://debug.challenges.cloudflare.com/" }, frameId: 3, url: "about:blank" }
  );
  check(`[${label}] InitContentScript treats about:blank under Cloudflare challenge as disabled`,
    blankInitReply?.disabled === true && executeScriptCalls.length === 0);

  const cleanReply = await onMessage(
    { action: "wblock:getCleanURL", url: "https://debug.challenges.cloudflare.com/?utm_source=test" },
    { tab: { id: 7 }, frameId: 0, url: "https://debug.challenges.cloudflare.com/?utm_source=test" }
  );
  check(`[${label}] wblock:getCleanURL leaves Cloudflare challenge URLs untouched`,
    cleanReply?.cleanUrl === "https://debug.challenges.cloudflare.com/?utm_source=test");
}

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nAll Cloudflare Turnstile exclusion checks passed!");
