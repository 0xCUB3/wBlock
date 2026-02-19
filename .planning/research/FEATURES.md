# Feature Research

**Domain:** macOS Developer ID Distribution Pipeline (code signing, notarization, Homebrew cask)
**Researched:** 2026-02-19
**Confidence:** HIGH (Apple official docs + Homebrew official docs + verified community sources)

---

## Context

wBlock is a macOS app with 6 Safari extension targets (.appex), 1 XPC service (.xpc), and 1 embedded framework. The current build pipeline builds with `CODE_SIGNING_ALLOWED=NO` then re-signs manually via shell script. This approach has a known failure mode on macOS Tahoe (error 163: spawn failed) because post-build manual signing of Safari extensions and XPC services can drop or corrupt the entitlements and team identifiers that Gatekeeper validates at launch time.

The existing Homebrew cask uses `version :latest` / `sha256 :no_check`, which excludes it from `brew upgrade` and auto-bumping workflows.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that make the distribution pipeline functional. Missing any of these = app cannot be installed or launched by end users.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Developer ID Application signing — correct signing order | App must launch on any Mac without Gatekeeper blocking it; error 163 means the signing chain is broken | MEDIUM | Must sign bottom-up: frameworks → XPC services → .appex extensions → main app bundle. Never use `--deep`. Each component needs its own entitlements. Confidence: HIGH (Apple official docs) |
| Hardened runtime flag on every signed component | Required for notarization; Apple has required `--options runtime` on all notarized software since 2019 | LOW | Every `codesign` call must include `--options runtime --timestamp`. Currently present in build-dmg.sh but fragile due to post-build approach. Confidence: HIGH |
| Secure timestamp on every signature | Required for notarization; proves signing happened before certificate expiry | LOW | `--timestamp` flag in codesign. Already in build-dmg.sh. Confidence: HIGH |
| Notarization via `xcrun notarytool submit --wait` | Gatekeeper on macOS 10.15+ refuses to launch apps that are not notarized, even if signed; error 163 is consistent with quarantine/notarization failure | LOW | Currently in place in the workflow. Must be per-DMG (sign the app, pack it into DMG, notarize the DMG). Confidence: HIGH |
| Stapling the notarization ticket to the DMG | Allows Gatekeeper to verify without a network call; critical for users who install behind a firewall or offline | LOW | `xcrun stapler staple wBlock.dmg`. Already in workflow. Confidence: HIGH |
| Entitlements passed correctly to each target | Safari extensions require `com.apple.security.app-sandbox` + `com.apple.security.application-groups`; XPC service requires sandbox + network client + app group; main app requires app group + iCloud + push | HIGH | The manual re-sign approach (current) risks passing wrong entitlements or no entitlements to nested bundles. This is the most likely root cause of error 163. Confidence: HIGH |
| App group ID consistent across all targets | All 6 extensions + XPC service + main app share `group.skula.wBlock`; if any component is signed with a different or missing app group, inter-process communication fails at launch | MEDIUM | Currently in all .entitlements files. The issue is ensuring the signed binary actually carries these, not just that the .entitlements file exists. Confidence: HIGH |
| Versioned DMG filename in GitHub Release | Homebrew and users need a stable URL pattern per version; `wBlock.dmg` with no version in the name works only with `version :latest` which is non-functional for upgrades | LOW | Must be `wBlock-1.2.0.dmg` or similar so the cask URL can embed `#{version}`. Confidence: HIGH |
| SHA256 checksum in Homebrew cask | `version :latest` + `sha256 :no_check` excludes the cask from `brew upgrade` and from Homebrew's autobump robot; users cannot get updates via Homebrew | LOW | Moving to a versioned URL + real SHA256 is the minimum fix. Confidence: HIGH |

---

### Differentiators (Competitive Advantage)

