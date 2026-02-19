# Phase 12: Homebrew Cask - Research

**Researched:** 2026-02-19
**Domain:** Homebrew Cask DSL, tap repository structure, CI automation for cask updates
**Confidence:** HIGH

## Summary

Phase 12 takes the already-working notarized DMG pipeline from Phase 11 and makes it consumable via Homebrew. There are three distinct work streams: (1) renaming the DMG to include the version string, (2) authoring a correct `Casks/wblock.rb` that passes `brew audit --cask`, `brew livecheck`, and `brew install`, and (3) wiring CI to auto-update `version` and `sha256` in `wblock.rb` on every tag push and commit the result back to the repo.

The existing cask at `Casks/wblock.rb` uses `version "latest"` and `sha256 :no_check` — the explicit Out of Scope entries in REQUIREMENTS.md. These must be replaced with a pinned version string, a real SHA256, and the `#{version}` interpolation pattern. The existing CI workflow uploads an unversioned `wBlock.dmg`; it must be changed to upload `wBlock-${VERSION}.dmg` so the cask URL can embed the version.

The tap is currently hosted inside the main `0xCUB3/wBlock` repo (accessed via `brew tap 0xcub3/wblock https://github.com/0xCUB3/wBlock`). This two-argument `brew tap` pattern works for any Git URL, so no separate `homebrew-tap` repo is required. CI can commit directly to the main repo using the built-in `GITHUB_TOKEN` — no PAT needed, because we are not forking or opening PRs against a third-party tap.

**Primary recommendation:** Update `build-dmg.sh` and the CI workflow to produce a versioned DMG, rewrite `Casks/wblock.rb` with the correct DSL, then add a CI step after the release upload that computes SHA256 via `curl | shasum`, patches the cask file with `sed`, and pushes the commit back to `main` using `GITHUB_TOKEN`.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BREW-01 | DMG output is versioned (`wBlock-${VERSION}.dmg`) with version extracted from the tag | `build-dmg.sh` must accept a `VERSION` env var; CI extracts it from `GITHUB_REF_NAME` (strip `v` prefix); `hdiutil` writes to `wBlock-${VERSION}.dmg` |
| BREW-02 | Homebrew cask uses pinned `version`, real `sha256`, versioned URL with `#{version}` interpolation | Cask DSL section below; replace current `version "latest"` / `sha256 :no_check` with real values |
| BREW-03 | Homebrew cask includes a `livecheck` block with `strategy :github_latest` | `livecheck do; url :url; strategy :github_latest; end` — uses cask `url` field as source |
| BREW-04 | CI auto-updates version and SHA256 in `Casks/wblock.rb` on each tag push | Post-release CI step: `curl | shasum -a 256`, `sed` to patch `wblock.rb`, `git commit && git push` with `GITHUB_TOKEN` |
| BREW-05 | Homebrew cask includes a `zap` stanza to clean up preferences, caches, and app support | `zap trash:` with paths derived from bundle ID `skula.wBlock`; documented paths below |
</phase_requirements>

---

## Standard Stack

### Core
| Tool/File | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Homebrew Cask DSL | Current (Homebrew 4.x) | Declare install/uninstall/livecheck behavior | The only way to distribute via `brew install --cask` |
| `hdiutil` | macOS built-in | Create DMG from .app | Already used in `build-dmg.sh`; no new dependency |
| `shasum` | macOS/Linux built-in | Compute SHA256 of release asset | Used in CI to pin the hash in the cask |
| `sed` | macOS/Linux built-in | Patch `version` and `sha256` in `wblock.rb` | Standard pattern for in-place cask updates |
| `GITHUB_TOKEN` | GitHub Actions built-in | Push cask update commit back to main repo | Works for same-repo pushes; no PAT needed |

### No New Libraries Required
This phase is shell scripting + Homebrew DSL. No new npm/Swift/Xcode dependencies.

---

## Architecture Patterns

### Tap Repository Layout

The cask already lives in the main `0xCUB3/wBlock` repo:

```
wBlock/
├── Casks/
│   └── wblock.rb        # Homebrew cask definition
├── scripts/
│   └── build-dmg.sh     # Must be updated to produce versioned DMG
└── .github/workflows/
    └── homebrew-cask.yml # Must be updated: versioned upload + cask patch step
```

