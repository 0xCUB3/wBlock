// Behavioral check for the userscript injector's privileged bridges.
//
// The page-context GM_xmlhttpRequest bridge must only honor requests that carry
// a per-script token issued at injection time (otherwise any page script could
// borrow the extension's CORS-free network access). GM runtime ports must be
// namespaced with a per-script token so other page scripts cannot guess the
// channel name and spoof port messages.
//
// Run: node scripts/test_userscript_bridge_auth.mjs [path/to/userscript-injector.js]
// Defaults to "wBlock Scripts (iOS)/Resources/userscript-injector.js".

import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { webcrypto } from "node:crypto";
import { fileURLToPath } from "node:url";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const injectorPath = process.argv[2]
  ?? path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "userscript-injector.js");
const source = readFileSync(injectorPath, "utf8");
const cacheRevision = (source.match(/WBLOCK_BUNDLED_USERSCRIPT_CACHE_REVISION = ['\"]([^'\"]+)/) || [])[1] || "";

let failures = 0;
const check = (name, cond) => {
  console.log(`${cond ? "PASS" : "FAIL"}: ${name}`);
  if (!cond) failures += 1;
};
const tick = () => new Promise((r) => setTimeout(r, 20));

// The userscript we inject. It exercises GM_xmlhttpRequest (with a portName) and
// opens a runtime port, recording what it observes.
const USER_SCRIPT_CONTENT = `
  GM_xmlhttpRequest({ url: 'https://api.test/data', method: 'GET', portName: 'streamport' });
  immersiveTranslateBrowserAPI = {};
  const port = immersiveTranslateBrowserAPI.runtime.connect('streamport');
  window.__portName = port.name;
  window.__portMessages = [];
  port.onMessage.addListener(function (m) { window.__portMessages.push(m); });
`;

const fakeScript = {
  id: "test-script-1",
  name: "Bridge Auth Test Script",
  content: USER_SCRIPT_CONTENT,
  sourceURL: "https://scripts.test/bridge-auth.user.js",
  isLocal: false,
  matches: ["https://example.com/*"],
  grant: ["GM_xmlhttpRequest"],
  injectInto: "page",
  runAt: "document-start",
  isEnabled: true,
  payloadRevision: 0,
  cacheCategory: "bundled",
  cacheRevision,
};

// ---------------------------------------------------------------------------
// Phase 1: load the injector as a content script and let it inject fakeScript.
// ---------------------------------------------------------------------------

const windowMessageListeners = [];   // engine-level window 'message' listeners
const appendedScripts = [];          // wrapper sources appended to the DOM
const sentMessages = [];             // browser.runtime.sendMessage calls

function makeElement(tag) {
  return {
    tagName: String(tag).toUpperCase(),
    textContent: "",
    attributes: {},
    nonce: "",
    parentNode: null,
    children: [],
    style: {},
    setAttribute(k, v) { this.attributes[k] = v; },
    getAttribute(k) { return k in this.attributes ? this.attributes[k] : null; },
    removeAttribute(k) { delete this.attributes[k]; },
    appendChild(c) { this.children.push(c); c.parentNode = this; return c; },
    remove() { this.parentNode = null; },
    addEventListener() {},
    removeEventListener() {},
  };
}

function buildContentScriptSandbox(
  initialSessionValue = null,
  userScripts = [fakeScript],
  href = "https://example.com/page",
  cachedUserScripts = [],
  documentStartCacheAllowed = true,
  nativeHandler = null,
) {
  const head = makeElement("head");
  head.appendChild = (c) => {
    head.children.push(c);
    c.parentNode = head;
    const inlineProbe = c.textContent.match(/^document\.documentElement\.setAttribute\('([^']+)', '1'\)$/);
    if (inlineProbe) {
      docEl.setAttribute(inlineProbe[1], "1");
    } else if (c.textContent) {
      appendedScripts.push(c.textContent);
    }
    return c;
  };
  const docEl = makeElement("html");
  docEl.appendChild = head.appendChild;

  const sandbox = {};
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.top = sandbox;
  sandbox.self = sandbox;
  const pageURL = new URL(href);
  sandbox.location = { href, hostname: pageURL.hostname, protocol: pageURL.protocol };
  sandbox.addEventListener = (type, fn) => { if (type === "message") windowMessageListeners.push(fn); };
  sandbox.removeEventListener = () => {};
  sandbox.postMessage = () => {};
  sandbox.console = { log() {}, warn() {}, error() {}, info() {}, debug() {}, trace() {} };
  sandbox.setTimeout = setTimeout;
  sandbox.clearTimeout = clearTimeout;
  sandbox.atob = (b64) => Buffer.from(b64, "base64").toString("binary");
  sandbox.crypto = webcrypto;
  sandbox.URL = URL;
  sandbox.Blob = class Blob { constructor(p, o) { this.parts = p; this.type = (o && o.type) || ""; } };
  sandbox.TextDecoder = TextDecoder;
  sandbox.TextEncoder = TextEncoder;
  sandbox.__fetches = [];
  sandbox.__sentMessages = [];
  sandbox.fetch = async (url) => {
    sandbox.__fetches.push(String(url));
    return { ok: true, status: 200, text: async () => "{}" };
  };
  const sessionValues = new Map();
  if (initialSessionValue !== null) {
    sessionValues.set("__wblock_warm_start_v1", initialSessionValue);
  }
  const sessionStorageWrites = [];
  sandbox.sessionStorage = {
    getItem: (key) => sessionValues.get(key) ?? null,
    setItem: (key, value) => {
      sessionStorageWrites.push([key, String(value)]);
      sessionValues.set(key, String(value));
    },
    removeItem: (key) => sessionValues.delete(key),
  };
  sandbox.__sessionValues = sessionValues;
  sandbox.__sessionStorageWrites = sessionStorageWrites;
  // The warm-start cache now lives in localStorage (sessionStorage is only a
  // legacy read fallback), so the sandbox mocks both stores separately.
  const localValues = new Map();
  const localStorageWrites = [];
  sandbox.localStorage = {
    getItem: (key) => localValues.get(key) ?? null,
    setItem: (key, value) => {
      localStorageWrites.push([key, String(value)]);
      localValues.set(key, String(value));
    },
    removeItem: (key) => localValues.delete(key),
  };
  sandbox.__localValues = localValues;
  sandbox.__localStorageWrites = localStorageWrites;
  sandbox.document = {
    readyState: "complete",
    documentElement: docEl,
    head,
    body: makeElement("body"),
    createElement: makeElement,
    currentScript: null,
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener: () => {},
    removeEventListener: () => {},
  };
  sandbox.browser = {
    runtime: {
      sendMessage: async (msg) => {
        sentMessages.push(msg);
        sandbox.__sentMessages.push(msg);
        if (nativeHandler) return nativeHandler(msg, sandbox);
        if (msg.action === "getUserScripts") return {
          userScripts: JSON.parse(JSON.stringify(userScripts)),
          documentStartCacheAllowed,
          cacheRevision
        };
        if (msg.action === "getCachedDocumentStartUserScripts") return {
          userScripts: JSON.parse(JSON.stringify(cachedUserScripts)),
          cacheRevision,
          documentStartCacheAllowed
        };
        if (msg.action === "gmXmlhttpRequest") {
          return { status: 200, responseText: "OK", responseHeaders: "", finalUrl: msg.url };
        }
        return { ok: true };
      },
      onMessage: { addListener: (fn) => { sandbox.__onMessage = fn; } },
      connect: () => ({ onMessage: { addListener() {} }, onDisconnect: { addListener() {} }, postMessage() {}, disconnect() {} }),
    },
  };
  return sandbox;
}

const initialSentMessages = sentMessages.length;
const contentSandbox = buildContentScriptSandbox();
vm.createContext(contentSandbox);
vm.runInContext(source, contentSandbox, { filename: "userscript-injector.js" });
let repeatedEvaluationSucceeded = true;
try {
  vm.runInContext(source, contentSandbox, { filename: "userscript-injector-repeat.js" });
} catch {
  repeatedEvaluationSucceeded = false;
}
check("injector can be evaluated repeatedly in one isolated world", repeatedEvaluationSucceeded);

const rydScript = {
  ...fakeScript,
  id: "ryd-test",
  name: "Return YouTube Dislike",
  sourceURL: "https://raw.githubusercontent.com/Anarios/return-youtube-dislike/main/Extensions/UserScript/Return%20Youtube%20Dislike.user.js",
};
const rydSandbox = buildContentScriptSandbox(null, [rydScript], "https://www.youtube.com/watch?v=Z8CtXdQExek");
vm.createContext(rydSandbox);
vm.runInContext(source, rydSandbox, { filename: "userscript-injector-ryd-prefetch.js" });
await tick();
await tick();
check(
  "enabled Return YouTube Dislike primes the votes response cache",
  rydSandbox.__fetches.includes("https://returnyoutubedislikeapi.com/votes?videoId=Z8CtXdQExek"),
);

// Dispatch a message event from *inside* the content-script realm so that
// event.source is the same `window` object the listeners compare against
// (Node's vm wraps cross-realm objects, which would otherwise break the
// event.source === window guard that works fine in a real browser).
contentSandbox.__listeners = windowMessageListeners;
vm.runInContext(
  `globalThis.__fire = (data) => { for (const fn of globalThis.__listeners) fn({ source: window, data }); };`,
  contentSandbox,
);

// Let the async getUserScripts -> inject pipeline settle.
await tick();
await tick();

check("injector appended a userscript wrapper", appendedScripts.length >= 1);
const wrapperSource = appendedScripts[0] || "";

const xhrBridgeId = (wrapperSource.match(/const xhrBridgeId = '([^']*)';/) || [])[1] || "";
const portBridgeId = (wrapperSource.match(/const portBridgeId = '([^']*)';/) || [])[1] || "";
check("wrapper embeds a non-empty xhrBridgeId", xhrBridgeId.length > 0);
check("wrapper embeds a non-empty portBridgeId", portBridgeId.length > 0);

const initialRequests = contentSandbox.__sentMessages.filter((m) => m && m.action === "getUserScripts");
check("initialization makes one authoritative getUserScripts request", initialRequests.length === 1);
check("initialization makes zero cached requests", !contentSandbox.__sentMessages.some((m) => m && m.action === "getCachedDocumentStartUserScripts"));
check(
  "cold initialization writes only the bounded warm-start cache",
  [...contentSandbox.__sessionStorageWrites, ...contentSandbox.__localStorageWrites]
    .every(([key]) => key === "__wblock_warm_start_v1")
);

// ---------------------------------------------------------------------------
// Phase 2: the engine-level XHR bridge must gate on the issued token.
// ---------------------------------------------------------------------------

const gmXhrCalls = () => sentMessages.filter((m) => m && m.action === "gmXmlhttpRequest");

const staleSessionWrapperIndex = appendedScripts.length;
const staleSessionSandbox = buildContentScriptSandbox(
  JSON.stringify({ savedAt: Date.now(), cacheRevision: "old-revision", scripts: [fakeScript] }),
  [],
  "https://example.com/page",
  [],
);
vm.createContext(staleSessionSandbox);
vm.runInContext(source, staleSessionSandbox, { filename: "userscript-injector-stale-session.js" });
await tick();
await tick();
check("injector does not restore stale page sessionStorage directly", appendedScripts.length === staleSessionWrapperIndex);

const freshIOSWrapperIndex = appendedScripts.length;
const freshIOSSandbox = buildContentScriptSandbox(
  null,
  [fakeScript],
  "https://example.com/page",
  [fakeScript],
  false,
);
vm.createContext(freshIOSSandbox);
vm.runInContext(source, freshIOSSandbox, { filename: "userscript-injector-ios-fresh.js" });
await tick();
await tick();
const freshIOSWrapper = appendedScripts[freshIOSWrapperIndex] || "";
check(
  "cache-disabled native response still runs and seeds only quarantined state",
  freshIOSWrapper.includes("const xhrBridgeId = '")
    && freshIOSSandbox.__localStorageWrites.some(([key]) => key === "__wblock_warm_start_v1")
);
check(
  "fresh native scripts still request execution validation",
  freshIOSSandbox.__sentMessages.some(message => message.action === "validateUserScriptExecution")
);

// A Vencord-sized page-world payload must be seeded even when iOS reports that
// trusted document-start caching is unavailable. On the next navigation it may
// execute with page authority, while extension privileges remain quarantined.
const largeWarmScript = {
  ...fakeScript,
  id: "vencord-like",
  name: "Vencord",
  namespace: "https://github.com/Vendicated/Vencord",
  content: "window.__warmPageExecuted = true;\n" + USER_SCRIPT_CONTENT + "\n/*" + "x".repeat(700 * 1024) + "*/",
  sourceURL: "https://raw.githubusercontent.com/Vencord/builds/main/Vencord.user.js",
  matches: ["*://*.discord.com/*"],
  grant: ["GM_xmlhttpRequest", "unsafeWindow"],
};
const seedSandbox = buildContentScriptSandbox(
  null, [largeWarmScript], "https://discord.com/app", [], false,
);
vm.createContext(seedSandbox);
vm.runInContext(source, seedSandbox, { filename: "userscript-injector-warm-seed.js" });
await tick();
await tick();
const seededCache = seedSandbox.__localValues.get("__wblock_warm_start_v1") || "";
const seededPayload = seededCache ? JSON.parse(seededCache) : null;
check(
  "iOS authoritative response seeds the quarantined Vencord warm start",
  seededPayload?.scripts?.length === 1 && seededPayload.scripts[0].id === largeWarmScript.id,
);
check(
  "warm-start cache is bounded by its complete serialized size",
  new TextEncoder().encode(seededCache).length <= 2 * 1024 * 1024,
);
check(
  "warm-start cache persists no storage snapshot or bridge credentials",
  seededPayload?.scripts?.every(script =>
    !("storageSnapshot" in script)
      && !("storageBridgeId" in script)
      && !("menuBridgeId" in script)
      && !("xhrBridgeId" in script)
      && !("portBridgeId" in script)
  ),
);

let resolveWarmReply;
const warmReply = new Promise((resolve) => { resolveWarmReply = resolve; });
const warmWrapperIndex = appendedScripts.length;
const warmSandbox = buildContentScriptSandbox(
  seededCache, [], "https://discord.com/app", [], false,
  (msg) => (msg.action === "getUserScripts" || msg.action === "validateUserScriptExecution") ? warmReply : { ok: true },
);
vm.createContext(warmSandbox);
vm.runInContext(source, warmSandbox, { filename: "userscript-injector-warm-start.js" });
await tick();
await tick();
const warmWrapper = appendedScripts[warmWrapperIndex] || "";
check("official Discord wildcard warm-starts on the root discord.com host", warmWrapper.length > 700 * 1024);
let warmPageExecutionSucceeded = true;
try {
  vm.runInContext(warmWrapper, warmSandbox, { filename: "userscript-injector-warm-page.js" });
} catch {
  warmPageExecutionSucceeded = false;
}
check("cached page-world script executes before native responses resolve", warmPageExecutionSucceeded && warmSandbox.__warmPageExecuted === true);
check("warm-start execution sends no validation request", !warmSandbox.__sentMessages.some(message => message.action === "validateUserScriptExecution"));
check("large warm-start payload executes once before native resolves", appendedScripts.slice(warmWrapperIndex).length === 1);

// Dark Reader is the sole content-world warm path. Its descriptor carries the
// native-generated digest, so the page-controlled cache cannot authorize altered
// content before native validation.
const darkReaderSourceURL = "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/dark-reader/dist/dark-reader.user.js";
const darkReaderContent = "globalThis.__darkReaderContentExecuted = true;";
const darkReaderDigestBytes = await webcrypto.subtle.digest("SHA-256", new TextEncoder().encode(darkReaderContent));
const darkReaderDigest = Buffer.from(darkReaderDigestBytes).toString("hex");
const darkReaderScript = {
  ...fakeScript,
  id: "dark-reader-content",
  name: "Dark Reader",
  content: darkReaderContent,
  sourceURL: darkReaderSourceURL,
  injectInto: "content",
  contentDigest: darkReaderDigest,
};
const malformedContentCache = JSON.stringify({ version: 1, savedAt: Date.now(), scripts: [{ ...darkReaderScript, contentDigest: "" }] });
const malformedContentSandbox = buildContentScriptSandbox(
  malformedContentCache, [], "https://example.com/page", [], false,
  (msg) => msg.action === "getUserScripts" ? new Promise(() => {}) : { ok: true },
);
vm.createContext(malformedContentSandbox);
vm.runInContext(source, malformedContentSandbox, { filename: "userscript-injector-dark-reader-malformed.js" });
await tick();
check("malformed Dark Reader content cache is rejected", !malformedContentSandbox.__sentMessages.some((m) => m.action === "validateUserScriptExecution"));

const tamperedContentSandbox = buildContentScriptSandbox(
  JSON.stringify({ version: 1, savedAt: Date.now(), scripts: [{
    ...darkReaderScript,
    content: "globalThis.__darkReaderTamperedExecuted = true;",
  }] }),
  [], "https://example.com/page", [], false,
  (msg) => msg.action === "getUserScripts" ? new Promise(() => {}) : { ok: true },
);
vm.createContext(tamperedContentSandbox);
vm.runInContext(source, tamperedContentSandbox, { filename: "userscript-injector-dark-reader-tampered.js" });
await tick();
await tick();
check("altered cached bytes fail before native validation", !tamperedContentSandbox.__sentMessages.some((m) => m.action === "validateUserScriptExecution"));
check("altered cached bytes never execute in the content world", tamperedContentSandbox.__darkReaderTamperedExecuted !== true);

let resolveDarkReaderValidation;
const darkReaderValidation = new Promise((resolve) => { resolveDarkReaderValidation = resolve; });
const darkReaderSandbox = buildContentScriptSandbox(
  JSON.stringify({ version: 1, savedAt: Date.now(), scripts: [darkReaderScript] }),
  [], "https://example.com/page", [], false,
  (msg) => {
    if (msg.action === "validateUserScriptExecution") return darkReaderValidation;
    if (msg.action === "getUserScripts") return new Promise(() => {});
    return { ok: true };
  },
);
vm.createContext(darkReaderSandbox);
vm.runInContext(source, darkReaderSandbox, { filename: "userscript-injector-dark-reader-content.js" });
await tick();
const darkReaderActions = darkReaderSandbox.__sentMessages.map((m) => m.action);
check("exact Dark Reader content candidate validates before getUserScripts", darkReaderActions[0] === "validateUserScriptExecution" && darkReaderActions[1] === "getUserScripts");
check("Dark Reader validation includes the digest of its exact cached bytes", darkReaderSandbox.__sentMessages[0]?.contentDigest === darkReaderDigest);
check("content warm start does not execute before validation", darkReaderSandbox.__darkReaderContentExecuted !== true);
resolveDarkReaderValidation({ ok: true });
for (let i = 0; i < 10; i++) await tick();
check("content warm start executes after validation succeeds", darkReaderSandbox.__darkReaderContentExecuted === true);
check("content warm start has no released XHR privilege before reconciliation", !darkReaderSandbox.__sentMessages.some((m) => m.action === "gmXmlhttpRequest"));

let resolveRejectedValidation;
const rejectedValidation = new Promise((resolve) => { resolveRejectedValidation = resolve; });
const rejectedDarkReaderSandbox = buildContentScriptSandbox(
  JSON.stringify({ version: 1, savedAt: Date.now(), scripts: [darkReaderScript] }),
  [], "https://example.com/page", [], false,
  (msg) => msg.action === "validateUserScriptExecution" ? rejectedValidation : new Promise(() => {}),
);
vm.createContext(rejectedDarkReaderSandbox);
vm.runInContext(source, rejectedDarkReaderSandbox, { filename: "userscript-injector-dark-reader-rejected.js" });
await tick();
resolveRejectedValidation({ ok: false, error: "userscript-integrity-mismatch" });
await tick();
await tick();
check("digest rejection prevents content warm execution", rejectedDarkReaderSandbox.__darkReaderContentExecuted !== true);

let resolveStaleValidation;
const staleValidation = new Promise((resolve) => { resolveStaleValidation = resolve; });
const staleValidatedSandbox = buildContentScriptSandbox(
  JSON.stringify({ version: 1, savedAt: Date.now(), scripts: [darkReaderScript] }),
  [], "https://example.com/page", [], false,
  (msg) => msg.action === "validateUserScriptExecution" ? staleValidation : new Promise(() => {}),
);
vm.createContext(staleValidatedSandbox);
vm.runInContext(source, staleValidatedSandbox, { filename: "userscript-injector-dark-reader-stale-validation.js" });
await tick();
await staleValidatedSandbox.__onMessage({ type: "wblock:clearDocumentStartSessionCache" });
resolveStaleValidation({ ok: true });
await tick();
await tick();
check("invalidation prevents an older successful validation from executing", staleValidatedSandbox.__darkReaderContentExecuted !== true);
const warmToken = (warmWrapper.match(/const xhrBridgeId = '([^']*)';/) || [])[1] || "";
const warmPortMatch = warmWrapper.match(/const portBridgeId = '([^']*)';/);
check("quarantined warm start receives no runtime-port token", !!warmPortMatch && warmPortMatch[1] === "");
warmSandbox.__listeners = windowMessageListeners;
vm.runInContext(`globalThis.__fire = (data) => { for (const fn of globalThis.__listeners) fn({ source: window, data }); };`, warmSandbox);
vm.runInContext(`__fire({ type: 'wblock-gm-xhr-request', id: 'warm', bridgeId: ${JSON.stringify(warmToken)}, url: 'https://queued.example/' });`, warmSandbox);
await tick();
check(
  "provisional warm-start XHR waits for native verification",
  !warmSandbox.__sentMessages.some(message => message.action === "gmXmlhttpRequest"),
);
resolveWarmReply({ userScripts: [largeWarmScript], documentStartCacheAllowed: false });
await tick();
await tick();
await tick();
check("exact authority preserves the single warm-start execution", appendedScripts.slice(warmWrapperIndex).length === 1);
check(
  "exact authority flushes the quarantined XHR once",
  warmSandbox.__sentMessages.filter(message => message.action === "gmXmlhttpRequest" && message.url === "https://queued.example/").length === 1,
);

let resolveSubdomainReply;
const subdomainReply = new Promise((resolve) => { resolveSubdomainReply = resolve; });
const subdomainWrapperIndex = appendedScripts.length;
const subdomainSandbox = buildContentScriptSandbox(
  seededCache, [], "https://canary.discord.com/channels/1/2", [], false,
  (msg) => msg.action === "getUserScripts" ? subdomainReply : { ok: true },
);
vm.createContext(subdomainSandbox);
vm.runInContext(source, subdomainSandbox, { filename: "userscript-injector-warm-subdomain.js" });
await tick();
await tick();
check(
  "official Discord wildcard warm-starts on Discord subdomains",
  (appendedScripts[subdomainWrapperIndex] || "").length > 700 * 1024,
);
resolveSubdomainReply({ userScripts: [], documentStartCacheAllowed: false });
await tick();

const tamperedScript = {
  ...largeWarmScript,
  resourceContents: { unexpected: "page-controlled descriptor field" },
};
let resolveTamperedReply;
const tamperedReply = new Promise((resolve) => { resolveTamperedReply = resolve; });
const tamperedWrapperIndex = appendedScripts.length;
const tamperedSandbox = buildContentScriptSandbox(
  JSON.stringify({ version: 1, savedAt: Date.now(), scripts: [tamperedScript] }),
  [], "https://discord.com/app", [], false,
  (msg) => msg.action === "getUserScripts" ? tamperedReply : { ok: true },
);
vm.createContext(tamperedSandbox);
vm.runInContext(source, tamperedSandbox, { filename: "userscript-injector-warm-tampered.js" });
await tick();
await tick();
const tamperedWrapper = appendedScripts[tamperedWrapperIndex] || "";
const tamperedToken = (tamperedWrapper.match(/const xhrBridgeId = '([^']*)';/) || [])[1] || "";
tamperedSandbox.__listeners = windowMessageListeners;
vm.runInContext(`globalThis.__fire = (data) => { for (const fn of globalThis.__listeners) fn({ source: window, data }); };`, tamperedSandbox);
vm.runInContext(`__fire({ type: 'wblock-gm-xhr-request', id: 'tampered', bridgeId: ${JSON.stringify(tamperedToken)}, url: 'https://tampered.example/' });`, tamperedSandbox);
resolveTamperedReply({ userScripts: [largeWarmScript], documentStartCacheAllowed: false });
await tick();
await tick();
check(
  "tampered warm-start descriptor never receives XHR authority",
  !tamperedSandbox.__sentMessages.some(message => message.action === "gmXmlhttpRequest" && message.url === "https://tampered.example/"),
);

for (const [label, cache] of [
  ["expired", { version: 1, savedAt: Date.now() - 31 * 60 * 1000, scripts: [largeWarmScript] }],
  ["oversized", { version: 1, savedAt: Date.now(), scripts: [{ ...largeWarmScript, content: "x".repeat(2 * 1024 * 1024 + 1) }] }],
  ["disabled host", { version: 1, savedAt: Date.now(), scripts: [{ ...largeWarmScript, disabledHosts: ["discord.com"] }] }],
  ["resource privileged", { version: 1, savedAt: Date.now(), scripts: [{ ...largeWarmScript, resourceNames: ["payload"] }] }],
  ["storage snapshot", { version: 1, savedAt: Date.now(), scripts: [{ ...largeWarmScript, storageSnapshot: { secret: "page-controlled" } }] }],
  ["forged bridge", { version: 1, savedAt: Date.now(), scripts: [{ ...largeWarmScript, portBridgeId: "page-controlled" }] }],
]) {
  const wrapperIndex = appendedScripts.length;
  const sandbox = buildContentScriptSandbox(JSON.stringify(cache), [], "https://discord.com/app", [], false);
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename: `userscript-injector-warm-${label.replaceAll(" ", "-")}.js` });
  await tick();
  await tick();
  check(`${label} warm-start cache is rejected`, appendedScripts.length === wrapperIndex);
}

