// The first page after Safari starts (or after a profile switch) must still get
// its userscripts. The page's warm-start cache then holds a copy stamped with a
// revision from an earlier native host. Native rejects that copy, and the
// authoritative reply for the same script arrives while the rejection is still
// on its way.
//
// Run: node scripts/test_userscript_cold_start.mjs [path/to/userscript-injector.js]

import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { webcrypto } from "node:crypto";
import { fileURLToPath } from "node:url";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = readFileSync(process.argv[2]
  ?? path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "userscript-injector.js"), "utf8");

let failures = 0;
const check = (name, condition) => {
  console.log(`${condition ? "PASS" : "FAIL"}: ${name}`);
  if (!condition) failures += 1;
};
const settle = async () => { for (let i = 0; i < 5; i += 1) await new Promise(resolve => setTimeout(resolve, 10)); };

const hideShorts = {
  id: "hide-shorts",
  name: "Hide Shorts",
  content: "window.__hideShortsRuns = (window.__hideShortsRuns || 0) + 1;",
  sourceURL: "https://scripts.test/hide-shorts.user.js",
  isLocal: false,
  matches: ["https://www.youtube.com/*"],
  grant: ["none"],
  injectInto: "page",
  runAt: "document-start",
  isEnabled: true,
};

// One page load against a native host at revision `hostRevision`. The page
// cached the script under `cachedRevision` (null for no cache). Validation
// answers only when the test releases it, as a host that is still starting
// does. `staleReplies` is how many replies carry a revision that native has
// already left behind, as when the script list changes right after the reply.
function loadPage({ cachedRevision, hostRevision, staleReplies = 0 }) {
  const injected = [];
  const makeElement = tag => ({
    tagName: String(tag).toUpperCase(), textContent: "", attributes: {}, children: [], style: {},
    setAttribute(key, value) { this.attributes[key] = value; },
    getAttribute(key) { return this.attributes[key] ?? null; },
    removeAttribute(key) { delete this.attributes[key]; },
    appendChild(child) { this.children.push(child); return child; },
    remove() {}, addEventListener() {}, removeEventListener() {},
  });
  const root = makeElement("html");
  root.appendChild = child => {
    const probe = child.textContent.match(/^document\.documentElement\.setAttribute\('([^']+)', '1'\)$/);
    if (probe) root.setAttribute(probe[1], "1");
    else if (child.attributes["data-userscript"]) injected.push(child.attributes["data-userscript"]);
    return child;
  };
  const head = makeElement("head");
  head.appendChild = root.appendChild;

  const storage = values => ({
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: key => values.delete(key),
  });
  const sent = [];
  const validations = [];
  const sandbox = {
    queueMicrotask, setTimeout, clearTimeout, URL, TextEncoder, TextDecoder, crypto: webcrypto,
    console: { log() {}, warn() {}, error() {}, info() {} },
    location: { href: "https://www.youtube.com/", hostname: "www.youtube.com", protocol: "https:", pathname: "/" },
    addEventListener() {}, removeEventListener() {}, postMessage() {},
    sessionStorage: storage(new Map()),
    localStorage: storage(new Map(cachedRevision === null ? [] : [["__wblock_warm_start_v1", JSON.stringify({
      version: 1, savedAt: Date.now(), scripts: [{ ...hideShorts, payloadRevision: cachedRevision }],
    })]])),
    document: {
      readyState: "loading", documentElement: root, head, body: null, createElement: makeElement,
      querySelector: () => null, querySelectorAll: () => [], addEventListener() {}, removeEventListener() {},
    },
    browser: { runtime: {
      onMessage: { addListener() {}, removeListener() {} },
      sendMessage: message => {
        sent.push(message.action);
        if (message.action === "getUserScripts") {
          const payloadRevision = staleReplies-- > 0 ? hostRevision - 1 : hostRevision;
          return Promise.resolve({ userScripts: [{ ...hideShorts, payloadRevision }] });
        }
        if (message.action === "validateUserScriptExecutions") {
          return new Promise(resolve => validations.push(() => resolve({
            results: message.scripts.map(script => script.payloadRevision === hostRevision
              ? { ok: true } : { ok: false, error: "userscript-state-changed" }),
          })));
        }
        return Promise.resolve({ ok: true });
      },
    } },
  };
  sandbox.window = sandbox.globalThis = sandbox.top = sandbox.self = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename: "userscript-injector.js" });
  const cachedRevisions = () => JSON.parse(sandbox.localStorage.getItem("__wblock_warm_start_v1") || '{"scripts":[]}')
    .scripts.map(script => script.payloadRevision);
  // Each round answers the validations asked so far and lets the page react.
  const finish = async () => {
    for (let round = 0; round < 4; round += 1) {
      await settle();
      while (validations.length) validations.shift()();
    }
    await settle();
  };
  return { injected, sent, cachedRevisions, finish, requests: () => sent.filter(action => action === "getUserScripts").length };
}

// The native host restarted: its revision counter no longer matches the cache.
const cold = loadPage({ cachedRevision: 7, hostRevision: 1 });
await settle();
check("cold start: the cached copy waits for native validation", cold.sent[0] === "validateUserScriptExecutions"
  && cold.injected.length === 0);
check("cold start: the authoritative reply arrives while that validation is pending", cold.sent.includes("getUserScripts"));
await cold.finish();
check("cold start: the script runs once the stale cached copy is rejected", cold.injected.length === 1);
check("cold start: the page cache now holds the copy the host accepts, so a reload starts warm",
  cold.cachedRevisions().join() === "1");

// The same host as before: the cached copy validates, and the authoritative
// copy of the same script must not run as well.
const warm = loadPage({ cachedRevision: 1, hostRevision: 1 });
await warm.finish();
check("warm start: a validated cached copy runs exactly once", warm.injected.length === 1);
check("warm start: nothing is requested again", warm.requests() === 1);

// The script list changed between the reply and its validation: the fresh copy
// is rejected too, and the page must ask once more.
const changed = loadPage({ cachedRevision: null, hostRevision: 2, staleReplies: 1 });
await changed.finish();
check("changed list: a rejected fresh copy is requested again and runs once",
  changed.requests() === 2 && changed.injected.length === 1);

// A host that keeps rejecting must not be asked forever.
const rejecting = loadPage({ cachedRevision: null, hostRevision: 2, staleReplies: Infinity });
await rejecting.finish();
check("changed list: a copy rejected again is not requested a third time",
  rejecting.requests() === 2 && rejecting.injected.length === 0);

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nAll userscript cold-start checks passed");
