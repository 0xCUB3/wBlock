---
phase: 10-build-and-entitlements
plan: 01
subsystem: infra
tags: [entitlements, sandbox, hardened-runtime, codesigning, safari-extension]

# Dependency graph
requires: []
provides:
  - All 6 Safari extension targets have com.apple.security.app-sandbox in entitlements
  - wBlock Ads target has ENABLE_HARDENED_RUNTIME = YES in Debug and Release
affects: [11-notarization, 12-distribution]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "All Safari extension entitlements must include app-sandbox and application-groups"
    - "ENABLE_HARDENED_RUNTIME = YES is required on all targets for notarization"

key-files:
  created: []
  modified:
    - wBlock Advanced/wBlock_Advanced.entitlements
    - wBlock Privacy/wBlock_Privacy.entitlements
    - wBlock Security/wBlock_Security.entitlements
    - wBlock Custom/wBlock_Custom.entitlements
    - wBlock Foreign/wBlock_Foreign.entitlements
    - wBlock.xcodeproj/project.pbxproj

key-decisions:
  - "Added app-sandbox to 5 extension entitlements matching the Ads entitlements structure (reference file was already correct)"
  - "Fixed ENABLE_HARDENED_RUNTIME from NO to YES in both Debug and Release for wBlock Ads — required for notarization"

patterns-established:
  - "Entitlements pattern: app-sandbox first, then application-groups array"

requirements-completed: [SIGN-03, SIGN-04]

# Metrics
duration: 8min
completed: 2026-02-19
---

# Phase 10 Plan 01: Fix Extension Entitlements and Hardened Runtime Summary

**app-sandbox added to 5 Safari extensions (Advanced, Privacy, Security, Custom, Foreign) and ENABLE_HARDENED_RUNTIME flipped to YES on wBlock Ads — both required for Safari registration and notarization**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-02-19T20:27:00Z
- **Completed:** 2026-02-19T20:35:38Z
- **Tasks:** 1
- **Files modified:** 6

## Accomplishments
- Added `com.apple.security.app-sandbox: true` to all 5 extension entitlements missing it (Advanced, Privacy, Security, Custom, Foreign)
- Fixed `ENABLE_HARDENED_RUNTIME = NO` to `YES` in both Debug and Release for wBlock Ads target
- Verified project builds cleanly with no errors after changes

## Task Commits

Each task was committed atomically:

1. **Task 1: Add app-sandbox to five extension entitlements and fix hardened runtime** - `6da8d0f` (fix)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `wBlock Advanced/wBlock_Advanced.entitlements` - added com.apple.security.app-sandbox key
- `wBlock Privacy/wBlock_Privacy.entitlements` - added com.apple.security.app-sandbox key
- `wBlock Security/wBlock_Security.entitlements` - added com.apple.security.app-sandbox key
- `wBlock Custom/wBlock_Custom.entitlements` - added com.apple.security.app-sandbox key
- `wBlock Foreign/wBlock_Foreign.entitlements` - added com.apple.security.app-sandbox key
- `wBlock.xcodeproj/project.pbxproj` - changed ENABLE_HARDENED_RUNTIME from NO to YES at lines 2543 and 2573 (wBlock Ads Debug and Release)

## Decisions Made
- Used `wBlock Ads/wBlock_Ads.entitlements` as the reference template since it was already correct
- Applied changes to all 5 missing extensions atomically in a single commit alongside the pbxproj fix

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. All verification checks passed on first attempt:
- 5 entitlements files each have 1 `app-sandbox` entry
- 0 occurrences of `ENABLE_HARDENED_RUNTIME = NO` in project file
- 18 occurrences of `ENABLE_HARDENED_RUNTIME = YES` (was 16, now 18)
- Build succeeded with no errors

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All extension entitlements are now correct for Safari registration
- Hardened runtime enabled on all targets — prerequisite for notarization in Phase 11
- Phase 11 (Notarization) can proceed; open design decision remains on Path A vs Path B for aps-environment/iCloud entitlements

---
*Phase: 10-build-and-entitlements*
*Completed: 2026-02-19*
