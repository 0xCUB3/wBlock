---
phase: 13-fix-broken-script-based-ad-blocking-afte
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - "wBlock Advanced/Resources/script.js"
  - "wBlock Scripts (iOS)/Resources/background.js"
  - "wBlock Scripts (iOS)/Resources/content.js"
autonomous: true
requirements: [FIX-SCRIPTLETS]

must_haves:
  truths:
    - "Script-based ad blocking (YouTube ads, etc.) works on macOS Safari"
    - "Script-based ad blocking works on iOS Safari"
    - "All three JS extension files contain properly bundled @adguard/safari-extension 4.2.1 code"
    - "All wBlock custom code (logger, zapper, caching, etc.) is preserved unchanged"
  artifacts:
    - path: "wBlock Advanced/Resources/script.js"
      provides: "macOS app extension content script with updated safari-extension 4.2.1 bundle"
      contains: "SafariExtension v4.2.1"
    - path: "wBlock Scripts (iOS)/Resources/background.js"
      provides: "iOS web extension background script with updated safari-extension 4.2.1 bundle"
      contains: "SafariExtension v4.2.1"
    - path: "wBlock Scripts (iOS)/Resources/content.js"
      provides: "iOS web extension content script with updated safari-extension 4.2.1 bundle"
      contains: "SafariExtension v4.2.1"
  key_links:
    - from: "scriptlets bundle"
      to: "SafariExtension framework"
      via: "rollup IIFE bundle integration"
      pattern: "getScriptletFunction|passSourceAndProps"
    - from: "SafariExtension framework"
      to: "wBlock custom code"
      via: "ConsoleLogger, ContentScript, BackgroundScript references"
      pattern: "new ConsoleLogger.*wBlock"
---

<objective>
Rebuild the three Safari extension JS files using the ameshkov/safari-blocker build system with @adguard/safari-extension bumped to 4.2.1 (from 4.1.0). This ensures scriptlets v2.2.16, extended-css v2.1.1, and the SafariExtension v4.2.1 framework are all properly bundled together by rollup, fixing the broken script-based ad blocking caused by the manual scriptlet paste in PR #253.

Purpose: Restore YouTube ad blocking and all scriptlet-based filtering on macOS and iOS Safari.
Output: Three updated JS files with properly integrated @adguard/safari-extension 4.2.1 bundle, all wBlock custom code preserved.
</objective>

<execution_context>
@/Users/skula/.claude/get-shit-done/workflows/execute-plan.md
@/Users/skula/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Clone safari-blocker, bump to safari-extension 4.2.1, and build extension JS</name>
  <files>
    (temporary clone in /tmp/safari-blocker)
  </files>
  <action>
    1. Clone https://github.com/ameshkov/safari-blocker to /tmp/safari-blocker (shallow clone, master branch)

    2. In /tmp/safari-blocker/extensions/appext/package.json, change `@adguard/safari-extension` from `"4.1.0"` to `"4.2.1"`

    3. In /tmp/safari-blocker/extensions/webext/package.json, change `@adguard/safari-extension` from `"4.1.0"` to `"4.2.1"`

    4. Build the appext JS (produces script.js for macOS):
       ```
       cd /tmp/safari-blocker/extensions/appext
       pnpm install && pnpm run build
       ```
       The built output goes to /tmp/safari-blocker/extensions/appext/dist/script.js
       (also copied to /tmp/safari-blocker/app-extension/Resources/script.js)

    5. Build the webext JS (produces background.js + content.js for iOS):
       ```
       cd /tmp/safari-blocker/extensions/webext
       pnpm install && pnpm run build
       ```
       The built output goes to /tmp/safari-blocker/extensions/webext/dist/background.js and dist/content.js
       (also copied to /tmp/safari-blocker/web-extension/Resources/)

    6. Verify builds succeeded:
       - /tmp/safari-blocker/extensions/appext/dist/script.js exists and contains "SafariExtension"
       - /tmp/safari-blocker/extensions/webext/dist/background.js exists and contains "SafariExtension"
       - /tmp/safari-blocker/extensions/webext/dist/content.js exists and contains "SafariExtension"

    NOTE: pnpm must be available. If not, install with `npm install -g pnpm` first.
  </action>
  <verify>
    All three dist files exist and contain the string "4.2.1" in the SafariExtension version marker.
    Run: grep "SafariExtension v" /tmp/safari-blocker/extensions/appext/dist/script.js /tmp/safari-blocker/extensions/webext/dist/background.js /tmp/safari-blocker/extensions/webext/dist/content.js
  </verify>
  <done>Three fresh JS files built from safari-blocker with @adguard/safari-extension 4.2.1 (scriptlets 2.2.16, extended-css 2.1.1, SafariExtension framework 4.2.1 all properly bundled by rollup).</done>
</task>

