# Architecture Research

**Domain:** macOS app code signing and Homebrew distribution pipeline
**Researched:** 2026-02-19
**Confidence:** HIGH (current codebase read directly; Apple official docs and developer forums verified)

---

## Current State (Broken Architecture)

The existing pipeline has a fundamental structural error: it builds with `CODE_SIGNING_ALLOWED=NO` then manually re-signs after the fact. This breaks because:

1. Xcode does not embed provisioning profiles during a `CODE_SIGNING_ALLOWED=NO` build
2. Re-signing with `codesign` alone cannot replicate what Xcode does — it cannot create or embed the `embedded.provisionprofile` inside each bundle
3. For `com.apple.Safari.content-blocker` extensions that share an App Group, the provisioning profiles must be embedded at build time so macOS can validate group membership at runtime

Additionally, the main app entitlements include `aps-environment` (push notifications) and iCloud/CloudKit — these are "advanced capabilities" that require a **Developer ID provisioning profile** even for distribution outside the App Store. The current build never creates or embeds these profiles.

The Homebrew cask uses `version "latest"` and `sha256 :no_check`, which means users get no integrity verification and `brew upgrade` cannot detect version changes.

---

## Recommended Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Developer Portal (one-time setup)            │
│  App IDs registered + capabilities enabled + profiles created        │
│  → Developer ID Application cert (in P12 secret)                    │
│  → Developer ID provisioning profiles (in base64 secrets)           │
└─────────────────────────────────────────────────────────────────────┘
                                |
                                v
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub Actions Workflow                        │
│                                                                      │
│  1. Import Developer ID cert → temp keychain                         │
│  2. Install provisioning profiles → ~/Library/MobileDevice/...      │
│  3. xcodebuild archive (Automatic signing, cert in keychain)         │
│     → wBlock.xcarchive (properly signed, profiles embedded)         │
│  4. xcodebuild -exportArchive (method: developer-id)                 │
│     → wBlock.app (signed and ready for notarization)                │
│  5. hdiutil create → wBlock.dmg                                      │
│  6. xcrun notarytool submit --wait → notarize DMG                   │
│  7. xcrun stapler staple → attach ticket to DMG                     │
│  8. gh release upload → attach DMG to GitHub release tag            │
│  9. Calculate sha256 of DMG                                          │
│  10. Update Casks/wblock.rb (version + sha256) → commit + push      │
└─────────────────────────────────────────────────────────────────────┘
                                |
                                v
┌─────────────────────────────────────────────────────────────────────┐
│                       Homebrew Tap (Casks/wblock.rb)                 │
│  version "2.0.1"                                                     │
│  sha256 "abc123..."                                                  │
│  url "https://github.com/.../releases/download/v2.0.1/wBlock.dmg"  │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Modified vs New |
|-----------|----------------|-----------------|
| `scripts/build-dmg.sh` | Build, sign, and package the DMG | Replace entirely with archive/export approach |
| `ExportOptions.plist` | Tell xcodebuild how to export: method, team, signing style | New file (checked into repo) |
| `.github/workflows/homebrew-cask.yml` | CI orchestration: cert import, profile install, build, notarize, release, cask update | Modify significantly |
| `Casks/wblock.rb` | Homebrew cask descriptor | Modify: add real version + sha256 |
| Developer Portal (one-time) | Register App IDs, enable capabilities, create provisioning profiles | Manual prerequisite |

---

## Recommended Project Structure Changes

```
wBlock/
├── ExportOptions.plist          # NEW — tells xcodebuild how to export for Developer ID
├── scripts/
│   └── build-dmg.sh            # REPLACE — remove CODE_SIGNING_ALLOWED=NO approach
├── .github/workflows/
│   └── homebrew-cask.yml       # MODIFY — add profile install, fix build flow
└── Casks/
    └── wblock.rb               # MODIFY — real version + sha256
```

---

## Architectural Patterns

### Pattern 1: xcodebuild archive + exportArchive (the correct signing approach)

