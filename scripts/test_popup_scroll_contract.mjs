#!/usr/bin/env node
// Regression coverage for the Safari extension popup overflow behavior.
//
// Run: node scripts/test_popup_scroll_contract.mjs

import { readFileSync } from "node:fs";
import path from "node:path";

const root = process.cwd();
const cssPath = path.join(root, "wBlock Scripts (iOS)", "Resources", "pages", "popup", "popup.css");
const css = readFileSync(cssPath, "utf8");

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function ruleFor(selector) {
  const rules = [...css.matchAll(/([^{}]+)\{([^}]*)\}/g)];
  for (const match of rules) {
    const selectors = match[1].split(",").map((part) => part.trim());
    if (selectors.length === 1 && selectors[0] === selector) {
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
      return [
        part.slice(0, separator).trim(),
        part.slice(separator + 1).trim(),
      ];
    }));
}

const html = declarationsFor("html");
if (html.get("max-height") !== "100vh") {
  fail("html must be bounded to the popup viewport height");
}
if (html.get("overflow") !== "hidden") {
  fail("html must not become a second scroll container");
}

const body = declarationsFor("body");
if (body.get("overflow") !== "hidden") {
  fail("body must not become a second scroll container");
}

const popup = declarationsFor(".popup");
if (popup.get("overflow-y") !== "auto") {
  fail(".popup must scroll vertically when runtime content exceeds the menu height");
}
if (!/100vh/.test(popup.get("max-height") || "")) {
  fail(".popup max-height must be tied to the visible viewport");
}
if (popup.get("min-height") !== "0") {
  fail(".popup must be allowed to shrink inside the flex body before it can scroll");
}

const rules = declarationsFor(".rules");
if (rules.has("overflow") || rules.has("overflow-y") || rules.has("max-height")) {
  fail(".rules must not create a nested scrollbar inside the scrolling popup");
}

console.log("PASS");
