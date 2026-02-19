---
phase: 12-homebrew-cask
plan: 01
subsystem: infra
tags: [homebrew, cask, dmg, ci, github-actions, notarization, distribution]

requires:
  - phase: 11-notarization-pipeline
    provides: Notarization CI workflow with build-dmg.sh that produces a signed DMG

provides:
  - Versioned DMG output from build-dmg.sh via VERSION env var
  - Complete Homebrew cask with pinned version, versioned URL, livecheck, and zap stanza
  - CI pipeline that extracts version from tag, builds versioned DMG, and auto-updates Casks/wblock.rb on push

affects: [future-releases, homebrew-tap]

tech-stack:
  added: []
  patterns:
    - "VERSION env var pattern: build script produces wBlock-${VERSION}.dmg when set, wBlock.dmg when unset"
    - "CI cask auto-update: sed patches version+sha256, commits, pushes HEAD:main after upload"
    - "SHA256 computed from local DMG (not re-downloaded) to avoid CDN propagation race"

key-files:
  created: []
  modified:
    - scripts/build-dmg.sh
    - Casks/wblock.rb
    - .github/workflows/homebrew-cask.yml

key-decisions:
  - "SHA256 computed from local DMG file in CI (not re-downloaded from GitHub) to avoid CDN propagation race condition"
  - "sed -i '' used for macOS runners (macos-latest) — not GNU sed -i"
  - "Cask URL uses v#{version} tag prefix matching GitHub release tag format"
  - "git push origin HEAD:main in Update cask step — workflow only triggers on tags so no infinite loop"

patterns-established:
  - "Versioned artifacts: use VERSION env var to control output filename in build scripts"
  - "CI cask auto-update: compute SHA256 locally, sed-patch, commit, push to main"

requirements-completed: [BREW-01, BREW-02, BREW-03, BREW-04, BREW-05]

duration: 1min
completed: 2026-02-19
---

# Phase 12 Plan 01: Homebrew Cask Summary

**Versioned Homebrew cask with livecheck/zap + CI auto-update of version and sha256 on each tag push**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-02-19T23:05:28Z
- **Completed:** 2026-02-19T23:06:40Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Rewrote Casks/wblock.rb with pinned version, versioned URL (`v#{version}/wBlock-#{version}.dmg`), livecheck block (`strategy :github_latest`), and zap stanza with 4 `skula.wBlock` bundle ID paths
- Added VERSION env var support to build-dmg.sh so CI produces `wBlock-2.0.1.dmg` while local dev still gets `wBlock.dmg`
- Wired homebrew-cask.yml with: Extract version step, VERSION passed to Build DMG, versioned DMG references in Notarize and Upload steps, and Update cask step that computes SHA256 locally and pushes updated wblock.rb to main

## Task Commits

Each task was committed atomically:

1. **Task 1: Versioned DMG output and cask rewrite** - `e3231af` (feat)
2. **Task 2: CI workflow version extraction, versioned DMG references, and cask auto-update step** - `b5ef3ba` (feat)

## Files Created/Modified

- `scripts/build-dmg.sh` - Added VERSION env var and DMG_NAME logic; DMG_PATH now uses DMG_NAME variable
- `Casks/wblock.rb` - Fully rewritten: pinned version 2.0.1, versioned URL, livecheck, zap stanza
- `.github/workflows/homebrew-cask.yml` - Added Extract version step, VERSION env to Build DMG, versioned DMG refs in Notarize/Upload, Update cask step with sed+git push

## Decisions Made

- SHA256 computed from local DMG file (not re-downloaded from GitHub releases CDN) to avoid propagation race where cask update runs before CDN has the file
- `sed -i ''` used (macOS BSD sed syntax) since the workflow runs on `macos-latest`
- `git push origin HEAD:main` in Update cask step — safe because workflow only triggers on `push: tags:`, not branch pushes, so no infinite loop

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. The CI already has the required secrets from Phase 11.

## Next Phase Readiness

- All 5 BREW requirements complete
- Cask will pass `brew audit` once a real versioned DMG is uploaded to a GitHub release
- `sha256 "PLACEHOLDER_UPDATED_BY_CI"` is intentional — CI overwrites it on first tag push
- Phase 12 (Homebrew Cask) is now complete

---
*Phase: 12-homebrew-cask*
*Completed: 2026-02-19*
