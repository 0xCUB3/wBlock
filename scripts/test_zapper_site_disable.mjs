// Behavioral check for zapper-content.js per-site disable handling:
// - applies saved rules as a <style> element when enabled
// - suppresses/clears hiding when the native protobuf flag says disabled
// - migrates the legacy local-only disabled key to native exactly once
//
// Run: node scripts/test_zapper_site_disable.mjs [path/to/zapper-content.js]

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const scriptPath = process.argv[2]
  ?? path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "zapper-content.js");
const source = readFileSync(scriptPath, "utf8");

let failures = 0;
const check = (name, cond) => {
  console.log(`${cond ? "PASS" : "FAIL"}: ${name}`);
  if (!cond) failures += 1;
};

const HOST = "example.com";
const STYLE_ID = "wblock-zapper-style";
const LEGACY_KEY = `wblock.zapperRulesDisabled.v1:${HOST}`;

function makeSandbox({ nativeRules, nativeDisabled, inheritedRules = [], localStorageSeed = {}, isTopFrame = true, getRulesDelayMs = 0, siteStateDelayMs = 0, broadcastReload = null }) {
  const native = {
    rules: [...nativeRules],
    disabled: nativeDisabled,
    setDisabledCalls: [],
    getRulesCalls: 0,
    siteStateCalls: 0,
  };
  const storage = new Map(Object.entries(localStorageSeed));
  const storageCalls = {get:0, set:0};
  const elementsById = new Map();

  const makeStyleElement = (id) => ({
    id,
    textContent: "",
    appendChild() {},
  });

  const documentStub = {
    getElementById: (id) => elementsById.get(id) ?? null,
    createElement: (tag) => {
      const el = makeStyleElement("");
      el.tagName = tag;
      return el;
    },
    documentElement: {
      appendChild: (el) => {
        elementsById.set(el.id, el);
      },
    },
    querySelectorAll: () => [],
    addEventListener() {},
  };

  const handleNativeAction = (message) => {
    switch (message.action) {
      case "getZapperRules":
        native.getRulesCalls += 1;
        if (getRulesDelayMs > 0) {
          return new Promise((resolve) => setTimeout(() => resolve({
            ok: true,
            rules: [...native.rules],
            disabled: native.disabled
          }), getRulesDelayMs));
        }
        return { ok: true, rules: [...native.rules], inheritedRules, disabled: native.disabled };
      case "setSiteZapperDisabled":
        native.disabled = Boolean(message.disabled);
        native.setDisabledCalls.push({ hostname: message.hostname, disabled: native.disabled });
        return { ok: true, disabled: native.disabled };
      case "syncZapperRules":
        native.rules = [...(message.rules ?? [])];
        return { ok: true, rules: [...native.rules] };
      case "getSiteDisabledState":
        return { disabled: false };
      default:
        return {};
    }
  };

  let onMessageListener = null;
  const intervalDelays = [];
  const intervalCallbacks = [];
  const browserStub = {
    i18n: { getMessage: (key) => key },
    storage: {
      local: {
        get: async (key) => {
          storageCalls.get += 1;
          const keys = Array.isArray(key) ? key : [key];
          const out = {};
          for (const k of keys) {
            if (storage.has(k)) out[k] = storage.get(k);
          }
          return out;
        },
        set: async (items) => {
          storageCalls.set += 1;
          for (const [k, v] of Object.entries(items)) storage.set(k, v);
        },
        remove: async (key) => {
          const keys = Array.isArray(key) ? key : [key];
          for (const k of keys) storage.delete(k);
        },
      },
    },
    runtime: {
      // Background bridge: forwards zapper messages to native verbatim.
      sendMessage: async (message) => {
        if (message.action === "wblock:zapper:getRules") {
          return handleNativeAction({ ...message, action: "getZapperRules" });
        }
        if (message.action === "wblock:zapper:syncRules") {
          return handleNativeAction({ ...message, action: "syncZapperRules" });
        }
        if (message.action === "wblock:zapper:setDisabled") {
          return handleNativeAction({ ...message, action: "setSiteZapperDisabled" });
        }
        if (message.action === "wblock:getSiteDisabledState") {
          native.siteStateCalls += 1;
          if (siteStateDelayMs) await new Promise(resolve => setTimeout(resolve, siteStateDelayMs));
          return { ok: true, ...handleNativeAction({ ...message, action: "getSiteDisabledState" }) };
        }
        if (message.action === "wblock:zapper:broadcastReload") {
          if (typeof broadcastReload === 'function') return broadcastReload();
          return { ok: true };
        }
        return {};
      },
      onMessage: {
        addListener: (fn) => {
          onMessageListener = fn;
        },
      },
    },
  };

  const windowStub = {
    setInterval: (fn, delay) => { intervalDelays.push(delay); intervalCallbacks.push(fn); return 1; },
    clearInterval: () => {},
    addEventListener() {},
    location: { hostname: HOST, protocol: "https:" },
  };
  windowStub.top = isTopFrame ? windowStub : {};

  const sandbox = {
    browser: browserStub,
    document: documentStub,
    window: windowStub,
    location: windowStub.location,
    setTimeout,
    clearTimeout,
    setInterval: windowStub.setInterval,
    clearInterval: windowStub.clearInterval,
    console,
    Promise,
    Date,
    Math,
    Number,
    Array,
    Set,
    Map,
    String,
    Boolean,
    Object,
    JSON,
  };
  sandbox.globalThis = sandbox;

  return {
    sandbox,
    native,
    storage,
    storageCalls,
    intervalDelays,
    intervalCallbacks,
    styleText: () => elementsById.get(STYLE_ID)?.textContent ?? null,
    sendRuntimeMessage: (message) => onMessageListener?.(message),
  };
}

