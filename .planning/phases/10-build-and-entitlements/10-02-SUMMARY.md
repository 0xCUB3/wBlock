---
phase: 10-build-and-entitlements
plan: 02
subsystem: infra
tags: [xcodebuild, codesign, developer-id, gatekeeper, spctl, ci, github-actions]

# Dependency graph
requires:
  - phase: 10-build-and-entitlements
    provides: ExportOptions.plist and archive pipeline established in this same phase
provides:
  - ExportOptions.plist at repo root with developer-id method, automatic signing, team DNP7DGUB7B
  - build-dmg.sh rewritten to use xcodebuild archive + exportArchive (no manual codesign)
  - CI spctl Gatekeeper gate after build, before notarization
  - Privacy extension entitlements bug eliminated (no more wrong case statement)
affects: [11-notarization, homebrew-cask, release-pipeline]

# Tech tracking
tech-stack:
  added: [ExportOptions.plist]
  patterns: [xcodebuild archive + exportArchive for Developer ID distribution]

key-files:
  created:
    - ExportOptions.plist
  modified:
    - scripts/build-dmg.sh
    - .github/workflows/homebrew-cask.yml

key-decisions:
  - "Use xcodebuild archive + exportArchive instead of CODE_SIGNING_ALLOWED=NO + manual codesign — Apple-documented path for Developer ID, resolves error 163"
  - "signingStyle automatic with teamID DNP7DGUB7B — xcodebuild finds cert in keychain, no explicit identity string needed"
  - "spctl gate placed after Build DMG, before Notarize, so signing regressions are caught before wasting notarization time"

patterns-established:
  - "Build pipeline: archive -> exportArchive -> spctl gate -> notarize -> staple -> upload"
  - "ExportOptions.plist at repo root, referenced by -exportOptionsPlist flag in build script"

requirements-completed: [SIGN-01, SIGN-02, SIGN-05]

# Metrics
duration: 1min
completed: 2026-02-19
---

# Phase 10 Plan 02: Build Pipeline Rewrite Summary

**Replaced CODE_SIGNING_ALLOWED=NO + manual codesign with xcodebuild archive + exportArchive pipeline, added spctl Gatekeeper gate to CI, and eliminated the Privacy extension entitlements bug**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-02-19T20:34:44Z
- **Completed:** 2026-02-19T20:35:46Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created ExportOptions.plist with developer-id method, automatic signing style, team DNP7DGUB7B
- Rewrote build-dmg.sh to use xcodebuild archive + xcodebuild -exportArchive, removing all manual codesign logic (sign_item function, case statement, codesign --verify)
- Added "Verify Gatekeeper assessment" step to CI workflow (spctl --assess --type execute) between Build DMG and Notarize, catching signing regressions early
- Removed SIGNING_IDENTITY and DEVELOPMENT_TEAM_ID env vars from CI Build DMG step (no longer needed)
- Privacy extension entitlements bug resolved by deleting the broken case statement entirely

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ExportOptions.plist and rewrite build-dmg.sh** - `e74d067` (feat)
2. **Task 2: Add spctl Gatekeeper assessment gate to CI workflow** - `5d5e50f` (feat)

## Files Created/Modified
- `ExportOptions.plist` - Export config: developer-id method, automatic signing, DNP7DGUB7B team, stripSwiftSymbols
- `scripts/build-dmg.sh` - Rewritten to archive + exportArchive pipeline, no manual codesign
- `.github/workflows/homebrew-cask.yml` - Gatekeeper gate added, SIGNING_IDENTITY env vars removed

## Decisions Made
- Used `signingStyle automatic` (not manual) so xcodebuild resolves the certificate from the keychain without needing an explicit identity string in the plist
- stripSwiftSymbols=true included in ExportOptions.plist for smaller binary
- spctl gate verifies `build/homebrew/export/wBlock.app` — the path exportArchive writes to (changed from old DerivedData path)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. The keychain import step already in CI provides the certificate xcodebuild archive needs.

## Next Phase Readiness
- Build pipeline is correct and Gatekeeper-ready
- Phase 11 (Notarization) can proceed: DMG is at `build/homebrew/wBlock.dmg`, app is at `build/homebrew/export/wBlock.app`
- Open design decision: Path A (Developer ID provisioning profile covering CloudKit + push) vs Path B (strip those entitlements for Developer ID builds). Resolve by auditing CloudKit/APNs runtime usage before Phase 11 planning.

---
*Phase: 10-build-and-entitlements*
*Completed: 2026-02-19*
