#!/usr/bin/env node
// Native Safari popup layout and disable-failure visibility.
//
// Run: node scripts/test_popup_native_layout_contract.mjs

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const popupDir = path.join(root, "wBlock Scripts (iOS)", "Resources", "pages", "popup");
const css = readFileSync(path.join(popupDir, "popup.css"), "utf8");
const html = readFileSync(path.join(popupDir, "popup.html"), "utf8");
const js = readFileSync(path.join(popupDir, "popup.js"), "utf8");

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function ruleFor(selector) {
  const rules = [...css.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}]+)\{([^}]*)\}/g)];
  for (const match of rules) {
    const selectors = match[1].split(",").map((part) => part.trim());
    if (selectors.includes(selector)) {
      return match[2];
    }
  }
  return "";
}

function declarationsFor(selector) {
  const rule = ruleFor(selector);
  if (!rule) fail(`missing ${selector} rule`);
  return new Map(rule
    .split(";")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => {
      const separator = part.indexOf(":");
      if (separator === -1) fail(`invalid declaration in ${selector}: ${part}`);
      return [part.slice(0, separator).trim(), part.slice(separator + 1).trim()];
    }));
}

if (/#ff7a18|255,\s*122,\s*24/i.test(css)) {
  fail("popup must not keep the leftover orange accent");
}

const rootVars = declarationsFor(":root");
if (rootVars.get("--accent") !== "#007aff") {
  fail("popup accent must follow the app's system blue");
}

const switchRule = declarationsFor(".switch");
if (switchRule.get("width") !== "51px" || switchRule.get("height") !== "31px") {
  fail("toggles must use native UISwitch metrics (51x31)");
}

const checked = declarationsFor(".switch input:checked + .slider");
if (checked.get("background") !== "var(--accent)") {
  fail("on-state toggles must use the blue accent, not a custom track color");
}

if (!html.includes('class="popup-sticky"') || html.indexOf('id="error"') > html.indexOf('class="section"')) {
  fail("errors must sit in the sticky header, above the first section");
}

const sticky = declarationsFor(".popup-sticky");
if (sticky.get("position") !== "sticky" || sticky.get("top") !== "0") {
  fail("status and errors must stay pinned while the popup scrolls");
}

if (!js.includes("if (popup) popup.scrollTop = 0")) {
  fail("setError must jump back to the sticky banner");
}

if (!js.includes("kind === 'error'") || !js.includes("popup_status_error")) {
  fail("site-setting failures must flip the header status to Error");
}

const handler = js.slice(js.indexOf("disableToggle.addEventListener('change'"));
const nextIdx = handler.indexOf("const next = !disableToggle.checked;");
const tryIdx = handler.indexOf("try {");
if (!(nextIdx >= 0 && nextIdx < tryIdx)) {
  fail("desired site state must be visible to the timeout catch");
}

if (!js.includes("return null;") ||
    !js.includes("typeof actuallyDisabled === 'boolean'") ||
    !js.includes("actuallyDisabled === next")) {
  fail("timed-out site toggles must reconcile only from a confirmed native read");
}

console.log("PASS");
