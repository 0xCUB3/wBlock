# Project Research Summary

**Project:** wBlock v1.2 — Distribution & Code Signing
**Domain:** macOS Developer ID code signing, notarization, and Homebrew cask distribution
**Researched:** 2026-02-19
**Confidence:** HIGH

## Executive Summary

The current wBlock distribution pipeline is broken by design. Building with `CODE_SIGNING_ALLOWED=NO` then re-signing with shell-level `codesign` cannot produce a correctly signed app bundle on macOS Sequoia or Tahoe. The root cause is structural: provisioning profiles cannot be embedded post-build, so any target with managed capabilities (CloudKit, push notifications, app groups) ends up with entitlements the OS cannot validate against a profile. Gatekeeper's launch-time check rejects the app silently with error 163 — and the right-click bypass was removed in Sequoia 15.1, so there is no user-side workaround. The fix is not incremental. The entire build approach must change to `xcodebuild archive` + `xcodebuild -exportArchive` with `method: developer-id`, which is the Apple-documented and industry-standard path for this type of app.

Beyond the signing failure, research identified two pre-existing entitlements bugs in the current codebase: the Privacy extension is signed with the main app's entitlements file (wrong path in the `build-dmg.sh` case statement), and the Advanced and Privacy extensions are missing `com.apple.security.app-sandbox`, which causes Safari to silently ignore them. These bugs would persist and cause failures even if the signing approach were fixed in isolation. They must be corrected alongside the build script change.

The Homebrew cask issue is separate but adjacent: `version :latest` with `sha256 :no_check` disables `brew upgrade`, tamper detection, and any auto-bump automation. Switching to a versioned cask with a real SHA256 and a `livecheck` block is low-effort and unblocks the entire Homebrew update path. Automating the cask update as a CI step after each tag push eliminates the manual release ceremony. The path from broken pipeline to working distribution has clear dependencies and no ambiguous decisions except one: whether to create a Developer ID provisioning profile for the main app's CloudKit and push capabilities, or strip those entitlements from the Developer ID build path (which is simpler if those capabilities are unused in the direct-download variant).

## Key Findings

### Recommended Stack

The correct stack for macOS Developer ID distribution of an app with Safari extensions uses entirely Apple-native tooling. `xcodebuild archive` is the only build path that correctly embeds provisioning profiles, validates managed entitlements, and signs in the required bottom-up order (framework → XPC → extensions → app). Pairing it with `xcodebuild -exportArchive` using a `method: developer-id` ExportOptions.plist gives Xcode full control over the final signing pass. Notarization via `xcrun notarytool` with API key auth (already in the existing workflow) and `xcrun stapler staple` on the DMG are correct as-is and need no changes.

**Core technologies:**
- `xcodebuild archive` + `xcodebuild -exportArchive`: build and sign — only correct path for Developer ID with managed entitlements; Xcode handles signing order and provisioning profile embedding automatically
- `ExportOptions.plist`: declarative export config committed to the repo; `method: developer-id`, `signingStyle: automatic`, `teamID: DNP7DGUB7B`, `stripSwiftSymbols: true`
- `xcrun notarytool submit --wait`: notarization — already in place, no changes needed
- `xcrun stapler staple`: ticket embedding — already in place, no changes needed
- `hdiutil create`: DMG packaging — already in place, no changes needed
- Homebrew versioned cask with `livecheck`: update discovery, integrity verification, `brew upgrade` support

**New GitHub Secrets required:**
- `MACOS_PROFILE_APP_B64`: Developer ID provisioning profile for `skula.wBlock` (covers CloudKit + push); obtained from Apple Developer portal, encoded as base64
- `MACOS_PROFILE_FILTERUPDATESERVICE_B64`: Developer ID provisioning profile for the XPC service; needed only if notarization rejects the XPC service without one

**One-time Developer Portal prerequisite:** Create Developer ID provisioning profiles for `skula.wBlock` with CloudKit + push notifications + App Groups capabilities enabled. Content blocker extensions (Ads, Privacy, Security, Foreign, Custom, Advanced) likely do not need provisioning profiles since they only use app-sandbox + app-groups, which are free entitlements on macOS for Developer ID distribution.

