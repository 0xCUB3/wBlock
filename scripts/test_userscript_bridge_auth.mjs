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
  contentSandbox.__sessionStorageWrites.every(([key]) => key === "__wblock_warm_start_v1")
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
    && freshIOSSandbox.__sessionStorageWrites.some(([key]) => key === "__wblock_warm_start_v1")
);

// A Vencord-sized page-world payload must be seeded even when iOS reports that
// trusted document-start caching is unavailable. On the next navigation it may
// execute with page authority, while extension privileges remain quarantined.
const largeWarmScript = {
  ...fakeScript,
  id: "vencord-like",
  name: "Vencord",
  namespace: "https://github.com/Vendicated/Vencord",
  content: USER_SCRIPT_CONTENT + "\n/*" + "x".repeat(700 * 1024) + "*/",
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
const seededCache = seedSandbox.__sessionValues.get("__wblock_warm_start_v1") || "";
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
  (msg) => msg.action === "getUserScripts" ? warmReply : { ok: true },
);
vm.createContext(warmSandbox);
vm.runInContext(source, warmSandbox, { filename: "userscript-injector-warm-start.js" });
await tick();
await tick();
const warmWrapper = appendedScripts[warmWrapperIndex] || "";
check("official Discord wildcard warm-starts on the root discord.com host", warmWrapper.length > 700 * 1024);
check("large warm-start payload executes once before native resolves", appendedScripts.slice(warmWrapperIndex).length === 1);
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

console.log(failures === 0 ? "\nAll checks passed." : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
