# Coding Conventions

**Analysis Date:** 2026-02-17

## Naming Patterns

**Files:**
- PascalCase for single-purpose files: `FilterList.swift`, `AppFilterManager.swift`, `OnboardingView.swift`
- Extension files use `+` format: `ProtobufDataManager+Extensions.swift`
- Request handlers: `ContentBlockerRequestHandler.swift`, `WebExtensionRequestHandler.swift`
- Manager classes follow `*Manager` pattern: `AppFilterManager.swift`, `ProtobufDataManager.swift`, `UserScriptManager.swift`

**Functions:**
- camelCase for all function names: `checkAndEnableFilters()`, `toggleFilterListSelection()`, `fastApplyDisabledSitesChanges()`
- Private functions use `private func`: `setupAsync()`, `saveRuleCounts()`, `loadSavedRuleCounts()`
- Async functions explicitly declare `async`: `func checkAndEnableFilters(forceReload: Bool = false) async`
- Functions describing state checks use `is/has` prefix: `hasCompletedOnboarding`, `isApproachingTotalSafariRuleCapacity`, `hasUnappliedChanges`

**Variables:**
- camelCase for properties and local variables: `filterLists`, `statusDescription`, `isLoading`, `lastRuleCount`
- Boolean properties prefix with `is/has/show`: `isLoading`, `hasError`, `showingAddFilterSheet`, `isApproachingTotalSafariRuleCapacity`
- Private/internal properties use `private` access modifier: `private var missingFilters`, `private(set) var filterUpdater`
- Published properties explicitly marked: `@Published var filterLists: [FilterList] = []`

**Types:**
- PascalCase for all types: `FilterList`, `FilterListCategory`, `OnboardingStep`, `BlockingLevel`
- Enums use PascalCase: `enum Platform`, `enum FilterListCategory`, `enum OnboardingStep`
- Structs use PascalCase: `struct ContentBlockerTargetInfo`, `struct AutoUpdateStatus`
- Classes use PascalCase: `class AppFilterManager`, `class ProtobufDataManager`, `class UserScriptManager`

**Constants:**
- UPPER_SNAKE_CASE for module-level constants: `APP_CONTENT_BLOCKER_ID`, `let serviceName = "skula.wBlock.FilterUpdateService"`
- PascalCase for type constants used in enums: `case minimal = "Minimal"`, `case recommended = "Recommended"`

## Code Style

**Formatting:**
- 4-space indentation (inferred from code)
- Opening braces on same line: `func setUp() {` not `func setUp()\n{`
- Single line for simple statements: `guard let url = URL(string: urlString) else { return nil }`
- Multi-line conditions use standard indentation

**Linting:**
- Not detected in project (no .swiftlint.yml or swiftformat config found)
- Code style appears consistent with Swift community conventions

## Import Organization