Features that make the pipeline robust, automatable, and maintainable long-term. Not strictly required to unblock installation, but valuable for ongoing releases.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| `xcodebuild archive` + `exportArchive` instead of `CODE_SIGNING_ALLOWED=NO` + manual re-sign | Xcode's export pipeline handles entitlement injection, provisioning profile matching, and signing order correctly for all nested bundles; eliminates the root cause of error 163 | MEDIUM | Requires `ExportOptions.plist` with `method: developer-id`, `signingStyle: automatic`, `teamID`. The archive approach is the Apple-documented path for Developer ID distribution. Confidence: HIGH (Apple docs, defn.io verified) |
| `livecheck` block in Homebrew cask | Enables `brew livecheck` to detect new versions automatically; allows Homebrew's autobump robot or owner's own GitHub Action to open version-bump PRs without manual intervention | LOW | Use `strategy :github_latest` for casks that follow GitHub latest release. Requires versioned URL. Confidence: HIGH (Homebrew docs) |
| `zap` stanza in Homebrew cask | Allows `brew uninstall --zap` to clean up preferences, caches, and app groups from `~/Library`; expected by power users | LOW | Adds `~/Library/Preferences/skula.wBlock*.plist`, `~/Library/Application Support/wBlock`, `~/Library/Caches/skula.wBlock` etc. Confidence: MEDIUM |
| GitHub Action for automatic Homebrew cask bump on release | After a tag push, CI automatically opens a PR against the Homebrew tap to bump version + SHA256; eliminates manual steps | MEDIUM | Use `macauley/action-homebrew-bump-cask` or `eugenesvk/action-homebrew-bump-cask`. Requires a Personal Access Token (not GITHUB_TOKEN) with `public_repo` and `workflow` scopes, because the action forks the tap repo. Confidence: HIGH |
| Release artifact verification step in CI | After notarization, run `spctl --assess --type execute --verbose wBlock.app` and `codesign --verify --deep --strict --verbose=2 wBlock.app` to gate the release; fail fast if signing is broken before the DMG is published | LOW | Already partially present (`codesign --verify` in build-dmg.sh), but should be expanded and placed after notarization. Confidence: HIGH |

---

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Keeping `CODE_SIGNING_ALLOWED=NO` + post-build manual re-sign | Avoids needing provisioning profiles or Xcode archive step; faster iteration in CI | This is the root cause of error 163. Post-build codesign on `.appex` and `.xpc` bundles that were built without signing often produces incorrect or incomplete entitlement seals. macOS validates the code directory hash chain at spawn time; any mismatch = error 163. | Use `xcodebuild archive` then `xcodebuild -exportArchive` with Developer ID method. Xcode handles entitlement injection and signing order correctly. |
| `version :latest` + `sha256 :no_check` in Homebrew cask | Simplest possible cask; no need to update SHA256 on each release | Cask is excluded from `brew upgrade`, from Homebrew's autobump robot, and from `brew livecheck`. Users on Homebrew cannot update without `brew reinstall wblock`. Semantically broken. | Version-pinned cask: `version "1.2.0"`, `sha256 "..."`, versioned URL with `#{version}` interpolation, `livecheck` block. |
| Signing the DMG itself (not just the app inside) | Some tutorials suggest this | DMGs are not code-signed in the Developer ID sense — they are notarized as a container. Signing the DMG with `codesign` has no Gatekeeper effect and is not standard practice. | Sign the `.app` bundle inside, pack into DMG, notarize the DMG as a whole. |
| Using `altool` for notarization | Older workflows use `altool` | Apple permanently sunset `altool` notarization uploads on November 1, 2023. All submissions must use `xcrun notarytool`. | `xcrun notarytool submit --wait` with API key (p8 file), as currently implemented. |
| `--deep` flag in codesign | Seems convenient — signs everything in one call | `--deep` does not pass entitlements to nested bundles. Each nested component gets signed without its specific entitlements, breaking sandbox and app group validation. Apple explicitly warns against `--deep` for production signing. | Sign bottom-up: frameworks → XPC → .appex → main app, each with its own entitlements file. |
| Sparkle auto-update framework | In-app update without Homebrew; users get updates faster | Significant complexity for an app that already has an App Store version and Homebrew distribution. Sparkle requires an appcast XML feed, DSA/EdDSA signatures per release, and a separate signing key. Doubles the per-release ceremony. Homebrew + App Store covers the update surface adequately. | Use `livecheck` in Homebrew cask + standard App Store update. |