// (a) An arbitrary page script posting without a valid token is ignored.
const beforeBad = gmXhrCalls().length;
vm.runInContext(
  `__fire({ type: 'wblock-gm-xhr-request', id: 'spoof-1', bridgeId: 'gmxhr-not-a-real-token', url: 'https://evil.example/', method: 'GET' });`,
  contentSandbox,
);
await tick();
check("XHR bridge rejects a request with an unknown token", gmXhrCalls().length === beforeBad);

// (b) A request missing the token field entirely is ignored.
const beforeMissing = gmXhrCalls().length;
vm.runInContext(
  `__fire({ type: 'wblock-gm-xhr-request', id: 'spoof-2', url: 'https://evil.example/', method: 'GET' });`,
  contentSandbox,
);
await tick();
check("XHR bridge rejects a request with no token", gmXhrCalls().length === beforeMissing);

// (c) A request carrying the issued token is proxied.
vm.runInContext(
  `__fire({ type: 'wblock-gm-xhr-request', id: 'legit-1', bridgeId: ${JSON.stringify(xhrBridgeId)}, url: 'https://ok.example/', method: 'GET' });`,
  contentSandbox,
);
await tick();
check("XHR bridge accepts a request with the issued token", gmXhrCalls().some((m) => m.url === "https://ok.example/"));

