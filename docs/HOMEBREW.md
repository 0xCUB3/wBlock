# Homebrew cask release

Install wBlock from [homebrew/cask](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/w/wblock.rb). No extra tap is needed. The cask downloads the signed and notarized DMG from GitHub Releases.

The App Store version is recommended because it updates automatically. Homebrew users get app updates with `brew upgrade --cask wblock`.

## Install

```sh
brew install --cask wblock
```

To upgrade later, run `brew update` followed by `brew upgrade --cask wblock`.

## Move from the old tap

The old `0xcub3/wblock` tap has moved to `homebrew/cask`. Its `tap_migrations.json` redirects the old cask name to Homebrew.

Quit wBlock before switching. To explicitly reinstall from the upstream cask and remove the old tap, run the following commands. Do not use `--zap`, which deletes app data.

```sh
brew update
brew reinstall --cask homebrew/cask/wblock
brew untap 0xcub3/wblock
```

## Release flow

The workflow `.github/workflows/homebrew-cask.yml` runs when a stable version tag such as `3.2.3` is pushed. For a manual run, set `release_tag` to the existing tag. Both jobs build the tagged source.

Use plain numeric tags without a leading `v`. The upstream cask uses the version in both the tag path and the DMG filename, so `v3.2.3` would not match its download URL.

The workflow runs regression tests and builds iOS for the simulator before building the macOS DMG. It signs the app with Developer ID, then notarizes and staples `build/homebrew/wBlock-${VERSION}.dmg`.

If there is no GitHub Release for the tag, the workflow creates a draft. It uploads the DMG before publishing that draft. A release can also be prepared as a draft with the release notes before the workflow runs. Do not publish it until the DMG is ready.

The upload does not replace an existing asset. Once a DMG has shipped, keep it unchanged so Homebrew's recorded SHA-256 remains valid. A rerun with the same asset name fails; ship a new version if the binary needs to change.

## Upstream updates

[Homebrew autobump](https://docs.brew.sh/Autobump) checks eligible casks every three hours and opens version-update PRs. The upstream wBlock cask has no autobump exclusion. Its default livecheck reads version tags from the GitHub repository. Homebrew approved that default in [the original cask review](https://github.com/Homebrew/homebrew-cask/pull/297065).

No separate update bot or cross-repository token is needed. Homebrew controls review and merging; its API and local Homebrew caches can lag behind the merge. A tag can appear while the DMG is still building. If a bot run checks before the download exists, a later run can pick it up after upload. Publishing a release does not make it immediately available through `brew upgrade`.

To check detection locally, run the following commands. `--autobump` includes casks normally skipped because Homebrew maintains them automatically.

```sh
brew tap --force homebrew/cask
brew livecheck --cask --autobump homebrew/cask/wblock
```

If a stable release remains missing, check for an existing [wBlock update PR](https://github.com/Homebrew/homebrew-cask/pulls?q=is%3Apr+wblock) before opening another. If none exists, submit a version bump with the actual release version and the SHA-256 shown in the workflow summary.

```sh
brew bump-cask-pr --version=3.2.3 --sha256=REPLACE_WITH_DMG_SHA256 wblock
```

Replace `REPLACE_WITH_DMG_SHA256` before running that example. Follow [Homebrew's contribution requirements](https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request), including disclosure if AI was used and personally answering maintainer review questions.

## Required GitHub Actions secrets

For Developer ID signing, set `MACOS_CERT_P12_B64` and `MACOS_CERT_PASSWORD`. The optional `MACOS_PROFILE_APP_B64` installs a provisioning profile.

For notarization, set `APPLE_API_KEY_ID` and `APPLE_API_ISSUER_ID` with `APPLE_API_KEY_P8_B64`.

The workflow uses its repository-scoped `GITHUB_TOKEN` to publish the release. `HOMEBREW_TAP_TOKEN` is no longer used and can be removed from repository secrets.