### Expected Features

The "features" for this milestone are pipeline capabilities, not user-facing features. Missing any P1 item means the app fails to launch or Homebrew users cannot upgrade.

**Must have (table stakes — v1.2 launch):**
- Switch to `xcodebuild archive` + `exportArchive` — root cause fix for error 163; eliminates the manual re-sign approach
- `ExportOptions.plist` committed to repo — required by `xcodebuild -exportArchive`
- Fix Privacy extension entitlements path in `build-dmg.sh` — existing bug causing notarization rejection (wrong entitlements file assigned in case statement)
- Add `com.apple.security.app-sandbox` to Advanced and Privacy extension entitlements — existing bug causing silent Safari registration failure
- Versioned DMG output (`wBlock-${VERSION}.dmg`) — prerequisite for versioned Homebrew cask URL
- Versioned Homebrew cask with real SHA256 and `livecheck` block — unblocks `brew upgrade` and auto-bumping

**Should have (v1.2.x, add after v1.2 validates):**
- Notarization log fetch on failure (`xcrun notarytool log <UUID>`) — without this, CI shows "status: Invalid" with no actionable detail
- `xcrun stapler validate` step after stapling — catches silent stapler failures (error 65)
- Post-notarization `spctl --assess` gate before DMG upload — catches signing regressions before they reach users
- Automated cask update CI step (compute sha256, sed version + sha256 into cask file, git commit, git push) — eliminates manual release ceremony
- Keychain cleanup in CI (`security delete-keychain` with `if: always()`) — prevents keychain accumulation if the job is cancelled

**Defer (v2+):**
- Auto-bump GitHub Action (opens PR against Homebrew tap) — adds PAT secret complexity; automate in-repo cask update first
- `zap` stanza in cask — nice for power users; non-blocking
- Styled DMG via `create-dmg` tool — cosmetic; current `hdiutil` DMG works for Homebrew

**Anti-features (do not implement):**
- `CODE_SIGNING_ALLOWED=NO` + post-build manual re-sign — this is the root cause of error 163; remove entirely
- `codesign --deep` — Apple TN2206 explicitly warns against it for nested bundles; does not propagate per-component entitlements
- `version :latest` + `sha256 :no_check` in the cask — disables `brew upgrade` and tamper detection
- `altool` for notarization — permanently sunset November 2023

### Architecture Approach

The target architecture has three layers: (1) one-time Developer Portal setup — create App IDs, enable capabilities, create Developer ID provisioning profiles, store as base64 GitHub Secrets; (2) GitHub Actions CI pipeline — import cert, install profiles to `~/Library/MobileDevice/Provisioning Profiles/` (using `.provisionprofile` extension, not `.mobileprovision`), archive, export, create DMG, notarize, staple, upload to release, update cask; (3) Homebrew tap — versioned `wblock.rb` auto-updated by CI after each successful release. The key structural change is that signing moves from a post-build shell operation to Xcode's responsibility during the archive step. The CI workflow structure (cert import, notarize, staple, release) stays the same — only the build step changes.

**Modified components:**
1. `scripts/build-dmg.sh` — replace entirely with `xcodebuild archive` + `xcodebuild -exportArchive` + `hdiutil create`; remove all `codesign` calls and the `sign_item()` function
2. `.github/workflows/homebrew-cask.yml` — add provisioning profile install step before build; update build step; add cask auto-update step after upload
3. `Casks/wblock.rb` — real version + sha256 + livecheck + verified URL parameter
4. `wBlock Privacy/wBlock_Privacy.entitlements` — verify `app-sandbox` key is present (it may already be in the file but not applied due to wrong path in build script)
5. `wBlock Advanced/wBlock_Advanced.entitlements` — add `com.apple.security.app-sandbox: true`

**New files:**
1. `ExportOptions.plist` — `method: developer-id`, `signingStyle: automatic`, `teamID: DNP7DGUB7B`, `stripSwiftSymbols: true`

### Critical Pitfalls