// (d) Native responses are authoritative; page sessionStorage is ignored.
const authoritativeWrapperIndex = appendedScripts.length;
const authoritativeSandbox = buildContentScriptSandbox(null, [fakeScript], "https://example.com/page", []);
vm.createContext(authoritativeSandbox);
vm.runInContext(source, authoritativeSandbox, { filename: "userscript-injector-authoritative-dedup.js" });
authoritativeSandbox.__listeners = windowMessageListeners;
vm.runInContext(
  `globalThis.__fire = (data) => { for (const fn of globalThis.__listeners) fn({ source: window, data }); };`,
  authoritativeSandbox,
);
await tick();
await tick();
await tick();
await tick();
const authoritativeWrapper = appendedScripts[authoritativeWrapperIndex] || "";
const authoritativeXhrBridgeId = (authoritativeWrapper.match(/const xhrBridgeId = '([^']*)';/) || [])[1] || "";
check(
  "authoritative descriptor injects a single userscript wrapper",
  authoritativeWrapper.length > 0
    && authoritativeXhrBridgeId.length > 0
    && appendedScripts.length === authoritativeWrapperIndex + 1
);

const authoritativeWrapperCountBeforeInvalidation = appendedScripts.length;
await authoritativeSandbox.__onMessage({ type: "wblock:clearDocumentStartSessionCache" });
await tick();
await tick();
check(
  "invalidation does not hot-run a second copy of an already executed script",
  appendedScripts.length === authoritativeWrapperCountBeforeInvalidation,
);