Users install via:
```bash
brew tap 0xcub3/wblock https://github.com/0xCUB3/wBlock
brew install --cask wblock
```

This works because `brew tap <user>/<name> <URL>` accepts any Git-compatible URL regardless of the repository name. (HIGH confidence — verified against official Homebrew Taps docs.)

### Pattern 1: Versioned DMG in build-dmg.sh

**What:** `build-dmg.sh` reads a `VERSION` env var (set by CI from the Git tag) and writes `wBlock-${VERSION}.dmg` instead of `wBlock.dmg`.
**When to use:** Every tagged release run.

```bash
# In build-dmg.sh
VERSION="${VERSION:-}"
if [[ -z "${VERSION}" ]]; then
  DMG_NAME="wBlock.dmg"
else
  DMG_NAME="wBlock-${VERSION}.dmg"
fi
DMG_PATH="${OUT_DIR}/${DMG_NAME}"
```

In `homebrew-cask.yml`:
```yaml
- name: Extract version
  run: |
    TAG="${GITHUB_REF_NAME}"
    echo "VERSION=${TAG#v}" >> "$GITHUB_ENV"

- name: Build DMG
  env:
    SIGNING_IDENTITY: "Developer ID Application: Alexander Skula (DNP7DGUB7B)"
    VERSION: ${{ env.VERSION }}
  run: |
    bash scripts/build-dmg.sh
```

And the release upload step must reference the versioned path:
```yaml
- name: Upload to GitHub Release
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    set -euo pipefail
    tag="${GITHUB_REF_NAME}"
    dmg="build/homebrew/wBlock-${VERSION}.dmg"
    if ! gh release view "${tag}" >/dev/null 2>&1; then
      gh release create "${tag}" --title "${tag}" --notes ""
    fi
    gh release upload "${tag}" "${dmg}" --clobber
```

### Pattern 2: Correct Cask DSL (wblock.rb)

**What:** Replace the placeholder cask with a fully correct DSL that passes `brew audit --cask`.

```ruby
# Source: https://docs.brew.sh/Cask-Cookbook
cask "wblock" do
  version "2.0.1"
  sha256 "PLACEHOLDER_UPDATED_BY_CI"

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
    "~/Library/Caches/skula.wBlock",
    "~/Library/Application Support/wBlock",
    "~/Library/Saved Application State/skula.wBlock.savedState",
  ]
end
```

Key points:
- `url :url` in livecheck tells Homebrew to use the cask `url` value as the livecheck source — `strategy :github_latest` then queries GitHub's latest release API.
- The `verified:` parameter ties the URL to a specific domain and is required by `brew audit` for GitHub URLs.
- `trash:` is preferred over `delete:` (moves to Trash instead of permanent delete).
- Stanza order matters: `version`, `sha256`, `url`, `name`, `desc`, `homepage`, `livecheck`, artifact (`app`), `zap`.

### Pattern 3: CI Cask Auto-Update Step

**What:** After uploading the DMG to GitHub Releases, compute its SHA256 and patch `Casks/wblock.rb`, then commit and push.

```yaml
- name: Update cask version and sha256
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    set -euo pipefail

    TAG="${GITHUB_REF_NAME}"
    VERSION="${VERSION}"   # already set in env from extract-version step
    DMG_URL="https://github.com/0xCUB3/wBlock/releases/download/${TAG}/wBlock-${VERSION}.dmg"

    SHA256=$(curl -sL "${DMG_URL}" | shasum -a 256 | awk '{print $1}')

    CASK="Casks/wblock.rb"

    # macOS-compatible sed (requires empty string after -i on macOS)
    sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "${CASK}"
    sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "${CASK}"

    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add "${CASK}"
    git commit -m "update wblock cask to ${VERSION}" || echo "nothing to commit"
    git push origin HEAD:main
```

Note on `sed` portability: GitHub Actions `macos-latest` runners use macOS sed, which requires `sed -i ''` (with empty string argument). Linux runners use GNU sed, which uses `sed -i` (no argument). Since this workflow runs on `macos-latest`, use `sed -i ''`.

### Anti-Patterns to Avoid

