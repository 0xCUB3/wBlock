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
if (autoplaySection.get("overflow") !== "visible") {
  fail("#no-autoplay-section overflow must be visible so WebKit does not clip abspos descendants of a radiused card");
}
if (autoplaySection.get("background") !== "transparent") {
  fail("#no-autoplay-section background must be transparent; card chrome lives on ::before");
}
if (autoplaySection.get("border") !== "0") {
  fail("#no-autoplay-section border must be 0; card chrome lives on ::before");
}
if (autoplaySection.get("border-radius") !== "0") {
  fail("#no-autoplay-section border-radius must be 0 so WebKit does not clip abspos descendants");
}

const autoplaySectionBefore = declarationsFor("#no-autoplay-section::before");
if (autoplaySectionBefore.get("border-radius") !== "10px") {
  fail("#no-autoplay-section::before must own the 10px card radius");
}
if (autoplaySectionBefore.get("background") !== "var(--group)") {
  fail("#no-autoplay-section::before must paint var(--group)");
}
if (autoplaySectionBefore.get("border") !== "0.5px solid var(--separator)") {
  fail("#no-autoplay-section::before must paint the 0.5px separator border");
}

const sliderRule = declarationsFor(".slider");
if (sliderRule.get("position") !== "relative") {
  fail(".slider position must be relative so the track stays in-flow");
}
if (sliderRule.has("inset")) {
  fail(".slider must not use inset:0; the track is in-flow, not stretched abspos");
}

const switchRule = declarationsFor(".switch");
const switchLineHeight = switchRule.get("line-height");
if (switchLineHeight !== "0" && switchLineHeight !== "31px") {
  fail(".switch must use line-height 0 or 31px so Safari does not clip the knob in the line box");
}
if (switchRule.get("overflow") !== "visible") {
  fail(".switch must keep overflow visible so Safari does not clip the knob");
}

if (/<label[^>]*id="no-autoplay-title"/i.test(html) || /<label[^>]*\bclass="[^"]*\brow\b[^"]*"[^>]*\bfor="no-autoplay-enabled-toggle"/i.test(html) || /<label[^>]*\bfor="no-autoplay-enabled-toggle"[^>]*\bclass="[^"]*\brow\b/i.test(html)) {
  fail("enabled row must not be a wrapping label");
}

const enabledSectionStart = html.indexOf('id="no-autoplay-section"');
const enabledSectionEnd = html.indexOf('id="no-autoplay-site-row"');
if (enabledSectionStart === -1 || enabledSectionEnd === -1 || enabledSectionStart > enabledSectionEnd) {
  fail("enabled row must live in #no-autoplay-section before the site exception row");
}
const enabledRowHtml = html.slice(enabledSectionStart, enabledSectionEnd);
if (enabledRowHtml.includes("row-trailing")) {
  fail("enabled toggle must not be wrapped in .row-trailing");
}

if (!/<div\s+id="no-autoplay-title"[^>]*>[\s\S]*?<label\s+class="switch"\s+for="no-autoplay-enabled-toggle">\s*<input\s+id="no-autoplay-enabled-toggle"/m.test(html)) {
  fail("enabled row must use switch-only label markup as a sibling of #no-autoplay-title");
}

if (!/id="no-autoplay-site-row"[^>]*\bhidden\b/.test(html)) {
  fail("site exception row must start hidden in markup");
}

if (/<label[^>]*id="no-autoplay-site-row"/i.test(html) || /<label[^>]*\bclass="[^"]*\btoggle-row\b[^"]*"[^>]*\bfor="no-autoplay-site-toggle"/i.test(html) || /<label[^>]*\bfor="no-autoplay-site-toggle"[^>]*\bclass="[^"]*\btoggle-row\b/i.test(html)) {
  fail("site exception row must not be a wrapping label");
}

if (!/<div\s+id="no-autoplay-site-row"\s+class="toggle-row"[^>]*hidden[^>]*>[\s\S]*?<label\s+class="switch"\s+for="no-autoplay-site-toggle">\s*<input\s+id="no-autoplay-site-toggle"/m.test(html)) {
  fail("site exception row must use switch-only label markup");
}

if (!js.includes("siteRow.hidden = !state.enabled || !options.host")) {
  fail("site exception row must stay hidden unless No Autoplay is on for a site");
}

for (const needle of [
  "getNoAutoplayState",
  "setNoAutoplayEnabled",
  "setNoAutoplaySiteAllowed",
  "action: 'getNoAutoplayState'",
  "action: 'setNoAutoplayEnabled'",
  "action: 'setNoAutoplaySiteAllowed'",
]) {
  if (!js.includes(needle)) {
    fail(`popup.js must contain ${needle}`);
  }
}

function sliceBetween(startMarker, endMarker) {
  const start = js.indexOf(startMarker);
  if (start === -1) fail(`popup.js must contain ${startMarker}`);
  const end = js.indexOf(endMarker, start + startMarker.length);
  if (end === -1) fail(`popup.js must contain ${endMarker} after ${startMarker}`);
  return js.slice(start, end);
}

