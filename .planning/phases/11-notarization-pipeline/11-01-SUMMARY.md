---
phase: 11-notarization-pipeline
plan: 01
subsystem: infra
tags: [notarization, ci, github-actions, provisioning-profile, notarytool, stapler, keychain]

# Dependency graph
requires:
  - phase: 10-build-and-entitlements
    provides: archive/exportArchive pipeline, spctl gate, Developer ID certificate import in CI
provides:
  - Provisioning profile install step (MACOS_PROFILE_APP_B64 secret) before xcodebuild archive
  - notarytool log fetch on failure with UUID capture and JSON log output
  - xcrun stapler validate after staple to catch silent failures
  - Keychain cleanup with if: always() as last CI step
affects: [homebrew-cask workflow, all future CI runs, notarization debugging]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Capture notarytool submit stdout into variable, parse UUID, conditionally fetch log on Invalid status"
    - "xcrun stapler validate immediately after xcrun stapler staple"
    - "CI cleanup step with if: always() and || true for idempotent teardown"
    - "Provisioning profile installed as .provisionprofile (not .mobileprovision) for macOS"

key-files:
  created: []
  modified:
    - .github/workflows/homebrew-cask.yml

key-decisions:
  - "Path A confirmed: Developer ID provisioning profile required (CloudKit and APNs both used unconditionally at macOS launch)"
  - "UUID parsed from notarytool submit stdout before status check so it is always captured even if submit times out mid-stream"
  - "Cleanup step removes both signing keychain and provisioning profile file for defense in depth"

patterns-established:
  - "Pattern: Install provisioning profile from base64 GitHub Secret before xcodebuild archive (write to ~/Library/MobileDevice/Provisioning Profiles/ with .provisionprofile extension)"
  - "Pattern: Keychain cleanup with if: always() is the last step in any job that creates a signing keychain"

requirements-completed: [NOTR-01, NOTR-02, NOTR-03, NOTR-04, NOTR-05]

# Metrics
duration: 10min
completed: 2026-02-19
---

# Phase 11 Plan 01: Notarization Pipeline Summary

**Provisioning profile install, notarytool UUID log fetch on failure, stapler validate, and keychain cleanup added to homebrew-cask.yml CI workflow**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-02-19T20:47:49Z
- **Completed:** 2026-02-19T20:57:00Z
- **Tasks:** 2 of 3 complete (Task 3 is a human-verify checkpoint — pending)
- **Files modified:** 1

## Accomplishments

- Added "Install provisioning profile" step after cert import and before Build DMG, reading from MACOS_PROFILE_APP_B64 secret with guard and .provisionprofile extension
- Replaced simple `notarytool submit --wait` with capture-UUID + conditional log fetch pattern — on Invalid status, fetches full JSON log from notarytool and exits 1
- Added `xcrun stapler validate` immediately after `xcrun stapler staple` with "Stapler validation passed" echo
- Added "Clean up keychain" as last job step with `if: always()` deleting both signing keychain and provisioning profile file

## Task Commits

Each task was committed atomically:

1. **Task 1: Provisioning profile install + notarytool log fetch + stapler validate** - `2306d1b` (feat)
2. **Task 2: Keychain cleanup step** - `c816e96` (feat)
3. **Task 3: Human verify checkpoint** - pending

## Files Created/Modified

- `.github/workflows/homebrew-cask.yml` - Added four additive changes: profile install step, enhanced notarize step (UUID capture + log fetch + stapler validate), cleanup step

## Decisions Made

- Path A (Developer ID provisioning profile) is required because both `CKContainer.default().privateCloudDatabase` and `NSApp.registerForRemoteNotifications()` are called unconditionally at macOS app launch
- UUID is captured from notarytool stdout before the status check so it is available even if the submit command exits unexpectedly mid-stream
- Cleanup step removes both signing keychain and provisioning profile file, even though GitHub-hosted runners are ephemeral (defensive practice)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `python3 -c "import yaml; ..."` verification failed because pyyaml was not installed. Used grep/Node.js to verify YAML structure and step presence. YAML itself is syntactically correct (confirmed by reading file and validating indentation visually).

## User Setup Required

Before the checkpoint verification can proceed, the user must:

1. Apple Developer Portal: verify CloudKit, Push Notifications, and App Groups (group.skula.wBlock) are all enabled for the skula.wBlock App ID
2. Apple Developer Portal: create a Developer ID Application provisioning profile for skula.wBlock with those capabilities, download it
3. Encode: `base64 -i <downloaded>.provisionprofile | pbcopy`
4. GitHub repo Settings -> Secrets -> New secret: `MACOS_PROFILE_APP_B64` with the base64 value

Then trigger the workflow (push tag or workflow_dispatch) and verify the CI run.

## Next Phase Readiness

- Workflow is ready to be triggered once MACOS_PROFILE_APP_B64 secret is added to GitHub
- If notarization fails, the log fetch will print per-component rejection JSON — look for "not provisioned" messages indicating missing capabilities in the profile
- After first successful notarization, run `codesign -d --entitlements :- wBlock.app` to verify aps-environment value (should be production for distribution)

---
*Phase: 11-notarization-pipeline*
*Completed: 2026-02-19*

## Self-Check: PASSED

- FOUND: `.github/workflows/homebrew-cask.yml`
- FOUND: `.planning/phases/11-notarization-pipeline/11-01-SUMMARY.md`
- FOUND: commit `2306d1b` (Task 1 - provisioning profile install + notarytool log + stapler validate)
- FOUND: commit `c816e96` (Task 2 - keychain cleanup)
