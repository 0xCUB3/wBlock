# Stack Research

**Domain:** macOS Developer ID code signing, notarization, and Homebrew cask distribution
**Researched:** 2026-02-19
**Confidence:** HIGH for core tools (all Apple-native); MEDIUM for xcodebuild archive/exportArchive pattern (confirmed working but iCloud/APS entitlements require provisioning profile); HIGH for Homebrew cask format

---

## Critical Context: What Actually Breaks Today

The current `build-dmg.sh` builds with `CODE_SIGNING_ALLOWED=NO` then re-signs manually with `codesign`. This approach has two fatal flaws:

1. **iCloud and APS entitlements require a provisioning profile.** `wBlock.entitlements` contains `aps-environment`, `com.apple.developer.icloud-container-identifiers`, and `com.apple.developer.icloud-services`. These are "managed capabilities" that Apple's notary service validates against a provisioning profile. Signing without one means the embedded entitlements are unauthorized, and macOS Sequoia/Tahoe's Gatekeeper enforces this strictly via launch constraint checks. Result: `CODESIGNING 4 Launch Constraint Violation` → spawn error 163. (Source: Apple Developer Forums thread/750283, freecodecamp code signing handbook — CONFIDENCE: HIGH)

2. **Signing order with `--deep` is unreliable.** The current script iterates extensions and XPC services manually, which is correct in principle. But `CODE_SIGNING_ALLOWED=NO` strips all signature metadata from the build output, so re-signing manually cannot reconstruct the inner-to-outer seal correctly without rebuilding. TN2206 states nested code must be signed before the outer signature is computed. (Source: Apple TN2206 — CONFIDENCE: HIGH)

**The fix:** Replace the `CODE_SIGNING_ALLOWED=NO` + manual `codesign` approach with `xcodebuild archive` + `xcodebuild -exportArchive` using Developer ID. This lets Xcode handle provisioning profile embedding, entitlement validation, and correct signing order.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `xcodebuild archive` | Xcode 16+ (current on macOS-latest runner) | Build signed `.xcarchive` | Only way to get Xcode to correctly embed Developer ID provisioning profiles, validate managed entitlements (iCloud, APS), and sign in the correct inside-out order |
| `xcodebuild -exportArchive` | Same | Export `.app` from archive for Developer ID | Uses `ExportOptions.plist` with `method: developer-id`; Xcode handles all provisioning; this is the documented Apple path for direct distribution |
| `xcrun notarytool submit` | Xcode 14+ | Upload to Apple notary service | Replaced deprecated `altool` in Nov 2023. API key auth (`--key`, `--key-id`, `--issuer`) is preferred over app-specific passwords in CI — no keychain prompt; credentials passed as files |
| `xcrun stapler staple` | Xcode 14+ | Attach notarization ticket to DMG | Required so app runs offline without contacting Apple's OCSP server. Must staple the DMG (not the `.app`) when distributing as DMG |
| `hdiutil create` | macOS built-in | Create DMG from signed `.app` | Already in the build script; no change needed for the DMG creation step itself |

### Supporting Tools (CI Setup)

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `security create-keychain` / `security import` | macOS built-in | Import Developer ID cert into ephemeral CI keychain | Already in `homebrew-cask.yml`; this part is correct and does not need to change |
| `-allowProvisioningUpdates` xcodebuild flag | Xcode 14+ | Lets xcodebuild communicate with Apple Developer portal to download/update provisioning profiles | Required in CI because provisioning profiles for iCloud/APS entitlements are not embedded in the repo. Requires `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_P8` to be set |
| `-authenticationKeyPath` / `-authenticationKeyID` / `-authenticationKeyIssuerID` | Xcode 14+ | Authenticate xcodebuild's portal access | Same App Store Connect API key used for notarytool. Secrets `APPLE_API_KEY_ID` and `APPLE_API_ISSUER_ID` already exist in the workflow |

### ExportOptions.plist (New file required)

