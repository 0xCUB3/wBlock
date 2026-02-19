# Roadmap: wBlock

## Milestones

- ✅ **v1.0 Filter Compatibility** — Phases 1-6 (shipped 2026-02-18)
- ✅ **v1.1 Element Zapper Rule Management** — Phases 7-9 (shipped 2026-02-19)
- 🚧 **v1.2 Distribution & Code Signing** — Phases 10-12 (in progress)

## Phases

<details>
<summary>✅ v1.0 Filter Compatibility (Phases 1-6) — SHIPPED 2026-02-18</summary>

- [x] Phase 1: Validation Fix and Platform Constants (2/2 plans) — completed 2026-02-17
- [x] Phase 2: Conditional Evaluator (1/1 plan) — completed 2026-02-17
- [x] Phase 3: Include Resolver (2/2 plans) — completed 2026-02-17
- [x] Phase 4: Pipeline Integration (2/2 plans) — completed 2026-02-18
- [x] Phase 5: Hardening and UX (2/2 plans) — completed 2026-02-18
- [x] Phase 6: Background Path Parity (1/1 plan) — completed 2026-02-18

See: `.planning/milestones/v1.0-ROADMAP.md` for full details.

</details>

<details>
<summary>✅ v1.1 Element Zapper Rule Management (Phases 7-9) — SHIPPED 2026-02-19</summary>

- [x] Phase 7: iOS Sync Bridge (1/1 plan) — completed 2026-02-19
- [x] Phase 8: Data Layer (1/1 plan) — completed 2026-02-19
- [x] Phase 9: Settings UI and Rule Management (1/1 plan) — completed 2026-02-19

See: `.planning/milestones/v1.1-ROADMAP.md` for full details.

</details>

### 🚧 v1.2 Distribution & Code Signing (In Progress)

**Milestone Goal:** Fix DMG code signing so the Homebrew/direct-download release works on macOS Tahoe, improve the notarization pipeline, and add proper version pinning to the Homebrew cask.

- [x] **Phase 10: Build and Entitlements** — Switch to `xcodebuild archive` + `exportArchive`, fix two pre-existing entitlements bugs, gate CI on Gatekeeper assessment (completed 2026-02-19)
- [x] **Phase 11: Notarization Pipeline** — Resolve `aps-environment`/iCloud entitlements for Developer ID, install provisioning profiles in CI, add observability and validation steps (completed 2026-02-19)
- [ ] **Phase 12: Homebrew Cask** — Versioned DMG output, versioned cask with real SHA256 and livecheck, CI auto-update on each tag push

## Phase Details

### Phase 10: Build and Entitlements
**Goal**: A correctly signed `.app` and `.dmg` that passes Gatekeeper on a machine without the Developer ID cert installed, with all Safari extensions registering in Safari Preferences after a clean install
**Depends on**: Nothing (first phase of v1.2)
**Requirements**: SIGN-01, SIGN-02, SIGN-03, SIGN-04, SIGN-05
**Success Criteria** (what must be TRUE):
  1. `spctl --assess --type execute -v wBlock.app` exits 0 on a clean machine (no developer cert installed)
  2. All 6 Safari extensions appear in Safari Preferences after installing the DMG on a clean machine
  3. `ExportOptions.plist` exists in the repository and the build script uses `xcodebuild -exportArchive` with it
  4. Privacy extension is signed with `wBlock_Privacy.entitlements`, not the main app entitlements
  5. Advanced and Privacy extension entitlements include `com.apple.security.app-sandbox: true`
**Plans**: 2 plans

Plans:
- [x] 10-01-PLAN.md -- Fix extension entitlements (add app-sandbox) and hardened runtime
- [x] 10-02-PLAN.md -- Rewrite build-dmg.sh with archive+exportArchive, create ExportOptions.plist, add spctl CI gate

### Phase 11: Notarization Pipeline
**Goal**: A notarized and stapled DMG that macOS accepts at launch, with a CI pipeline that emits actionable error output on failure and cleans up after itself
**Depends on**: Phase 10
**Requirements**: NOTR-01, NOTR-02, NOTR-03, NOTR-04, NOTR-05
**Success Criteria** (what must be TRUE):
  1. DMG passes `xcrun stapler validate` after the notarization step completes
  2. The app launches on macOS Tahoe without a Gatekeeper prompt or error 163 after a clean DMG install
  3. When notarization fails, CI prints the full notarytool JSON log (not just "status: Invalid")
  4. CI keychain is deleted in an `if: always()` cleanup step, preventing accumulation across cancelled runs
**Plans**: 1 plan

Plans:
- [ ] 11-01-PLAN.md -- Add provisioning profile install, notarytool log fetch, stapler validate, and keychain cleanup to CI

### Phase 12: Homebrew Cask
**Goal**: A versioned Homebrew cask where `brew install wblock`, `brew upgrade wblock`, `brew audit --cask wblock`, and `brew livecheck wblock` all pass, with CI keeping the cask current on every tag push
**Depends on**: Phase 11
**Requirements**: BREW-01, BREW-02, BREW-03, BREW-04, BREW-05
**Success Criteria** (what must be TRUE):
  1. `brew install wblock` installs the current version and the app launches without Gatekeeper errors
  2. `brew upgrade wblock` succeeds after a new tag is pushed (version and SHA256 in cask match the release)
  3. `brew audit --cask wblock` passes with no errors or warnings
  4. `brew livecheck wblock` reports the current GitHub release version
  5. The cask includes a `zap` stanza that removes preferences, caches, and app support on uninstall
**Plans**: TBD

Plans:
- [ ] 12-01: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Validation Fix and Platform Constants | v1.0 | 2/2 | Complete | 2026-02-17 |
| 2. Conditional Evaluator | v1.0 | 1/1 | Complete | 2026-02-17 |
| 3. Include Resolver | v1.0 | 2/2 | Complete | 2026-02-17 |
| 4. Pipeline Integration | v1.0 | 2/2 | Complete | 2026-02-18 |
| 5. Hardening and UX | v1.0 | 2/2 | Complete | 2026-02-18 |
| 6. Background Path Parity | v1.0 | 1/1 | Complete | 2026-02-18 |
| 7. iOS Sync Bridge | v1.1 | 1/1 | Complete | 2026-02-19 |
| 8. Data Layer | v1.1 | 1/1 | Complete | 2026-02-19 |
| 9. Settings UI and Rule Management | v1.1 | 1/1 | Complete | 2026-02-19 |
| 10. Build and Entitlements | v1.2 | Complete    | 2026-02-19 | 2026-02-19 |
| 11. Notarization Pipeline | 1/1 | Complete   | 2026-02-19 | - |
| 12. Homebrew Cask | v1.2 | 0/? | Not started | - |
