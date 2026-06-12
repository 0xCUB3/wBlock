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

function makeSandbox({ nativeRules, nativeDisabled, localStorageSeed = {} }) {
  const native = {
    rules: [...nativeRules],
    disabled: nativeDisabled,
    setDisabledCalls: [],
  };
  const storage = new Map(Object.entries(localStorageSeed));
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
        return { ok: true, rules: [...native.rules], disabled: native.disabled };
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
  const browserStub = {
    i18n: { getMessage: (key) => key },
    storage: {
      local: {
        get: async (key) => {
          const keys = Array.isArray(key) ? key : [key];
          const out = {};
          for (const k of keys) {
            if (storage.has(k)) out[k] = storage.get(k);
          }
          return out;
        },
        set: async (items) => {
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
        return {};
      },
      sendNativeMessage: async (_appId, message) => handleNativeAction(message),
      onMessage: {
        addListener: (fn) => {
          onMessageListener = fn;
        },
      },
    },
  };

  const windowStub = {
    setInterval: () => 1,
    clearInterval: () => {},
    addEventListener() {},
    location: { hostname: HOST, protocol: "https:" },
  };

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
  const env = makeSandbox({ nativeRules: [".ad-banner", "#promo"], nativeDisabled: false });
  loadScript(env.sandbox);

  const applied = await waitFor(() => (env.styleText() ?? "").includes(".ad-banner"));
  check("applies native rules as display:none CSS when enabled", applied);
  check(
    "generated CSS hides every selector",
    (env.styleText() ?? "").includes("#promo { display: none !important; }")
  );

  env.native.disabled = true;
  env.sendRuntimeMessage({ type: "wblock:zapper:reloadRules" });
  const cleared = await waitFor(() => env.styleText() === "");
  check("clears applied hiding when native flag flips to disabled", cleared);

  const metaCached = await waitFor(() => {
    const meta = env.storage.get(`wblock.zapperMeta.v1:${HOST}`);
    return meta && meta.disabled === true;
  });
  check("caches the disabled flag in local meta for early paint", metaCached);
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

if (failures > 0) {
  console.error(`\n${failures} zapper site-disable check(s) failed`);
  process.exit(1);
}
console.log("\nAll zapper site-disable checks passed");
process.exit(0);