Create `ExportOptions.plist` at repo root. This file drives `xcodebuild -exportArchive`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
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
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
```

`signingStyle: automatic` means Xcode picks the certificate automatically from the keychain (matching `DEVELOPMENT_TEAM`). `method: developer-id` is the key flag that selects Developer ID over App Store. (Source: Apple forums thread/750283, defn.io build guide — CONFIDENCE: HIGH)

---

## Key Entitlement Issue: iCloud and APS

`wBlock.entitlements` currently contains:

```xml
<key>aps-environment</key>
<string>development</string>
<key>com.apple.developer.aps-environment</key>
<string>development</string>
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.skula.wBlock</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
```

These are **managed capabilities** that require a provisioning profile for Developer ID distribution. Apple's notary service validates that the signing certificate is authorized for these capabilities. Without a provisioning profile, notarization accepts the submission but macOS 15/26 launch constraints block execution. (Source: Apple freecodecamp handbook, Apple developer forums thread discussion — CONFIDENCE: HIGH)

**Two valid paths:**

**Path A (recommended): Create a Developer ID provisioning profile** with iCloud/CloudKit/Push enabled for App ID `skula.wBlock`. Create this in the Apple Developer portal at developer.apple.com/account → Certificates, Identifiers & Profiles → Profiles → +. Select "Developer ID Application" type. When `-allowProvisioningUpdates` is passed to `xcodebuild archive`, it will download this profile automatically from the portal using the API key credentials.

**Path B (simpler if iCloud is not used in macOS DMG build):** Strip `aps-environment` and `com.apple.developer.aps-environment` from the macOS entitlements file for the DMG build path (keep them only for the App Store build). APS (push notifications) and iCloud are App Store capabilities; the direct-distribution DMG does not need them if the macOS app doesn't actively use CloudKit or push in the non-App-Store variant.

Path A is the correct long-term solution. Path B works only if CloudKit/push are genuinely unused in the macOS direct-distribution build.

---

## Key Finding: Extension Types — Direct Distribution Works

wBlock's extensions are:
- `com.apple.Safari.content-blocker` — 5 content blocker extensions (Ads, Privacy, Security, Foreign, Custom)
- `com.apple.Safari.extension` — 1 Safari App Extension (Advanced, `wBlock_Advanced`)

**Critical distinction:** `com.apple.Safari.extension` (Safari App Extension) CAN be distributed via Developer ID outside the App Store. This is the format wBlock uses. `com.apple.Safari.web-extension` (Safari Web Extension) cannot. (Source: Apple developer forums thread/667859, underpassapp.com Safari extension types article — CONFIDENCE: HIGH)

Content blockers (`com.apple.Safari.content-blocker`) are also distributable via Developer ID with standard entitlements. (Source: App Extension Programming Guide, Apple library archive — CONFIDENCE: HIGH)

Conclusion: Direct distribution via Developer ID is the correct and supported path for wBlock's extension architecture.

---

## App Groups Entitlements

All targets share `group.skula.wBlock` in `com.apple.security.application-groups`. For macOS Developer ID, the group format `group.skula.wBlock` (without team prefix) is an iOS-style app group ID. As of February 2025, Apple completed support for iOS-style app group IDs on macOS, and Developer ID provisioning profiles now authorize both formats. This is no longer a blocking issue. (Source: Apple Developer Forums thread/721701 — CONFIDENCE: MEDIUM, search summary from Apple engineer post)

If `xcodebuild -exportArchive` fails with "No profiles for app group were found," update the App Group identifier to the macOS-style `DNP7DGUB7B.group.skula.wBlock` in both entitlements files and the App Group registered in the Developer portal. However, try Path A first — the iOS-style group should work with a current provisioning profile.

---

## Revised `build-dmg.sh` Architecture

Replace the `CODE_SIGNING_ALLOWED=NO` build + manual `codesign` with:

```bash
# Step 1: Archive (Xcode handles signing, provisioning, entitlement validation)
xcodebuild archive \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${OUT_DIR}/wBlock.xcarchive" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${KEY_PATH}" \
  -authenticationKeyID "${APPLE_API_KEY_ID}" \
  -authenticationKeyIssuerID "${APPLE_API_ISSUER_ID}"

# Step 2: Export for Developer ID (Xcode re-signs with Developer ID cert)
xcodebuild -exportArchive \
  -archivePath "${OUT_DIR}/wBlock.xcarchive" \
  -exportPath "${OUT_DIR}/export" \
  -exportOptionsPlist "${ROOT_DIR}/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "${KEY_PATH}" \
  -authenticationKeyID "${APPLE_API_KEY_ID}" \
  -authenticationKeyIssuerID "${APPLE_API_ISSUER_ID}"