---

## Feature Dependencies

```
[Versioned DMG filename]
    └──required by──> [SHA256 in Homebrew cask]
                           └──required by──> [livecheck block]
                                                  └──enables──> [Auto-bump GitHub Action]

[xcodebuild archive + exportArchive]
    └──required before──> [Correct entitlements on all targets]
                               └──required for──> [Notarization success]
                                                       └──required for──> [Stapled DMG]
                                                                               └──required for──> [Gatekeeper acceptance on Tahoe]

[Developer ID cert in CI keychain]
    └──required by──> [xcodebuild archive + exportArchive]
    └──required by──> [Manual codesign approach (current, broken)]

[Apple API key (p8)]
    └──required by──> [xcrun notarytool submit]

[Gatekeeper acceptance]
    └──enables──> [Homebrew install without manual xattr removal]
```

### Dependency Notes

- **Versioned DMG must precede SHA256 cask:** The URL cannot embed `#{version}` if the artifact has no version in its name. The current workflow outputs a flat `wBlock.dmg` — this must change before the Homebrew cask can be properly versioned.
- **Correct signing must precede notarization:** Apple's notary service rejects submissions where components have invalid entitlements or are missing hardened runtime. Fix signing before expecting notarization to succeed.
- **xcodebuild archive approach requires Xcode project signing configuration:** The project must have `CODE_SIGN_STYLE = Automatic` or explicit provisioning profile assignments in the Xcode project file. If `CODE_SIGNING_ALLOWED=NO` is baked into the project's build settings (not just passed on the command line), this must be reverted.

---

## MVP Definition

### Launch With (v1.2 — Unblocks installation on macOS Tahoe)

These are the minimum changes to make `brew install wblock` produce an app that launches without error 163 on macOS Tahoe.

- [ ] **Switch to `xcodebuild archive` + `exportArchive`** — Replace the `CODE_SIGNING_ALLOWED=NO` + manual re-sign approach with Xcode's native archive/export pipeline using `method: developer-id`. This is the root cause fix for error 163.
- [ ] **ExportOptions.plist** — Create with `method: developer-id`, `signingStyle: automatic`, `teamID: DNP7DGUB7B`. Commit to repository.
- [ ] **Versioned DMG output** — Rename output artifact to `wBlock-${VERSION}.dmg` (extract version from the tag); update the GitHub Release upload step accordingly.
- [ ] **Versioned Homebrew cask** — Replace `version :latest` / `sha256 :no_check` with a pinned `version` stanza, real `sha256`, versioned URL with `#{version}` interpolation, and a `livecheck` block using `strategy :github_latest`.

### Add After Validation (v1.2.x)

- [ ] **Auto-bump GitHub Action** — Add a workflow step that runs after a successful release to open a PR against the Homebrew tap with the new version and SHA256; trigger: first time a manual Homebrew cask bump is needed after v1.2 ships.
- [ ] **`zap` stanza in cask** — Add cleanup paths for `~/Library/Preferences`, `~/Library/Application Support`, `~/Library/Caches`; trigger: user reports leftover files after uninstall.
- [ ] **Post-notarization spctl verify step** — After stapling, run `spctl --assess --type execute --verbose` on the extracted app to gate the release; trigger: any Gatekeeper failure in the wild.

### Future Consideration (v2+)

