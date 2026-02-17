# Codebase Concerns

**Analysis Date:** 2026-02-17

## Tech Debt

**Duplicate logic in SharedAutoUpdateManager:**
- Issue: `wBlockCoreService/SharedAutoUpdateManager.swift` intentionally duplicates subset of logic from `wBlock/AppFilterManager.swift` to avoid pulling SwiftUI dependencies into the shared service layer. This creates maintenance burden—bug fixes or feature changes may need to be applied to both files.
- Files: `wBlockCoreService/SharedAutoUpdateManager.swift` (line 17-19 notes this explicitly), `wBlock/AppFilterManager.swift`
- Impact: Inconsistent behavior between auto-update path and manual apply path; higher cost to maintain both implementations
- Fix approach: Extract truly common logic (filter download, version checking) into pure Foundation utilities in `wBlockCoreService/` that neither file duplicates

**Complex AppFilterManager class (2,088 lines):**
- Issue: `wBlock/AppFilterManager.swift` is significantly overloaded—combines filter list management, rule application, disabled sites monitoring, cloud sync coordination, and UI state management into single 2,088-line class.
- Files: `wBlock/AppFilterManager.swift`
- Impact: Difficult to test individual concerns; high cyclomatic complexity; fragile when modifying one feature
- Fix approach: Extract monitoring (disabled sites, rule count updates) into separate managers; separate apply orchestration from list management

**DispatchQueue-based file monitoring with manual resource management:**
- Issue: `wBlock/AppFilterManager.swift` (lines 256-315) uses low-level DispatchSource file descriptor monitoring with manual open/close lifecycle. Requires careful cleanup in deinit and error handling.
- Files: `wBlock/AppFilterManager.swift` (lines 70-76 properties, 256-350 setup/teardown)
- Impact: Risk of file descriptor leaks if exceptions occur; resource exhaustion over long app sessions; difficult to test
- Fix approach: Migrate to FileManager change notifications or AsyncSequence-based watching API if available

**Protobuf-based UserDefaults replacement without migration guard:**
- Issue: `wBlockCoreService/ProtobufDataManager.swift` replaced UserDefaults with protobuf binary format. Migration code exists (lines 940-950) but stores only in-memory; if migration fails, data loss on relaunch.
- Files: `wBlockCoreService/ProtobufDataManager.swift` (lines 940-950), `wBlockCoreService/ProtobufDataManager+Extensions.swift`
- Impact: Data loss risk during app updates; complex migration path for future breaking changes
- Fix approach: Add explicit migration audit step after app launch; store migration status in persistent marker file with checksum

## Known Bugs

**saveRuleCounts() misses empty-filters case:**
- Symptoms: When user disables all filters and applies changes, `lastRuleCount` is set to 0 but `saveRuleCounts()` is not always called on all code paths
- Files: `wBlock/AppFilterManager.swift` (lines 886-924 for empty filters case, line 922 where saveRuleCounts() IS called)
- Trigger: Disable all filters → click Apply → check UI on relaunch
- Current state: Actually handled correctly in lines 919-923, but the empty-filter path is deeply nested making it easy to miss in future edits
- Workaround: None needed currently, but refactor needed to prevent regression

**Disabled sites monitor can get stuck:**
- Symptoms: File descriptor may be left open if `setupDisabledSitesObserver()` fails mid-setup; subsequent attempts to re-setup may fail.
- Files: `wBlock/AppFilterManager.swift` (lines 276-315)
- Trigger: Rapid app restarts during edge case failures in directory monitoring setup
- Current mitigation: `deinit` cleanup in lines 344-349 closes descriptor, but error path doesn't invalidate state flag
- Workaround: Force kill and reopen app

**UserScript metadata prefetch can timeout silently:**
- Symptoms: Default userscripts show "downloading..." but never update if prefetch task times out
- Files: `wBlockCoreService/UserScriptManager.swift` (lines 1823+ prefetch logic), no explicit timeout handling visible in prefetch callback
- Trigger: Slow network connection + rapid app state changes
- Current mitigation: Task is stored but cancellation not guaranteed; status may remain stale
- Workaround: Manually open Settings > User Scripts to retry

**Filter updates can lose etag/lastModified validators:**
- Symptoms: After filter update, if `ProtobufDataManager` refresh from disk occurs concurrently, the stored validators (etag, lastModified) may not be persisted correctly on next update check
- Files: `wBlock/FilterListUpdater.swift` (lines 32-38 retrieve validators), `wBlockCoreService/ProtobufDataManager.swift` (lines 447-492 refresh logic)
- Trigger: Filter update + cloud sync download + manual refresh all occurring in tight window
- Current mitigation: Validators are re-fetched from network if missing, but wastes bandwidth
- Workaround: None needed; graceful degradation works but inefficient