# Step 3: Wrap in DMG
hdiutil create -volname "wBlock" \
  -srcfolder "${OUT_DIR}/export/wBlock.app" \
  -ov -format UDZO "${DMG_PATH}"
```

The manual `codesign` loop is entirely removed. The `sign_item()` function and all manual extension/XPC signing is replaced by Xcode's export step.

---

## Notarytool — No Changes Needed

The existing notarize+staple step in `homebrew-cask.yml` is correct:

```bash
xcrun notarytool submit "${dmg}" \
  --key "${key_path}" \
  --key-id "${APPLE_API_KEY_ID}" \
  --issuer "${APPLE_API_ISSUER_ID}" \
  --wait
xcrun stapler staple "${dmg}"
```

`--wait` blocks until Apple's notary service completes. The default timeout is sufficient for typical submissions. Add `--timeout 30m` if submissions are timing out. To retrieve the full notarization log on failure: `xcrun notarytool log <submission-id> --key ... --key-id ... --issuer ...`. The log JSON shows per-component signing issues. (Source: notarytool man page via keith.github.io — CONFIDENCE: HIGH)

---

## Homebrew Cask: Upgrade from `version :latest` to Versioned Cask

Current cask:
```ruby
version "latest"
sha256 :no_check
url "https://github.com/0xCUB3/wBlock/releases/latest/download/wBlock.dmg"
```

This is functionally acceptable for a self-hosted tap but prevents `brew livecheck`, prevents `brew upgrade` from knowing when there's a new version, and excludes the cask from homebrew-cask's autobump bot if ever submitted there.

**Recommended versioned format:**

```ruby
cask "wblock" do
  version "2.0.1"
  sha256 "REPLACE_WITH_ACTUAL_SHA256_OF_DMG"

  url "https://github.com/0xCUB3/wBlock/releases/download/v#{version}/wBlock.dmg",
      verified: "github.com/0xCUB3/wBlock/"
  name "wBlock"
  desc "Safari content blocker for macOS, iOS, and iPadOS"
  homepage "https://github.com/0xCUB3/wBlock"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "wBlock.app"
end
```

Key changes:
- `version "2.0.1"` with `#{version}` interpolation in URL — ties cask version to release tag
- `sha256` with actual checksum — security; prevents tampered downloads
- `livecheck` with `strategy :github_latest` — enables `brew livecheck` to detect new releases automatically
- `verified:` parameter — documents that the download URL is from the same GitHub repo as the homepage

Compute the SHA256 after the signed DMG is built: `shasum -a 256 wBlock.dmg`

The cask must be updated on each release (version + sha256). This can be automated in the GitHub Actions workflow after upload. (Source: Homebrew Cask Cookbook official docs — CONFIDENCE: HIGH)

---

## macOS Sequoia/Tahoe Gatekeeper Requirements

macOS 15 (Sequoia) hardened Gatekeeper in two ways relevant here:
1. Control-click override removed — users must go to System Settings > Privacy & Security to allow unnotarized apps. Properly notarized apps are unaffected.
2. Launch constraint violations now terminate apps silently — apps with invalid entitlements (not authorized by provisioning profile) fail with `CODESIGNING 4` at launch, not at installation. This is what causes error 163.

macOS 26 (Tahoe) continues these requirements. No new signing mechanism was introduced — properly notarized Developer ID apps work as before. (Source: developer.apple.com/news/?id=saqachfa, eclecticlight.co Gatekeeper article — CONFIDENCE: HIGH)

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `xcodebuild archive` + `exportArchive` | `CODE_SIGNING_ALLOWED=NO` + manual `codesign` | Never for production distribution — manual signing cannot embed provisioning profiles required for managed entitlements |
| `xcrun notarytool` with API key auth | App-specific password auth | App-specific password works but requires more keychain setup in CI; API key is already being used so no change |
| Versioned cask with sha256 | `version :latest` + `sha256 :no_check` | Only use `:latest` if the download URL genuinely never contains a version (e.g., always `/latest/download/`). The wBlock URL uses `/latest/` now but can be changed to versioned once tags drive the release |
| `hdiutil create` (already in script) | `create-dmg` tool | `create-dmg` adds a nice background and icon layout but requires `brew install create-dmg` on the runner. Not worth the overhead for a bare-bones DMG. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `CODE_SIGNING_ALLOWED=NO` for production builds | Strips all signing infrastructure from build outputs; prevents Xcode from embedding provisioning profiles; requires errorprone manual reconstruction | `xcodebuild archive` with Developer ID — Xcode handles this correctly |
| `codesign --deep` | Apple TN2206 and gist.github.com/rsms explicitly warn this does not work correctly in practice for nested bundles; it applies the same entitlements to all nested code | Manual inside-out signing (or let `xcodebuild -exportArchive` do it) |
| Signing extensions with the main app's entitlements file | Each extension needs its own entitlements; applying `wBlock.entitlements` (which has `aps-environment` and iCloud) to the content blocker extensions would fail notarization | Per-extension entitlements files (already exists in the project) |
| `altool` for notarization | Deprecated and removed as of November 2023 | `xcrun notarytool` |
| `sha256 :no_check` in versioned cask | No tamper detection; `brew upgrade` cannot determine if update is needed | Actual SHA256 checksum computed after each build |

