# Homebrew cask release

wBlock is distributed through the dedicated tap repo `0xCUB3/homebrew-wblock`.
The cask downloads the signed and notarized DMG from GitHub Releases.

> [!NOTE]
> The App Store version is generally preferred because it provides automatic app updates. This DMG/Homebrew release has the same features and is available for users who prefer installing outside the App Store.

## Install

```sh
brew tap 0xcub3/wblock
brew install --cask wblock
```

To upgrade later:

```sh
brew update
brew upgrade --cask wblock
```

## Release flow

The workflow `.github/workflows/homebrew-cask.yml` builds and publishes the Homebrew DMG. It runs when a version tag is pushed, or manually through `workflow_dispatch`.

Accepted tag styles:

- `v2.1.1`
- `2.1.1`

The workflow:

1. extracts `VERSION` from the tag, stripping a leading `v` when present
2. imports the Developer ID certificate
3. optionally installs a macOS provisioning profile
4. builds `build/homebrew/wBlock-${VERSION}.dmg` with `scripts/build-dmg.sh`
5. notarizes and staples the DMG
6. uploads it to the matching GitHub Release
7. updates `Casks/wblock.rb` in `0xCUB3/homebrew-wblock` with the new version and SHA-256

## Required GitHub Actions secrets

Signing:

- `MACOS_CERT_P12_B64`: base64-encoded exported `.p12` for the Developer ID Application certificate and private key
- `MACOS_CERT_PASSWORD`: password used when exporting the `.p12`
- `MACOS_PROFILE_APP_B64`: optional base64-encoded provisioning profile

Notarization:

- `APPLE_API_KEY_ID`: App Store Connect API key ID
- `APPLE_API_ISSUER_ID`: App Store Connect issuer UUID
- `APPLE_API_KEY_P8_B64`: base64-encoded `.p8` API key

Tap update:

- `HOMEBREW_TAP_TOKEN`: token with push access to `0xCUB3/homebrew-wblock`

## Notes

- Signing uses `Developer ID Application: Alexander Skula (DNP7DGUB7B)`.
- Release assets are versioned as `wBlock-${VERSION}.dmg`.
- The in-repo `Casks/wblock.rb` is kept as a copy/reference; the install path uses the dedicated tap.