// (e) A native invalidation creates a new request generation. An old
// authoritative reply must not execute; the post-invalidation reply may run.
const deferred = () => {
  let resolve;
  const promise = new Promise((r) => { resolve = r; });
  return { promise, resolve };
};
const oldFreshReply = deferred();
const authoritativeReply = deferred();
let freshRequestCount = 0;
const raceWrapperIndex = appendedScripts.length;
const raceSandbox = buildContentScriptSandbox(null, [], "https://example.com/page", [], true, (msg) => {
  if (msg.action === "getUserScripts") {
    freshRequestCount += 1;
    return freshRequestCount === 1 ? oldFreshReply.promise : authoritativeReply.promise;
  }
  return { ok: true };
});
vm.createContext(raceSandbox);
vm.runInContext(source, raceSandbox, { filename: "userscript-injector-generation-race.js" });
await tick();
check("invalidation race starts one authoritative request", freshRequestCount === 1);
await raceSandbox.__onMessage({ type: "wblock:clearDocumentStartSessionCache" });
check("explicit invalidation requests a new generation", freshRequestCount === 2);
oldFreshReply.resolve({ userScripts: [{ ...fakeScript, content: "window.__staleAfterClear = true;" }] });
await tick();
authoritativeReply.resolve({ userScripts: [{ ...fakeScript, content: "window.__authoritativeAfterClear = true;" }] });
await tick();
await tick();
const raceWrappers = appendedScripts.slice(raceWrapperIndex);
check("stale authoritative reply never executes after invalidation", !raceWrappers.some(wrapper => wrapper.includes("window.__staleAfterClear")));
check("post-invalidation authoritative reply executes once", raceWrappers.filter(wrapper => wrapper.includes("window.__authoritativeAfterClear")).length === 1);