- **`version "latest"` + `sha256 :no_check`:** Explicitly listed as Out of Scope in REQUIREMENTS.md. Disables `brew upgrade` and tamper detection. `brew audit --cask` will warn about this combination for third-party taps.
- **Hardcoded version in URL without `#{version}` interpolation:** Makes it impossible for `brew upgrade` to construct the new download URL automatically.
- **`delete:` instead of `trash:` in zap:** Permanently removes files; `trash:` is preferred and expected by `brew audit`.
- **`strategy :github_latest` without a `url`:** Every livecheck block requires a `url` key; omitting it causes `brew audit --cask` failure.
- **Pushing to main with `actions/checkout@v4` default fetch depth:** The auto-commit step needs `git push origin HEAD:main`; ensure the checkout step uses `persist-credentials: true` (which is the default for `actions/checkout@v4`).
- **Running `sed -i ''` on Linux:** macOS sed requires the empty string; Linux/GNU sed does not accept it. Since the workflow runs on `macos-latest` this is fine, but worth noting if the runner ever changes.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SHA256 computation | Custom download + hash script | `curl -sL URL \| shasum -a 256 \| awk '{print $1}'` | One-liner, no dependencies, works on macOS and Linux |
| Cask version detection | Custom version API | `strategy :github_latest` in livecheck block | Homebrew's built-in GitHub API integration; maintained by Homebrew team |
| DMG creation | Custom disk image tool | `hdiutil create` (already in `build-dmg.sh`) | Already implemented; no changes needed to DMG format |

**Key insight:** The plumbing (notarization, signing, upload) is done. This phase is almost entirely file edits and one new CI step.

---

## Common Pitfalls

### Pitfall 1: CI commits trigger another workflow run
**What goes wrong:** The `git push origin HEAD:main` in the cask-update step triggers `homebrew-cask.yml` again (because it pushes to main, but the workflow triggers on `push: tags`).
**Why it happens:** Workflow push triggers and `git push` in a workflow step.
**How to avoid:** The workflow triggers on `push: tags: ["v*", ...]` only — a commit to `main` (not a tag) will NOT retrigger `homebrew-cask.yml`. No special handling needed.
**Warning signs:** If you ever add `push: branches: [main]` to the trigger, this becomes a loop.

### Pitfall 2: Race condition — SHA256 computed before release upload completes
**What goes wrong:** `curl -sL DMG_URL` returns a 404 or partial download if the GitHub release upload hasn't fully propagated.
**Why it happens:** The `gh release upload` step completes on the CLI side but GitHub's CDN may not have propagated yet.
**How to avoid:** Add a short retry loop or sleep before computing SHA256. `gh release view` can confirm the asset exists. Alternatively, compute SHA256 from the local DMG file before uploading, then upload with the known hash:
```bash
SHA256=$(shasum -a 256 "build/homebrew/wBlock-${VERSION}.dmg" | awk '{print $1}')
```
This is more reliable than downloading from GitHub.
**Warning signs:** `brew install wblock` fails with SHA256 mismatch.

### Pitfall 3: `brew audit --cask` fails on `verified:` domain
**What goes wrong:** The `verified:` parameter in the `url` stanza must exactly match the URL's domain or audit fails.
**Why it happens:** `brew audit` validates that the `verified:` value is a prefix of the `url` value.
**How to avoid:** Use `verified: "github.com/0xCUB3/wBlock/"` which matches `https://github.com/0xCUB3/wBlock/releases/...`.
**Warning signs:** `brew audit --cask wblock` outputs "URL's verified value should be a prefix of the URL".

### Pitfall 4: livecheck `url :url` resolves to versioned URL, not repo URL
**What goes wrong:** If `livecheck do; url :url; ...` is used, livecheck uses the cask `url` field value — which contains `#{version}` already substituted. `strategy :github_latest` queries `https://api.github.com/repos/0xCUB3/wBlock/releases/latest` which works regardless.
**Why it happens:** GitHub Latest strategy parses the API response, not the URL string itself.
**How to avoid:** Use `url :url` (preferred) or `url "https://github.com/0xCUB3/wBlock"` explicitly. Both work.
**Warning signs:** `brew livecheck wblock` returns no version or wrong version.