1. **`CODE_SIGNING_ALLOWED=NO` + manual re-sign produces error 163** — provisioning profiles cannot be embedded post-build; Gatekeeper's launch-time check rejects the app silently on macOS Sequoia+; the right-click bypass is gone. Fix: switch to `xcodebuild archive`; never separate build and sign for Developer ID distribution.

2. **wBlock Privacy signed with main app entitlements (existing bug in `build-dmg.sh`)** — the case statement maps the Privacy extension to `wBlock/wBlock.entitlements` which contains APS + iCloud entitlements. This causes notarization rejection. Fix: use `wBlock Privacy/wBlock_Privacy.entitlements` instead. This bug exists independent of the signing approach.

3. **Missing `app-sandbox` on Advanced and Privacy extensions (existing bug)** — Safari silently ignores any `.appex` without `com.apple.security.app-sandbox: true`. No error dialog, no crash log. Fix: add the entitlement to both files before the first notarization attempt.

4. **`aps-environment` + iCloud entitlements require a Developer ID provisioning profile** — the main app carries managed capabilities that Apple's notary service validates against a provisioning profile. Without one, notarization may accept the submission but macOS 15/26 launch constraints block execution. Fix: create a Developer ID provisioning profile in the Apple Developer portal for `skula.wBlock`, or strip those entitlements from the Developer ID build path if CloudKit and push are genuinely unused in the direct-download variant.

5. **Notarytool log not fetched on failure** — `notarytool submit --wait` prints "status: Invalid" with no per-component detail. The full rejection reason is in a separate JSON log fetched via `xcrun notarytool log <UUID>`. The current workflow has no log fetch on failure. Fix: capture the submission UUID from notarytool output and always run `xcrun notarytool log` when status is Invalid.

## Implications for Roadmap

Based on the dependency chain from FEATURES.md and the phase mapping from PITFALLS.md, a 3-phase structure is correct. Everything in Phase 1 is a prerequisite for phases 2 and 3 — signing must be correct before notarization is meaningful, and notarization must succeed before the cask can carry a real SHA256.

### Phase 1: Fix the Build and Entitlements

**Rationale:** The signing approach and the entitlements bugs are the root cause of every downstream failure. Nothing else can be validated until a correctly signed app can be produced. Phase 1 must be completed and verified on a clean VM before moving on. Exit criteria: `spctl --assess --type execute -v wBlock.app` passes on a machine without the Developer ID cert installed, and all 6 extensions appear in Safari Preferences after a clean DMG install.

**Delivers:** A correctly signed `.app` and `.dmg` that passes Gatekeeper on a machine without the Developer ID cert, with all 6 Safari extensions visible after a clean DMG install.

**Addresses:**
- Switch to `xcodebuild archive` + `xcodebuild -exportArchive`
- Create `ExportOptions.plist`
- Fix Privacy extension entitlements path in `build-dmg.sh`
- Add `app-sandbox` to Advanced and Privacy extension entitlements
- Verify `ENABLE_HARDENED_RUNTIME=YES` is set on all targets in Xcode project
- Verify CI keychain setup is intact (partition list, search list)