const setEnabledBody = sliceBetween(
  "async function setNoAutoplayEnabled(enabled)",
  "async function setNoAutoplaySiteAllowed",
);
if (!setEnabledBody.includes("response.ok !== true")) {
  fail("setNoAutoplayEnabled must fail closed when response.ok is not true");
}
if (setEnabledBody.includes("try {")) {
  fail("setNoAutoplayEnabled must not catch native failures internally");
}
if (setEnabledBody.includes("markNoAutoplayNativeMigrated")) {
  fail("setNoAutoplayEnabled must not mark native migration; only migrateLegacyNoAutoplayToNative may");
}
if (!setEnabledBody.includes("mirrorNoAutoplayLocalCache")) {
  fail("setNoAutoplayEnabled must mirror native response after a successful write");
}

const setSiteBody = sliceBetween(
  "async function setNoAutoplaySiteAllowed(siteHost, allowed)",
  "function updateNoAutoplayControls",
);
if (!setSiteBody.includes("response.ok !== true")) {
  fail("setNoAutoplaySiteAllowed must fail closed when response.ok is not true");
}
if (setSiteBody.includes("try {")) {
  fail("setNoAutoplaySiteAllowed must not catch native failures internally");
}
if (setSiteBody.includes("markNoAutoplayNativeMigrated")) {
  fail("setNoAutoplaySiteAllowed must not mark native migration; only migrateLegacyNoAutoplayToNative may");
}
if (!setSiteBody.includes("mirrorNoAutoplayLocalCache")) {
  fail("setNoAutoplaySiteAllowed must mirror native response after a successful write");
}

const migrateBody = sliceBetween(
  "async function migrateLegacyNoAutoplayToNative(local, siteHost)",
  "async function getNoAutoplayState(siteHost)",
);
if (!migrateBody.includes("markNoAutoplayNativeMigrated")) {
  fail("migrateLegacyNoAutoplayToNative must mark native migration after all writes succeed");
}
if (!migrateBody.includes("siteResponse.ok !== true")) {
  fail("migrateLegacyNoAutoplayToNative must verify site allow writes with response.ok");
}
if (!migrateBody.includes("enabledResponse.ok !== true")) {
  fail("migrateLegacyNoAutoplayToNative must verify enabled write with response.ok");
}
const collectBody = sliceBetween(
  "async function collectLegacyNoAutoplayAllowHosts(siteHost, localSiteAllowed)",
  "async function migrateLegacyNoAutoplayToNative(local, siteHost)",
);
if (!collectBody.includes("throw error") && !collectBody.includes("throw")) {
  fail("collectLegacyNoAutoplayAllowHosts must throw on storage enumeration failure");
}
if (!collectBody.includes("normalizedLegacyNoAutoplayAllowHost")) {
  fail("legacy migration must skip hosts rejected by DisabledSitesNormalizer");
}
const invalidHostIdx = migrateBody.indexOf("siteResponse.error === 'Invalid host'");
const invalidHostContinueIdx = migrateBody.indexOf("continue;", invalidHostIdx);
if (invalidHostIdx === -1 || invalidHostContinueIdx === -1) {
  fail("legacy migration must skip native Invalid host responses");
}
const hostsIdx = migrateBody.indexOf("collectLegacyNoAutoplayAllowHosts");
const enabledWriteIdx = migrateBody.indexOf("setNoAutoplayEnabled");
if (hostsIdx === -1 || enabledWriteIdx === -1 || hostsIdx > enabledWriteIdx) {
  fail("migrateLegacyNoAutoplayToNative must copy allowed hosts before enabling No Autoplay");
}
const markIdx = migrateBody.indexOf("markNoAutoplayNativeMigrated");
if (markIdx === -1) {
  fail("migrateLegacyNoAutoplayToNative must call markNoAutoplayNativeMigrated");
}
const migrateBeforeMark = migrateBody.slice(0, markIdx);
if (!migrateBeforeMark.includes("return false")) {
  fail("migrateLegacyNoAutoplayToNative must abort without marking when writes fail");
}
if (migrateBeforeMark.lastIndexOf("return false") > migrateBeforeMark.lastIndexOf("ok !== true")) {
  // last return false should follow ok checks in each branch
}
const getStateBody = sliceBetween(
  "async function getNoAutoplayState(siteHost)",
  "async function setNoAutoplayEnabled(enabled)",
);
if (!getStateBody.includes("return null")) {
  // readNoAutoplayLocalCache returns null; getState should handle local === null
}
if (!getStateBody.includes("local !== null") && !getStateBody.includes("local ??")) {
  fail("getNoAutoplayState must prefer local cache when migration did not complete");
}
const readCacheBody = sliceBetween(
  "async function readNoAutoplayLocalCache(siteHost)",
  "async function mirrorNoAutoplayLocalCache(enabled, siteHost, siteAllowed)",
);
if (!readCacheBody.includes("return null")) {
  fail("readNoAutoplayLocalCache must return null on storage read failure");
}

console.log("PASS");
