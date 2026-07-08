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
if (popup.get("overflow-y") !== "auto") {
  fail(".popup must scroll vertically when runtime content exceeds the menu height");
}
if (popup.get("max-height") !== "600px") {
  fail(".popup must be capped below Safari's popover clipping height");
}
if (popup.get("min-height") !== "0") {
  fail(".popup must be allowed to shrink before it can scroll");
}

const rules = declarationsFor(".rules");
if (rules.has("overflow") || rules.has("overflow-y") || rules.has("max-height")) {
  fail(".rules must not create a nested scrollbar inside the scrolling popup");
}

console.log("PASS");
