// Regression checks for #1169:
// 1. Shipped uBO set-cookie / set-cookie-reload scriptlets accept negative
//    integers (such as duckduckgo.com##+js(set-cookie, bg, -1)) and reject
//    out-of-range integers, unsupported literal values, and unsupported paths.
// 2. The parser's SAFE_COOKIE_VALUES table stays in exact sync with uBO's
//    get-safe-cookie-values.fn in resources.json.
//
// Run: node scripts/test_set_cookie_scriptlet.mjs

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const setCookieSource = readFileSync(
  path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "scriptlets", "set-cookie.js"),
  "utf8"
);
const setCookieReloadSource = readFileSync(
  path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "scriptlets", "set-cookie-reload.js"),
  "utf8"
);

function runScriptlet(source, scriptletName, calls) {
  const jar = new Map();
  let reloads = 0;
  const document = {
    baseURI: "https://duckduckgo.com/",
    location: { hostname: "duckduckgo.com", href: "https://duckduckgo.com/" },
    get cookie() {
      return [...jar.entries()].map(([k, v]) => `${k}=${v}`).join("; ");
    },
    set cookie(header) {
      const first = String(header).split(";")[0];
      const eq = first.indexOf("=");
      if (eq !== -1) jar.set(first.slice(0, eq).trim(), first.slice(eq + 1).trim());
    },
  };
  const window = {
    location: {
      hostname: "duckduckgo.com",
      href: "https://duckduckgo.com/",
      reload() { reloads += 1; },
    },
  };
  const ctx = vm.createContext({
    document,
    window,
    URL,
    Request,
    XMLHttpRequest: class XMLHttpRequest { open() {} send() {} },
    EventTarget,
    fetch: () => Promise.reject(new Error("unused")),
    console,
    __wbeScriptletCalls: { [scriptletName]: calls },
  });
  ctx.globalThis = ctx;
  vm.runInContext(source, ctx);
  return { jar, reloads };
}

// #1169: duckduckgo.com##+js(set-cookie, bg, -1) and range boundaries.
{
  const { jar } = runScriptlet(setCookieSource, "set-cookie", [
    ["bg", "-1"],
    ["min", "-32767"],
    ["max", "32767"],
    ["zero", "0"],
    ["quoted", "\"-1\""],
    ["word", "Accept"],
    ["nopath", "-1", "none"],
    ["rootpath", "-1", "/"],
  ]);
  assert.equal(jar.get("bg"), "-1");
  assert.equal(jar.get("min"), "-32767");
  assert.equal(jar.get("max"), "32767");
  assert.equal(jar.get("zero"), "0");
  assert.equal(jar.get("quoted"), "\"-1\"");
  assert.equal(jar.get("word"), "Accept");
  assert.equal(jar.get("nopath"), "-1");
  assert.equal(jar.get("rootpath"), "-1");
}

// Invalid values and paths must not set cookies.
{
  const { jar } = runScriptlet(setCookieSource, "set-cookie", [
    ["under", "-32768"],
    ["over", "32768"],
    ["plus", "+1"],
    ["badword", "not_allowed"],
    ["emptyval", ""],
    ["", "-1"],
    ["badpath", "-1", "/search"],
  ]);
  assert.equal(jar.size, 0, `unexpected cookies set: ${JSON.stringify([...jar])}`);
}

// set-cookie-reload accepts -1 and triggers one reload.
{
  const { jar, reloads } = runScriptlet(setCookieReloadSource, "set-cookie-reload", [
    ["bg", "-1"],
  ]);
  assert.equal(jar.get("bg"), "-1");
  assert.equal(reloads, 1);
}

// Keep cosmetic.rs SAFE_COOKIE_VALUES in sync with uBO's get-safe-cookie-values.fn.
{
  const resources = JSON.parse(
    readFileSync(path.join(repoRoot, "Packages", "wblock-engine", "resources", "resources.json"), "utf8")
  );
  const safeFn = resources.find(r => r.name === "get-safe-cookie-values.fn");
  assert.ok(safeFn, "missing get-safe-cookie-values.fn in resources.json");
  const fnSource = Buffer.from(safeFn.content, "base64").toString("utf8");
  const uboValues = Array.from(vm.runInNewContext(`${fnSource}; getSafeCookieValuesFn();`));

  const cosmeticRs = readFileSync(
    path.join(repoRoot, "Packages", "wblock-engine", "crates", "wbe", "src", "parse", "cosmetic.rs"),
    "utf8"
  );
  const block = /const SAFE_COOKIE_VALUES: &\[&str\] = &\[([\s\S]*?)\];/.exec(cosmeticRs);
  assert.ok(block, "missing SAFE_COOKIE_VALUES in cosmetic.rs");
  const rustValues = [...block[1].matchAll(/"([^"]+)"/g)].map(m => m[1]);
  assert.deepEqual(rustValues, uboValues, "SAFE_COOKIE_VALUES drifted from get-safe-cookie-values.fn");
}

console.log("PASS test_set_cookie_scriptlet");