**What:** Archive the app with Xcode's signing machinery active, then export the archive. Signing happens during `xcodebuild archive` — not after. The cert in the keychain and provisioning profiles in `~/Library/MobileDevice/Provisioning Profiles/` are picked up automatically by Xcode's Automatic signing machinery.

**When to use:** Always for macOS Developer ID distribution. This is Apple's supported workflow.

**Trade-offs:** Requires provisioning profiles for any target with advanced capabilities (App Groups, CloudKit, push notifications). Simpler than manual `codesign` because Xcode handles signing order (frameworks → extensions → XPC services → app).

**Build script pattern:**

```bash
# Step 1: Archive (signing happens here)
xcodebuild archive \
  -project wBlock.xcodeproj \
  -scheme wBlock \
  -configuration Release \
  -destination "platform=macOS" \
  -archivePath build/wBlock.xcarchive \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=DNP7DGUB7B

# Step 2: Export (extracts signed .app from archive)
xcodebuild -exportArchive \
  -archivePath build/wBlock.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates

# Step 3: Package into DMG
hdiutil create \
  -volname "wBlock" \
  -srcfolder build/export/wBlock.app \
  -ov -format UDZO \
  build/wBlock.dmg
```

### Pattern 2: ExportOptions.plist for Developer ID

**What:** A plist checked into the repo that declares the export method and signing configuration. The `developer-id` method tells Xcode to sign for distribution outside the App Store.

**When to use:** Always with `xcodebuild -exportArchive`.

**File content:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>DNP7DGUB7B</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
```

**Note on `signingStyle`:** Use `automatic` so Xcode finds the cert and profiles that are installed. Do not use `manual` unless you have explicit `PROVISIONING_PROFILE_SPECIFIER` per target in the project.

### Pattern 3: Provisioning Profile Installation in CI

**What:** Store each provisioning profile as a base64-encoded GitHub Secret. In CI, decode and place in `~/Library/MobileDevice/Provisioning Profiles/` with a `.provisionprofile` extension (not `.mobileprovision` — macOS profiles use `.provisionprofile`).

**Why this matters:** macOS App Groups entitlement is handled differently from iOS. On macOS, the OS does not require the provisioning profile to contain the app groups entitlement for Developer ID distribution — but the profile must still be present for any target with advanced capabilities (CloudKit, push notifications). The main app target has both.

**Critical:** Use `.provisionprofile` extension on macOS. The `.mobileprovision` extension causes xcodebuild to run iOS-style validation that incorrectly requires App Groups to be listed in the profile.

**CI step pattern:**

```yaml
- name: Install provisioning profiles
  env:
    MACOS_PROFILE_APP_B64: ${{ secrets.MACOS_PROFILE_APP_B64 }}
    MACOS_PROFILE_FILTERUPDATESERVICE_B64: ${{ secrets.MACOS_PROFILE_FILTERUPDATESERVICE_B64 }}
  run: |
    PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$PROFILES_DIR"
    echo "${MACOS_PROFILE_APP_B64}" | base64 --decode \
      > "$PROFILES_DIR/wBlock_App.provisionprofile"
    echo "${MACOS_PROFILE_FILTERUPDATESERVICE_B64}" | base64 --decode \
      > "$PROFILES_DIR/wBlock_FilterUpdateService.provisionprofile"
    # Content blocker extensions that only use app groups
    # do NOT need provisioning profiles for Developer ID distribution
    # (app groups are a "free" entitlement on macOS for non-App-Store)
