---
phase: 13-fix-broken-script-based-ad-blocking-afte
plan: 01
subsystem: extension-scripts
tags: [safari-extension, scriptlets, javascript, ios, macos]
dependency_graph:
  requires: []
  provides: [properly-bundled-safari-extension-4.2.1]
  affects: [wBlock Advanced, wBlock Scripts iOS]
tech_stack:
  added: []
  patterns: [rollup IIFE bundle, pnpm build, upstream-splice pattern]
key_files:
  created: []
  modified:
    - wBlock Advanced/Resources/script.js
    - wBlock Scripts (iOS)/Resources/background.js
    - wBlock Scripts (iOS)/Resources/content.js
decisions:
  - Spliced approach: take upstream portion from fresh build up to @file comment, append wBlock custom code verbatim
  - Used @file comment block as the stable boundary marker between upstream and wBlock custom sections
metrics:
  duration: ~20 minutes
  completed: 2026-02-19
---

# Quick Task 13: Fix Broken Script-Based Ad Blocking — Summary

**One-liner:** Rebuilt all three Safari extension JS files via rollup with @adguard/safari-extension 4.2.1, restoring properly bundled scriptlets 2.2.16 + extended-css 2.1.1.

## What Was Done

Cloned ameshkov/safari-blocker (shallow), bumped `@adguard/safari-extension` from 4.1.0 to 4.2.1 in both `appext` and `webext` package.json files, ran `pnpm install && pnpm run build` for both, then spliced the freshly built upstream portion with the preserved wBlock custom code sections.

The splice boundary was the `/** @file ... */` comment block that precedes the entry-point code — identical in both the stock build output and existing wBlock files, making it a stable anchor point.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Clone safari-blocker, bump to 4.2.1, build appext + webext JS | (prep) |
| 2 | Splice built JS into wBlock files, preserving all custom code | 4615e3f |

## Verification Results

- `SafariExtension v4.2.1` present in all three files
- `handleZapperMessage` preserved in script.js
- `engineTimestamp` (caching) preserved in background.js
- `window.adguard` preserved in content.js
- `node --check` passes for all three files (no JS syntax errors)
- Xcode build: `** BUILD SUCCEEDED **`

## Deviations from Plan

None — plan executed exactly as written. The splice approach worked cleanly using the `/**\n * @file` comment boundary.

## Self-Check

- [x] wBlock Advanced/Resources/script.js — contains "SafariExtension v4.2.1"
- [x] wBlock Scripts (iOS)/Resources/background.js — contains "SafariExtension v4.2.1"
- [x] wBlock Scripts (iOS)/Resources/content.js — contains "SafariExtension v4.2.1"
- [x] Commit 4615e3f exists on main branch
- [x] Xcode build succeeded
