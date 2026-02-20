# AdGuard Scriptlets in wBlock

wBlock vendors AdGuard's scriptlet bundle into three extension JS files. The bundle implements
`#%#//scriptlet(...)` filter list rules (things like `set-constant`, `prevent-fetch`,
`json-prune`, etc.) and is built from the [`ameshkov/safari-blocker`](https://github.com/ameshkov/safari-blocker)
rollup harness, which integrates `@adguard/safari-extension` (the scriptlet runtime and
SafariExtension framework) with wBlock's custom initialization code (element zapper, blocked
count, engine setup, logger bindings). The bundle is committed directly into the repository —
no build step is required at app build time.

## Where the bundle lives

| File | Target |
|------|--------|
| `wBlock Advanced/Resources/script.js` | macOS app extension (appext) |
| `wBlock Scripts (iOS)/Resources/background.js` | iOS web extension background script |
| `wBlock Scripts (iOS)/Resources/content.js` | iOS web extension content script |

## How it works (architecture)

Each of the three files is a concatenation of two parts:

1. **Upstream `@adguard/safari-extension` rollup output** — scriptlets, extended-css, and the
   SafariExtension framework (ContentScript/BackgroundScript API), built by the safari-blocker
   rollup config.

2. **wBlock custom initialization code** — logger binding (`wBlockLogger`), element zapper
   (`handleZapperMessage`), blocked count tracking (`engineTimestamp`), and engine setup
   (`window.adguard`). This section is written and maintained by wBlock.

The boundary between the two parts is marked by a `@file` JSDoc comment that begins the
wBlock custom section in each file:

| File | Boundary marker |
|------|----------------|
| `script.js` | `@file App extension content script.` |
| `background.js` | `@file Background script for the WebExtension.` |
| `content.js` | `@file Content script for the WebExtension.` |

`@adguard/scriptlets` is a **transitive dependency** of `@adguard/safari-extension`, not
something wBlock depends on directly. To update scriptlets, bump the safari-extension version.

## Update cadence

Update the scriptlet bundle **quarterly** (approximately every 3 months), or immediately when
a scriptlet used by wBlock's default filter lists is missing from the current bundle.

**Current versions (as of 2026-02-20):**
- `@adguard/safari-extension`: 4.2.1
- `@adguard/scriptlets`: 2.2.16

Check for new releases at:
- https://github.com/AdguardTeam/Scriptlets/releases
- https://www.npmjs.com/package/@adguard/safari-extension

## How to update

Prerequisites: `node`, `pnpm`, `git` (all available via Homebrew on macOS).

Run:

```bash
./scripts/update-scriptlets.sh [safari-extension-version]
```

If no version argument is given, the script auto-detects npm latest and prints the version
before proceeding (you have 5 seconds to abort with Ctrl-C if the version is unexpected).

Example with explicit version:

```bash
./scripts/update-scriptlets.sh 4.3.0
```

The script:
1. Clones `ameshkov/safari-blocker` (depth=1) into a temp directory
2. Bumps `@adguard/safari-extension` in both `extensions/appext/package.json` and
   `extensions/webext/package.json`
3. Builds appext (`pnpm install && pnpm run build` → `dist/script.js`)
4. Builds webext (`pnpm install && pnpm run build` → `dist/background.js`, `dist/content.js`)
5. Splices each built file into the corresponding wBlock file, preserving the wBlock custom code
6. Runs all verification checks (see Smoke Test below)
7. Prints a summary with the exact `git commit` command to use

On success the temp directory is cleaned up automatically. On error it is left in place for
debugging (its path is printed when the error occurs).

## Smoke test

Steps 1-3 are automated by the script. Steps 4-5 are manual.

1. **Check version marker** (all three files):
   ```bash
   grep "SafariExtension v" "wBlock Advanced/Resources/script.js"
   grep "SafariExtension v" "wBlock Scripts (iOS)/Resources/background.js"
   grep "SafariExtension v" "wBlock Scripts (iOS)/Resources/content.js"
   ```

2. **Verify wBlock custom code is preserved:**
   ```bash
   grep "handleZapperMessage" "wBlock Advanced/Resources/script.js"
   grep "wBlockLogger"         "wBlock Advanced/Resources/script.js"
   grep "engineTimestamp"      "wBlock Scripts (iOS)/Resources/background.js"
   grep "window.adguard"       "wBlock Scripts (iOS)/Resources/content.js"
   ```

3. **JS syntax check:**
   ```bash
   node --check "wBlock Advanced/Resources/script.js"
   node --check "wBlock Scripts (iOS)/Resources/background.js"
   node --check "wBlock Scripts (iOS)/Resources/content.js"
   ```

4. **Xcode build:**
   ```bash
   xcodebuild -scheme wBlock -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
   ```

5. **Manual browser test:** Open youtube.com in Safari and confirm pre-roll ads are blocked.

## Scriptlet coverage

`trusted-replace-fetch-response` **is present** in the current bundle
(`wBlock Advanced/Resources/script.js`, `@adguard/scriptlets` 2.2.16, confirmed 2026-02-20).
This scriptlet is used by several YouTube ad-blocking rules in EasyList and AdGuard Base.

## Committing

Commit all three JS files together with a version-descriptive message:

```bash
git add 'wBlock Advanced/Resources/script.js' \
        'wBlock Scripts (iOS)/Resources/background.js' \
        'wBlock Scripts (iOS)/Resources/content.js'
git commit -m "rebuild extension JS with safari-extension X.Y.Z (scriptlets A.B.C)"
```

The rollup output embeds the current build date (`SafariExtension vX.Y.Z (build date: ...)`),
so date-only diffs in git are expected and normal after each update.

## Troubleshooting

**"pnpm: command not found"**
Install via `brew install pnpm`.

**"node: command not found"**
Install via `brew install node`.

**Script fails at splice step with "boundary pattern not found"**
The `@file` boundary markers may have changed in an upstream update. Grep for them manually:
```bash
grep -n "@file App extension content script" "wBlock Advanced/Resources/script.js"
grep -n "@file Background script for the WebExtension" "wBlock Scripts (iOS)/Resources/background.js"
grep -n "@file Content script for the WebExtension" "wBlock Scripts (iOS)/Resources/content.js"
```
If any are missing, the upstream format changed and the splice logic in `update-scriptlets.sh`
needs updating. Check `extensions/appext/src/index.ts` and `extensions/webext/src/index.ts` in
the cloned safari-blocker for the new entry-point comment.

**`SafariExtension v` grep fails after script completes**
The build may not have completed successfully. The temp directory (path printed on error)
contains the build output for inspection.

**`sed: 1: ...: invalid command code` on macOS**
The script uses `sed -i ''` (BSD sed syntax). Do not substitute GNU sed without adjusting the
flag.

## History

Before this automation (prior to 2026-02-20), updates were done by manually extracting the
scriptlet function bundle from the `@adguard/scriptlets` package and pasting it into the JS
files by hand. This path is **deprecated** because it does not bundle the SafariExtension
framework, causing version mismatches and runtime failures. See the Quick-13 incident
(2026-02-19) which prompted this automation.
