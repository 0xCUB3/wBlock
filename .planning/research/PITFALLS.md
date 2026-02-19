# Pitfalls Research

**Domain:** macOS Developer ID code signing, notarization, and Homebrew cask distribution for a Safari content blocker with multiple extensions
**Researched:** 2026-02-19
**Confidence:** HIGH (multiple Apple developer forum threads, official documentation, direct code inspection of wBlock build scripts and entitlements files)

---

## Critical Pitfalls

### Pitfall 1: Building with CODE_SIGNING_ALLOWED=NO then re-signing manually

**What goes wrong:**
The build succeeds and `codesign --verify` passes locally, but the app fails to launch on other Macs. On macOS Sequoia and Tahoe this manifests as error 153/163 ("Launchd job spawn failed") with no user-visible recovery path — the "right-click Open" Gatekeeper bypass was removed in Sequoia 15.1. The app appears signed to `codesign -v` but Gatekeeper's launch-time check rejects it silently.

**Why it happens:**
When Xcode builds with `CODE_SIGNING_ALLOWED=NO` it does not write a correct `CodeResources` resource seal, does not embed a provisioning profile, and leaves ad-hoc or no signature fragments in nested bundles. The subsequent manual `codesign` pass re-signs the outer bundles but the inner `CodeResources` seal records the state of the unsigned nested content. Gatekeeper's strict launch check sees the mismatch and blocks the app. Launchd caches code signing requirements; a binary that has been seen without proper signing, then re-signed, can also trip the cache.

Additionally, any extended attributes (`com.apple.quarantine`, resource-fork xattrs) left on the `.app` tree from the build process will invalidate the signature when quarantined on the end user's machine.

**How to avoid:**
Pass the signing identity directly to `xcodebuild` at build time — never separate build and sign:
```bash
xcodebuild \
  -project wBlock.xcodeproj \
  -scheme wBlock \
  -configuration Release \
  CODE_SIGN_IDENTITY="Developer ID Application: Alexander Skula (DNP7DGUB7B)" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=DNP7DGUB7B \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ENABLE_HARDENED_RUNTIME=YES \
  build
```
Remove `CODE_SIGNING_ALLOWED=NO` from `scripts/build-dmg.sh` entirely. Let Xcode produce a properly signed product; then package it into a DMG. Run `xattr -cr` on the `.app` before packaging to clear any residual extended attributes.

**Warning signs:**
- `codesign -vvv --deep --strict` passes but `spctl --assess --type execute -v wBlock.app` says "rejected"
- App launches on the build machine but fails on a clean machine without the Developer ID cert
- Console shows `AMFI: code signature validation failed` or error 163 in system log

**Phase to address:** Phase 1 — first task in the build script fix, blocks everything else

---

### Pitfall 2: wBlock Privacy extension signed with main app entitlements (existing bug)

**What goes wrong:**
The `scripts/build-dmg.sh` case statement maps the Privacy extension to the wrong entitlements file:
```bash
"wBlock Privacy") entitlements="${ROOT_DIR}/wBlock/wBlock.entitlements" ;;
```
This applies the **main app's** entitlements to the Privacy `.appex`. The main app entitlements contain `aps-environment: development`, `com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services: CloudKit`, and `com.apple.security.application-groups`. These entitlements are not valid for an app extension signed with Developer ID without a matching provisioning profile, causing notarization rejection.

The correct file is `wBlock Privacy/wBlock_Privacy.entitlements` which contains only the app group.

**Why it happens:**
The case statement was likely written when the directory structure was different, or was copy-pasted from the main app entry and never corrected.

**How to avoid:**
Fix the case statement:
```bash
"wBlock Privacy") entitlements="${ROOT_DIR}/wBlock Privacy/wBlock_Privacy.entitlements" ;;
```
Add a pre-signing validation step that asserts every entitlements path actually exists before calling `codesign`.

**Warning signs:**
- `notarytool log` shows "entitlement not supported" or "The signature of the binary is invalid" for `wBlock Privacy.appex`
- `codesign -d --entitlements :- "wBlock Privacy.appex"` shows `aps-environment` or iCloud keys

