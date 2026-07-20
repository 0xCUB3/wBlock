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
  injectInto: "page",
  runAt: "document-start",
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

function buildContentScriptSandbox() {
  const head = makeElement("head");
  head.appendChild = (c) => {
    head.children.push(c);
    c.parentNode = head;
    if (c.textContent) appendedScripts.push(c.textContent);
    return c;
  };
  const docEl = makeElement("html");
  docEl.appendChild = head.appendChild;

  const sandbox = {};
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.top = sandbox;
  sandbox.self = sandbox;
  sandbox.location = { href: "https://example.com/page", hostname: "example.com", protocol: "https:" };
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
        if (msg.action === "getUserScripts") return { userScripts: [fakeScript] };
        if (msg.action === "gmXmlhttpRequest") {
          return { status: 200, responseText: "OK", responseHeaders: "", finalUrl: msg.url };
        }
        return { ok: true };
      },
      onMessage: { addListener() {} },
      connect: () => ({ onMessage: { addListener() {} }, onDisconnect: { addListener() {} }, postMessage() {}, disconnect() {} }),
    },
  };
  return sandbox;
}

const contentSandbox = buildContentScriptSandbox();
vm.createContext(contentSandbox);
vm.runInContext(source, contentSandbox, { filename: "userscript-injector.js" });

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

// ---------------------------------------------------------------------------
// Phase 2: the engine-level XHR bridge must gate on the issued token.
// ---------------------------------------------------------------------------

const gmXhrCalls = () => sentMessages.filter((m) => m && m.action === "gmXmlhttpRequest");

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
