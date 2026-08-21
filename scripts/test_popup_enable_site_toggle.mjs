// Behavioral contract for the popup's site-enable toggle.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const popup = readFileSync(path.join(root, "wBlock Scripts (iOS)", "Resources/pages/popup/popup.js"), "utf8");
const html = readFileSync(path.join(root, "wBlock Scripts (iOS)", "Resources/pages/popup/popup.html"), "utf8");
const localesRoot = path.join(root, "wBlock Scripts (iOS)", "Resources/_locales");
const localeNames = ["ar", "de", "el", "en", "es", "fr", "hu", "it", "ja", "ko", "pl", "pt_BR", "ro", "ru", "tr", "zh_CN", "zh_TW"];
const english = JSON.parse(readFileSync(path.join(localesRoot, "en", "messages.json"), "utf8"));
const requiredKeys = [
  "popup_enable_on_site",
  "popup_warning_open_app_to_apply",
  "popup_status_unavailable",
];

const check = (condition, message) => {
  if (!condition) {
    console.error(`FAIL: ${message}`);
    process.exit(1);
  }
};

check(html.includes('data-i18n="popup_enable_on_site"'), "popup uses the enable wording key");
check(html.includes('id="enable-toggle"'), "popup uses the enable toggle control");
check(!/<label[^>]*\bclass="[^"]*\btoggle-row\b[^"]*"[^>]*\bfor="enable-toggle"/i.test(html) && !/<label[^>]*\bfor="enable-toggle"[^>]*\bclass="[^"]*\btoggle-row\b/i.test(html), "enable row must not be a wrapping label");
check(/<div\s+class="toggle-row">\s*<div\s+id="enable-title"\s+class="label"\s+data-i18n="popup_enable_on_site">[\s\S]*?<label\s+class="switch"\s+for="enable-toggle">\s*<input\b[^>]*\bid="enable-toggle"[^>]*\/>/m.test(html), "enable row must use switch-only label markup");
check(/<input\b[^>]*\bid="enable-toggle"[^>]*\bdisabled\b[^>]*\/>/m.test(html), "enable toggle must start disabled until native state is known");
check(popup.includes("const disableToggle = document.getElementById('enable-toggle');"), "popup binds the enable control");

// Slice setupListeners body and the enable-toggle change handler specifically
const setupListenersMatch = popup.match(/function\s+setupListeners\s*\(\)\s*\{([\s\S]*?)\n\}/);
check(Boolean(setupListenersMatch), "setupListeners function found in popup.js");
const setupListenersBody = setupListenersMatch[1];

const enableHandlerStartIndex = setupListenersBody.indexOf("if (disableToggle) {");
const zapperHandlerStartIndex = setupListenersBody.indexOf("if (zapperEnabledToggle) {");
check(enableHandlerStartIndex !== -1, "enable-toggle block found in setupListeners");
check(zapperHandlerStartIndex !== -1, "zapperEnabledToggle block found in setupListeners");
check(enableHandlerStartIndex < zapperHandlerStartIndex, "enable-toggle block comes before zapper block in setupListeners");

const enableHandlerBlock = setupListenersBody.slice(enableHandlerStartIndex, zapperHandlerStartIndex);

// 1. Handler must NOT contain settleMs, sleep(350), or sleep(1200)
check(!enableHandlerBlock.includes("settleMs"), "enable handler must not contain settleMs");
check(!enableHandlerBlock.includes("sleep(350)"), "enable handler must not contain sleep(350)");
check(!enableHandlerBlock.includes("sleep(1200)"), "enable handler must not contain sleep(1200)");

// 2. Handler must contain previousChecked and targetHost/targetTab locals
check(enableHandlerBlock.includes("const previousChecked = !disableToggle.checked;"), "enable handler must define previousChecked local");
check(enableHandlerBlock.includes("const targetHost = host;"), "enable handler must snapshot host as targetHost local");
check(enableHandlerBlock.includes("const targetTab = tab;"), "enable handler must snapshot tab as targetTab local");

