# Requirements: wBlock v1.2 Distribution & Code Signing

**Defined:** 2026-02-19
**Core Value:** Any popular community filter list that works in AdGuard or uBlock Origin should also work in wBlock

## v1.2 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Build & Signing

- [x] **SIGN-01**: App is built via `xcodebuild archive` + `xcodebuild -exportArchive` with `method: developer-id` instead of `CODE_SIGNING_ALLOWED=NO` + manual re-sign
- [x] **SIGN-02**: `ExportOptions.plist` with `method: developer-id`, `signingStyle: automatic`, `teamID: DNP7DGUB7B` is committed to the repository
- [x] **SIGN-03**: Privacy extension is signed with its own entitlements file (`wBlock_Privacy.entitlements`), not the main app's
- [x] **SIGN-04**: Advanced and Privacy extension entitlements include `com.apple.security.app-sandbox: true`
- [x] **SIGN-05**: CI runs `spctl --assess --type execute` after signing to gate the release before publishing

### Notarization

- [x] **NOTR-01**: `aps-environment`/iCloud entitlements are resolved for Developer ID distribution (either provisioning profile or separate entitlements file)
- [x] **NOTR-02**: Provisioning profile(s) are installed in CI before `xcodebuild archive` via GitHub Secrets
- [x] **NOTR-03**: CI fetches `xcrun notarytool log <UUID>` on notarization failure for actionable error output
- [x] **NOTR-04**: CI runs `xcrun stapler validate` after stapling to catch silent failures
- [x] **NOTR-05**: CI deletes the signing keychain in an `if: always()` step to prevent accumulation

### Homebrew

- [x] **BREW-01**: DMG output is versioned (`wBlock-${VERSION}.dmg`) with version extracted from the tag
- [x] **BREW-02**: Homebrew cask uses pinned `version`, real `sha256`, versioned URL with `#{version}` interpolation
- [x] **BREW-03**: Homebrew cask includes a `livecheck` block with `strategy :github_latest`
- [x] **BREW-04**: CI auto-updates version and SHA256 in `Casks/wblock.rb` on each tag push
- [x] **BREW-05**: Homebrew cask includes a `zap` stanza to clean up preferences, caches, and app support

## Future Requirements

Deferred to v1.2.x or later. Tracked but not in current roadmap.

### Automation

- **AUTO-01**: GitHub Action opens PR against Homebrew tap to bump version on release (requires PAT with `public_repo` scope)
- **AUTO-02**: Styled DMG via `create-dmg` with drag-and-drop installer UI

## Out of Scope

| Feature | Reason |
|---------|--------|
| `CODE_SIGNING_ALLOWED=NO` + manual re-sign | Root cause of error 163; must be removed entirely |
| `codesign --deep` | Does not propagate per-component entitlements; Apple warns against it |
| `version :latest` + `sha256 :no_check` | Disables `brew upgrade` and tamper detection |
| `altool` for notarization | Permanently sunset November 2023 |
| Sparkle auto-update framework | App Store + Homebrew covers update surface; Sparkle adds significant complexity |
| Multi-arch SHA256 in cask | wBlock ships universal binary; single SHA256 is correct |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SIGN-01 | Phase 10 | Complete |
| SIGN-02 | Phase 10 | Complete |
| SIGN-03 | Phase 10 | Complete |
| SIGN-04 | Phase 10 | Complete |
| SIGN-05 | Phase 10 | Complete |
| NOTR-01 | Phase 11 | Complete |
| NOTR-02 | Phase 11 | Complete |
| NOTR-03 | Phase 11 | Complete |
| NOTR-04 | Phase 11 | Complete |
| NOTR-05 | Phase 11 | Complete |
| BREW-01 | Phase 12 | Complete |
| BREW-02 | Phase 12 | Complete |
| BREW-03 | Phase 12 | Complete |
| BREW-04 | Phase 12 | Complete |
| BREW-05 | Phase 12 | Complete |

**Coverage:**
- v1.2 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-02-19*
*Last updated: 2026-02-19 after roadmap creation*