// ---------------------------------------------------------------------------
// Phase 3: evaluate the wrapper as the page would, and check GM_xmlhttpRequest
// tags its request with the token + namespaced port, and that ports only accept
// messages on the namespaced channel.
// ---------------------------------------------------------------------------

const pagePosted = [];
const pageMessageListeners = [];
function buildPageSandbox() {
  const s = {};
  s.window = s;
  s.globalThis = s;
  s.top = s;
  s.self = s;
  s.location = { href: "https://example.com/page", hostname: "example.com", protocol: "https:", pathname: "/page" };
  s.addEventListener = (type, fn) => { if (type === "message") pageMessageListeners.push(fn); };
  s.removeEventListener = () => {};
  s.postMessage = (msg) => { pagePosted.push(msg); };
  s.console = { log() {}, warn() {}, error() {}, info() {}, debug() {}, trace() {} };
  s.setTimeout = setTimeout;
  s.clearTimeout = clearTimeout;
  s.atob = (b64) => Buffer.from(b64, "base64").toString("binary");
  s.crypto = webcrypto;
  s.URL = URL;
  s.Blob = class Blob { constructor(p, o) { this.parts = p; this.type = (o && o.type) || ""; } };
  s.TextDecoder = TextDecoder;
  s.TextEncoder = TextEncoder;
  s.navigator = { userAgent: "test", clipboard: { writeText: async () => {} } };
  const head = makeElement("head");
  const docEl = makeElement("html");
  s.document = {
    readyState: "complete",
    documentElement: docEl,
    head,
    body: makeElement("body"),
    createElement: makeElement,
    currentScript: makeElement("script"),
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener: () => {},
    removeEventListener: () => {},
  };
  return s;
}