## Security Considerations

**URLSession with no certificate pinning:**
- Risk: MitM attacks possible against filter list downloads, userscript downloads, and cloud sync fetches
- Files: `wBlock/FilterListUpdater.swift` (lines 18-25), `wBlockCoreService/UserScriptManager.swift` (lines 62-69), `wBlockCoreService/SharedAutoUpdateManager.swift` (lines 78-84)
- Current mitigation: HTTPS URLs used; system certificate validation applies
- Recommendations: Add certificate pinning for GitHub raw content and critical filter list sources; validate URL schemes before download

**Cloud sync record encryption unclear:**
- Risk: CloudKit records contain filter lists, userscripts, and whitelist data. If encryption key is compromised, sensitive blocking rules and whitelisted sites exposed.
- Files: `wBlock/CloudSyncManager.swift` (entire file uses CKContainer.default().privateCloudDatabase)
- Current mitigation: Uses CloudKit's private database; user's iCloud account provides auth/encryption at rest
- Recommendations: Document encryption assumptions; audit what data is synced; consider client-side encryption layer for userscripts

**File permissions on container directory:**
- Risk: App group container directory is readable/writable by all apps in the group. Content blocker extension could theoretically be compromised to write malicious rules into shared directory.
- Files: `wBlockCoreService/ProtobufDataManager.swift` (lines 494-499 app group file URLs)
- Current mitigation: Content blocker extension is same developer signature; no cross-developer app groups used
- Recommendations: Verify file permissions on container after writes; add integrity check (SHA256 hash) of rule files in extension before applying

**Userscript execution without sandbox isolation:**
- Risk: Custom userscripts uploaded by user could contain malicious code that steals browsing data via modification of web traffic
- Files: `wBlockCoreService/UserScriptManager.swift` (upload/import logic), userscript resources applied via WebExtensionRequestHandler
- Current mitigation: Userscripts are user's own choice to import; browser sandbox limits damage to active tab
- Recommendations: Validate userscript metadata structure; add user-facing warning about script trust before enabling; sanitize imported metadata

## Performance Bottlenecks

**Filter conversion memory usage on large lists:**
- Problem: When applying 200+ filters with high rule counts, combined string concatenation can consume significant heap memory
- Files: `wBlock/AppFilterManager.swift` (lines 1804-1877 memory-efficient streaming approach exists but may not be used everywhere)
- Cause: Some filter conversion paths still build complete combined filter string in memory before writing to disk
- Improvement path: Audit all filter file write paths to ensure streaming I/O is used; profile memory during "Apply Changes" with maximum filter load

**Disabled sites monitor triggers full rebuild on every change:**
- Problem: File system event on disabled sites triggers full content blocker rebuild even if only 1 site changed
- Files: `wBlock/AppFilterManager.swift` (lines 318-341), specifically line 337 checks `lastRuleCount > 0` but always rebuilds
- Cause: Architecture always does full rebuild instead of incremental rule update
- Improvement path: Implement incremental delta application that only updates affected rules; add debounce to coalesce rapid changes into single rebuild

**URLSession memory cache configured but URLCache is disabled:**
- Problem: `URLSessionConfiguration.default` uses URLCache with no disk caching (line 67 in UserScriptManager: `diskCapacity: 0`), but repeated requests for same filter list re-download instead of caching
- Files: `wBlockCoreService/UserScriptManager.swift` (lines 62-69), `wBlock/FilterListUpdater.swift` (lines 18-25), `wBlockCoreService/SharedAutoUpdateManager.swift` (lines 78-84)
- Cause: Three separate URLSession instances, each with own 2MB memory cache; no persistent cache to reuse between app sessions
- Improvement path: Implement shared persistent cache directory for filter list downloads; consider URLSession cache duration policies

**ContentBlockerTargetManager lookups called repeatedly:**
- Problem: `ContentBlockerTargetManager.shared.allTargets(forPlatform:)` called multiple times during apply (lines 719, 927, 1206, etc.), fetching same data
- Files: `wBlock/AppFilterManager.swift` (scattered calls across apply flow)
- Cause: No caching of target list within single apply session
- Improvement path: Cache targets at start of apply, reuse throughout session

**Protobuf serialization/deserialization on every data access:**
- Problem: `latestAppDataSnapshot()` calls `diskStore.readAppData()` which deserializes entire protobuf file even if only one field needed
- Files: `wBlockCoreService/ProtobufDataManager.swift` (lines 449-467)
- Cause: No field-level lazy loading in protobuf schema
- Improvement path: Benchmark deserialization cost; if significant, restructure protobuf schema into separate files per concern (rules, settings, sync state)

