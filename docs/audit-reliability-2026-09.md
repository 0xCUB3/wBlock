# September 2026 reliability audit implementation

This branch implements the actionable findings from the audit of `35834142`, on top of `ccb29f23`. Changes are split into ordinary commits for review in PR #780. The original main worktree and the sibling userscript repository are not modified.

This is a record of implemented changes and their evidence, not a claim that the application is bug-free.

## Compatibility and the DNR limit correction

The project retains its existing macOS 12.3 and iOS/iPadOS 15.4 deployment targets and its existing `XROS_DEPLOYMENT_TARGET = 2.0` setting. Older navigation, change-observation, and login-item fallbacks remain in place. The wBlock scheme does not offer a native visionOS build destination in the validation environment, so no successful visionOS build is claimed.

Current Safari supports 30,000 combined dynamic and session DNR rules. This is confirmed in [WebKit's implementation](https://github.com/WebKit/WebKit/blob/ea232f38603949069f5757d9b3b9210dc3eb94db/Source/WebKit/Shared/Extensions/WebExtensionConstants.h) and is not lowered globally by this PR. The earlier 5,000 limit is historical; [Safari 16.4's release announcement](https://webkit.org/blog/13966/webkit-features-in-safari-16-4/) documents that version's limit and the introduction of the runtime quota property.

The native generator retains a 30,000-rule ceiling. Installation uses the browser's reported quota, subtracts unrelated dynamic/session rules, and retains a conservative fallback only when the older runtime does not report its capacity. Protected-site and exception rules take precedence over redirects both during native generation and installation; a late exception cannot be discarded before the installer sees it. When protections exhaust capacity, no stripping rules are admitted. A replacement happens in one atomic `updateDynamicRules` call, not by deleting the old set and installing a sequence of partial batches. The 150,000-rule Safari content-blocker limit is a separate limit and is unchanged.

## Coverage of the actionable findings

| Audit ID | Change | Main regression evidence |
| --- | --- | --- |
| F01 | Coordinated corruption recovery validates backup data, preserves corrupt bytes, repairs the canonical file, and keeps a last-known-good backup. Transient read errors do not overwrite valid data. | Isolated real protobuf-manager recovery, unreadable-backup, no-backup, and restart cases. |
| F02 | Three-way filter collection merging distinguishes stale unchanged records from additions and preserves external deletions and concurrent insertions. | Two-manager deletion/unrelated-save and concurrent-insertion tests. |
| F03 | First migration initializes storage atomically and persists before stamping completion. Existing canonical data wins over legacy defaults. | Durable migration, failed migration, missing flag, and competing initializer tests. |
| F04 | Lowercase metadata dispatch handles `@updateURL` and `@downloadURL`. | Parser and resolved-endpoint assertions. |
| F05 | Less/Stylus variable maps use deterministic last-declaration-wins handling instead of a duplicate-key trap. | Both real bundled compiler backends receive repeated UserCSS variable names. |
| F06 | Failed required includes abort publication without advancing source bytes or revision state. Successfully fetched empty includes remain valid. | Injected HTTP, network, decoding, cancellation, and valid-empty-child cases. |
| F07 | Compilation uses refreshed download-derived counts/timestamps while retaining the run's selection snapshot. | Production mapping helper test with previously missing counts. |
| F08 | Explicit overflow metrics reach callers; truncated target output is never published. Uncapped base caches preserve repeat detection. Background processing rejects overflow before reloading Safari. | Production finalize/save helper over isolated files with a reduced injectable limit; existing cache tests. |
| F09 | Pending revisions identify source digests and recoverable staged files. Old bytes cannot be mistaken for a new completed publication. | Hard-exit subprocess, staged-file recovery, digest mismatch, and generation acknowledgement tests. |
| F10 | Userscript resource chunks carry the same page URL and payload revision as content chunks. | Real shipped injector request construction under the browser harness. |
| F11 | No Autoplay and Zapper use content-to-background-to-native messaging. Unknown site state does not silently enable Zapper hiding. | Behavioral content/background tests without direct native access in the content sandbox. |
| F12 | Custom-list restore upserts included source, title, description, category, and selection. | Production backup code with isolated real source files and injected managers. |
| F13 | Inline-list restore validates and retains stable UUID identity and is idempotent. | Repeated restore and malformed identity cases. |
| F14 | Explicit empty script exceptions and false Zapper disabled state restore correctly; legacy absent fields retain deliberate compatibility semantics. | Backup round-trip and unrelated-state preservation tests. |
| F15 | Only genuine local insertions create pending add generations. Unchanged old copies no longer veto remote deletion. Acknowledgement consumes only the generation actually synced. | Pure production reconciler, add/update notification classification, and generation acknowledgement tests. |
| F16 | Same-content remote updates apply the incoming display name and preserve legacy description semantics. | Production metadata merge helper tests. |
| F17 | Structured `@match` excludes fragments; raw `@include` subjects retain their own semantics. | Exact match with fragments and separate include cases. |
| F18 | Regex-form includes/excludes are recognized and evaluated with length and progress/time limits. | Matching/nonmatching patterns and a hostile-regex subprocess. |
| F19 | Refresh equality covers authoritative script metadata and resource content rather than five selected fields. | Independent authoritative-field changes. |
| F20 | A verified pending download is treated as an update before the network/no-change path, so a deferred rebuild is not lost behind a later 304. | Pending revision recovery tests and inspected background/app call paths. No live BGTask scheduler execution is claimed. |
| F21 | Launch-agent reconciliation caches only a result that satisfies the requested state, allowing retry after transient failure. | Inspected state transition and full app compilation; no real login-item registration is exercised. |
| F22 | Zapper uses coalesced invalidation, mtime-aware native refresh, and a coarse top-frame fallback that broadcasts to all frames in the tab. | Idle subframe, fallback tick, same-tick burst, and in-flight invalidation tests. |
| F23 | DNR uses compatible initiator fields and safe request-domain downgrades. Unsupported redirect scopes are skipped rather than widened; unrepresentable protections prevent unsafe installation. | Legacy/modern serialized-rule and real background harness cases. |
| F24 | Native and runtime quota accounting retain protective rules before redirects; chunk-generation/count validation and atomic replacement prevent partial installation. | Real 30,001-rule late-exception generation, disabled-site reservation, protective-only overflow, old/new runtime quotas, mixed chunks, and failed replacement cases. |
| F25 | Parameterized rules-viewer UI tests run in their own configured simulator job, not the no-argument shell-test glob. Scratch compiler tests use explicit isolated directories. | Full CI entry point plus the dedicated UI suite. |
| F26 | The App Intent distinguishes overlap rejection, successful completion, and completion with errors. | Full app compilation and inspected result handling; new strings added to localization tables. |

## Review follow-ups included

The popup status protocol (R02) now uses a short cross-process lock and an owner token; stale/non-owner completions cannot overwrite a newer run. Its subprocess regression verifies a single claimant and rejects stale completion.

Staged filter markers (R03) carry generations and clear only the marker actually consumed. The direct store regression retains a newer marker written after an old snapshot was read.

Cloud applies recheck local mutation revisions around suspended work. Per-script disabled-host comparison and merge occur inside the coordinated protobuf disk mutation, not just against an earlier in-memory view. Changed and unrelated keys survive; deleted scripts cannot acquire orphan exception entries. Backup restores also register a local mutation so older remote imports cannot publish over the restore.

Inline restore failure tests cover rollback of transaction-owned bytes, preserving newer bytes, and surfacing failure instead of claiming successful restoration. Persistence outcome plumbing is checked at the caller rather than relying only on successful file writes.

## Independent review corrections

Corruption recovery copies the corrupt bytes before atomic canonical replacement, rather than creating a missing-main crash window. Missing-main initialization also recovers a valid backup under the file lock, including interrupted writes from older versions, without replacing it with defaults. A restart regression covers that exact on-disk state.

Authoritative userscript refresh hydrates resource sidecars before comparison, and protobuf decoding restores `lastUpdated`. Backup restore includes hosts recorded only in the disabled-Zapper set, preserving unrelated sites. Isolated protobuf and production backup regressions cover timestamp decoding and disabled-only restoration.

## Dependency and tooling updates

| Component | Before | After |
| --- | --- | --- |
| Less | 4.9.0 | 4.9.1 |
| Dart Sass | 1.102.0 | 1.104.0 |
| PostCSS | 8.5.26 | 8.5.28 |
| Extension esbuild | 0.28.1 | 0.28.2 |
| swift-psl | 1.1.155 | 1.1.172 |
| actions/checkout | v5 | v7.0.1, pinned commit |
| actions/cache | v4 | v6.1.0, pinned commit |

Compiler artifacts include updated provenance, checksums, and existing upstream license notices. They still execute in the offline disposable WebKit Worker host with denied network/storage capabilities and bounded execution. Extension minification retains the Safari 15 syntax target. SwiftPM resolution accepted the suffix-list update without changing the other package pins.

SafariConverterLib 4.3.0 and SwiftProtobuf 1.38.1 are unchanged. SafariConverterLib pins Swift Argument Parser 1.5.0 exactly, so this PR does not force an incompatible lockfile-only upgrade to that transitive dependency. Stylus and postcss-nested retain their current versions. Swift 6 language mode is not enabled as a cosmetic maintenance change.

## Security, service lifetime, and validation limits

R01 no longer relies on page-visible tokens. Scripts requiring native GM network or storage run in the isolated world, even when their descriptor requests page injection. Genuine GM calls and streaming responses use extension runtime messaging directly; page messages cannot invoke those operations. Cached page code never acquires native authority after reconciliation.

Tube Cleaner retains its page hooks. Its only page-writable native projection is the bounded `wblock.tubeCleaner.sponsorBlock` playback-preference object: booleans, bounded duration, eight category modes and at most 200 bounded channel names. The isolated host fixes the script identity, action and key after native execution validation, coalesces writes, and rejects unknown fields. These preferences are deliberately public/page-writable, like the script's existing localStorage preferences; this channel provides no arbitrary storage, user IDs, credentials, networking or runtime ports.

Page loaders requesting `unsafeWindow` and only GM XHR, such as Vencord, retain page execution but use ordinary page fetch under CSP/CORS, not extension networking. Other scripts needing both arbitrary native GM privileges and page globals must separate those responsibilities rather than inherit a privileged page bridge. Node regressions exercise genuine isolated calls, observed-token replay, forged storage/stream messages, warm-cache reconciliation and Tube preferences. A real WebKit `WKContentWorld` test verifies isolation and replay rejection with the shipped injector; it is not a full Safari extension integration test.

R04 now has explicit service ownership. Both service entry points acquire a public libxpc transaction before starting detached work; early acknowledgement occurs only after acquisition. The task releases it in `defer` after the updater and final popup-status publication finish, so invalidating the client connection cannot make accepted work idle-exitable. The ordering regression checks acquisition, acknowledgement/disconnect, publication and release, and exercises the actual SDK transaction pair.

No runtime validation on macOS 12.3 or iOS 15.4, live CloudKit account exchange, battery benchmark, or successful native visionOS build is claimed. Node harnesses model browser messaging; they are not substitutes for running the extension in the oldest supported Safari. Existing Swift 6 migration warnings remain outside this Swift 5-mode reliability patch.

## Validation commands

Local builds use Xcode 26.6 and the existing signed wBlock DerivedData directory. They do not create an unsigned second wBlock installation or launch it against the user's settings.

```sh
export DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer
export PATH="$DEVELOPER_DIR/usr/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export WBLOCK_DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/wBlock-ccgvgkpgtaqtzjfxeodsttzpctkj"
bash scripts/run-ci-tests.sh
xcodebuild -project wBlock.xcodeproj -scheme wBlock -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath "$WBLOCK_DERIVED_DATA" build
xcodebuild -project wBlock.xcodeproj -scheme wBlock -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$WBLOCK_DERIVED_DATA" build
bash scripts/test_rules_viewer_ui.sh <available-iPhone-simulator-UUID>
git diff --check
```

The PR's check results are the authoritative status for its current pushed commit. A green result on an earlier commit must not be presented as validation of a later one.