**Order:**
1. Foundation framework imports
2. Combine/async/concurrency imports
3. Platform-specific imports (SwiftUI, AppKit, UIKit)
4. Local module imports (wBlockCoreService)
5. Conditional compilation blocks (#if os(macOS))

**Example from `ContentView.swift`:**
```swift
import Combine
import SafariServices
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import wBlockCoreService

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif
```

**Path Aliases:**
- No custom path aliases detected
- Full module paths used: `import wBlockCoreService`

## Error Handling

**Patterns:**
- Combine `guard` with early return for nil checks: `guard fileExists(at: url) else { return nil }`
- Do-catch for I/O operations: `do { try data.write(to: url, options: .atomic) } catch { logger.error(...) }`
- Result types not heavily used; async/await with try/catch preferred
- Errors logged via Logger: `logger.error("❌ Failed to load data: \(error.localizedDescription)")`
- Published error state tracked: `@Published var hasError: Bool = false`
- Specific error message setting: `self.statusDescription = "One or more content blockers exceeded Safari's rule limit..."`

**Examples from `ProtobufDataManager.swift`:**
```swift
do {
    let loaded = try await diskStore.readAppData(from: dataFileURL)
    appData = loaded.appData
    lastError = nil
    return true
} catch {
    lastError = error
    logger.error("❌ Failed to refresh protobuf data from disk: \(error.localizedDescription)")
    return false
}
```

## Logging

**Framework:** `os.log` with `Logger` for structured logging (imported in most core service files)

**Patterns:**
- Logger instantiated per class: `private let logger = Logger(subsystem: "com.skula.wBlock", category: "ProtobufDataManager")`
- Emoji prefixes for log levels: `🔧 initializing`, `✅ success`, `❌ error`, `🔄 in progress`, `📝 note`
- Conditional compilation for platform-specific logging: `#if os(macOS)` sections in `FilterUpdateXPC.swift`
- Legacy `NSLog` used in utility functions: `NSLog("[\(label)] Elapsed Time: \(formattedTime) ms")` in `measure()` function
- `ConcurrentLogManager.shared.error()` used in `AppFilterManager.swift` for categorized error logging

**Examples from codebase:**
```swift
logger.info("🔧 ProtobufDataManager initializing...")
logger.error("❌ Failed to refresh protobuf data from disk: \(error.localizedDescription)")
logger.info("✅ Created data directory: \(dataDir.path)")
os_log("Invalid XPC timeout: %.2fs", log: log, type: .error, seconds)
```

## Comments

**When to Comment:**
- MARK sections used extensively to organize logical groups: `// MARK: - Disk I/O (off MainActor)`, `// MARK: - Initialization`
- Doc comments for public APIs: `/// Waits for the initial protobuf load to complete.`
- Inline comments explain non-obvious logic: `// If nothing changed on disk, avoid redundant decode work.`
- Comments for important patterns: `// Fallback (shouldn't happen): suspend until initial load flips isLoading`

**JSDoc/TSDoc:**
- Documentation comments use `///` for public/exposed types
- Example from `FilterList.swift`: `/// Maps ISO 639-1 language codes to their primary region's flag emoji`
- Multi-line docs preserved: `/// Returns a formatted string for the last updated date`
- Parameter documentation not heavily used; rely on parameter names for clarity

## Function Design

**Size:**
- Functions average 10-50 lines for business logic
- Simple accessors/getters often single line: `private var hasCompletedOnboarding: Bool { dataManager.hasCompletedOnboarding }`
- Complex flows broken into helper functions: `setupAsync()` calls `setup()` then runs dependent setup
- Computed properties used for derived state: `private var appliedSafariRulesCount: Int { filterManager.lastRuleCount }`

**Parameters:**
- Default values common for optional behavior: `func checkAndEnableFilters(forceReload: Bool = false)`
- Trailing closures for completion handlers: `func updateFilters(_ reply: @escaping (Bool) -> Void)`
- Async/await preferred over callbacks in modern code

**Return Values:**
- Optional returns for fallible operations: `func fileFingerprint(at url: URL) -> String?`
- Tuple returns for grouped related values: `func readAppData(from url: URL) throws -> (appData: Wblock_Data_AppData, rawData: Data, modificationDate: Date?)`
- Discardable results marked when not always needed: `@discardableResult public func refreshFromDiskIfModified() async -> Bool`

## Module Design

**Exports:**
- Framework target `wBlockCoreService` exports public APIs: `public struct FilterList`, `public class ProtobufDataManager`
- Main app target `wBlock` contains view logic and app-level managers
- Extension targets contain minimal request handlers: `ContentBlockerRequestHandler.swift`
- Internal types marked `internal` or use default access: `private actor ProtobufDiskStore`

**Barrel Files:**
- Not used; imports are direct to specific modules

## Access Control

**Public:** Framework APIs, data models, manager singletons
**Internal (default):** Most helpers and internal state
**Private:** Implementation details, internal state mutations, helper functions

**Example pattern from `ProtobufDataManager.swift`:**
```swift
@MainActor
public class ProtobufDataManager: ObservableObject {
    public var lastRuleCount: Int { Int(appData.ruleCounts.lastRuleCount) }

    @MainActor
    public func setHasCompletedOnboarding(_ value: Bool) async { ... }

    private let logger = Logger(subsystem: "com.skula.wBlock", category: "ProtobufDataManager")
    private actor ProtobufDiskStore { ... }
}
```

## Concurrency

**Actor Usage:** Off-main-thread I/O work isolated in actors: `private actor ProtobufDiskStore` for file operations
**MainActor:** UI-related classes and publishers: `@MainActor class AppFilterManager`
**Async/Await:** Preferred pattern for all concurrent work instead of callback-based APIs
**Task Usage:** Background tasks for non-blocking operations: `Task { [weak connection] in ... }`

## Type Safety

**Protocols:** Defined for XPC interfaces: `@objc public protocol FilterUpdateProtocol`
**Generics:** Minimal use; prefer concrete types and composition
**Optionals:** Explicit handling with `guard let` or `if let` chains
**Enums with Associated Values:** Used for request results: `enum FilterFetchOutcome { case success, noUpdate, failure }`

---

*Convention analysis: 2026-02-17*