- [ ] **`create-dmg` for styled DMG** — Replace `hdiutil create -format UDZO` with `create-dmg` for a drag-and-drop installer UI; defer until users request it. Current plain DMG works fine for Homebrew.
- [ ] **Multi-arch SHA256 in cask** — Homebrew supports separate `sha256` per arch (`on_arm` / `on_intel`); only needed if wBlock ships distinct arm64 and x86_64 binaries. Currently a universal binary, so single SHA256 is correct.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| `xcodebuild archive` + `exportArchive` (root cause fix) | HIGH — app fails to launch today | MEDIUM — requires ExportOptions.plist, project config audit | P1 |
| Versioned DMG filename | HIGH — blocks Homebrew versioning | LOW — change output path in build script and CI | P1 |
| Versioned Homebrew cask + real SHA256 | HIGH — current cask cannot upgrade | LOW — edit cask file; compute SHA256 after build | P1 |
| `livecheck` block in cask | MEDIUM — enables automated bumping | LOW — 3-line addition to cask | P1 |
| Auto-bump GitHub Action | MEDIUM — removes manual release step | MEDIUM — new workflow file, PAT secret required | P2 |
| `zap` stanza | LOW — cosmetic for power users | LOW | P3 |
| Post-notarization spctl gate | MEDIUM — catches signing regressions before publishing | LOW — 2-line addition to workflow | P2 |

**Priority key:**
- P1: Must have for launch (v1.2)
- P2: Should have, add when possible
- P3: Nice to have, future consideration

---

## Competitor Distribution Analysis

How comparable macOS apps with Safari extensions handle their distribution pipeline:

| Aspect | AdGuard for Safari | 1Blocker | wBlock (current) | wBlock (target) |
|--------|-------------------|----------|-----------------|----------------|
| Build method | Xcode archive + export | Xcode archive + export | `CODE_SIGNING_ALLOWED=NO` + manual re-sign | Xcode archive + export |
| Signing approach | Developer ID via exportArchive | Developer ID via exportArchive | Post-build codesign per component | Developer ID via exportArchive |
| Notarization | `notarytool` per DMG | `notarytool` per DMG | `notarytool` (in place) | `notarytool` (unchanged) |
| Homebrew cask | Versioned, livecheck | Versioned, livecheck | `version :latest`, no livecheck | Versioned, livecheck |
| Auto-update | Sparkle + Homebrew | Sparkle + Homebrew | App Store only | App Store + Homebrew |

**Key insight:** Every mature macOS app using Safari extensions distributes via `xcodebuild archive` then `exportArchive`. The post-build manual re-sign approach is non-standard and specifically breaks on newer macOS versions where the kernel validates the code directory hashes of Safari extensions and XPC services at spawn time.

---

## Implementation Notes

### What error 163 means

Error 163 (`errSecCSInvalidIdentity` or spawn failure) occurs when the kernel validates a process's code signature at spawn time and the identity cannot be verified. For an app bundle with Safari extensions and XPC services, this typically means:

1. The entitlement seal in the code directory does not match the entitlements claimed at runtime, OR
2. The team identifier embedded in the code signature does not match the team ID expected by the app group container, OR
3. The hardened runtime flag is inconsistent across nested bundles.

All three root causes point to the manual post-build codesign approach. Xcode's `exportArchive` with `method: developer-id` handles all three correctly.

### ExportOptions.plist (target state)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>DNP7DGUB7B</string>
</dict>
</plist>
```

### Homebrew cask (target state)

```ruby
cask "wblock" do
  version "1.2.0"
  sha256 "abc123..."  # computed after build: shasum -a 256 wBlock-1.2.0.dmg

  url "https://github.com/0xCUB3/wBlock/releases/download/v#{version}/wBlock-#{version}.dmg",
      verified: "github.com/0xCUB3/wBlock/"
  name "wBlock"
  desc "Safari content blocker for macOS, iOS, and iPadOS"
  homepage "https://github.com/0xCUB3/wBlock"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "wBlock.app"

  zap trash: [
    "~/Library/Preferences/skula.wBlock.plist",
    "~/Library/Application Support/wBlock",
    "~/Library/Caches/skula.wBlock",
  ]