const pageSandbox = buildPageSandbox();
vm.createContext(pageSandbox);
try {
  vm.runInContext(wrapperSource, pageSandbox, { filename: "wrapper.js" });
} catch (e) {
  check("wrapper evaluates without throwing", false);
  console.log("  wrapper error:", e && e.message);
}
await tick();

// In-realm dispatcher for the page context (same reason as contentSandbox).
pageSandbox.__listeners = pageMessageListeners;
vm.runInContext(
  `globalThis.__firePage = (data) => { for (const fn of globalThis.__listeners) fn({ source: window, data }); };`,
  pageSandbox,
);

const xhrRequest = pagePosted.find((m) => m && m.type === "wblock-gm-xhr-request");
check("GM_xmlhttpRequest posts a wblock-gm-xhr-request", !!xhrRequest);
check("GM_xmlhttpRequest includes the issued bridgeId", !!xhrRequest && xhrRequest.bridgeId === xhrBridgeId);
check(
  "GM_xmlhttpRequest namespaces the requested portName",
  !!xhrRequest && xhrRequest.portName === `${portBridgeId}::streamport`,
);

check("runtime port exposes the plain name to the script", pageSandbox.__portName === "streamport");

// A page script guessing the plain port name must NOT reach the port.
vm.runInContext(
  `__firePage({ type: 'wblock:gm-port-message', portName: 'streamport', message: 'SPOOFED' });`,
  pageSandbox,
);
check("port ignores messages on the plain (guessable) name", (pageSandbox.__portMessages || []).length === 0);

