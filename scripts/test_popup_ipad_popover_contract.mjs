#!/usr/bin/env node
// Regression coverage for iPad Safari popup sizing and active-tab URL recovery.
//
// Run: node scripts/test_popup_ipad_popover_contract.mjs

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

function blockAfter(source, startPattern) {
  const start = source.search(startPattern);
  if (start === -1) return "";
  const open = source.indexOf("{", start);
  if (open === -1) return "";
  let depth = 0;
  for (let index = open; index < source.length; index += 1) {
    if (source[index] === "{") depth += 1;
    if (source[index] === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(open + 1, index);
    }
  }
  return "";
}

function declarationsFor(selector, stylesheet = css) {
  const rules = [...stylesheet.replace(/\/\*[\s\S]*?\*\//g, "").matchAll(/([^{}]+)\{([^}]*)\}/g)];
  for (const match of rules) {
    const selectors = match[1].split(",").map((part) => part.trim());
    if (!selectors.includes(selector)) continue;
    return new Map(match[2]
      .split(";")
      .map((part) => part.trim())
      .filter(Boolean)
      .map((part) => {
        const separator = part.indexOf(":");
        return [part.slice(0, separator).trim(), part.slice(separator + 1).trim()];
      }));
  }
  return new Map();
}

const popup = declarationsFor(".popup");
if (popup.get("max-height") !== "600px") {
  fail("unscoped .popup must keep max-height: 600px for content-sized popovers");
}

const supportsCss = blockAfter(css, /@supports\s*\(-webkit-touch-callout:\s*none\)/);
if (!supportsCss) fail("missing Safari @supports block");
for (const selector of ["html", "body", ".popup"]) {
  const declarations = declarationsFor(selector, supportsCss);
  if (declarations.get("height") === "100%" || declarations.get("max-height") === "100%") {
    fail(`Safari @supports must not apply 100% height to unscoped ${selector}`);
  }
  if ((selector === "html" || selector === "body") && declarations.get("overflow") === "hidden") {
    fail(`Safari @supports must not hide overflow on unscoped ${selector}`);
  }
}
if (!supportsCss.includes("html.ios-phone-sheet") || !supportsCss.includes("html.ios-phone-sheet .popup")) {
  fail("Safari sheet fill must be scoped to html.ios-phone-sheet");
}

const getActiveTab = blockAfter(js, /async function getActiveTab\(\)/);
const currentWindowIndex = getActiveTab.indexOf("{ active: true, currentWindow: true }");
const lastFocusedIndex = getActiveTab.indexOf("{ active: true, lastFocusedWindow: true }");
const activeOnlyIndex = getActiveTab.indexOf("{ active: true }");
if (!(currentWindowIndex >= 0 && currentWindowIndex < lastFocusedIndex && lastFocusedIndex < activeOnlyIndex)) {
  fail("getActiveTab must try currentWindow, lastFocusedWindow, then all active tabs");
}
if (!getActiveTab.includes("hasUsableHttpUrl(candidate)") ||
    !getActiveTab.includes("return candidate;") ||
    !getActiveTab.includes("browser.tabs.get(fallbackTab.id)")) {
  fail("getActiveTab must prefer http(s) URLs and resolve an id-only fallback with tabs.get");
}

const usableUrl = blockAfter(js, /function hasUsableHttpUrl\(tab\)/);
if (!usableUrl.includes("url.protocol === 'http:'") || !usableUrl.includes("url.protocol === 'https:'")) {
  fail("active-tab selection must recognize only usable http and https URLs");
}

const refreshUi = blockAfter(js, /async function refreshUi\(\)/);
const missingUrlIndex = refreshUi.indexOf("const tabUrlMissing");
const missingUrlProbeIndex = refreshUi.indexOf("supportProbe = await probeTabSupport(tab.id)");
const unsupportedDiagnosticIndex = refreshUi.indexOf("reason: 'url_unsupported'");
if (!(missingUrlIndex >= 0 && missingUrlIndex < missingUrlProbeIndex && missingUrlProbeIndex < unsupportedDiagnosticIndex)) {
  fail("refreshUi must probe an id-only tab before logging url_unsupported");
}
if (!refreshUi.includes("pageSupport = { supported: true, host: supportProbe.host }")) {
  fail("refreshUi must use the probe host when an iPad tab URL is missing");
}

const probeTabSupport = blockAfter(js, /async function probeTabSupport\(tabId\)/);
if (!probeTabSupport.includes("const response = await sendTabMessageWithRetry") ||
    !probeTabSupport.includes("host: response.host") ||
    !probeTabSupport.includes("protocol: response.protocol") ||
    /return\s+(true|false)\s*;/.test(probeTabSupport)) {
  fail("probeTabSupport must return the validated host/protocol payload instead of a boolean");
}

console.log("PASS");