end
```

### Signing order for wBlock (bottom-up)

The correct order for manual codesign (if not using exportArchive) is:

1. `wBlockCoreService.framework` (embedded framework)
2. `FilterUpdateService.xpc` — with `FilterUpdateService.entitlements`
3. Each `.appex` extension — with its own entitlements file:
   - `wBlock Ads.appex` → `wBlock_Ads.entitlements`
   - `wBlock Privacy.appex` → `wBlock_Privacy.entitlements` (currently using `wBlock.entitlements`)
   - `wBlock Security.appex` → `wBlock_Security.entitlements`
   - `wBlock Foreign.appex` → `wBlock_Foreign.entitlements`
   - `wBlock Custom.appex` → `wBlock_Custom.entitlements`
   - `wBlock Advanced.appex` → `wBlock_Advanced.entitlements`
4. `wBlock.app` — with `wBlock.entitlements`

This order is already implemented in `scripts/build-dmg.sh`, but the root issue is that when `CODE_SIGNING_ALLOWED=NO` was used at build time, the nested bundles may have been built without their entitlements baked into the binary, making post-build signing unreliable.

### The application-groups entitlement and Developer ID

wBlock's main app entitlements include `aps-environment` (push notifications) and `com.apple.developer.icloud-container-identifiers` (CloudKit). These are managed entitlements that require provisioning profile authorization on iOS but are typically OK without a profile for Developer ID on macOS — macOS Developer ID apps can use application-groups and CloudKit without an explicit provisioning profile as long as the Xcode project is configured with automatic signing. The `exportArchive` path handles this automatically.

---

## Sources

- **Apple Developer ID overview:** [Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/) — requirements, certificate types, notarization; HIGH confidence (official Apple)
- **Notarization workflow:** [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) — notarytool, stapler, hardened runtime requirements; HIGH confidence (official Apple)
- **Distributing Mac apps via GitHub Actions:** [defn.io walkthrough (2023)](https://defn.io/2023/09/22/distributing-mac-apps-with-github-actions/) — ExportOptions.plist structure, archive/export workflow, DMG creation, notarization; MEDIUM confidence (third-party, verified against Apple docs)
- **Homebrew Cask Cookbook:** [docs.brew.sh/Cask-Cookbook](https://docs.brew.sh/Cask-Cookbook) — version stanza, sha256, livecheck, zap, auto_updates; HIGH confidence (official Homebrew docs)
- **Homebrew livecheck strategies:** [docs.brew.sh/Brew-Livecheck](https://docs.brew.sh/Brew-Livecheck) — GithubLatest, GithubReleases strategies; HIGH confidence (official Homebrew docs)
- **`version :latest` exclusion from autobump:** [Homebrew/homebrew-cask discussions](https://github.com/orgs/Homebrew/discussions/3808) — confirmed casks with `:latest` excluded from bump workflows; HIGH confidence (official maintainer discussion)
- **Auto-bump GitHub Action:** [macauley/action-homebrew-bump-cask](https://github.com/macauley/action-homebrew-bump-cask) — PAT requirement, inputs; MEDIUM confidence (community action, widely used)
- **macOS signing bottom-up order:** [rsms gist on macOS distribution](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5) — sign nested components before parent; never use `--deep`; HIGH confidence (well-cited community reference)
- **`--deep` anti-pattern (entitlements not propagated):** Apple Developer Forums, multiple threads — confirmed `--deep` does not pass per-component entitlements; HIGH confidence (Apple dev forums, corroborated by official docs)
- **altool sunset (November 2023):** Apple official announcement — `xcrun notarytool` is the only supported path; HIGH confidence (official)
- **wBlock entitlements (first-party):** `/Users/skula/Documents/wBlock/wBlock/wBlock.entitlements`, `wBlock Ads/wBlock_Ads.entitlements`, `FilterUpdateService/FilterUpdateService.entitlements` — confirmed app group IDs, sandbox flags; HIGH confidence (source code)

---

*Feature research for: macOS Developer ID Distribution Pipeline*
*Researched: 2026-02-19*