```

**Which targets need provisioning profiles:**
- `skula.wBlock` (main app) — YES: has CloudKit + push notifications (advanced capabilities)
- `skula.wBlock.FilterUpdateService` — VERIFY: has network client + app groups; app groups alone do not require a profile on macOS, but verify if notarization rejects it
- Extension targets (Ads, Advanced, Security, Foreign, Custom, Privacy) — likely NO: only have app-sandbox + app-groups; on macOS, app groups for Developer ID do not require a provisioning profile

### Pattern 4: Homebrew Cask with Real Version and SHA256

**What:** Use an explicit version number and SHA256 hash in the cask. The URL includes the version. A CI step after release calculates the sha256 and updates the cask file.

**Why:** `version "latest"` with `sha256 :no_check` provides no security guarantee and prevents `brew upgrade` from detecting version changes. Homebrew's own cask audit will flag `:no_check` as an issue for third-party taps.

**Cask structure:**

```ruby
cask "wblock" do
  version "2.0.1"
  sha256 "abc123def456..."  # SHA256 of the notarized DMG

  url "https://github.com/0xCUB3/wBlock/releases/download/v#{version}/wBlock.dmg"
  name "wBlock"
  desc "Safari content blocker for macOS, iOS, and iPadOS"
  homepage "https://github.com/0xCUB3/wBlock"

  app "wBlock.app"

  zap trash: [
    "~/Library/Group Containers/group.skula.wBlock",
    "~/Library/Preferences/skula.wBlock.plist",
  ]
end
```

**Automated cask update in CI:**

```bash
VERSION="${GITHUB_REF_NAME#v}"  # strip leading 'v' from tag
DMG="build/wBlock.dmg"
SHA256=$(shasum -a 256 "${DMG}" | awk '{print $1}')

# Update version and sha256 in cask file
sed -i '' "s/version \".*\"/version \"${VERSION}\"/" Casks/wblock.rb
sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" Casks/wblock.rb

git config user.email "actions@github.com"
git config user.name "GitHub Actions"
git add Casks/wblock.rb
git commit -m "bump wblock cask to ${VERSION}"
git push
```

---

## Data Flow

### Build + Release Flow

```
[Tag pushed: v2.0.1]
    |
    v
[GitHub Actions: homebrew-cask.yml triggered]
    |
    v
[Import Developer ID cert into temp keychain]
    |
    v
[Decode + install provisioning profiles to ~/Library/MobileDevice/...]
    |
    v
[xcodebuild archive → wBlock.xcarchive]
    |  (Xcode: resolves cert from keychain, picks up profiles,
    |   signs frameworks → XPC → extensions → app in correct order,
    |   embeds profiles into bundles)
    v
[xcodebuild -exportArchive → build/export/wBlock.app]
    |  (reads ExportOptions.plist: method=developer-id)
    v
[hdiutil create → build/wBlock.dmg]
    |
    v
[xcrun notarytool submit --wait → Apple checks for malware]
    |
    v
[xcrun stapler staple → ticket embedded in DMG]
    |
    v
[gh release upload → DMG attached to GitHub release v2.0.1]
    |
    v
[sha256 = $(shasum -a 256 wBlock.dmg)]
    |
    v
[sed update Casks/wblock.rb: version + sha256]
    |
    v
[git push → cask file updated in repo]
    |
    v
