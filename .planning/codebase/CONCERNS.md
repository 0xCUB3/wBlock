# Codebase Concerns

**Analysis Date:** 2026-02-17

## Tech Debt

**Intentional logic duplication in SharedAutoUpdateManager:**
- Issue: `SharedAutoUpdateManager.swift` explicitly duplicates filter-checking and network-fetch logic from `AppFilterManager` / `FilterListUpdater` to avoid importing SwiftUI. The comment at line 17 acknowledges this: "NOTE: This intentionally duplicates a subset of logic."
- Files: `wBlockCoreService/SharedAutoUpdateManager.swift`, `wBlock/FilterListUpdater.swift`
- Impact: When filter-checking behavior changes in `FilterListUpdater`, the duplicate code in `SharedAutoUpdateManager` must be updated in sync manually. Divergence will cause auto-updates to behave differently than manual updates.
- Fix approach: Extract shared network/filter-check primitives into a protocol or pure-Foundation helper in `wBlockCoreService` that both consumers use.

**`saveFilterListsSync()` fire-and-forget wrapper used everywhere:**
- Issue: `saveFilterListsSync()` in `AppFilterManager.swift` (line 87) wraps `saveFilterLists()` in an unstructured `Task {}` and is called in 18 places. There is no error handling or ordering guarantee; rapid calls can silently race.
- Files: `wBlock/AppFilterManager.swift`
- Impact: If a save fails (e.g. disk full, app group inaccessible), the failure is silent. Rapid toggling of multiple filters creates multiple concurrent save tasks.
- Fix approach: Replace with a debounced or serialized async save path, and propagate errors to the UI.

**`APP_CONTENT_BLOCKER_ID` constant is defined but never used:**
- Issue: `AppFilterManager.swift` lines 16-19 define `APP_CONTENT_BLOCKER_ID` for both macOS and iOS, but no code in the file references this constant — the actual bundle IDs come from `ContentBlockerTargetManager.shared.allTargets()`.
- Files: `wBlock/AppFilterManager.swift`
- Impact: Dead code; misleads future readers into thinking this is the active identifier.
- Fix approach: Remove the constant.

**`UserScriptManager` still reads/writes `UserDefaults.standard` directly:**
- Issue: `UserScriptManager.swift` (lines 711, 1870, 1880) uses `UserDefaults.standard` for the `userScriptsInitialSetupCompleted` key even though `ProtobufDataManager` was built specifically to replace `UserDefaults`. The migration code in `ProtobufDataManager.swift` line 903 migrates this key, but `UserScriptManager` continues to use the old store.
- Files: `wBlockCoreService/UserScriptManager.swift`, `wBlockCoreService/ProtobufDataManager.swift`
- Impact: The setup flag is split across two storage systems. After migration the protobuf copy diverges if `UserDefaults.standard` is modified directly.
- Fix approach: Replace the three `UserDefaults.standard` calls in `UserScriptManager` with `ProtobufDataManager.shared.autoUpdateUserscriptsInitialSetupCompleted` (the protobuf field already exists).

**Metadata sanitization duplicated across two files:**
- Issue: The same five App Store term replacements (`malicious → suspicious`, etc.) are defined identically in both `wBlock/FilterListUpdater.swift` (lines 131-150) and `wBlockCoreService/ProtobufDataManager.swift` (lines 760-790).
- Files: `wBlock/FilterListUpdater.swift`, `wBlockCoreService/ProtobufDataManager.swift`
- Impact: If a new term needs sanitizing, or the replacement wording changes, it must be updated in two places.
- Fix approach: Move the canonical list into `wBlockCoreService/Utils.swift` (already contains `FilterListMetadataParser`) and have both callers import from there.

**`checkAndEnableFilters` is a synchronous method that spawns an unstructured `Task`:**
- Issue: `AppFilterManager.checkAndEnableFilters(forceReload:)` (line 628) is a non-`async` function that internally creates `Task { await applyChanges() }`. `ContentView.swift` awaits it as though it is async (lines 199, 255, 291, 686), but there is nothing to await — the work runs in a detached task.
- Files: `wBlock/AppFilterManager.swift`, `wBlock/ContentView.swift`
- Impact: Callers believe they are waiting for the apply to finish before proceeding with UI updates; they are not. This is a latent ordering bug.
- Fix approach: Convert `checkAndEnableFilters` to `async`, remove the internal `Task {}`, and propagate `await` correctly through all call sites.