## Fragile Areas

**Apply Changes state machine has implicit assumptions:**
- Files: `wBlock/AppFilterManager.swift` (lines 796-1253 applyChanges method)
- Why fragile: Relies on exact ordering of MainActor.run blocks, task detached priorities, and UI state updates. Missing a `saveFilterListsSync()` or `saveRuleCounts()` call on any path causes silent data loss. Complex branching (empty filters, all selected, updates available) makes it easy to miss paths.
- Safe modification: Add explicit state enum for apply phase (checking, updating, converting, saving, reloading, completed, failed) instead of nested conditionals; add assertion at end of each phase that required data was persisted
- Test coverage gaps: No integration tests for all apply-path combinations; no tests for concurrent apply + cloud sync; no tests for apply failure recovery

**ProtobufDataManager disk I/O with concurrent access:**
- Files: `wBlockCoreService/ProtobufDataManager.swift` (entire file)
- Why fragile: Uses private actor `ProtobufDiskStore` for serialization but appData is @Published on MainActor. If extension writes to disk while app is deserializing, or vice versa, race condition can cause data loss. `refreshFromDiskIfModified()` compares modification dates but this is racy on fast filesystems.
- Safe modification: Add explicit write-lock file; compare file content hash, not just modification date; add retry logic with exponential backoff for concurrent writes
- Test coverage gaps: No concurrent write tests; no tests for extension writing while app is reading; no data corruption recovery tests

**Disabled sites observer can leak if didSet chain breaks:**
- Files: `wBlock/AppFilterManager.swift` (lines 256-350)
- Why fragile: Complex setup with multiple guard statements and file descriptor management. If any error occurs mid-setup but `disabledSitesDirectoryFileDescriptor` was already set, the error path doesn't always guarantee cleanup.
- Safe modification: Use defer block immediately after descriptor assignment to guarantee cleanup; extract into separate initializer function with explicit error handling
- Test coverage gaps: No tests for monitor setup failure cases; no tests for rapid re-setup cycles

**Filter URL migration and backward compatibility:**
- Files: `wBlock/AppFilterManager.swift` (lines 201-242 migration logic)
- Why fragile: Migration of custom filter files from "<name>.txt" to ID-based naming (lines 1844-1854) relies on heuristics to detect legacy files. If user has both formats, migration could duplicate or lose filters.
- Safe modification: Add explicit migration version marker; detect exactly one source of truth per filter ID before migration; add audit log of what was migrated
- Test coverage gaps: No tests for mixed legacy/new filter states; no tests for migration rollback

## Scaling Limits

**Extension rule count per blocker: 150,000 hard limit:**
- Current capacity: 150,000 rules per Safari content blocker extension on iOS/macOS
- Limit: wBlock distributes filters across 5+ blockers (Ads, Privacy, Security, Foreign, Custom, Advanced) = ~750,000 total rules possible
- Scaling path: If user enables 200+ large filter lists, will exceed limit. Currently handled by auto-disabling filters and showing warnings. Better approach: implement incremental/staged enablement with priority scoring; add mode that only blocks common trackers (subset of each filter)

**Protobuf file size growth:**
- Current capacity: `wblock_data.pb` grows with userscripts (each stores full content), disabled sites list, and rule count history
- Limit: App group container directory has iOS sandbox limits; large userscripts (>10MB) will slow serialization and add latency to every data access
- Scaling path: Implement size quota checks; compress userscript content; move large script histories to separate append-only log; archive old history

**Cloud sync record size limits:**
- Current capacity: CloudKit record size limit is 1 MB per record
- Limit: If user has 200+ custom filters + 50+ userscripts + large whitelist, sync record could exceed 1 MB
- Scaling path: Split sync record into multiple CloudKit records per type (filters, scripts, settings); implement pagination for whitelist; add compression option

**Disabled sites whitelist is linear O(n) lookup:**
- Current capacity: Whitelist stored as [String] array; lookup on every request is O(n)
- Limit: With 10,000+ whitelisted sites, lookup becomes noticeable on high-traffic sites
- Scaling path: Migrate to Set<String> or trie data structure; implement domain suffix matching for wildcard entries

## Dependencies at Risk

**Protocol Buffers (SwiftProtobuf) maintenance risk:**
- Risk: SwiftProtobuf is community-maintained; Swift team may not maintain long-term. Generated `DataModels.pb.swift` (1,467 lines) is generated code difficult to patch manually.
- Impact: Breaking API changes in Swift language could require regeneration; adding new fields requires regenerating entire file
- Migration plan: Keep backup of proto schema and generation script committed; monitor SwiftProtobuf releases; evaluate alternative (JSONCodable) as fallback