[Users: brew install wblock / brew upgrade wblock → verified DMG]
```

### Signing Order (Critical)

Xcode enforces correct signing order automatically during `xcodebuild archive`. The manual approach in `build-dmg.sh` attempted to replicate this but missed that embedded bundles must be signed before their parents:

```
1. wBlockCoreService.framework (embedded framework)
2. FilterUpdateService.xpc (XPC service)
3. wBlock Ads.appex (content blocker extension)
4. wBlock Advanced.appex
5. wBlock Security.appex
6. wBlock Foreign.appex
7. wBlock Custom.appex
8. wBlock Privacy.appex
9. wBlock.app (main bundle, signed last)
```

`xcodebuild archive` handles this order. Manual `codesign` in the old script did frameworks first, then XPC, then extensions, then app — which is correct order, but without embedded provisioning profiles.

---

## Anti-Patterns

### Anti-Pattern 1: CODE_SIGNING_ALLOWED=NO + Manual Codesign

**What people do:** Build with `CODE_SIGNING_ALLOWED=NO` to avoid needing certs during the build, then call `codesign --force --sign "Developer ID Application: ..."` on each bundle afterward.

**Why it's wrong:** Provisioning profiles cannot be embedded after the fact with `codesign`. The profile must be embedded during the Xcode build step. Without embedded profiles, the main app's CloudKit and push notification entitlements have no profile backing them, and macOS Gatekeeper will block the app at launch (not install — launch).

**Do this instead:** Import the Developer ID cert into a keychain before running `xcodebuild archive`. Let Xcode's Automatic signing find the cert and profiles and embed them during the build.

### Anti-Pattern 2: -allowProvisioningUpdates Without API Key in Headless CI

**What people do:** Pass `-allowProvisioningUpdates` to `xcodebuild` in CI and expect it to automatically create/download profiles.

**Why it's wrong:** `-allowProvisioningUpdates` with Automatic signing requires Xcode to communicate with Apple's developer portal. In headless CI this needs either: (a) the Apple ID signed into Xcode on a macOS machine, or (b) `-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID` passed to xcodebuild with an App Store Connect API key. Without these, the flag is ignored or fails silently.

**Do this instead:** Pre-install provisioning profiles as base64 GitHub Secrets (downloaded manually from the Developer Portal and exported by Xcode). This avoids needing live developer portal access in CI. The cert is still imported from a secret; the profiles are decoded and dropped in the standard location before `xcodebuild archive` runs.

### Anti-Pattern 3: .mobileprovision Extension for macOS Profiles

**What people do:** Export a macOS provisioning profile and save it with a `.mobileprovision` extension in CI (copying iOS workflows).

**Why it's wrong:** When xcodebuild encounters a `.mobileprovision` file for a macOS target, it runs iOS-style validation, including requiring App Groups to be listed in the profile. On macOS, App Groups for Developer ID distribution do not need to be in the profile. The `.mobileprovision` extension triggers incorrect validation errors.

**Do this instead:** Use `.provisionprofile` extension for macOS provisioning profiles. The provisioning profile file itself is the same format — only the filename extension matters to xcodebuild.

### Anti-Pattern 4: version "latest" + sha256 :no_check in the Cask

**What people do:** Point the cask URL at the `/releases/latest/download/` GitHub redirect and skip SHA256 verification.

**Why it's wrong:** (1) No integrity check — a compromised release asset goes undetected. (2) `brew upgrade` cannot determine if the installed version is current because there is no version to compare. (3) Homebrew's own policies discourage `:no_check` for anything other than truly unversioned URLs.

**Do this instead:** Use a versioned download URL (`/releases/download/v#{version}/wBlock.dmg`) and a real SHA256. Automate the cask update as the final step in the release CI pipeline.

### Anti-Pattern 5: Hardcoded Entitlements That Block Developer ID Notarization

**What people do:** Leave `aps-environment: development` in the main app entitlements for Developer ID distribution.

**Why it's wrong:** The `aps-environment` entitlement with value `development` is for Xcode-managed development builds. For Developer ID distribution, the notary service may reject the app if the entitlement is present but the provisioning profile doesn't authorize it, or if it's inconsistent with the signing context.

**Do this instead:** Use separate `.entitlements` files for development vs. distribution builds (via Xcode configurations), or verify that the Developer ID provisioning profile you create explicitly includes the push notifications capability with the correct environment.

---

## Integration Points

### Modified Files

| File | Change | Why |
|------|--------|-----|
| `scripts/build-dmg.sh` | Replace `CODE_SIGNING_ALLOWED=NO` build + manual codesign with `xcodebuild archive` + `xcodebuild -exportArchive` | Signing must happen during Xcode build |
| `.github/workflows/homebrew-cask.yml` | Add profile install step before build; update build step; add cask update step | CI needs profiles before build; cask needs real version |
| `Casks/wblock.rb` | Change `version "latest"` + `sha256 :no_check` to real version + sha256 | Integrity verification; `brew upgrade` compatibility |

### New Files