async function waitFor(predicate, timeoutMs = 2000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (predicate()) return true;
    await new Promise((r) => setTimeout(r, 10));
  }
  return predicate();
}

function loadScript(sandbox) {
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename: "zapper-content.js" });
}

// Scenario 1+2: enabled rules apply, then native disable + reloadRules clears them.
{
  const env = makeSandbox({ nativeRules: [".ad-banner", "#promo"], nativeDisabled: false,
    localStorageSeed: { [`wblock.zapperRules.v1:${HOST}`]: { corrupt: true } } });
  loadScript(env.sandbox);

  const applied = await waitFor(() => (env.styleText() ?? "").includes(".ad-banner"));
  check("applies native rules as display:none CSS when enabled", applied);
  check(
    "generated CSS hides every selector",
    (env.styleText() ?? "").includes("#promo { display: none !important; }")
  );

  env.native.disabled = true;
  const firstReload = env.sendRuntimeMessage({ type: "wblock:zapper:reloadRules" });
  const secondReload = env.sendRuntimeMessage({ type: "wblock:zapper:reloadRules" });
  await Promise.all([firstReload, secondReload]);
  const cleared = await waitFor(() => env.styleText() === "");
  check("clears applied hiding when native flag flips to disabled", cleared);
  check("back-to-back invalidations coalesce into one native rules fetch", env.native.getRulesCalls === 2);

  const metaCached = await waitFor(() => {
    const meta = env.storage.get(`wblock.zapperMeta.v1:${HOST}`);
    return meta && meta.disabled === true;
  });
  check("caches the disabled flag in local meta for early paint", metaCached);
  check("top frame uses only a coarse five-minute fallback poll",
    env.intervalDelays.length === 1 && env.intervalDelays[0] === 5 * 60 * 1000);
}

// Subframes are push-only and do not start periodic native refreshes.
{
  const env = makeSandbox({ nativeRules: [], nativeDisabled: false, isTopFrame: false });
  loadScript(env.sandbox);
  await new Promise((r) => setTimeout(r, 20));
  check("subframes do not start periodic rule polling", env.intervalDelays.length === 0);
  check("empty zapper startup reads storage at most twice", env.storageCalls.get <= 2);
  check("unchanged empty zapper state does not write storage", env.storageCalls.set === 0);
  check("empty zapper rules create no styles", env.styleText() === null);
  check("empty zapper rules need no site-state messages", env.native.siteStateCalls === 0);
  env.native.rules = ['.later'];
  await env.sendRuntimeMessage({ type: 'wblock:zapper:reloadRules' });
  check("an initially empty frame applies newly added rules", env.styleText().includes('.later'));
  env.native.rules = [];
  await env.sendRuntimeMessage({ type: 'wblock:zapper:reloadRules' });
  check("removing all rules clears existing CSS", env.styleText() === '');
  const stateCalls = env.native.siteStateCalls;
  await env.sendRuntimeMessage({ type: 'wblock:zapper:reloadRules' });
  check("clearing empty rules needs no site-state message", env.native.siteStateCalls === stateCalls);
}

