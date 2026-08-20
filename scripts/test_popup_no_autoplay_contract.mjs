#!/usr/bin/env node
// Regression coverage for No Autoplay popup controls.
//
// Safari iOS lets author `display` beat the UA [hidden] rule, so the site
// exception row stays visible unless CSS forces [hidden] to display:none.
//
// Run: node scripts/test_popup_no_autoplay_contract.mjs

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const popupDir = path.join(root, "wBlock Scripts (iOS)", "Resources", "pages", "popup");
const css = readFileSync(path.join(popupDir, "popup.css"), "utf8")
  .replace(/\/\*[\s\S]*?\*\//g, "");
const html = readFileSync(path.join(popupDir, "popup.html"), "utf8");
const js = readFileSync(path.join(popupDir, "popup.js"), "utf8");

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

const hidden = declarationsFor("[hidden]");
if (hidden.get("display") !== "none !important") {
  fail("[hidden] must force display:none so iOS cannot show flex toggle rows");
}

const autoplaySection = declarationsFor("#no-autoplay-section");
const sectionTop = Number.parseInt(autoplaySection.get("margin-top") || "", 10);
if (!Number.isFinite(sectionTop) || sectionTop < 8) {
  fail("#no-autoplay-section must sit below the zapper hint so its top edge renders");
}

const siteRow = declarationsFor("#no-autoplay-site-row");
const marginTop = Number.parseInt(siteRow.get("margin-top") || "", 10);
if (!Number.isFinite(marginTop) || marginTop < 8) {
  fail("#no-autoplay-site-row must leave space under the No Autoplay toggle");
}

if (!/id="no-autoplay-site-row"[^>]*\bhidden\b/.test(html)) {
  fail("site exception row must start hidden in markup");
}

if (!js.includes("siteRow.hidden = !state.enabled || !options.host")) {
  fail("site exception row must stay hidden unless No Autoplay is on for a site");
}

console.log("PASS");