**Phase to address:** Phase 1 — fix alongside the `CODE_SIGNING_ALLOWED=NO` removal

---

### Pitfall 3: Missing com.apple.security.app-sandbox on Safari extensions

**What goes wrong:**
Safari refuses to register any `.appex` that is not sandboxed. If `com.apple.security.app-sandbox: true` is absent from an extension's entitlements, Safari silently ignores it — the extension does not appear in Safari Preferences > Extensions. No crash, no error message to the user.

Inspecting the wBlock entitlements files reveals that `wBlock Advanced/wBlock_Advanced.entitlements` and `wBlock Privacy/wBlock_Privacy.entitlements` do **not** include `com.apple.security.app-sandbox`. The Ads, Custom, Foreign, and Security extensions do include it. This means wBlock Advanced and wBlock Privacy may be silently not registered by Safari in the Developer ID build.

**Why it happens:**
The container app does not need to be sandboxed for Developer ID distribution, but every `.appex` must be. Entitlements files copied from the container app or created without the sandbox key will produce this silent failure.

**How to avoid:**
Every `.appex` entitlements file must include:
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```
Audit all six extension entitlements files before the first notarization attempt.

**Warning signs:**
- After clean install from DMG, one or more extensions do not appear in Safari Preferences > Extensions
- Silent failure — no crash log, no error dialog

**Phase to address:** Phase 1 — entitlements audit during build script fix

---

### Pitfall 4: aps-environment and iCloud entitlements require Developer ID provisioning profile

**What goes wrong:**
The main app (`wBlock/wBlock.entitlements`) contains `aps-environment: development` and `com.apple.developer.icloud-container-identifiers`/`com.apple.developer.icloud-services: CloudKit`. For Developer ID distribution, these entitlements require a Developer ID provisioning profile that explicitly grants them. Signing without such a profile produces a notarization rejection: "The application bundle's signature contains entitlements that are not supported."

Using `aps-environment: development` in a distribution build also routes push notifications to Apple's sandbox (APNs development) environment, not production.

**Why it happens:**
The entitlements file was created for the App Store build path, which uses a provisioning profile granting these capabilities. The Developer ID path does not automatically embed a profile and therefore cannot assert these entitlements without explicit profile creation.

**How to avoid:**
Two options:
1. Create a Developer ID provisioning profile in the Apple Developer portal with CloudKit and APN capabilities for the app's bundle ID, and embed it during the Developer ID build.
2. Maintain separate entitlements files: one for App Store (with `aps-environment`, iCloud) and one for Developer ID (without them, or with `aps-environment: production`).

Option 2 is simpler and avoids profile management complexity in CI. Use a separate Xcode build configuration (e.g., `Release-DirectDownload`) with a dedicated entitlements file override.

**Warning signs:**
- `notarytool log` shows "com.apple.developer.aps-environment is not supported" or "not provisioned in profile"
- Notarization returns "Invalid" status without further output — always fetch the log with `xcrun notarytool log <UUID>`

**Phase to address:** Phase 2 — requires Apple Developer portal work and build configuration restructuring

---

### Pitfall 5: Signing order violation (parent before children)

**What goes wrong:**
If the `.app` bundle is signed before its nested `.appex` extensions, XPC services, or frameworks, the outer bundle's `CodeResources` seal covers the old (unsigned or previously-signed) nested items. Any subsequent signing of a nested bundle breaks the outer seal. `codesign --verify --deep --strict` fails with "a sealed resource is missing or invalid."

**Why it happens:**
macOS code signing is bottom-up: each bundle seals its contents. The outer bundle's seal must be the last thing created. The current `build-dmg.sh` signs in the correct order (frameworks → XPC → extensions → app), but this order is fragile — it must not be accidentally reversed during refactoring.

The `--deep` flag to `codesign` is deprecated as of macOS 13 and does not reliably handle signing order in complex nested structures.

**How to avoid:**
Maintain strict bottom-up signing order. When switching to Xcode-native signing (recommended in Pitfall 1), Xcode handles this automatically. Never use `codesign --deep` for production signing. Keep the manual order documented if the shell script approach is retained.

**Warning signs:**
- `codesign --verify --deep --strict wBlock.app` fails after a build script change
- Error: "a sealed resource is missing or invalid" specifying a path inside `.app/Contents/PlugIns/`

**Phase to address:** Phase 1 — resolved automatically when switching to Xcode-native signing

---

### Pitfall 6: Missing --options runtime on nested bundles fails notarization

**What goes wrong:**
Notarization fails with "The executable does not have the hardened runtime enabled" for one or more nested bundles. The outer `.app` may have `--options runtime` but if any `.appex`, XPC service, or framework executable does not, the notary service rejects the entire submission.

**Why it happens:**
The `sign_item` helper in `build-dmg.sh` does include `--options runtime`, so this is currently handled. The risk is accidental removal during refactoring. When using Xcode-native signing, the `ENABLE_HARDENED_RUNTIME` build setting must be set to `YES` for every target, not just the main app target.

**How to avoid:**
Set `ENABLE_HARDENED_RUNTIME=YES` on all targets in Xcode. Verify before notarization submission:
```bash
for bundle in wBlock.app/Contents/PlugIns/*.appex wBlock.app/Contents/XPCServices/*.xpc; do
  codesign -d -vvv "$bundle" 2>&1 | grep "flags="
done
# All should show flags=0x10000(runtime) or include "runtime"
```

**Warning signs:**
- `notarytool log <UUID>` contains "does not have the hardened runtime enabled" for any sub-path
- `codesign -d -vvv <nested_bundle>` does not show `flags=0x10000(runtime)`

**Phase to address:** Phase 1 — verify during build fix; auto-enforced by Xcode when `ENABLE_HARDENED_RUNTIME=YES` on all targets

---

### Pitfall 7: GitHub Actions keychain cert not accessible to codesign

**What goes wrong:**
`xcodebuild` or `codesign` reports "The specified item could not be found in the keychain" or hangs waiting for a keychain prompt, failing the CI job.

**Why it happens:**
Three separate failure modes:
1. The custom keychain is created but not added to the user's keychain search list (`security list-keychains -d user -s`). The codesign tool searches the default user keychains and does not find the imported cert.
2. The key partition list is not configured (`security set-key-partition-list -S apple-tool:,apple:`). Since macOS 10.12.5, this step is required to allow codesign to access key material without an interactive password prompt. The current `homebrew-cask.yml` already calls this — it must not be removed.
3. The keychain lock timeout expires mid-job. The current script sets a 6-hour lock timeout (`-lut 21600`), which is fine.

**How to avoid:**
The current `homebrew-cask.yml` has all three steps correctly. Preserve:
```bash
security list-keychains -d user -s "${KEYCHAIN_PATH}"  # add to search list
security set-key-partition-list -S apple-tool:,apple: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
```
Add a cleanup step with `if: always()` to delete the keychain after the job:
```bash
security delete-keychain "${KEYCHAIN_PATH}" || true
```

**Warning signs:**
- CI job hangs at `xcodebuild` with no output for >2 minutes
- `security find-identity -v -p codesigning` in CI shows no identities

**Phase to address:** Phase 1 — verify CI setup, add keychain cleanup

---

### Pitfall 8: Notarization rejection detail hidden in log, not in CLI output

**What goes wrong:**
`notarytool submit --wait` exits with a non-zero code and prints "status: Invalid" but gives no detail about which binary, which entitlement, or which rule caused the failure. Developers diagnose the wrong thing and waste time.

**Why it happens:**
The notarytool CLI design separates the status check from the log. The log contains per-binary rejection reasons and must be fetched separately with `xcrun notarytool log <UUID>`.

The current `homebrew-cask.yml` does not fetch the log on failure. If notarization fails, the CI job exits with no useful error.

**How to avoid:**
Capture the submission ID and always fetch the log on failure:
```bash
output=$(xcrun notarytool submit "${dmg}" \
  --key "${key_path}" --key-id "${APPLE_API_KEY_ID}" \
  --issuer "${APPLE_API_ISSUER_ID}" --wait 2>&1)
echo "${output}"
uuid=$(echo "${output}" | grep "id:" | head -1 | awk '{print $2}')
if echo "${output}" | grep -q "status: Invalid"; then
  xcrun notarytool log "${uuid}" \
    --key "${key_path}" --key-id "${APPLE_API_KEY_ID}" \
    --issuer "${APPLE_API_ISSUER_ID}"
  exit 1
fi
```

**Warning signs:**
- CI shows "status: Invalid" with no further detail
- No `notarytool log` call in the CI workflow after a failed submission

**Phase to address:** Phase 2 — add to notarization CI step

---

### Pitfall 9: Stapler fails because DMG hash changed after notarization

**What goes wrong:**
`xcrun stapler staple wBlock.dmg` fails with error 65 ("No ticket") even though `notarytool submit --wait` reported "Accepted."

**Why it happens:**
Stapling embeds the notarization ticket by matching the file's cdhash to the ticket Apple issued. If the DMG is modified in any way after submission (re-compressed, permissions changed, xattr modified, sign the DMG itself), the hash no longer matches the issued ticket and stapling fails.

**How to avoid:**
Never touch the DMG file between `notarytool submit` and `xcrun stapler staple`. Log the SHA-256 before submission and verify it matches before stapling:
```bash
shasum -a 256 "${dmg}" | tee "${dmg}.sha256"
# ... notarytool submit --wait ...
# ... verify sha256 unchanged ...
xcrun stapler staple "${dmg}"
xcrun stapler validate "${dmg}"  # explicit validation step
```

**Warning signs:**
- `stapler staple` exits code 65
- SHA-256 of the file after submission differs from what was submitted

**Phase to address:** Phase 2 — add validate step to notarization pipeline

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Single entitlements file for App Store and Developer ID builds | Less file management | App Store entitlements cause Developer ID notarization rejection | Never — split these |
| `CODE_SIGNING_ALLOWED=NO` + manual re-sign | Avoids dealing with Xcode signing settings in CI | Broken on macOS Sequoia+, error 163, unreproducible failures on end-user machines | Never |
| Omit `com.apple.security.app-sandbox` from extension entitlements | Avoids sandboxing complexity | Extension silently not loaded by Safari | Never |
| `codesign --deep` for production signing | One-liner | Deprecated since macOS 13, unreliable on nested bundles | Never in production |
| Hardcode signing identity string in CI | Simple setup | Breaks when certificate renews (Developer ID cert valid 5 years) | Acceptable short-term — document the expiry date |
| Skip fetching notarytool log on failure | Simpler workflow | No actionable error output on notarization failure | Never — always fetch log |
| `sha256 :no_check` in Homebrew cask | No hash management overhead | Less secure, Homebrew reviewers may reject for the official cask tap | Only for `:latest` version casks |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| GitHub Actions keychain | Not calling `security list-keychains -d user -s` after creating custom keychain | Always add custom keychain to user search list so `codesign` finds it |
| GitHub Actions keychain | Not setting partition list (`security set-key-partition-list`) | Required since macOS 10.12.5; without it codesign prompts interactively (hangs CI) |
| GitHub Actions keychain | No cleanup step | Add `security delete-keychain` in an `if: always()` step to prevent keychain accumulation |
| notarytool API key | Not cleaning up `.p8` key file | Write to `$RUNNER_TEMP`, never to workspace; the current workflow does this correctly |
| notarytool submit | Not fetching log on failure | Always run `xcrun notarytool log <UUID>` — the top-level "Invalid" status gives no detail |
| Homebrew cask URL | Pointing to the GitHub release page HTML, not the direct asset URL | Use the direct pattern: `https://github.com/user/repo/releases/download/v#{version}/wBlock.dmg` |
| Homebrew cask | No `livecheck` stanza | Without `livecheck`, automated version bump bots skip the cask; version must be updated manually forever |
| Homebrew cask | `version` string not matching tag exactly | The cask `version` must exactly match the string interpolated into the download URL; mismatches cause SHA validation errors on end-user install |
| Homebrew third-party tap | Not running `brew audit --cask wBlock` before publishing | `brew audit` catches URL validity, SHA format, stanza ordering issues that block installation |

---

## Performance Traps

Not applicable as a runtime concern. Only build pipeline timing matters.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Downloading provisioning profiles from Apple portal on every CI run | Slow CI, occasional portal rate limit | Embed profiles as base64 GitHub Secrets if needed | Every run if portal is slow |
| `notarytool submit --wait` with no overall job timeout | Workflow hangs during Apple notarization outages | Set a `timeout-minutes` on the CI job (30 minutes is generous) | Rare but happens during Apple service incidents |
| Not cleaning derived data between CI runs on self-hosted runners | Stale signed artifacts from previous cert | Always pass a fresh `-derivedDataPath`; add a `clean` step or use ephemeral runners | After cert rotation or entitlement changes |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Committing `.p12` or `.p8` to the repo (even in `.gitignore`) | Certificate exfiltration enables signing impersonation | Store only in GitHub Secrets; a file in `.gitignore` can still be pushed accidentally |
| Using `aps-environment: development` in distribution builds | Push notifications routed to Apple's sandbox; exposes internal notification infrastructure | Use `production` value or separate entitlements for Developer ID builds |
| Not deleting temporary keychain after CI job | Keychain persists if the runner is reused or if the job is cancelled mid-run | Add `security delete-keychain "${KEYCHAIN_PATH}" \|\| true` in an `if: always()` post-step |
| Embedding an API key path in the repo | Leaks the path conventions for finding the key | Always write the `.p8` to `$RUNNER_TEMP` and delete after use; current workflow does this correctly |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| DMG not stapled before distribution | Users on machines without internet see "app is damaged" because Gatekeeper cannot reach Apple's notarization servers to verify | Always staple and validate before upload; stapling embeds the ticket for offline verification |
| App run directly from DMG without copying to /Applications | App is translocation-sandboxed, writes config to a temporary path; settings may be lost when the DMG is ejected | Add a DMG background image with a drag-to-Applications arrow; consider using `hdiutil` with a window layout |
| Cask `sha256` not updated after re-releasing same version | `brew upgrade wBlock` fails with SHA mismatch | Automate cask update via GitHub Actions on tag push; never manually release a new binary without updating the cask |

---

## "Looks Done But Isn't" Checklist

- [ ] **Gatekeeper assessment (not just codesign verify):** `spctl --assess --type execute -v wBlock.app` must pass on a machine that does NOT have the Developer ID cert installed — this is a different check from `codesign --verify`
- [ ] **All 6 extensions visible in Safari:** After clean DMG install on a separate machine, open Safari Preferences > Extensions and confirm all six wBlock extensions appear
- [ ] **Notarization log is clean:** `xcrun notarytool log <UUID>` should show 0 issues — "Accepted" status does not mean zero warnings, and warnings can become errors in future macOS versions
- [ ] **Stapling validation:** `xcrun stapler validate wBlock.dmg` must pass after stapling — this is a separate step from `stapler staple` and catches silent failures
- [ ] **Hardened runtime on every nested bundle:** Verify each `.appex` and `.xpc` individually — `codesign -d -vvv <bundle> | grep flags` must show `runtime` flag
- [ ] **Entitlements audit:** `codesign -d --entitlements :- <bundle>` on every signed component should show only the entitlements that component actually needs
- [ ] **Homebrew cask installs cleanly:** `HOMEBREW_NO_INSTALL_FROM_API=1 brew install --cask wBlock` followed by `brew audit --cask wBlock` must pass

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Error 163 / app fails to launch after distribution | HIGH | Fix build script; rebuild with Xcode-native signing; re-notarize; re-staple; re-release DMG; update Homebrew cask sha256 |
| Notarization rejected for entitlement error | MEDIUM | Fix entitlements file(s); rebuild; re-submit to notarytool; re-staple — no new certificate needed |
| Safari extension missing from Preferences (silent failure) | MEDIUM | Add `app-sandbox` entitlement; rebuild; re-notarize; re-release — users must reinstall |
| Stapler error 65 (hash mismatch) | LOW | Do not re-sign or touch the DMG; just rerun `xcrun stapler staple` on the exact submitted file |
| Homebrew cask SHA mismatch after re-release | MEDIUM | Update `sha256` in cask file; push to tap; users get a working `brew upgrade` on next run |
| GitHub Actions keychain cert not found | LOW | Confirm `security list-keychains -d user -s` runs before xcodebuild; confirm partition list is set |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| CODE_SIGNING_ALLOWED=NO + re-sign causing error 163 | Phase 1: Fix build script | `spctl --assess -v wBlock.app` passes on clean VM without Developer ID cert |
| Wrong entitlements path for wBlock Privacy | Phase 1: Fix build script | `codesign -d --entitlements :- "wBlock Privacy.appex"` shows only `app-sandbox` + `application-groups` |
| Missing app-sandbox on wBlock Advanced and Privacy extensions | Phase 1: Entitlements audit | All 6 extensions appear in Safari Preferences after clean DMG install |
| aps-environment/iCloud entitlements in Developer ID build | Phase 2: Provisioning profile creation or entitlements split | `notarytool log` shows 0 issues |
| Signing order violation | Phase 1: Resolved by Xcode-native signing | `codesign --verify --deep --strict wBlock.app` exits 0 |
| Missing hardened runtime on nested bundles | Phase 1: Set ENABLE_HARDENED_RUNTIME on all targets | `codesign -d -vvv` shows runtime flag on every nested bundle |
| GitHub Actions keychain cert not found | Phase 1: CI setup verification | CI builds sign successfully with no interactive prompts |
| notarytool log not fetched on failure | Phase 2: Notarization pipeline | CI outputs full JSON log on any notarization rejection |
| Stapler fails after post-notarization modification | Phase 2: Lock DMG after creation | `xcrun stapler validate wBlock.dmg` exits 0 after each release |
| Homebrew cask SHA/version mismatch | Phase 3: Cask automation | `brew install --cask wBlock` and `brew audit --cask wBlock` both pass after each release |

---

## Sources

- Apple Developer Forums — [Error "Launch Failed" after code signing with entitlements](https://developer.apple.com/forums/thread/746626)
- Apple Developer Forums — [Mac app can't be opened after re-signing](https://developer.apple.com/forums/thread/697838)
- Apple Developer Forums — [Safari Web Extension requires provisioning profile](https://developer.apple.com/forums/thread/714678)
- Apple Developer Forums — [Invalid code signing entitlements with app group on macOS](https://developer.apple.com/forums/thread/775022)
- Apple Developer Forums — [App not launching after signing with hardened runtime](https://developer.apple.com/forums/thread/132109)
- Apple Developer Forums — [Code-signing and Notarization Accepted, but Stapler Fails](https://developer.apple.com/forums/thread/773379)
- Apple Developer Forums — [Why is security set-key-partition-list needed to use codesign?](https://developer.apple.com/forums/thread/666107)
- rsms gist — [macOS distribution: code signing, notarization, quarantine, distribution vehicles](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5) — HIGH confidence (aligns with Apple docs)
- Apple Developer Documentation — [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
- The Eclectic Light Company — [What's happening with code signing and future macOS](https://eclecticlight.co/2026/01/17/whats-happening-with-code-signing-and-future-macos/)
- The Eclectic Light Company — [Notarization: the hardened runtime](https://eclecticlight.co/2021/01/07/notarization-the-hardened-runtime/)
- Hackaday — [Apple Forces The Signing Of Applications In MacOS Sequoia 15.1](https://hackaday.com/2024/11/01/apple-forces-the-signing-of-applications-in-macos-sequoia-15-1/)
- Homebrew Documentation — [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
- GitHub — [beeware/briefcase: codesign --deep is deprecated](https://github.com/beeware/briefcase/issues/1221)
- GitHub — [tauri: codesign "The specified item could not be found in the keychain"](https://github.com/tauri-apps/tauri/issues/4051)
- Direct code inspection: `scripts/build-dmg.sh`, `wBlock/wBlock.entitlements`, `wBlock Privacy/wBlock_Privacy.entitlements`, `wBlock Advanced/wBlock_Advanced.entitlements`, `.github/workflows/homebrew-cask.yml` — HIGH confidence, first-party source

---
*Pitfalls research for: macOS code signing, notarization, and Homebrew cask distribution (wBlock v1.2)*
*Researched: 2026-02-19*