// An empty local configuration must still apply a parent domain's rules.
{
  const env = makeSandbox({ nativeRules: [], inheritedRules: ['.parent-ad'], nativeDisabled: false, isTopFrame: false });
  loadScript(env.sandbox);
  check("empty local rules still apply inherited rules", await waitFor(() => env.styleText()?.includes('.parent-ad')));
  check("inherited rules still check site state", env.native.siteStateCalls > 0);
}

// The top-frame safety tick asks the background to broadcast a reload, so an
// iframe with no timer still refreshes when native push is unavailable.
{
  const iframe = makeSandbox({ nativeRules: [".old"], nativeDisabled: false, isTopFrame: false });
  loadScript(iframe.sandbox);
  await waitFor(() => (iframe.styleText() ?? "").includes(".old"));
  iframe.native.rules = [".fresh-frame"];

  const top = makeSandbox({
    nativeRules: [],
    nativeDisabled: false,
    broadcastReload: () => iframe.sendRuntimeMessage({ type: "wblock:zapper:reloadRules" }),
  });
  loadScript(top.sandbox);
  await new Promise((r) => setTimeout(r, 20));
  await top.intervalCallbacks[0]();
  const iframeRefreshed = await waitFor(() => (iframe.styleText() ?? "").includes(".fresh-frame"));
  check("coarse top-frame tick refreshes iframe rules through background broadcast", iframeRefreshed);
}

// An invalidation during an in-flight initial read schedules one fresh pass;
// multiple invalidations in that window still coalesce to that same pass.
{
  const env = makeSandbox({
    nativeRules: [".initial"],
    nativeDisabled: false,
    getRulesDelayMs: 30,
  });
  loadScript(env.sandbox);
  await new Promise((r) => setTimeout(r, 5));
  env.native.rules = [".updated"];
  const first = env.sendRuntimeMessage({ type: "wblock:zapper:reloadRules" });
  const second = env.sendRuntimeMessage({ type: "wblock:zapper:reloadRules" });
  await Promise.all([first, second]);
  const updated = await waitFor(() => (env.styleText() ?? "").includes(".updated"));
  check("in-flight invalidation triggers one fresh follow-up read", updated && env.native.getRulesCalls === 2);
}

// Scenario 3: disabled from the start -> rules fetched but never applied.
{
  const env = makeSandbox({ nativeRules: [".ad-banner"], nativeDisabled: true });
  loadScript(env.sandbox);

  await waitFor(() => env.styleText() !== null);
  await new Promise((r) => setTimeout(r, 50));
  check("never applies hiding when site is disabled at load", (env.styleText() ?? "") === "");
}

// Scenario 4: legacy local-only disabled key migrates to native once, then is removed.
{
  const env = makeSandbox({
    nativeRules: [".ad-banner"],
    nativeDisabled: false,
    localStorageSeed: { [LEGACY_KEY]: true },
  });
  loadScript(env.sandbox);

  const migrated = await waitFor(
    () => env.native.setDisabledCalls.some((c) => c.hostname === HOST && c.disabled === true)
  );
  check("pushes legacy local disabled flag to native", migrated);

  const legacyRemoved = await waitFor(() => !env.storage.has(LEGACY_KEY));
  check("removes the legacy key after migration", legacyRemoved);

  const suppressed = await waitFor(() => env.styleText() === "");
  check("suppresses hiding after legacy migration", suppressed);
}

// A slower native host must not look like a disabled site after 800 ms.
{
  const env = makeSandbox({ nativeRules: [".slow-ad"], nativeDisabled: false, siteStateDelayMs: 1000 });
  loadScript(env.sandbox);
  check("slow site-state lookup still applies enabled zapper rules", await waitFor(() => (env.styleText() ?? "").includes(".slow-ad"), 3000));
}

// Startup state is shared, but later reloads still ask for current native rules.
{
  const env = makeSandbox({nativeRules:['.later-ad'], nativeDisabled:false});
  env.sandbox.__wblockZapperInitialization = Promise.resolve({ok:true,rules:['.startup-ad'],inheritedRules:[],disabled:false});
  loadScript(env.sandbox);
  check('zapper consumes combined frame startup', await waitFor(() => (env.styleText() ?? '').includes('.startup-ad')));
  check('combined startup avoids a separate zapper request', env.native.getRulesCalls === 0);
}

if (failures > 0) {
  console.error(`\n${failures} zapper site-disable check(s) failed`);
  process.exit(1);
}
console.log("\nAll zapper site-disable checks passed");
process.exit(0);