**Avoids:** Error 163, silent Safari extension registration failure, `codesign --deep` anti-pattern, signing order violation (resolved automatically by Xcode's archive step).

**Research flag:** No additional research needed. Patterns are fully documented and all implementation details are specified in STACK.md and ARCHITECTURE.md. This is a well-understood Apple-documented workflow.

### Phase 2: Fix the Notarization Pipeline

**Rationale:** Once signing is correct, notarization is the next gate. The `aps-environment`/iCloud entitlements issue requires either a Developer Portal action (creating a provisioning profile) or an entitlements split — the right path depends on whether CloudKit and push are used at runtime in the macOS direct-download build. The notarization observability gap (no log fetch on failure) must be closed before this phase enters a diagnostic loop.

**Delivers:** A notarized and stapled DMG that passes `xcrun stapler validate` and `spctl --assess --type execute` after stapling. A CI pipeline that emits actionable JSON error output on any notarization failure.

**Addresses:**
- Resolve `aps-environment`/iCloud entitlements: create Developer ID provisioning profile for `skula.wBlock` (Path A), or maintain a separate entitlements file for Developer ID builds without APS/iCloud (Path B)
- Install provisioning profile(s) in CI via GitHub Secrets before `xcodebuild archive`
- Add `xcrun notarytool log <UUID>` fetch on notarization failure
- Add `xcrun stapler validate` step after stapling
- Add post-notarization `spctl --assess` gate before DMG upload

**Avoids:** Silent notarization failure, `aps-environment: development` in a distribution build, stapler error 65, DMG modified between submission and stapling.

**Research flag:** One design decision needs resolution before Phase 2 starts — whether CloudKit and push notifications (`aps-environment`) are actively used at runtime in the macOS direct-download build path. A 5-10 minute audit of the macOS app code is sufficient. If those capabilities are unused, Path B (separate entitlements file for Developer ID) is simpler and avoids provisioning profile management complexity. If they are used, Path A (Developer ID provisioning profile) is required.

### Phase 3: Fix the Homebrew Cask and Automate

**Rationale:** Once the DMG is correctly signed and notarized, the cask can carry a real SHA256. Automating the cask update as a CI step closes the manual release loop and prevents future SHA drift between releases. This phase has no external research dependencies — Homebrew cask format is fully specified by official docs.

**Delivers:** A versioned Homebrew cask where `brew install wblock`, `brew upgrade wblock`, `brew audit --cask wblock`, and `brew livecheck wblock` all pass. CI auto-updates the cask version and SHA256 on each tag push.

**Addresses:**
- Rename DMG output to `wBlock-${VERSION}.dmg` (version extracted from tag ref)
- Update cask: versioned URL with `#{version}` interpolation, real SHA256, `livecheck` with `strategy :github_latest`, `verified:` URL parameter
- Add CI step after release upload: compute SHA256, sed version + sha256 into `Casks/wblock.rb`, git commit, git push

**Avoids:** `version :latest` / `sha256 :no_check` anti-pattern, manual SHA drift, `brew upgrade` failure, Homebrew audit failures.

**Research flag:** None. Standard patterns, fully covered by Homebrew official docs.

### Phase Ordering Rationale

- Phases 1 → 2 → 3 are strictly sequential by dependency: signing correctness is a prerequisite for notarization; notarization success produces the DMG whose SHA256 goes into the cask.
- Phases 1 and 2 are both required before the v1.2 milestone closes. Phase 3 follows immediately after without waiting for external feedback.
- macOS Sequoia and Tahoe remove all user-side Gatekeeper workarounds, making error 163 on macOS Tahoe a hard blocker with no user recovery path. Phase 1 is the highest priority item.
- The aps-environment/iCloud path decision in Phase 2 is the only item that might require a non-trivial design choice. Everything else is implementation of well-specified patterns.

### Research Flags

Needs additional investigation during planning:
- **Phase 2:** Whether CloudKit and push notifications (`aps-environment`) are actively used at runtime in the macOS direct-download build. Determines Path A (provisioning profile) vs. Path B (separate entitlements file). A code audit resolves this — no external research needed.

Standard patterns (no additional research needed):
- **Phase 1:** `xcodebuild archive` + `exportArchive` is fully documented by Apple; ExportOptions.plist structure is specified in STACK.md; entitlements files are first-party source.
- **Phase 3:** Homebrew cask format, `livecheck` stanza, and the sed-based cask update pattern are all in official Homebrew docs.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All core tools are Apple-native. xcodebuild archive/exportArchive pattern confirmed via Apple Developer Forums, official Apple docs, and verified community guides. Homebrew cask format from official Homebrew docs. No third-party dependencies required. |
| Features | HIGH | Feature set is small and well-defined. P1 features are documented Apple requirements. Priority matrix is clear and unambiguous. |
| Architecture | HIGH | Current architecture read directly from first-party source — `scripts/build-dmg.sh`, `.github/workflows/homebrew-cask.yml`, all entitlements files, `project.pbxproj`. Target architecture follows Apple-documented patterns exactly. Component boundaries are precise. |
| Pitfalls | HIGH | Most pitfalls identified from direct code inspection of the first-party codebase (wrong entitlements path in build script, missing app-sandbox in extension entitlements). Signing order and notarization failure patterns from Apple Developer Forums threads and official docs. |

**Overall confidence:** HIGH

### Gaps to Address

- **`aps-environment` / iCloud path decision (Phase 2):** Whether to create a Developer ID provisioning profile for `skula.wBlock` covering CloudKit + push (Path A), or strip those entitlements from the Developer ID build path (Path B). Resolve by auditing whether `CloudKit` containers, `UNUserNotificationCenter`, or APNs registration are called in the macOS non-App-Store code path. If not called, use Path B — simpler and no portal management. Decision point at the start of Phase 2.

- **App Group ID format fallback:** Research notes that iOS-style app group IDs (`group.skula.wBlock`, without team prefix) are now fully supported on macOS as of February 2025, with MEDIUM confidence (Apple engineer forum post, not official docs). If `xcodebuild -exportArchive` fails with an app group profile error, update the identifier to the macOS-style `DNP7DGUB7B.group.skula.wBlock` in all entitlements files and the Developer portal. This is a fallback, not a first-pass step.

- **FilterUpdateService provisioning profile:** The XPC service (`skula.wBlock.FilterUpdateService`) has network-client and app-groups entitlements. App groups alone do not require a provisioning profile for macOS Developer ID distribution. Start Phase 2 without a profile for this target and add one only if notarization rejects it with an entitlement error.

## Sources

### Primary (HIGH confidence)
- Apple TN2206 — inside-out signing order, nested code requirements for macOS bundles
- [Apple Developer Forums thread/750283](https://developer.apple.com/forums/thread/750283) — `xcodebuild archive` + `exportArchive` for Developer ID
- [Apple Developer ID overview](https://developer.apple.com/developer-id/) — certificate types, notarization requirements
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) — notarytool, stapler, hardened runtime
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) — version, sha256, url, livecheck, zap stanzas
- [Homebrew Brew Livecheck docs](https://docs.brew.sh/Brew-Livecheck) — GithubLatest strategy
- [notarytool man page](https://keith.github.io/xcode-man-pages/notarytool.1.html) — `--key`, `--wait`, `--timeout` flags
- [xcodebuild man page](https://keith.github.io/xcode-man-pages/xcodebuild.1.html) — `-allowProvisioningUpdates`, `-authenticationKeyPath`
- [freecodecamp Apple code signing handbook](https://www.freecodecamp.org/news/apple-code-signing-handbook/) — managed capabilities requiring provisioning profiles for Developer ID
- [rsms gist on macOS distribution](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5) — no `--deep`, bottom-up signing order
- wBlock first-party source: `scripts/build-dmg.sh`, `.github/workflows/homebrew-cask.yml`, all `.entitlements` files, `project.pbxproj`, `Casks/wblock.rb`

### Secondary (MEDIUM confidence)
- [defn.io distributing mac apps with GitHub Actions (2023)](https://defn.io/2023/09/22/distributing-mac-apps-with-github-actions/) — ExportOptions.plist structure, complete pipeline reference
- [Apple Developer Forums thread/721701](https://developer.apple.com/forums/thread/721701) — iOS-style app group IDs now supported on macOS (Feb 2025 Apple engineer post)
- [underpassapp.com Safari extension types](https://underpassapp.com/news/2023-4-24.html) — `com.apple.Safari.extension` vs `.web-extension` distribution rules
- [macauley/action-homebrew-bump-cask](https://github.com/macauley/action-homebrew-bump-cask) — PAT requirements for cask auto-bump
- [builtfast.dev Homebrew tap automation](https://builtfast.dev/blog/automating-homebrew-tap-updates-with-github-actions/) — cask update CI pattern

### Tertiary (referenced for context)
- [eclecticlight.co — code signing and future macOS](https://eclecticlight.co/2026/01/17/whats-happening-with-code-signing-and-future-macos/) — macOS Tahoe signing landscape
- [Apple Developer Forums thread/697838](https://developer.apple.com/forums/thread/697838) — Mac app fails to open after re-signing
- [Apple Developer Forums thread/773379](https://developer.apple.com/forums/thread/773379) — Notarization accepted but stapler fails

---
*Research completed: 2026-02-19*
*Ready for roadmap: yes*
