// Behavioral checks for the shipped (minified) content script's bfcache restore.
// On a persisted pageshow the content script asks the background to reinsert the
// frame's styles, but only when they are missing, the page is not a Cloudflare
// challenge, and the styles were not applied into the page itself (blank frames).
// It never reruns the page's initialization, and it retries a failed request
// only.
//
// Run: node scripts/test_content_frame_style_restore.mjs [path/to/content.js]
// Defaults to "wBlock Scripts (iOS)/Resources/content.js".

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const bundlePath = process.argv[2]
  ?? path.join(repoRoot, "wBlock Scripts (iOS)", "Resources", "content.js");
const source = readFileSync(bundlePath, "utf8");

let failures = 0;
const check = (name, cond) => {
  console.log(`${cond ? "PASS" : "FAIL"}: ${name}`);
  if (!cond) failures += 1;
};
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// Init reply for a page whose hides come from the background (no payload).
const backgroundReply = { type: "InitContentScript", disabled: false, paused: false };
// Init reply for a frame the background cannot target: the payload is applied in-page.
const pageReply = {
  type: "InitContentScript", disabled: false, paused: false,
  payload: { css: [".ad-slot-0"], styles: [], procedural: [], scriptlets: [] }
};

// Runs the shipped content script in a fake page, then returns handles to deliver
// pageshow events and inspect the messages it sent. Call close() to restore globals.
const openPage = async ({ initReply, title = "page", marker = "", restoreReply = () => Promise.resolve({ restored: true }) }) => {
  const messages = [];
  const pageshowListeners = [];
  const inserted = [];
  const windowScenario = {
    location: { href: "https://example.com/", hostname: "example.com", pathname: "/", protocol: "https:" },
    frameElement: null,
    addEventListener: (name, listener) => { if (name === "pageshow") pageshowListeners.push(listener); },
    removeEventListener() {},
    dispatchEvent: () => true,
    MutationObserver: class { observe() {} disconnect() {} }
  };
  windowScenario.top = windowScenario;
  const documentScenario = {
    readyState: "complete",
    title,
    documentElement: { appendChild: el => { inserted.push(el); return el; }, removeChild() {} },
    head: null,
    createElement: () => ({ setAttribute() {}, appendChild() {}, remove() {}, parentNode: null, style: {} }),
    createTextNode: text => ({ text }),
    querySelector: () => null,
    querySelectorAll: () => [],
    getElementsByTagName: () => [],
    addEventListener() {},
    removeEventListener() {}
  };
  const browserScenario = {
    runtime: {
      sendMessage(message) {
        messages.push(message);
        if (message && message.type === "InitContentScript") return Promise.resolve(initReply);
        if (message && message.action === "wblock:restoreFrameStyles") return restoreReply(messages);
        return Promise.resolve({});
      },
      onMessage: { addListener() {} }
    }
  };
  const globals = {
    document: documentScenario,
    window: windowScenario,
    location: windowScenario.location,
    getComputedStyle: () => ({ getPropertyValue: name => (name === "--wblock-frame-styles" ? marker : "") }),
    Node: class Node {},
    Element: class Element {},
    HTMLElement: class HTMLElement {},
    navigator: { userAgent: "test" },
    CSS: { supports: () => false }
  };
  const saved = {};
  for (const [key, value] of Object.entries(globals)) {
    saved[key] = Object.getOwnPropertyDescriptor(globalThis, key);
    Object.defineProperty(globalThis, key, { value, configurable: true, writable: true });
  }
  const close = () => {
    for (const [key, descriptor] of Object.entries(saved)) {
      if (descriptor === undefined) delete globalThis[key];
      else Object.defineProperty(globalThis, key, descriptor);
    }
  };
  try {
    new Function("browser", "window", "self", source)(browserScenario, windowScenario, windowScenario);
    await sleep(20);
  } catch (error) {
    close();
    throw error;
  }
  return {
    messages,
    inserted,
    close,
    pageshow: (persisted) => { for (const listener of pageshowListeners) listener({ persisted }); },
    restores: () => messages.filter(message => message && message.action === "wblock:restoreFrameStyles"),
    initializations: () => messages.filter(message => message && message.type === "InitContentScript").length
  };
};

const scenario = async (name, options, body) => {
  const page = await openPage(options);
  try {
    await body(page);
  } catch (error) {
    check(`${name} ran without throwing`, false);
    console.error(error);
  } finally {
    page.close();
  }
};

await scenario("normal load", { initReply: backgroundReply }, async page => {
  page.pageshow(false);
  await sleep(20);
  check("a non-persisted pageshow sends no restore", page.restores().length === 0);
});

await scenario("bfcache restore with styles missing", { initReply: backgroundReply }, async page => {
  page.pageshow(true);
  await sleep(20);
  const restores = page.restores();
  check("a persisted pageshow asks for the styles once", restores.length === 1);
  check("the restore request carries no payload beyond its action", restores.length === 1 && Object.keys(restores[0]).join() === "action");
  check("restoring does not rerun page initialization", page.initializations() === 1);
});

await scenario("bfcache restore with styles still present", { initReply: backgroundReply, marker: "1" }, async page => {
  page.pageshow(true);
  await sleep(20);
  check("present styles are not inserted again", page.restores().length === 0);
});

await scenario("blank frame applied in the page", { initReply: pageReply }, async page => {
  check("the in-page style element was appended", page.inserted.length > 0);
  page.pageshow(true);
  await sleep(20);
  check("in-page styles are not restored by the background", page.restores().length === 0);
});

await scenario("Cloudflare challenge", { initReply: backgroundReply, title: "Just a moment..." }, async page => {
  page.pageshow(true);
  await sleep(20);
  check("a challenge page sends no restore", page.restores().length === 0);
});

await scenario("site disabled while cached", { initReply: { ...backgroundReply, disabled: true } }, async page => {
  page.pageshow(true);
  await sleep(20);
  check("the content script still asks; the background answers from native state", page.restores().length === 1);
});

await scenario("failed restore is retried", { initReply: backgroundReply, restoreReply: messages => Promise.resolve(
  messages.filter(message => message && message.action === "wblock:restoreFrameStyles").length === 1
    ? { state: "error", error: "native unavailable" }
    : { restored: true }
) }, async page => {
  page.pageshow(true);
  await sleep(400);
  check("the failed request is retried after its delay", page.restores().length === 2);
  await sleep(300);
  check("a successful retry ends the attempts", page.restores().length === 2);
});

await scenario("overlapping pageshows share one request", { initReply: backgroundReply, restoreReply: () => new Promise(resolve => setTimeout(() => resolve({ restored: true }), 50)) }, async page => {
  page.pageshow(true);
  page.pageshow(true);
  await sleep(120);
  check("two pageshows in flight send one request", page.restores().length === 1);
});

await scenario("states other than error are not retried", { initReply: backgroundReply, restoreReply: () => Promise.resolve({ restored: false, state: "skipped" }) }, async page => {
  page.pageshow(true);
  await sleep(400);
  check("a skipped, stale or empty restore is answered once", page.restores().length === 1);
});

await scenario("error retries stop after the bounded attempts", { initReply: backgroundReply, restoreReply: () => Promise.resolve({ restored: false, state: "error", error: "native unavailable" }) }, async page => {
  page.pageshow(true);
  await sleep(4700);
  check("an error is retried three times, then given up", page.restores().length === 4);
});

console.log(failures === 0 ? "All tests passed!" : `${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
