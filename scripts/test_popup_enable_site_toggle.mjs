// Behavioral contract for the popup's site-enable toggle.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const popup = readFileSync(path.join(root, "wBlock Scripts (iOS)", "Resources/pages/popup/popup.js"), "utf8");
const html = readFileSync(path.join(root, "wBlock Scripts (iOS)", "Resources/pages/popup/popup.html"), "utf8");
const localesRoot = path.join(root, "wBlock Scripts (iOS)", "Resources/_locales");
const localeNames = ["ar", "de", "el", "en", "es", "fr", "hu", "it", "ja", "ko", "pl", "pt_BR", "ro", "ru", "tr", "zh_CN", "zh_TW"];

const check = (condition, message) => {
  if (!condition) {
    console.error(`FAIL: ${message}`);
    process.exit(1);
  }
};

check(html.includes('data-i18n="popup_enable_on_site"'), "popup uses the enable wording key");
check(html.includes('id="enable-toggle"'), "popup uses the enable toggle control");
check(popup.includes("const disableToggle = document.getElementById('enable-toggle');"), "popup binds the enable control");
check(popup.includes("const next = !disableToggle.checked;"), "checked=true maps to disabled=false when changing the site setting");
check(popup.includes("disableToggle.checked = !disabled;"), "native disabled state is inverted for the checked enable control");
check(popup.includes("pageUserScriptsRenderedDisabled = disableToggle ? !disableToggle.checked : false;"), "userscript rendering uses the inverted enable state");
check(popup.includes("zapperActivate.disabled = (disableToggle ? !disableToggle.checked : false) || disabled;"), "zapper activation uses the inverted enable state");

for (const checked of [false, true]) {
  const nativeDisabled = !checked;
  check((!checked) === nativeDisabled, `toggle semantics failed for checked=${checked}`);
}

for (const locale of localeNames) {
  const messages = JSON.parse(readFileSync(path.join(localesRoot, locale, "messages.json"), "utf8"));
  check(messages.popup_enable_on_site?.message, `missing enable toggle translation in ${locale}`);
  check(!messages.popup_disable_on_site, `stale disable toggle key remains in ${locale}`);
}

console.log("PASS");