---

## Version Compatibility

| Component | Version | Notes |
|-----------|---------|-------|
| Xcode | 16+ (macos-latest runner) | `xcodebuild archive` with API key auth requires Xcode 14+; Xcode 16 is current on GitHub-hosted `macos-latest` |
| `xcrun notarytool` | Ships with Xcode 13.1+ | Already used correctly in the workflow |
| `xcrun stapler` | Ships with Xcode | Unchanged |
| macOS deployment target | 14.0 (as set in project) | No change needed |
| GitHub Actions `macos-latest` | Currently macOS 15 (Sequoia) | Provides Xcode 16; sufficient for all operations |

---

## Integration with Existing `homebrew-cask.yml`

The workflow shape stays the same. Changes are:

1. **Remove** `SIGNING_IDENTITY` env var from "Build DMG" step (replaced by Xcode automatic signing)
2. **Add** API key file write before `xcodebuild archive` (same credentials already available as `APPLE_API_KEY_P8_B64`)
3. **Replace** `bash scripts/build-dmg.sh` with the new archive+export+DMG sequence (either inline in the workflow or kept in `build-dmg.sh`)
4. **Keep** the notarize+staple step unchanged
5. **Keep** the GitHub Release upload step unchanged

The certificate import step is still needed — `xcodebuild -exportArchive` with `method: developer-id` still uses the Developer ID cert from the keychain for the final signing pass.

---

## Sources

- Apple TN2206 (library archive technotes) — inside-out signing order, nested code requirements — CONFIDENCE: HIGH
- [Apple Developer Forums thread/750283](https://developer.apple.com/forums/thread/750283) — `xcodebuild archive` + `exportArchive` for Developer ID — CONFIDENCE: HIGH
- [gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5) — distribution vehicle choice, no `--deep` warning — CONFIDENCE: HIGH
- [defn.io distributing mac apps with github actions](https://defn.io/2023/09/22/distributing-mac-apps-with-github-actions/) — complete pipeline reference — CONFIDENCE: MEDIUM (2023, but workflow steps unchanged)
- [freecodecamp Apple code signing handbook](https://www.freecodecamp.org/news/apple-code-signing-handbook/) — managed capabilities requiring provisioning profiles for Developer ID — CONFIDENCE: HIGH
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) — version, sha256, url, livecheck stanza formats — CONFIDENCE: HIGH
- [notarytool man page](https://keith.github.io/xcode-man-pages/notarytool.1.html) — `--key`, `--key-id`, `--issuer`, `--wait`, `--timeout` flags — CONFIDENCE: HIGH
- [xcodebuild man page](https://keith.github.io/xcode-man-pages/xcodebuild.1.html) — `-allowProvisioningUpdates`, `-authenticationKeyPath` etc. — CONFIDENCE: HIGH
- [underpassapp.com Safari extension types](https://underpassapp.com/news/2023-4-24.html) — `com.apple.Safari.extension` vs `com.apple.Safari.web-extension` distribution rules — CONFIDENCE: HIGH
- [developer.apple.com/news saqachfa](https://developer.apple.com/news/?id=saqachfa) — macOS Sequoia runtime protection update — CONFIDENCE: HIGH
- [Apple Developer Forums thread/721701](https://developer.apple.com/forums/thread/721701) — iOS-style app group IDs now fully supported on macOS as of Feb 2025 — CONFIDENCE: MEDIUM

---
*Stack research for: wBlock Developer ID code signing, notarization, and Homebrew cask distribution*
*Researched: 2026-02-19*