<task type="auto">
  <name>Task 2: Splice built JS into wBlock files, preserving all wBlock custom code</name>
  <files>
    wBlock Advanced/Resources/script.js
    wBlock Scripts (iOS)/Resources/background.js
    wBlock Scripts (iOS)/Resources/content.js
  </files>
  <action>
    For each of the three JS files, the structure is:
    - UPSTREAM CODE: Everything from line 1 up to (but not including) the wBlock custom code
    - wBLOCK CUSTOM CODE: Everything from the wBlock custom section to EOF

    The wBlock custom code boundaries (in the CURRENT files) are:
    - script.js: Line 23526 starts with `  /**` / `   * @file App extension content script.` — everything from line 23526 to line 24604 (end) is wBlock custom. But note: the line just before (23525) is blank, and line 23524 ends the SafariExtension upstream section. The IIFE closing `})();` at line 24604 is part of wBlock custom.
    - background.js: Line 17091 starts with `  /**` / `   * @file Background script for the WebExtension.` — everything from line 17091 to line 17279 (end) is wBlock custom. The IIFE closing `})(browser);` at line 17279 is part of wBlock custom.
    - content.js: Line 22676 starts with `  /**` / `   * @file Content script for the WebExtension.` — everything from line 22676 to line 22729 (end) is wBlock custom. The IIFE closing `})(browser);` at line 22729 is part of wBlock custom.

    For each file, use this approach:

    **A) Extract wBlock custom code from the CURRENT file:**
    - script.js: Extract lines from `  /**` `   * @file App extension content script.` through `})();` at EOF (lines 23526-24604)
    - background.js: Extract lines from `  /**` `   * @file Background script for the WebExtension.` through `})(browser);` at EOF (lines 17091-17279)
    - content.js: Extract lines from `  /**` `   * @file Content script for the WebExtension.` through `})(browser);` at EOF (lines 22676-22729)

    Save each custom section to a temp file.

    **B) Take the freshly built file from Task 1 and remove its closing lines:**
    - The built script.js ends with `})();` — remove that closing
    - The built background.js ends with `})(browser);` — remove that closing
    - The built content.js ends with `})(browser);` — remove that closing

    **C) Concatenate: built file (without closing) + wBlock custom code (which includes the closing)**

    CRITICAL VALIDATION after each splice:
    - The wBlock custom code section must be BYTE-IDENTICAL to what was extracted. Use `diff` to verify.
    - The file must contain "SafariExtension v4.2.1" (not 4.0.4)
    - The file must NOT have duplicate IIFE closings
    - script.js must contain `const wBlockLogger = new ConsoleLogger("[wBlock Advanced]"`
    - script.js must contain `handleZapperMessage` (zapper code)
    - background.js must contain `const wBlockLogger = new ConsoleLogger('[wBlock Scripts]'`
    - background.js must contain `engineTimestamp` (caching code)
    - content.js must contain `const wBlockLogger = new ConsoleLogger('[wBlock Scripts]'`
    - content.js must contain `window.adguard` (content script exposure)

    IMPORTANT: The built files from safari-blocker are the "stock" extension code. The wBlock custom code REPLACES the stock extension's initialization/entry-point code at the bottom. The custom code uses types/classes defined in the upstream portion (ConsoleLogger, LoggingLevel, setLogger, ContentScript, BackgroundScript, setupDelayedEventDispatcher, MessageType, etc.), so the upstream portion MUST be complete and unmodified from the build output.
  </action>
  <verify>
    Run these checks:
    1. `grep "SafariExtension v4.2.1" "wBlock Advanced/Resources/script.js"` — must match
    2. `grep "SafariExtension v4.2.1" "wBlock Scripts (iOS)/Resources/background.js"` — must match
    3. `grep "SafariExtension v4.2.1" "wBlock Scripts (iOS)/Resources/content.js"` — must match
    4. `grep "handleZapperMessage" "wBlock Advanced/Resources/script.js"` — must match (zapper preserved)
    5. `grep "engineTimestamp" "wBlock Scripts (iOS)/Resources/background.js"` — must match (caching preserved)
    6. `grep "window.adguard" "wBlock Scripts (iOS)/Resources/content.js"` — must match (content script preserved)
    7. No JavaScript syntax errors: `node --check "wBlock Advanced/Resources/script.js"` (may not work for IIFE browser code, but try)
    8. Build the Xcode project: `xcodebuild -scheme wBlock -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` — must succeed
  </verify>
  <done>
    All three JS files updated with properly bundled @adguard/safari-extension 4.2.1 (scriptlets 2.2.16 + extended-css 2.1.1 + SafariExtension framework 4.2.1). All wBlock custom code (logger initialization, element zapper, caching layer, userscript handling) preserved byte-for-byte. Xcode build passes.
  </done>
</task>

</tasks>

<verification>
1. All three JS files contain "SafariExtension v4.2.1" version marker
2. All three JS files contain "@adguard/scriptlets" bundle (getScriptletFunction, passSourceAndProps)
3. All wBlock custom code preserved (zapper in script.js, caching in background.js, content script init in content.js)
4. Xcode project builds successfully
5. No JavaScript syntax errors in any file
</verification>

<success_criteria>
- Three JS files rebuilt with @adguard/safari-extension 4.2.1 properly bundled via rollup (not manually pasted)
- scriptlets v2.2.16, extended-css v2.1.1, and SafariExtension framework v4.2.1 all integrated correctly
- All wBlock custom code sections preserved identically
- Xcode build passes with CODE_SIGNING_ALLOWED=NO
</success_criteria>

<output>
After completion, create `.planning/quick/13-fix-broken-script-based-ad-blocking-afte/13-SUMMARY.md`
</output>