**CloudKit dependency for cloud sync:**
- Risk: CloudKit is Apple-proprietary; if Apple deprecates or changes API significantly, sync stops working. No fallback to alternative cloud provider.
- Impact: Users with cloud sync enabled will lose ability to sync settings across devices
- Migration plan: Design sync layer as protocol; implement CloudKit + local file backup as dual strategy; document how to export/import settings manually if cloud sync fails

**SafariServices extension APIs (reloadContentBlocker):**
- Risk: Safari extension APIs are controlled by Apple; changes in iOS/macOS versions can break reload behavior (WKErrorDomain 6 is already transient)
- Impact: Filter updates may fail silently if reload API changes
- Migration plan: Implement polling-based verification that extensions actually loaded new rules; add user-visible indicator if reload fails

## Missing Critical Features

**No persistent background sync for userscripts:**
- Problem: Userscript auto-update only happens during app foreground operation or explicit "Apply Changes". If user disables app and userscript source updates, user is out of date until next manual update.
- Blocks: YouTube ad-blocking and other dynamic content features that rely on current script versions
- Fix approach: Use BGProcessingTask (already implemented for filters in AppDelegate.swift) to auto-update userscripts on 6-hour schedule; add low-bandwidth mode that only checks metadata

**No conflict resolution for cloud sync:**
- Problem: If user enables a filter locally and cloud sync pulls a list of filters that includes the same filter, no merge strategy; whichever write wins (last-write-wins) without user awareness
- Blocks: Seamless multi-device workflows; complex scenarios break silently
- Fix approach: Implement merge strategy (e.g., union all enabled filters, conflict resolution timestamp); add UI to show what was merged and allow manual curation

**No rule validation before extension reload:**
- Problem: If filter conversion produces invalid JSON rules, extension reload fails silently. User sees "Failed to reload Extension X" but no details on what went wrong or how to fix.
- Blocks: Debugging custom filter syntax errors; validation error messages not shown to user
- Fix approach: Validate JSON rules before writing to disk; parse rules back after write; show specific validation error to user with line number and suggestion

**No ability to test filter matching without enabling on Safari:**
- Problem: User must enable a filter to see if it actually blocks sites they want blocked. No sandbox test environment.
- Blocks: Trying new filters without affecting browsing experience
- Fix approach: Implement lightweight rule engine that can test filter matching against URLs without involving Safari extension; add preview mode to filter details view

## Test Coverage Gaps

**No integration tests for apply changes flow:**
- What's not tested: Full end-to-end apply flow (update check → download → convert → reload) with realistic filter data; concurrent updates + cloud sync during apply; apply failure recovery and cleanup
- Files: `wBlock/AppFilterManager.swift` (applyChanges method and related), `wBlock/FilterListUpdater.swift`
- Risk: Regressions in apply flow often only caught by users; complex state machine makes it easy to introduce bugs
- Priority: HIGH—apply is core feature; current testing is manual only

**No tests for disabled sites observer:**
- What's not tested: File descriptor monitor setup/teardown; rapid re-setup cycles; concurrent file changes; cleanup in deinit
- Files: `wBlock/AppFilterManager.swift` (setupDisabledSitesObserver, checkForDisabledSitesChanges)
- Risk: Resource leaks, stale state, transient rebuild failures
- Priority: MEDIUM—affects whitelist feature but less frequently used than filters

**No tests for protobuf data persistence:**
- What's not tested: Concurrent reads/writes from app + extension; data corruption recovery; migration from UserDefaults; large file performance
- Files: `wBlockCoreService/ProtobufDataManager.swift`, `wBlockCoreService/ProtobufDataManager+Extensions.swift`
- Risk: Data loss on concurrent access; migration bugs remain hidden until next app version; silent corruption
- Priority: HIGH—data manager is critical infrastructure

**No tests for cloud sync merge logic:**
- What's not tested: Conflict resolution between local and remote; handling of deleted items; userscript sync with large content
- Files: `wBlock/CloudSyncManager.swift` (performTwoWaySync, mergeRemoteChanges, etc.)
- Risk: Silent data loss or duplication during sync; multi-device workflows break silently
- Priority: MEDIUM—feature is relatively new; cloud sync is optional

**No tests for userscript import/update:**
- What's not tested: Metadata parsing edge cases; handling of corrupted files; update with network failures; resource cleanup after failed download
- Files: `wBlockCoreService/UserScriptManager.swift` (import, update, validation logic)
- Risk: Malformed userscript leaves system in broken state; update failures are silent
- Priority: MEDIUM—userscript feature is less critical than filter blocking

---

*Concerns audit: 2026-02-17*