| File | Purpose |
|------|---------|
| `ExportOptions.plist` | Declares `method: developer-id`, `signingStyle: automatic`, `teamID: DNP7DGUB7B` |

### New GitHub Secrets Required

| Secret Name | Content | How to Obtain |
|-------------|---------|---------------|
| `MACOS_CERT_P12_B64` | (already exists) Developer ID Application cert as base64 P12 | Keychain Access → export cert |
| `MACOS_CERT_PASSWORD` | (already exists) P12 password | Set when exporting P12 |
| `MACOS_PROFILE_APP_B64` | Developer ID provisioning profile for `skula.wBlock` as base64 | Developer Portal → Profiles → Create → Developer ID → select App ID |
| `MACOS_PROFILE_FILTERUPDATESERVICE_B64` | Developer ID provisioning profile for `skula.wBlock.FilterUpdateService` | Same as above for XPC service App ID |
| `APPLE_API_KEY_ID` | (already exists) App Store Connect API key ID | App Store Connect → Keys |
| `APPLE_API_ISSUER_ID` | (already exists) API key issuer | App Store Connect → Keys |
| `APPLE_API_KEY_P8_B64` | (already exists) API key as base64 | Same as above |

### One-Time Developer Portal Prerequisites

These must be done manually in the Apple Developer Portal before the pipeline can work:

1. Register App IDs for all bundle identifiers if not already present:
   - `skula.wBlock`
   - `skula.wBlock.FilterUpdateService`
   - `skula.wBlock.wBlock-Ads` (and all other extension bundle IDs)

2. Enable capabilities on `skula.wBlock` App ID:
   - CloudKit (with container `iCloud.skula.wBlock`)
   - Push Notifications (for `aps-environment` entitlement)
   - App Groups (`group.skula.wBlock`)

3. Create **Developer ID** provisioning profiles for targets that need them:
   - `skula.wBlock` → Developer ID profile
   - `skula.wBlock.FilterUpdateService` → Developer ID profile (if notarization requires it)

4. Download profiles, encode as base64, store as GitHub Secrets

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Current (manual releases) | CI pipeline as described; no additional automation needed |
| Frequent releases | Add `brew bump-cask-pr` or cross-repo dispatch to automate Homebrew tap updates across multiple taps |
| Multi-platform (macOS + Windows) | Separate CI jobs per platform; code signing secrets scoped per platform |

---

## Sources

- Apple Developer Forums — xcodebuild exportArchive fails for developer-id signed app: https://developer.apple.com/forums/thread/688626
- Apple Developer Forums — Building macOS with App Groups using Developer ID: https://developer.apple.com/forums/thread/731656
- Apple Developer Forums — Developer ID provisioning profile required for CloudKit and push: https://developer.apple.com/support/developer-id/ (MEDIUM confidence via WebFetch)
- Apple Developer Portal: developer-id signing overview: https://developer.apple.com/developer-id/ (HIGH confidence)
- Distributing macOS apps with GitHub Actions (practical workflow): https://defn.io/2023/09/22/distributing-mac-apps-with-github-actions/ (MEDIUM confidence)
- xcodebuild man page (flags reference): https://keith.github.io/xcode-man-pages/xcodebuild.1.html (HIGH confidence)
- Homebrew cask automation (cask update pattern): https://builtfast.dev/blog/automating-homebrew-tap-updates-with-github-actions/ (MEDIUM confidence)
- wBlock codebase direct read: `scripts/build-dmg.sh`, `.github/workflows/homebrew-cask.yml`, `Casks/wblock.rb`, all `.entitlements` files, `wBlock.xcodeproj/project.pbxproj` (HIGH confidence)
- Programmatic macOS Developer ID build gist: https://gist.github.com/soffes/2a4d0f88b5ff8f81a2f53c0a5e7c2c41 (MEDIUM confidence)

---
*Architecture research for: macOS code signing and Homebrew distribution pipeline*
*Researched: 2026-02-19*