---

## Known Bugs

**Fallback URL placeholder in protobuf deserialization:**
- Symptoms: Any `FilterList` whose persisted URL string is empty or malformed will be constructed with `URL(string: "https://example.com")!` as its URL. The filter appears in the UI but all network operations on it will hit `example.com`.
- Files: `wBlockCoreService/ProtobufDataManager+Extensions.swift` lines 138, 572
- Trigger: Corrupt protobuf record, or a filter added by CloudSync with an invalid URL.
- Workaround: None visible to the user.

**CloudSync overwrites local custom filters without conflict resolution:**
- Symptoms: When a remote CloudKit payload lists custom filters, `CloudSyncManager.applyRemotePayload` (around line 400-450) replaces local filter state without checking for simultaneous local edits. The "last write wins" model means edits made on one device between syncs are silently discarded.
- Files: `wBlock/CloudSyncManager.swift`
- Trigger: Edit a custom filter on device A, then open device B (which syncs first).
- Workaround: None.

---

## Security Considerations

**Hardcoded fake User-Agent for gitflic.ru requests:**
- Risk: `NetworkRequestFactory.makeGitflicRequest` in `wBlockCoreService/Utils.swift` (lines 96-125) sends a fake Safari desktop User-Agent, fake `Referer`, `Sec-Fetch-*`, and other headers to impersonate a browser. This is required to work around gitflic.ru's bot-detection.
- Files: `wBlockCoreService/Utils.swift`
- Current mitigation: Limited to only the one gitflic.ru filter ("Bypass Paywalls Clean Filter").
- Recommendations: Document this explicitly. Consider whether hosting an App-Group-owned cached mirror of this filter would eliminate the need for header spoofing.

**Filter list URLs are fetched without certificate pinning:**
- Risk: Filter lists are downloaded over HTTPS from ~30 different third-party domains (AdGuard CDN, GitHub raw, easylist-downloads.adblockplus.org, etc.) without TLS certificate pinning. A MITM attacker on the same network could serve malicious filter rules.
- Files: `wBlock/FilterListUpdater.swift`, `wBlockCoreService/SharedAutoUpdateManager.swift`
- Current mitigation: HTTPS only. No active pinning.
- Recommendations: For the highest-impact lists (AdGuard, EasyList), consider SHA256 public-key pinning or at minimum verify content hash against a side-channel manifest.

**`try!` force-throws in static regex initialization:**
- Risk: `wBlockCoreService/Utils.swift` lines 13, 17, 21 use `try!` to initialize three `NSRegularExpression` static constants. A typo in a regex pattern literal will crash at startup.
- Files: `wBlockCoreService/Utils.swift`
- Current mitigation: Patterns are stable literals unlikely to change.
- Recommendations: Replace with `try?` + a compile-time `#if DEBUG` assertion, or use Swift's `Regex` literals which are validated at compile time.

---

## Performance Bottlenecks

**`categorizedFilters` computed property re-filters the full list on every SwiftUI invalidation:**
- Problem: `ContentView.categorizedFilters` (lines 77-99) iterates `filterManager.filterLists` twice per category per render pass. With ~100 filters across 7 categories this is a minor but observable O(n) per render.
- Files: `wBlock/ContentView.swift`
- Cause: No caching; the property is re-evaluated every time any `@Published` property on `filterManager` changes, including unrelated fields like `isLoading` or `progress`.
- Improvement path: Move to a separate `@State` or derive from `filterLists` changes only via `Combine` publisher.