// The namespaced channel (what the background echoes back) must reach the port.
vm.runInContext(
  `__firePage({ type: 'wblock:gm-port-message', portName: ${JSON.stringify(`${portBridgeId}::streamport`)}, message: 'REAL' });`,
  pageSandbox,
);
check(
  "port accepts messages on the namespaced channel",
  (pageSandbox.__portMessages || []).includes("REAL"),
);

// ---------------------------------------------------------------------------
// Cold-path validation round-trips must overlap, not serialize. With several
// document-start scripts enabled, every script's validateUserScriptExecution
// must be dispatched up front so a queued script does not lose the race
// against the page's own code (issue #537).
// ---------------------------------------------------------------------------

const parallelScripts = [
  { ...fakeScript, id: "parallel-1", name: "Parallel One", content: "window.__parallelOne = true;" },
  { ...fakeScript, id: "parallel-2", name: "Parallel Two", content: "window.__parallelTwo = true;" },
];
const heldValidations = [];
const parallelWrapperBase = appendedScripts.length;
const parallelSandbox = buildContentScriptSandbox(
  null, parallelScripts, "https://example.com/page", [], true,
  (msg) => {
    if (msg.action === "getUserScripts") {
      return { userScripts: JSON.parse(JSON.stringify(parallelScripts)), documentStartCacheAllowed: true, cacheRevision };
    }
    if (msg.action === "validateUserScriptExecution") {
      return new Promise((resolve) => { heldValidations.push({ scriptId: msg.scriptId, resolve }); });
    }
    return { ok: true };
  },
);
vm.createContext(parallelSandbox);
vm.runInContext(source, parallelSandbox, { filename: "userscript-injector-parallel-validation.js" });
await tick();
await tick();
check(
  "validation for queued document-start scripts dispatches concurrently",
  heldValidations.length === 2,
);
check("no script executes before its validation resolves", appendedScripts.length === parallelWrapperBase);
// Resolve out of order: execution must still follow the native script order.
for (const held of [...heldValidations].reverse()) held.resolve({ ok: true });
await tick();
await tick();
const parallelWrappers = appendedScripts.slice(parallelWrapperBase);
check("both scripts execute once validations resolve", parallelWrappers.length === 2);
check(
  "execution preserves native order despite out-of-order validation replies",
  (parallelWrappers[0] || "").includes("__parallelOne") && (parallelWrappers[1] || "").includes("__parallelTwo"),
);

// ---------------------------------------------------------------------------
// Local page-world document-start scripts are warm-start eligible: they
// execute quarantined with page authority before any native response, the
// same as remote page-world scripts (issue #537).
// ---------------------------------------------------------------------------

