#!/usr/bin/env node
// Regression coverage for the Safari extension popup overflow behavior.
//
// Run: node scripts/test_popup_scroll_contract.mjs

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const popupDir = path.join(root, "wBlock Scripts (iOS)", "Resources", "pages", "popup");
const css = readFileSync(path.join(popupDir, "popup.css"), "utf8");
const js = readFileSync(path.join(popupDir, "popup.js"), "utf8");

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function ruleFor(selector, stylesheet = css) {
  const rules = [...stylesheet.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}]+)\{([^}]*)\}/g)];
  for (const match of rules) {
    const selectors = match[1].split(",").map((part) => part.trim());
    if (selectors.includes(selector)) {
      return match[2];
    }
  }
  return "";
}

function declarationsFor(selector, stylesheet = css) {
  const rule = ruleFor(selector, stylesheet);
  if (!rule) fail(`missing ${selector} rule`);

  return new Map(rule
    .split(";")
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => {
      const separator = part.indexOf(":");
      if (separator === -1) fail(`invalid declaration in ${selector}: ${part}`);
      return [
        part.slice(0, separator).trim(),
        part.slice(separator + 1).trim(),
      ];
    }));
}

const rootRule = declarationsFor("body");
if (rootRule.get("background") !== "Canvas") {
  fail("popup root must paint a system background instead of showing the page behind it");
}

const popup = declarationsFor(".popup");
if (popup.get("overflow") !== "hidden") {
  fail(".popup must keep the header pinned instead of scrolling it over the cards");
}
if (popup.get("max-height") !== "600px") {
  fail(".popup must still cap content-sized popovers below Safari's clipping height");
}
if (popup.get("min-height") !== "0") {
  fail(".popup must be allowed to shrink before it can scroll");
}

const body = declarationsFor(".popup-body");
if (body.get("overflow-y") !== "auto") {
  fail(".popup-body must scroll vertically when runtime content exceeds the menu height");
}
if (body.get("min-height") !== "0") {
  fail(".popup-body must be allowed to shrink before it can scroll");
}

const rules = declarationsFor(".rules");
if (rules.has("overflow") || rules.has("overflow-y") || rules.has("max-height")) {
  fail(".rules must not create a nested scrollbar inside the scrolling popup");
}

const supportsStart = css.search(/@supports\s*\(-webkit-touch-callout:\s*none\)\s*\{/);
if (supportsStart === -1) {
  fail("iOS/iPadOS popovers must override the 600px cap inside @supports (-webkit-touch-callout: none)");
}
const supportsOpen = css.indexOf("{", supportsStart);
let depth = 0;
let supportsEnd = -1;
for (let i = supportsOpen; i < css.length; i++) {
  if (css[i] === "{") depth++;
  else if (css[i] === "}") {
    depth--;
    if (depth === 0) {
      supportsEnd = i;
      break;
    }
  }
}
if (supportsEnd === -1) {
  fail("iOS @supports block is not closed");
}
const iosCss = css.slice(supportsOpen + 1, supportsEnd);

const iosRoot = declarationsFor("body", iosCss);
if (iosRoot.get("height") !== "100%" || iosRoot.get("max-height") !== "100%") {
  fail("iOS html/body must fill the Safari sheet instead of sizing only to content");
}
if (iosRoot.get("overflow") !== "hidden") {
  fail("iOS html/body must not become a second scroll container");
}

const iosPopup = declarationsFor(".popup", iosCss);
if (iosPopup.get("height") !== "100%" || iosPopup.get("max-height") !== "100%") {
  fail("iOS .popup must fill the Safari sheet instead of stopping at 600px");
}

if (!js.includes("function syncPopupViewportHeight(") ||
    !js.includes("CSS.supports('-webkit-touch-callout', 'none')") ||
    !js.includes("window.innerHeight") ||
    !js.includes("document.documentElement.style.height") ||
    !js.includes("document.body.style.height") ||
    !js.includes("window.addEventListener('resize', syncPopupViewportHeight)")) {
  fail("iOS popup must size itself to the live sheet viewport, not a guessed px cap");
}

console.log("PASS");