**`countRulesInContent` reads entire filter file into memory as a `String`:**
- Problem: `FilterListUpdater.updateMissingVersionsAndCounts` (line 65) calls `loader.readLocalFilterContent` which loads the entire `.txt` file into a `String` just to count non-comment lines.
- Files: `wBlock/FilterListUpdater.swift`, `wBlock/FilterListLoader.swift`
- Cause: Convenience over efficiency; the `countRulesInContent` function uses `String.enumerateLines` but the content must be fully loaded first.
- Improvement path: Stream-read with `FileHandle` and count lines without loading the full string, or store the count immediately after download so it does not need to be recomputed.

**`ProtobufDataManager.latestAppDataSnapshot()` does a disk read on every `updateData` call:**
- Problem: Every setter in `ProtobufDataManager` calls `latestAppDataSnapshot()` which conditionally reads and deserializes the protobuf file from disk to avoid missing cross-process writes. With the frequency of `saveFilterListsSync()` calls, this could trigger many redundant disk reads.
- Files: `wBlockCoreService/ProtobufDataManager.swift`
- Cause: Cross-process safety design — extension processes write to the same file. The modification-date check mitigates but does not eliminate the cost.
- Improvement path: Consider a CoW (copy-on-write) versioned in-memory snapshot with explicit invalidation signals from extension processes rather than polling the modification date.

---

## Fragile Areas

**Migration stack in `AppFilterManager.setup()`:**
- Files: `wBlock/AppFilterManager.swift` (lines 154-250)
- Why fragile: Migrations run synchronously inside `setup()` without any version tracking. If a migration has a bug it runs again on every launch. Multiple sequential migrations (annoyances filter split, URL migration, deprecated filter removal, list deduplication) must each be idempotent and must not interact.
- Safe modification: Any new migration must be strictly additive and guarded by a unique persisted version flag. Test with a fresh install and with a user who skipped intermediate versions.
- Test coverage: No automated tests exist for the migration path.

**`disabledSitesDirectoryMonitor` using raw POSIX file descriptors:**
- Files: `wBlock/AppFilterManager.swift` (lines 69-76, 343-352)
- Why fragile: The disabled-sites monitor uses a `DispatchSourceFileSystemObject` backed by a raw `CInt` file descriptor. The `deinit` closes the descriptor manually. If `deinit` is called while the dispatch source is still active, or if the fd is closed twice, it will produce undefined behavior or a crash.
- Safe modification: Wrap the fd lifecycle in a dedicated `FileSystemMonitor` class with a formal `invalidate()` method. Do not rely on `deinit` ordering for resource cleanup.
- Test coverage: None.

**CloudKit sync races with local saves:**
- Files: `wBlock/CloudSyncManager.swift`
- Why fragile: `CloudSyncManager.observeLocalSaves()` (line 143) debounces protobuf saves by 1.5 s and triggers an upload. If the user triggers a manual apply while an upload is in flight, both the upload task and the re-apply write to the same shared protobuf file. There is no cross-process write lock beyond the atomic file-write in `ProtobufDiskStore.writeData`.
- Safe modification: Serialize CloudSync upload/apply operations through the existing `pendingSyncTask` cancellation mechanism, and confirm it correctly handles cancellation in the middle of a CKRecord push.
- Test coverage: None.

**`checkAndEnableFilters` being called from `OnboardingView` synchronously (line 861) while also being awaited from `ContentView`:**
- Files: `wBlock/OnboardingView.swift` line 861, `wBlock/ContentView.swift` lines 199-291, `wBlock/AppFilterManager.swift` lines 628-655
- Why fragile: The method is non-async but spawns a `Task`. Calling it synchronously from `OnboardingView` and "awaiting" it from `ContentView` produces two possible internal Task queues that both mutate `AppFilterManager` state. If both execute concurrently on `@MainActor` they will interleave UI state updates.
- Safe modification: Refactor to `async` as noted under Tech Debt above before adding any new callers.

---

## Scaling Limits

**Safari content blocker rule limit (150,000 per extension):**
- Current capacity: 5 extensions × 150,000 = 750,000 rules total across all wBlock extensions.
- Limit: Each extension hard-caps at 150,000 Safari rules. This constant is duplicated without a shared definition in `wBlock/AppFilterManager.swift` (lines 718, 974) and `wBlock/ContentView.swift` (line 59).
- Scaling path: Safari's per-extension limit is set by the OS and cannot be changed. Increasing capacity requires adding more extension targets or applying more aggressive rule deduplication/optimization.

