#!/usr/bin/env node
// Behavioral and structural contract for userscript rows and disclosure animations.
//
// Run: node scripts/test_popup_userscript_row_contract.mjs

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const popupDir = path.join(root, "wBlock Scripts (iOS)", "Resources", "pages", "popup");
const cssRaw = readFileSync(path.join(popupDir, "popup.css"), "utf8");
const css = cssRaw.replace(/\/\*[\s\S]*?\*\//g, "");
const html = readFileSync(path.join(popupDir, "popup.html"), "utf8");
const js = readFileSync(path.join(popupDir, "popup.js"), "utf8");

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function ruleFor(selector, stylesheet = css) {
  const rules = [...stylesheet.matchAll(/([^{}]+)\{([^}]*)\}/g)];
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

function sliceFunction(fnName) {
  const marker = `function ${fnName}(`;
  const start = js.indexOf(marker);
  if (start === -1) fail(`popup.js must contain ${marker}`);
  const openBrace = js.indexOf("{", start);
  if (openBrace === -1) fail(`cannot find opening brace for ${fnName}`);

  let depth = 0;
  for (let i = openBrace; i < js.length; i++) {
    if (js[i] === "{") depth++;
    else if (js[i] === "}") {
      depth--;
      if (depth === 0) {
        return js.slice(start, i + 1);
      }
    }
  }
  fail(`cannot find closing brace for ${fnName}`);
}

// --- Userscript rows contract ---

const renderFn = sliceFunction("renderPageUserScripts");

// Row element creation and class
if (!renderFn.includes("const row = document.createElement('div')") ||
    !renderFn.includes("row.className = 'userscript-row'")) {
  fail("renderPageUserScripts must use document.createElement('div') for the row with className 'userscript-row'");
}

// Must not use label as the row wrapper
if (/createElement\(['"]label['"]\)[^;]*\n[^\n]*userscript-row/.test(renderFn) ||
    /row\s*=\s*document\.createElement\(['"]label['"]\)/.test(renderFn)) {
  fail("renderPageUserScripts must NOT use a label element for userscript-row");
}

// Switch is createElement('label') with className 'switch' and htmlFor
if (!renderFn.includes("document.createElement('label')") ||
    !renderFn.includes("control.className = 'switch'") ||
    !renderFn.includes("control.htmlFor = toggleId")) {
  fail("userscript switch must be a label with className 'switch' and htmlFor set to toggleId");
}

// Checkbox is input.userscript-toggle with id, aria-labelledby, aria-label
if (!renderFn.includes("input.className = 'userscript-toggle'") ||
    !renderFn.includes("input.id = toggleId") ||
    !renderFn.includes("input.setAttribute('aria-labelledby', nameId)") ||
    !renderFn.includes("input.setAttribute('aria-label', script.name)")) {
  fail("userscript toggle checkbox must configure className, id, aria-labelledby, and aria-label");
}

// No row click handler that toggles
if (renderFn.includes("row.addEventListener") || js.includes(".userscript-row')") && js.includes("addEventListener('click'")) {
  fail("userscript-row must not attach a click listener that toggles");
}

// --- Disclosure animation markup contract ---

// popup.html has #userscripts-panel.disclosure-panel and #zapper-rules-panel.disclosure-panel
const userscriptsPanelMatch = html.match(/id="userscripts-panel"[^>]*class="([^"]*)"/);
if (!userscriptsPanelMatch || !userscriptsPanelMatch[1].split(/\s+/).includes("disclosure-panel")) {
  fail("popup.html must have #userscripts-panel with class disclosure-panel");
}

const rulesPanelMatch = html.match(/id="zapper-rules-panel"[^>]*class="([^"]*)"/);
if (!rulesPanelMatch || !rulesPanelMatch[1].split(/\s+/).includes("disclosure-panel")) {
  fail("popup.html must have #zapper-rules-panel with class disclosure-panel");
}

// Ensure panels wrap the lists and appear before the next major section
const userscriptsSectionStart = html.indexOf('id="userscripts-section"');
const userscriptsPanelStart = html.indexOf('id="userscripts-panel"');
const userscriptsListIndex = html.indexOf('id="userscripts-list"');
const userscriptsEmptyIndex = html.indexOf('id="userscripts-empty"');
const zapperTitleIndex = html.indexOf('id="zapper-title"');

if (userscriptsSectionStart === -1 ||
    userscriptsPanelStart <= userscriptsSectionStart ||
    userscriptsListIndex <= userscriptsPanelStart ||
    userscriptsEmptyIndex <= userscriptsPanelStart ||
    zapperTitleIndex <= userscriptsListIndex ||
    zapperTitleIndex <= userscriptsEmptyIndex) {
  fail("#userscripts-panel must wrap #userscripts-list and #userscripts-empty before the next section");
}

const zapperRulesPanelStart = html.indexOf('id="zapper-rules-panel"');
const zapperRulesIndex = html.indexOf('id="zapper-rules"');
const noAutoplaySectionIndex = html.indexOf('id="no-autoplay-section"');

if (zapperRulesPanelStart === -1 ||
    zapperRulesIndex <= zapperRulesPanelStart ||
    noAutoplaySectionIndex <= zapperRulesIndex) {
  fail("#zapper-rules-panel must wrap #zapper-rules before the next section");
}

// --- CSS disclosure and animation contract ---

const hiddenDecl = declarationsFor("[hidden]");
if (hiddenDecl.get("display") !== "none !important") {
  fail("[hidden] must force display: none !important for Safari iOS");
}

const panelDecl = declarationsFor(".disclosure-panel");
if (panelDecl.get("display") !== "grid") {
  fail(".disclosure-panel must use display: grid");
}
if (panelDecl.get("grid-template-rows") !== "0fr") {
  fail(".disclosure-panel must start with grid-template-rows: 0fr");
}
if (!panelDecl.get("transition")?.includes("grid-template-rows 0.2s ease-in-out")) {
  fail(".disclosure-panel must transition grid-template-rows over 0.2s ease-in-out");
}

const panelClosedDecl = declarationsFor(".disclosure-panel:not(.is-open)");
if (panelClosedDecl.get("pointer-events") !== "none") {
  fail(".disclosure-panel:not(.is-open) must have pointer-events: none");
}

const panelOpenDecl = declarationsFor(".disclosure-panel.is-open");
if (panelOpenDecl.get("grid-template-rows") !== "1fr") {
  fail(".disclosure-panel.is-open must have grid-template-rows: 1fr");
}

const chevronDecl = declarationsFor(".chevron");
const chevronTransition = chevronDecl.get("transition");
if (!chevronTransition || !chevronTransition.includes("0.2s ease-in-out")) {
  fail(".chevron transition must be 0.2s ease-in-out");
}

// prefers-reduced-motion: reduce must disable transitions on BOTH .disclosure-panel AND .chevron
const reducedMotionMatch = css.match(/@media\s*\(\s*prefers-reduced-motion:\s*reduce\s*\)\s*\{([\s\S]*?\})\s*\}/g);
if (!reducedMotionMatch) {
  fail("popup.css must contain a @media (prefers-reduced-motion: reduce) block");
}

let reducedDisablesPanel = false;
let reducedDisablesChevron = false;
for (const block of reducedMotionMatch) {
  const inner = block.replace(/@media[^{]*\{/, "").replace(/\}$/, "");
  const panelReduced = ruleFor(".disclosure-panel", inner);
  const chevronReduced = ruleFor(".chevron", inner);
  if (panelReduced && panelReduced.includes("transition: none")) {
    reducedDisablesPanel = true;
  }
  if (chevronReduced && chevronReduced.includes("transition: none")) {
    reducedDisablesChevron = true;
  }
}
if (!reducedDisablesPanel || !reducedDisablesChevron) {
  fail("prefers-reduced-motion must disable transitions on BOTH .disclosure-panel AND .chevron");
}

// --- JS disclosure logic contract ---

const setDisclosureInertFn = sliceFunction("setDisclosureInert");
if (!setDisclosureInertFn.includes("'inert' in panel") ||
    !setDisclosureInertFn.includes("panel.inert = inert") ||
    !setDisclosureInertFn.includes("aria-hidden")) {
  fail("setDisclosureInert must use 'inert' in panel with aria-hidden fallback/cleanup");
}

const setDisclosureOpenFn = sliceFunction("setDisclosureOpen");
if (!setDisclosureOpenFn.startsWith("function setDisclosureOpen(panel, open, toggle)")) {
  fail("setDisclosureOpen signature must accept (panel, open, toggle)");
}

const setUserscriptsExpandedFn = sliceFunction("setUserscriptsExpanded");
const setRulesExpandedFn = sliceFunction("setRulesExpanded");

// aria-expanded updates and passing toggle to setDisclosureOpen
if (!setUserscriptsExpandedFn.includes("aria-expanded") ||
    !/setDisclosureOpen\([^,]+,\s*expanded,\s*toggle\)/.test(setUserscriptsExpandedFn)) {
  fail("setUserscriptsExpanded must set aria-expanded and pass toggle as third arg to setDisclosureOpen");
}

if (!setRulesExpandedFn.includes("aria-expanded") ||
    !/setDisclosureOpen\([^,]+,\s*expanded,\s*toggle\)/.test(setRulesExpandedFn)) {
  fail("setRulesExpanded must set aria-expanded and pass toggle as third arg to setDisclosureOpen");
}

// Expand calls setDisclosureInert(panel, false) before panel.hidden = false and adds is-open
const inertFalsePos = setDisclosureOpenFn.indexOf("setDisclosureInert(panel, false)");
const hiddenFalsePos = setDisclosureOpenFn.indexOf("panel.hidden = false");
if (inertFalsePos === -1 || hiddenFalsePos === -1 || inertFalsePos > hiddenFalsePos) {
  fail("setDisclosureOpen expand path must call setDisclosureInert(panel, false) before panel.hidden = false");
}
if (!setDisclosureOpenFn.includes("requestAnimationFrame") ||
    !setDisclosureOpenFn.includes("classList.add('is-open')")) {
  fail("setDisclosureOpen expand branch must unhide and add is-open after requestAnimationFrame");
}

// Collapse path calls setDisclosureInert(panel, true) and toggle.focus() when panel contains activeElement before hide()
const inertTruePos = setDisclosureOpenFn.indexOf("setDisclosureInert(panel, true)");
const activeElementCheckPos = setDisclosureOpenFn.indexOf("panel.contains(document.activeElement)");
const toggleFocusPos = setDisclosureOpenFn.indexOf("toggle.focus()");
const hideDefPos = setDisclosureOpenFn.indexOf("const hide =");

if (inertTruePos === -1 || activeElementCheckPos === -1 || toggleFocusPos === -1 || hideDefPos === -1 ||
    inertTruePos > hideDefPos || activeElementCheckPos > hideDefPos || toggleFocusPos > hideDefPos ||
    activeElementCheckPos > toggleFocusPos) {
  fail("setDisclosureOpen collapse path must call setDisclosureInert(panel, true) and toggle.focus() when activeElement is within panel before hide()");
}

// Collapse waits for transitionend / timeout fallback before setting hidden
if (!setDisclosureOpenFn.includes("classList.remove('is-open')") ||
    !setDisclosureOpenFn.includes("transitionend") ||
    !setDisclosureOpenFn.includes("setTimeout") ||
    !setDisclosureOpenFn.includes("panel.hidden = true")) {
  fail("setDisclosureOpen collapse branch must remove is-open, wait for transitionend / timeout fallback, and set hidden");
}

console.log("PASS");