// 3. Handler must NOT assign `disableToggle.checked = next` (without bang).
//    Success uses `disableToggle.checked = !next`; unknown failure uses previousChecked; known reconcile uses !actuallyDisabled.
check(!/disableToggle\.checked\s*=\s*next(?!\w)/.test(enableHandlerBlock), "enable handler must not assign disableToggle.checked = next");
check(enableHandlerBlock.includes("disableToggle.checked = !next;"), "enable handler success path assigns disableToggle.checked = !next");
check(enableHandlerBlock.includes("disableToggle.checked = !actuallyDisabled;"), "enable handler reconcile path assigns disableToggle.checked = !actuallyDisabled");
check(enableHandlerBlock.includes("disableToggle.checked = previousChecked;"), "enable handler unknown failure path reverts to previousChecked");

// 4. Empty-host path reverts previousChecked
check(/if\s*\(!targetHost\)\s*\{\s*disableToggle\.checked\s*=\s*previousChecked;\s*return;\s*\}/m.test(enableHandlerBlock), "empty-host path reverts to previousChecked and returns");

// 5. setupListeners must not enable the toggle except in the change-handler finally (refreshUi is what enables it via disableToggle.disabled = filtersPaused)
const setupListenersWithoutFinally = setupListenersBody.replace(/finally\s*\{[\s\S]*?\}/g, "");
check(!/disableToggle\.disabled\s*=\s*false/.test(setupListenersWithoutFinally), "setupListeners must not enable toggle outside of change-handler finally block");
check(/finally\s*\{[\s\S]*?disableToggle\.disabled\s*=\s*false;[\s\S]*?\}/.test(enableHandlerBlock), "enable handler finally block must re-enable disableToggle");

// 6. Keep all existing checks
check(popup.includes("const next = !disableToggle.checked;"), "checked=true maps to disabled=false when changing the site setting");
check(popup.includes("const siteDisabled = disabled === true;"), "failed site-disabled reads must not count as enabled");
check(popup.includes("const siteDisabledUnknown = disabled === null;"), "unknown site-disabled reads must not be treated as enabled or disabled");
check(popup.includes("disableToggle.checked = !siteDisabled;"), "native disabled state is inverted for the checked enable control");
check(popup.includes("pageUserScriptsRenderedDisabled = disableToggle ? !disableToggle.checked : false;"), "userscript rendering uses the inverted enable state");
check(popup.includes("zapperActivate.disabled = (disableToggle ? !disableToggle.checked : false) || disabled;"), "zapper activation uses the inverted enable state");
check(popup.includes("let siteToggleGeneration = 0;"), "site toggle must track generations so stale refreshes cannot win");
check(popup.includes("let siteToggleInFlight = false;"), "site toggle must ignore overlapping refresh commits while a write is in flight");
check(popup.includes("const skipSiteToggleCommit = siteToggleInFlight || generationAtStart !== siteToggleGeneration;"), "refresh must not clobber an in-flight site toggle");
check(popup.includes("if (!siteToggleInFlight)"), "refresh must keep an in-flight site-toggle error visible");
check(popup.includes("readSiteDisabledStateAfterTimeout"), "timed-out writes must re-read native state before failing");
check(popup.includes("popup_warning_open_app_to_apply"), "missing base-rules cache must ask the user to open wBlock");
check(popup.includes("popup_status_unavailable"), "unreadable site state must surface an Unavailable status");
check(popup.includes("requiresFullApply"), "site toggle must honor native requiresFullApply");

for (const checked of [false, true]) {
  const nativeDisabled = !checked;
  check((!checked) === nativeDisabled, `toggle semantics failed for checked=${checked}`);
}

check(localeNames.length === 17, "site-toggle copy must cover all 17 locales");
for (const locale of localeNames) {
  const messages = JSON.parse(readFileSync(path.join(localesRoot, locale, "messages.json"), "utf8"));
  check(JSON.stringify(Object.keys(messages).sort()) === JSON.stringify(Object.keys(english).sort()), `${locale} must preserve popup locale key parity`);
  for (const key of requiredKeys) {
    check(messages[key]?.message, `missing ${key} translation in ${locale}`);
  }
  check(!messages.popup_disable_on_site, `stale disable toggle key remains in ${locale}`);
  if (locale !== "en") {
    check(messages.popup_warning_open_app_to_apply.message !== english.popup_warning_open_app_to_apply.message, `${locale} must have a real open-app-to-apply translation`);
    check(messages.popup_status_unavailable.message !== english.popup_status_unavailable.message, `${locale} must have a real unavailable-status translation`);
  }
}

console.log("PASS");