**In-memory log buffer capped at 5,000 entries:**
- Current capacity: `ConcurrentLogManager` keeps a maximum of 5,000 in-memory log entries (`wBlock/ConcurrentLogManager.swift` line 125).
- Limit: During a large auto-update (many filters, many log calls), the oldest entries are dropped. Diagnostic sessions that involve an initial download + apply + auto-update can produce thousands of entries quickly.
- Scaling path: Persist logs to a rolling file rather than only in memory.

---

## Dependencies at Risk

**gitflic.ru as a filter list host:**
- Risk: The "Bypass Paywalls Clean Filter" is hosted on `gitflic.ru`, a Russian code-hosting service with no guaranteed uptime SLA. The workaround requires faking browser request headers (`Utils.makeGitflicRequest`), which suggests the host actively restricts automated access.
- Impact: If gitflic.ru becomes inaccessible or changes its bot-detection, the filter will silently fail to update.
- Migration plan: Mirror the filter on a CDN or remove it from the default list and make it user-discoverable.

**`wBlockCoreService` depends on `ContentBlockerConverter` and `FilterEngine` as internal imports:**
- Risk: Both are imported as `internal import` in `wBlockCoreService.swift` (lines 8-9), meaning they are not re-exported. They appear to be binary or Swift Package dependencies. No version constraints are visible without inspecting the package manifest.
- Impact: A breaking API change in either library would require updating all conversion call sites in `wBlockCoreService/wBlockCoreService.swift`.
- Migration plan: Pin explicit versions in `Package.swift` / SPM manifest and review changelogs before updating.

---

## Missing Critical Features

**No automated tests:**
- Problem: The only test file found is `scripts/test_filter_update_http.swift`, which is a manual integration script, not an XCTest suite. There are no unit tests for any core logic: filter parsing, rule conversion, protobuf migration, CloudSync conflict resolution, or incremental cache.
- Blocks: Confident refactoring of `AppFilterManager`, migration code, or `SharedAutoUpdateManager` without regression risk.

**No version guard on data migrations:**
- Problem: Migrations in `AppFilterManager.setup()` and `ProtobufDataManager.migrateFromLegacyStorage()` run on every launch without a persisted "applied migrations" version. Individual migrations check for specific conditions (e.g. presence of old URL), but there is no single authoritative source of "which schema version this install is at."
- Blocks: Adding new migrations safely, detecting upgrade regressions.

---

## Test Coverage Gaps

**Filter apply pipeline:**
- What's not tested: The full path from `checkAndEnableFilters` → `applyChanges` → `convertOrReuseTargetRules` → `reloadContentBlockersInParallel` including incremental cache hit/miss behavior.
- Files: `wBlock/AppFilterManager.swift`
- Risk: Rule conversion or Safari reload regressions ship silently.
- Priority: High

**ProtobufDataManager migration:**
- What's not tested: `migrateFromLegacyStorage()` logic that reads `UserDefaults` and produces a `Wblock_Data_AppData` struct. Failures here silently lose all user preferences on first launch after upgrade.
- Files: `wBlockCoreService/ProtobufDataManager.swift` (line 858+)
- Risk: User settings (selected filters, whitelist, auto-update schedule) disappear on upgrade.
- Priority: High

**CloudSync two-way sync:**
- What's not tested: Conflict scenarios, schema version mismatches, and partial upload/download failures.
- Files: `wBlock/CloudSyncManager.swift`
- Risk: User data loss or duplication when syncing across devices.
- Priority: High

**`FilterListMetadataParser`:**
- What's not tested: Edge cases in the regex-based metadata extraction (missing Title, malformed version strings, Unicode in headers, lines > 2000 characters).
- Files: `wBlockCoreService/Utils.swift`
- Risk: Filter version display shows "N/A" or crashes for unexpected filter header formats.
- Priority: Medium

---

*Concerns audit: 2026-02-17*
