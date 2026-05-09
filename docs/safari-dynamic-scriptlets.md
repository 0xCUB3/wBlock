# Safari Dynamic Scriptlets

## What uBOL Safari Actually Does

uBOL's Safari target is built from uBlock's MV3 Safari package, not from a separate Safari-specific scriptlet runtime in `uBOL-home`.

Confirmed behavior:

- `uBOL-home` delegates the Safari build to uBlock's `mv3-safari` target: https://github.com/uBlockOrigin/uBOL-home/blob/main/Makefile#L21-L24
- The Safari manifest uses `scripting` and declarative net request permissions, but does not request `userScripts`: https://github.com/gorhill/uBlock/blob/master/platform/mv3/safari/manifest.json#L43-L53
- Stock scriptlets are precompiled into packaged extension files and registered with `browser.scripting.registerContentScripts`: https://github.com/gorhill/uBlock/blob/master/platform/mv3/extension/js/scripting-manager.js#L245-L305
- The MV3 build writes the generated scriptlet files under `rulesets/scripting/scriptlet/...`: https://github.com/gorhill/uBlock/blob/master/platform/mv3/make-rulesets.js#L944-L973
- Generated scriptlet files self-gate by hostname at runtime: https://github.com/gorhill/uBlock/blob/master/platform/mv3/extension/js/scriptlet.template.js#L94-L180
- Custom `userScripts` are a separate path and are not the stock Safari scriptlet path: https://github.com/gorhill/uBlock/blob/master/platform/mv3/extension/js/filter-manager.js#L284-L355

The important part is the delivery model. uBOL runs packaged files in `MAIN` world at `document_start`; it does not serialize the active scriptlet payload into inline code for `userScripts`.

## wBlock's Previous Shape

wBlock's advanced runtime is intentionally dynamic. Before this experiment:

- Swift compiles downloaded filters into `wblock_native_advanced_runtime.json` in the app group.
- The Scripts extension asks native messaging for either a page-specific payload or a registered document-start payload.
- Page-specific payloads are applied with `browser.scripting.executeScript({ func, args, world: 'MAIN' })`.
- The early registered path serialized scriptlet rule data into inline `browser.userScripts.register({ js: [{ code }], world: 'MAIN' })`.
- `content.js` still has a fallback that creates a `<script>` element and assigns `script.textContent` after trying to create a Trusted Types policy.

Those last two points were the Safari risk. They preserved dynamicity, but they were not how uBOL avoids page CSP and Trusted Types issues.

## Current Experiment

The current experiment keeps dynamic rule data but changes delivery:

- Background registers packaged `content.js` in `MAIN` world with `browser.scripting.registerContentScripts`.
- Background stores the indexed registered scriptlet payload in `browser.storage.local`.
- Isolated `content.js` posts cached registered scriptlets and page-specific native lookup results to the MAIN runner as data.
- MAIN-world `content.js` listens for `wblock:main-world-configuration` and calls `wBlockApplyConfiguration`.
- The advanced runtime no longer injects page configuration by creating a page `<script>` element with `textContent`.

This keeps executable code packaged while keeping downloaded filter data dynamic.

The Safari console after testing showed that this delivery change was not enough
for YouTube. The active failures still came from the scriptlet hooks themselves
(`trusted-json-edit-xhr-request`, `json-prune-fetch-response`,
`trusted-replace-fetch-response`, and `trusted-prevent-dom-bypass`) rather than
from the old inline `<script>.textContent` path.

Current mitigation:

- Keep CSS and network blocking active on YouTube.
- Keep YouTube JSON request/response scriptlets active, because suppressing all
  scriptlets lets video ads through.
- Suppress raw page-world `js`, DOM-bypass scriptlets, and node-text replacement
  scriptlets on YouTube-family hosts. Those are the pieces that correlate with
  Trusted Types and sandboxed-frame failures.
- Apply the same filtering in `content.js`, so old stored payloads cannot keep
  firing fragile rules after the native bundle changes.

## API Constraints

`browser.scripting.registerContentScripts` takes packaged JS file paths, not arbitrary runtime code. MDN documents `js` as an array of paths in the extension package: https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/scripting/RegisteredContentScript#js

`browser.userScripts.register` can take either `code` or `file`: https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/userScripts/ScriptSource#type

That gives us three realistic paths:

1. Packaged static scriptlet files, uBOL-style.
   - Best for Safari timing and CSP behavior.
   - Not fully dynamic unless the rules are bundled at app build time.
   - Good fit for default or curated compatibility rules.

2. Packaged static runner plus dynamic configuration.
   - Keep the code packaged, but feed current rule data from extension storage or native messaging.
   - Preserves dynamic list updates.
   - Main risk: rule data arrives after `document_start`, so early YouTube bootstrap requests or globals may already be missed.
   - A static runner can listen for `window.postMessage` from the isolated content script. That avoids creating page `<script>` tags and avoids serializing runtime data into executable source.

3. `userScripts` file source instead of inline code.
   - Keeps the early registered path dynamic-ish if the file runner can receive or read current config.
   - Needs a Safari proof before relying on it, because uBOL does not use this path for stock Safari scriptlets.
   - If Safari still treats `MAIN` user scripts poorly on Trusted Types pages, this does not solve the YouTube issue.

## Validation Hypothesis

The useful test is not another hand-written YouTube runtime. It is a delivery experiment:

1. Confirm the packaged `MAIN` runner registers at startup.
2. Confirm isolated content scripts can deliver cached registered payloads and page-specific native lookup payloads to the runner.
3. Compare Safari console behavior on YouTube against the previous inline `userScripts` registration.
4. If packaged `scripting` avoids the TrustedScript errors, decide whether to keep using it for:
   - curated static YouTube/uAssets compatibility rules, or
   - a dynamic config bridge with known timing tradeoffs.

Do not broaden `googlevideo.com/videoplayback` blocking. The generated uBOL Safari build does not do that by default, and it directly correlates with YouTube playback interruptions.

## Follow-Up Direction

Next steps:

1. Verify YouTube no longer shows `ad_playback` in QOE logs while also avoiding
   wBlock-owned `trusted-prevent-dom-bypass` or node-text replacement frames.
2. If YouTube still reports `videoplayback` 403s, inspect network rules rather
   than adding more scriptlet delivery layers.
3. If a future YouTube rule is needed, prefer a tiny curated packaged rule with
   a specific reproduction over re-enabling broad DOM/text mutations wholesale.
4. Leave YouTube playback URL protections in the compiler/DNR normalizer,
   independent of the scriptlet delivery work.

This does not fully match uBOL timing, because uBOL's rules are already baked into the file at `document_start`. It does match the part that matters for Safari CSP: executable code is packaged, dynamic data is data, and page injection no longer depends on inline script text.
