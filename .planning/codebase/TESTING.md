# Testing Patterns

**Analysis Date:** 2026-02-17

## Test Framework

**Runner:**
- Not detected - No XCTest targets in project

**Assertion Library:**
- Not applicable - No testing framework configured

**Run Commands:**
- Not applicable - No test suite present

**Status:** No unit tests, integration tests, or test targets found in project. No `*Tests` directories or `*.test.swift` files detected.

## Project Structure

**Targets without testing:**
- Main app: `wBlock` (macOS/iOS)
- Core service framework: `wBlockCoreService`
- Content blocker extensions: `wBlock Ads`, `wBlock Privacy`, `wBlock Custom`, `wBlock Foreign`, `wBlock Advanced`
- iOS variants of all above
- Filter update service: `FilterUpdateService`

**Why This Matters:**
The codebase contains critical business logic:
- `ProtobufDataManager.swift` (437 lines) - Centralized persistent data management
- `AppFilterManager.swift` (1800+ lines) - Complex filter application state machine
- `SharedAutoUpdateManager.swift` (59+ functions) - Background update scheduling
- `ProtobufDataManager+Extensions.swift` (750+ lines) - Filter/userscript persistence logic
- `ContentBlockerExtensionRequestHandler.swift` - Safari filter request handling

This code would benefit significantly from unit and integration testing.

## Manual Testing Observations

**Logging Infrastructure (Substitute for Testing):**
The codebase compensates for lack of unit tests with extensive structured logging:

1. **Conditional Logging in ProtobufDataManager:**
   - Every state transition logged with emoji indicators
   - Disk I/O operations tracked and reported
   - Migration steps logged with status: `logger.info("✅ Loaded protobuf data (\(loaded.rawData.count) bytes)")`
   - File system changes monitored: `logger.info("✅ Created data directory: \(dataDir.path)")`

2. **Error Tracking:**
   - Errors captured with context: `logger.error("❌ Failed to load data: \(error.localizedDescription)")`
   - State captured for debugging: `lastError` published property tracks last failure
   - Error UI display: `hasError` boolean triggers error message display

3. **Performance Monitoring:**
   - Measure utility function times critical operations: `measure(label: String, block: () -> T) -> T`
   - Filter apply times tracked: `lastConversionTime`, `lastReloadTime`, `lastFastUpdateTime`
   - Progress tracking: `@Published var progress: Float = 0` during apply operations

**Integration Points (Testable Interfaces):**
```swift
// Public interfaces that would benefit from testing:

// ProtobufDataManager - Data persistence
public func refreshFromDiskIfModified() async -> Bool
public func setHasCompletedOnboarding(_ value: Bool) async

// AppFilterManager - Filter application logic
public func checkAndEnableFilters(forceReload: Bool = false)
public func applyChanges(allowUserInteraction: Bool = false) async
public func toggleFilterListSelection(id: UUID)
public func addFilterList(name: String, urlString: String, category: FilterListCategory)

// Utils - Deterministic transformations
public static func parse(from content: String, maxLines: Int? = nil)
    -> (title: String?, description: String?, version: String?)
public static func computeInputSignature(filters: [FilterList], groupIdentifier: String) -> String?
```

## Test Data & Fixtures

**No Test Fixtures Present**

**Production Data Structures Available:**
- `FilterList` struct in `wBlockCoreService/FilterList.swift` - Codable, can be serialized
- `UserScript` struct in `wBlockCoreService/UserScript.swift` - Codable test data
- Protobuf definitions in `DataModels.pb.swift` - Generated from `.proto` files
- Factory data in `ProtobufDataManager+Extensions.swift` with default lists and userscripts

**Example of Hardcoded Default Data (Usable as Test Fixtures):**
```swift
// From ProtobufDataManager+Extensions.swift
"https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/greasemonkey/youtube-classic.user.js"
// Multiple filter list URLs defined as defaults
```

## Error Testing

**Not Formalized**

**Implicit Error Paths:**
1. File I/O failures - Caught and logged in `ProtobufDataManager`
2. Network timeouts - Handled in `FilterUpdateClient` with timeout guards
3. Invalid data - Nil-coalesced in parsing: `title ?? nil`
4. Rule limit exceeded - Tracked state: `categoriesApproachingLimit`, `disabledSites`