const localScript = {
  ...fakeScript,
  id: "local-gtm-dummy",
  name: "GTM Dummy Injector",
  content: "window.__localWarmExecuted = true;",
  sourceURL: "",
  isLocal: true,
  grant: [],
};
const localSeedSandbox = buildContentScriptSandbox(null, [localScript], "https://example.com/page");
vm.createContext(localSeedSandbox);
vm.runInContext(source, localSeedSandbox, { filename: "userscript-injector-local-warm-seed.js" });
await tick();
await tick();
const localSeededCache = localSeedSandbox.__localValues.get("__wblock_warm_start_v1") || "";
const localSeededPayload = localSeededCache ? JSON.parse(localSeededCache) : null;
check(
  "authoritative response seeds a local page-world script into the warm-start cache",
  localSeededPayload?.scripts?.some((script) => script.id === localScript.id) === true,
);

const localWarmWrapperIndex = appendedScripts.length;
const localWarmSandbox = buildContentScriptSandbox(
  localSeededCache, [localScript], "https://example.com/page", [], true,
  (msg) => (msg.action === "getUserScripts" ? new Promise(() => {}) : { ok: true }),
);
vm.createContext(localWarmSandbox);
vm.runInContext(source, localWarmSandbox, { filename: "userscript-injector-local-warm-start.js" });
await tick();
const localWarmWrapper = appendedScripts[localWarmWrapperIndex] || "";
check("local script warm-starts before any native response", localWarmWrapper.includes("__localWarmExecuted"));
let localWarmExecutionSucceeded = true;
try {
  vm.runInContext(localWarmWrapper, localWarmSandbox, { filename: "userscript-injector-local-warm-page.js" });
} catch {
  localWarmExecutionSucceeded = false;
}
check(
  "cached local page payload executes with page authority",
  localWarmExecutionSucceeded && localWarmSandbox.__localWarmExecuted === true,
);
check(
  "local warm start sends no validation request",
  !localWarmSandbox.__sentMessages.some((message) => message.action === "validateUserScriptExecution"),
);

// #670: userstyles warm-start from the page cache so dark CSS lands before
// first paint, then native digest validation confirms or removes it.
const styleCSS = "html { background: #000 !important; color: #eee !important; }";
const styleDigest = Buffer.from(await webcrypto.subtle.digest("SHA-256", new TextEncoder().encode(styleCSS))).toString("hex");
const cachedStyle = {
  id: "user-style-1", name: "Dark Example", kind: "style", content: styleCSS,
  sourceURL: "https://styles.test/dark.user.css", isLocal: false, matches: ["https://example.com/*"],
  injectInto: "content", runAt: "document-start", isEnabled: true, payloadRevision: 0,
  contentDigest: styleDigest, cacheCategory: "bundled", cacheRevision,
};
const styleElementsIn = (sandbox) => sandbox.document.head.children.filter((c) => c.tagName === "STYLE" && c.parentNode);

let resolveStyleValidation;
const styleValidation = new Promise((resolve) => { resolveStyleValidation = resolve; });
const styleSandbox = buildContentScriptSandbox(
  JSON.stringify({ version: 1, savedAt: Date.now(), scripts: [cachedStyle] }),
  [], "https://example.com/page", [], false,
  (msg) => msg.action === "validateUserScriptExecution" ? styleValidation : new Promise(() => {}),
);
vm.createContext(styleSandbox);
vm.runInContext(source, styleSandbox, { filename: "userscript-injector-style-warm.js" });
for (let i = 0; i < 6; i++) await tick();
check("cached userstyle is applied before native validation resolves", styleElementsIn(styleSandbox).length === 1 && styleElementsIn(styleSandbox)[0].textContent === styleCSS);
check("userstyle warm start validates with its content digest", styleSandbox.__sentMessages.some((m) => m.action === "validateUserScriptExecution" && m.contentDigest === styleDigest));
resolveStyleValidation({ ok: true });
for (let i = 0; i < 10; i++) await tick();
check("validated userstyle stays applied exactly once", styleElementsIn(styleSandbox).length === 1);

let resolveStyleRejection;
const styleRejection = new Promise((resolve) => { resolveStyleRejection = resolve; });
const rejectedStyleSandbox = buildContentScriptSandbox(
  JSON.stringify({ version: 1, savedAt: Date.now(), scripts: [cachedStyle] }),
  [], "https://example.com/page", [], false,
  (msg) => msg.action === "validateUserScriptExecution" ? styleRejection : new Promise(() => {}),
);
vm.createContext(rejectedStyleSandbox);
vm.runInContext(source, rejectedStyleSandbox, { filename: "userscript-injector-style-rejected.js" });
for (let i = 0; i < 6; i++) await tick();
check("rejected userstyle was applied provisionally", styleElementsIn(rejectedStyleSandbox).length === 1);
resolveStyleRejection({ ok: false, error: "userscript-integrity-mismatch" });
for (let i = 0; i < 10; i++) await tick();
check("rejected userstyle is removed after native validation fails", styleElementsIn(rejectedStyleSandbox).length === 0);

const noDigestStyleSandbox = buildContentScriptSandbox(
  JSON.stringify({ version: 1, savedAt: Date.now(), scripts: [{ ...cachedStyle, contentDigest: undefined }] }),
  [], "https://example.com/page", [], false,
  () => new Promise(() => {}),
);
vm.createContext(noDigestStyleSandbox);
vm.runInContext(source, noDigestStyleSandbox, { filename: "userscript-injector-style-nodigest.js" });
for (let i = 0; i < 6; i++) await tick();
check("userstyle without a digest never warm-starts", styleElementsIn(noDigestStyleSandbox).length === 0);

console.log(failures === 0 ? "\nAll checks passed." : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