### Pitfall 5: Tag format mismatch between cask version and GitHub release tag
**What goes wrong:** The cask stores `version "2.0.1"` (no `v` prefix) but the GitHub release tag is `v2.0.1`. The `#{version}` interpolation in the URL must produce the correct download URL.
**Why it happens:** GitHub releases commonly use `v`-prefixed tags; Homebrew cask `version` conventionally stores the bare version number.
**How to avoid:** The download URL pattern must use `v#{version}` in the path:
```ruby
url "https://github.com/0xCUB3/wBlock/releases/download/v#{version}/wBlock-#{version}.dmg"
```
The CI step must strip the `v` prefix when writing to `wblock.rb`: `VERSION=${TAG#v}`.
**Warning signs:** `brew install wblock` 404s on the download URL.

### Pitfall 6: git push fails because GITHUB_TOKEN lacks write permission
**What goes wrong:** `git push origin HEAD:main` returns 403 Permission denied.
**Why it happens:** The workflow `permissions` block must include `contents: write` for the token to push.
**How to avoid:** The existing workflow already has `permissions: contents: write`. Verify this is retained.
**Warning signs:** CI step fails with "remote: Permission to 0xCUB3/wBlock.git denied to github-actions[bot]".

### Pitfall 7: zap paths wrong bundle identifier
**What goes wrong:** `brew uninstall --zap wblock` does nothing useful because paths use the wrong bundle ID.
**Why it happens:** The bundle identifier is `skula.wBlock` (from `project.pbxproj`), not `com.0xCUB3.wBlock` or similar.
**How to avoid:** Use `skula.wBlock` as the bundle ID component in all zap paths.
**Warning signs:** After `brew uninstall --zap wblock`, preference files remain in `~/Library/Preferences/`.

---

## Code Examples

Verified patterns from official sources and project inspection:

### Complete wblock.rb (target state)
```ruby
# Source: https://docs.brew.sh/Cask-Cookbook
cask "wblock" do
  version "2.0.1"
  sha256 "PLACEHOLDER_UPDATED_BY_CI"

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
    "~/Library/Caches/skula.wBlock",
    "~/Library/Application Support/wBlock",
    "~/Library/Saved Application State/skula.wBlock.savedState",
  ]
end
```

### build-dmg.sh version change (diff-style)
```bash
# OLD:
DMG_PATH="${OUT_DIR}/wBlock.dmg"

# NEW: (VERSION env var set by CI or defaults to empty → keep old name for local builds)
VERSION="${VERSION:-}"
if [[ -n "${VERSION}" ]]; then
  DMG_NAME="wBlock-${VERSION}.dmg"
else
  DMG_NAME="wBlock.dmg"
fi
DMG_PATH="${OUT_DIR}/${DMG_NAME}"
```

### SHA256 computation from local file (preferred over re-download)
```bash
# Source: standard shasum usage, verified with macOS tooling
SHA256=$(shasum -a 256 "build/homebrew/wBlock-${VERSION}.dmg" | awk '{print $1}')
```

### CI step: extract version from tag
```yaml
- name: Extract version
  run: |
    # GITHUB_REF_NAME is e.g. "v2.0.1" — strip the v prefix for cask
    TAG="${GITHUB_REF_NAME}"
    echo "VERSION=${TAG#v}" >> "$GITHUB_ENV"
    echo "TAG=${TAG}" >> "$GITHUB_ENV"
```

### CI step: patch wblock.rb and commit
```yaml
- name: Update cask
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    set -euo pipefail
    SHA256=$(shasum -a 256 "build/homebrew/wBlock-${VERSION}.dmg" | awk '{print $1}')
    CASK="Casks/wblock.rb"
    sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "${CASK}"
    sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "${CASK}"
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add "${CASK}"
    git commit -m "update wblock cask to ${VERSION}" || echo "nothing to commit"
    git push origin HEAD:main
```