**Error Propagation Pattern:**
```swift
do {
    let loaded = try await diskStore.readAppData(from: dataFileURL)
    appData = loaded.appData
    lastError = nil
    return true
} catch {
    lastError = error  // Captured for debugging
    logger.error("❌ Failed: \(error.localizedDescription)")
    return false  // Graceful degradation
}
```

## Async Testing

**Not Formalized**

**Async/Await Usage Pattern Throughout Codebase:**
- Main actor-isolated mutations: `@MainActor public func setHasCompletedOnboarding(_ value: Bool) async`
- Off-actor file I/O: `private actor ProtobufDiskStore { func readAppData(from url: URL) async throws { ... } }`
- Checked continuations for callbacks: `withCheckedContinuation { cont in ... }` in `FilterUpdateXPC.swift`

**Example Async Pattern (Would Need Testing):**
```swift
@MainActor
public func setHasCompletedOnboarding(_ value: Bool) async {
    await updateData { $0.settings.hasCompletedOnboarding_p = value }
}

private func updateData(_ mutator: (inout Wblock_Data_AppData) -> Void) async {
    appData.withMutations(mutator)
    await saveData()
}

private func saveData() async {
    let result = try await diskStore.writeAppDataIfChanged(...)
    if result != nil {
        didSaveDataSubject.send()
    }
}
```

## Concurrency Safety

**Actor Isolation:**
- `ProtobufDataManager` marked `@MainActor` for all public APIs
- `ProtobufDiskStore` is private actor for thread-safe file I/O
- MainActor guard in `AppFilterManager` for all UI state mutations

**Sendable/Thread Safety:**
- Protobuf data structures marked `@unchecked Sendable` in generated code
- Async functions use proper actor isolation
- Shared mutable state protected: `private let disabledSitesMonitorQueue = DispatchQueue(...)`

## Mocking & Isolation

**No Mocking Framework**

**Injection Points (Would Enable Testing):**
1. `AppFilterManager` accepts injected `FilterListLoader`, `FilterListUpdater`, `ConcurrentLogManager`
2. `ProtobufDataManager` could accept injectable storage backend
3. File operations isolated in `ProtobufDiskStore` actor - mockable interface possible

**Example Dependency Injection (from `AppFilterManager.init`):**
```swift
init() {
    self.logManager = ConcurrentLogManager.shared
    self.loader = FilterListLoader()
    self.filterUpdater = FilterListUpdater(loader: self.loader, logManager: self.logManager)
}
// Could be refactored to accept injected dependencies for testing
```

## Coverage

**Requirements:** None enforced

**Estimated Coverage:** 0% - No tests present

**Critical Uncovered Areas:**
- `ProtobufDataManager` persistence layer and migrations
- `AppFilterManager.applyChanges()` state machine (1000+ line method)
- `SharedAutoUpdateManager` scheduling logic
- Filter list parsing and format conversion
- Safari rule limit enforcement
- Whitelist/disabled sites synchronization

## Test Size and Scope

**Unit Test Candidates:**
- `FilterListMetadataParser.parse()` - Pure function, deterministic
- `ContentBlockerIncrementalCache` - Pure hash/signature computation
- `FilterList.flagEmojis` computed property - Pure mapping
- Error response classification in `FilterUpdateResponseClassifier`

**Integration Test Candidates:**
- `ProtobufDataManager` save/load cycle with file I/O
- `AppFilterManager.checkAndEnableFilters()` with multiple extension targets
- `UserScriptManager` file operations and parsing

**E2E Test Candidates:**
- Full filter apply workflow from UI to Safari blocker
- Onboarding flow with multiple language selections
- Update detection and application

## Known Testing Gaps

**State Machine Testing:**
- `applyChanges()` in `AppFilterManager` is a complex state machine (1000+ lines) with multiple retry paths, progress tracking, error recovery
- Missing unit tests for state transitions and edge cases

**Data Migration:**
- `ProtobufDataManager` performs legacy data migration but has no test coverage
- No verification that old UserDefaults/SwiftData formats convert correctly

**Concurrency:**
- Async/await code throughout but untested
- Actor isolation unchecked in tests
- Race conditions possible in multi-process scenarios (main app + extension)

**XPC Communication:**
- `FilterUpdateClient` XPC timeout handling untested
- No verification of service connection failures

---

*Testing analysis: 2026-02-17*
