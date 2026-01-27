# Homebrew Cask (Signed + Notarized)

This repo ships a Homebrew cask (`Casks/wblock.rb`) that downloads `wBlock.dmg` from GitHub Releases.

## Installing via Homebrew

Homebrew “taps” use a naming convention: when you run `brew tap USER/TAP`, Homebrew tries to clone `https://github.com/USER/homebrew-TAP`.

Since the cask lives inside this repository (`0xCUB3/wBlock`), you have two options:

### Option A (works today): tap this repo by URL

```sh
brew tap 0xcub3/wblock https://github.com/0xCUB3/wBlock
brew install --cask wblock
```

### Option B (more standard): create a dedicated tap repo

Create a GitHub repo named `0xCUB3/homebrew-wblock` and put the cask at `Casks/wblock.rb`.
Then users can do:

```sh
brew tap 0xcub3/wblock
brew install --cask wblock
```

## Releasing a notarized DMG (GitHub Actions)

The workflow `.github/workflows/homebrew-cask.yml` runs on tags like `v1.2.3` and:
- builds `wBlock.app` with Developer ID signing
- creates `wBlock.dmg`
- notarizes + staples the DMG
- uploads `wBlock.dmg` to the GitHub Release for the tag

### Required GitHub Actions secrets

**Developer ID certificate**
- `MACOS_CERT_P12_B64`: base64 of your exported `.p12` (Developer ID Application cert + private key)
- `MACOS_CERT_PASSWORD`: password used when exporting the `.p12`

**App Store Connect API key (for notarization)**
- `APPLE_API_KEY_ID`: Key ID (e.g. `ABC123DEFG`)
- `APPLE_API_ISSUER_ID`: Issuer ID (UUID)
- `APPLE_API_KEY_P8_B64`: base64 of the downloaded `.p8` API key

### Notes
- The signing identity used is `Developer ID Application: Alexander Skula (DNP7DGUB7B)`.
- The release asset name must be exactly `wBlock.dmg` (the cask downloads `releases/latest/download/wBlock.dmg`).