### Verify cask locally
```bash
# After brew tap:
brew audit --cask wblock
brew livecheck wblock
brew install --cask wblock
brew upgrade --cask wblock  # test upgrade path
brew uninstall --cask --zap wblock
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `appcast` stanza for version checking | `livecheck` block with strategy | ~2020 | `appcast` is deprecated; must use `livecheck` |
| `version "latest"` + `sha256 :no_check` | Pinned version + real SHA256 | Homebrew policy | `brew upgrade` doesn't work without pinned version; tamper detection requires real hash |
| `brew cask install` command | `brew install --cask` | Homebrew 3.0 (2021) | Old form still works but is deprecated |
| `delete:` in zap | `trash:` in zap | ~2019 | `trash:` preferred; `delete:` still works but not recommended |

**Deprecated/outdated:**
- `version "latest"` in current `Casks/wblock.rb`: Must be replaced with pinned version.
- `sha256 :no_check` in current `Casks/wblock.rb`: Must be replaced with computed SHA256.
- Unversioned `wBlock.dmg` upload: Must become `wBlock-{VERSION}.dmg` for URL interpolation.

---

## Open Questions

1. **What exact version string should be in the initial committed wblock.rb?**
   - What we know: The cask must have a real version + sha256 before CI can auto-update it. An initial placeholder won't pass `brew install`.
   - What's unclear: The current HEAD version of wBlock is unknown from this research. Need to check `MARKETING_VERSION` or the most recent GitHub release tag.
   - Recommendation: The plan task that rewrites `wblock.rb` should read the current version from `project.pbxproj` (`MARKETING_VERSION`) and compute the SHA256 of the most recent release DMG. If no notarized DMG exists at the time of writing, commit a template with a comment noting CI will overwrite it on the next tag push.

2. **Does `brew audit --cask` run against a custom (non-homebrew/homebrew-cask) tap?**
   - What we know: There is a known Homebrew bug (issue #6138) where `brew audit` in v4.5.0 expected casks to be in a standard tap. The workaround is to run `brew audit --cask Casks/wblock.rb` with the file path directly, or `brew audit --cask 0xcub3/wblock/wblock`.
   - What's unclear: Whether this was fixed in later Homebrew versions.
   - Recommendation: Test both `brew audit --cask wblock` and `brew audit --cask Casks/wblock.rb` during implementation. Use the form that works.

3. **Should the cask-update commit be on `main` or on the tag's commit?**
   - What we know: `git push origin HEAD:main` pushes to `main` after the tagged commit. This means the cask in `main` will always reflect the latest release, but the tagged commit itself won't contain the updated cask.
   - What's unclear: Whether users installing from the tap get the `main` branch version (they do — Homebrew reads from the default branch, not from tags).
   - Recommendation: Push to `main`. This is the standard pattern for in-repo tap cask automation.

---

## Sources

### Primary (HIGH confidence)
- https://docs.brew.sh/Cask-Cookbook — Cask DSL reference: `version`, `sha256`, `url`, `livecheck`, `zap`, stanza ordering
- https://docs.brew.sh/Brew-Livecheck — `livecheck` block syntax, `strategy :github_latest`, `url :url` vs explicit string
- https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap — Tap naming, `Casks/` directory structure, two-argument `brew tap` with arbitrary URL
- https://docs.brew.sh/Taps — Two-argument `brew tap <user>/<repo> <URL>` works for any Git URL
- Project source: `Casks/wblock.rb` — Current placeholder cask (confirmed as needing rewrite)
- Project source: `scripts/build-dmg.sh` — Current DMG build script (confirmed unversioned)
- Project source: `.github/workflows/homebrew-cask.yml` — Existing CI (confirmed uploads unversioned DMG)
- Project source: `wBlock.xcodeproj/project.pbxproj` — Bundle identifiers confirmed as `skula.wBlock.*`
- Project source: `README.md` — Confirms tap command: `brew tap 0xcub3/wblock https://github.com/0xCUB3/wBlock`

### Secondary (MEDIUM confidence)
- https://builtfast.dev/blog/automating-homebrew-tap-updates-with-github-actions/ — Platform-aware `sed` pattern for cask updates; cross-repo workflow triggering via PAT
- https://josh.fail/2023/automate-updating-custom-homebrew-formulae-with-github-actions/ — Two-repo approach; SHA256 via `curl | shasum` pattern

### Tertiary (LOW confidence)
- GitHub issue #6138 (brew audit in custom taps) — `brew audit --cask <file-path>` as workaround; not verified against current Homebrew version

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Homebrew DSL is stable, verified against official docs
- Architecture: HIGH — Tap structure, cask DSL, and CI patterns verified against official docs + existing project files
- Pitfalls: HIGH for known issues (tag format, sed portability, SHA256 race); MEDIUM for brew audit custom tap behavior (one unverified source)
- zap paths: MEDIUM — Bundle ID `skula.wBlock` confirmed from `project.pbxproj`; specific path names (`~/Library/Application Support/wBlock`) follow convention and need runtime verification

**Research date:** 2026-02-19
**Valid until:** 2026-03-21 (Homebrew DSL is stable; 30 days)
