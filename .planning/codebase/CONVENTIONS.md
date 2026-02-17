# Coding Conventions

**Analysis Date:** 2026-02-17

## Naming Patterns

**Files:**
- PascalCase for all Swift source files: `AppFilterManager.swift`, `FilterListUpdater.swift`
- Extension files use `+` suffix: `ProtobufDataManager+Extensions.swift`
- Views use `View` suffix: `ContentView.swift`, `OnboardingView.swift`, `SettingsView.swift`
- ViewModels use `ViewModel` suffix: `ApplyChangesViewModel.swift`, `PopoverViewModel.swift`
- Managers use `Manager` suffix: `ConcurrentLogManager.swift`, `UserScriptManager.swift`

**Types:**
- `struct` for data models: `FilterList`, `LogEntry`, `ApplyChangesState`, `ApplyChangesPhaseProgress`
- `class` for ObservableObject view models and managers: `AppFilterManager`, `ProtobufDataManager`, `ApplyChangesViewModel`
- `actor` for concurrency-safe shared state: `ConcurrentLogManager`, `ProtobufDiskStore`
- `enum` for namespacing stateless utilities: `FilterListMetadataParser`, `NetworkRequestFactory`, `ContentBlockerIncrementalCache`
- `enum` for categories and phase states: `FilterListCategory`, `ApplyChangesPhase`, `ApplyChangesPhaseStatus`

**Properties and Functions:**
- camelCase for all properties and functions
- Boolean properties use `is`/`has`/`should` prefix: `isCustom`, `isSelected`, `hasError`, `hasUnappliedChanges`, `shouldShowRuleLimitIndicator`
- Computed display helpers named after what they return: `flagEmojis`, `lastUpdatedFormatted`, `compactFormat`, `exportFormat`
- Private helpers named with intent: `saveFilterListsSync()`, `prepareApplyRunState()`, `setupDisabledSitesObserver()`

**Constants:**
- `static let` for type-level constants: `LiquidGlassDesignSystem.standardCornerRadius`, `LiquidGlassDesignSystem.cardCornerRadius`
- `ALL_CAPS` for top-level module constants: `APP_CONTENT_BLOCKER_ID`
- Numeric literals use underscores for readability: `150_000`, `5_000`, `64 * 1024`

## Code Style

**Formatting:**
- 4-space indentation
- Trailing closures preferred for single-closure arguments
- Multi-line function signatures align parameters with one per line when long
- `defer` used for cleanup in functions with early returns

**Access Control:**
- `public` for everything in `wBlockCoreService` framework: structs, inits, computed props, static methods
- `private` aggressively applied to implementation details
- `private(set)` for writable-internally, readable-externally: `private(set) var filterUpdater`
- `internal import SwiftProtobuf` to scope framework imports

**Struct vs Class:**
- Data models are `struct` (value semantics): `FilterList`, `LogEntry`, `ApplyChangesState`
- Shared service objects are `class` with `@MainActor`: `AppFilterManager`, `ProtobufDataManager`, `ApplyChangesViewModel`
- True concurrency isolation uses `actor`: `ConcurrentLogManager`, `ProtobufDiskStore`

## Import Organization

**Order:**
1. Foundation and system frameworks (`import Foundation`, `import Combine`, `import Darwin`)
2. Apple UI/platform frameworks (`import SwiftUI`, `import SafariServices`)
3. Internal modules (`import wBlockCoreService`)
4. Conditional platform imports inside `#if os(macOS)` / `#if os(iOS)` blocks

**Platform Conditionals:**
```swift
#if os(macOS)
    import AppKit
#elseif os(iOS)
    import UIKit
#endif
```

## MARK Sections

MARK comments are used consistently to divide large files:
```swift
// MARK: - Migration
// MARK: - Core functionality
// MARK: - Rule limit UX
// MARK: - Helper Methods
// MARK: - Delegated methods
// MARK: - List Management
```

Pattern: `// MARK: - Section Name` (always with dash and space).

## Error Handling

**Patterns:**
- `guard` used for early exit with clear failure path — the dominant pattern
- `try?` for non-critical file I/O where failure is acceptable: `try? FileManager.default.removeItem(at: url)`
- `try` + `catch` for user-visible errors that need logging
- Errors logged via `ConcurrentLogManager` before returning or setting `hasError = true`
- No `Result<T, Error>` wrappers — functions return optionals or throw directly
- `@discardableResult` used in the test script's helper but not in production code

**Error reporting to UI:**
```swift
statusDescription = "Error message for user."
hasError = true
Task {
    await ConcurrentLogManager.shared.error(.system, "Log message", metadata: ["key": value])
}
```

**Network errors:**
- Caught in `do/catch`, logged via `ConcurrentLogManager`, function returns `false` or `nil`
- HTTP non-200 status is handled via `FilterUpdateResponseClassifier` (not raw `guard statusCode == 200`)

## Logging

**Framework:** `ConcurrentLogManager` (custom actor-based logger in `wBlock/ConcurrentLogManager.swift`)

**API:**
```swift
await ConcurrentLogManager.shared.info(.filterApply, "Message", metadata: ["key": "value"])
await ConcurrentLogManager.shared.error(.system, "Error message", metadata: ["error": error.localizedDescription])
await ConcurrentLogManager.shared.warning(.whitelist, "Warning message", metadata: [:])
await ConcurrentLogManager.shared.debug(.filterApply, "Debug message", metadata: [:])
```

**Log Categories** (enum `LogCategory`): `.system`, `.filterUpdate`, `.filterApply`, `.userScript`, `.network`, `.whitelist`, `.autoUpdate`, `.startup`

**Log Levels** (enum `LogLevel`): `.trace`, `.debug`, `.info`, `.warning`, `.error`

**In Safari extension targets** (`wBlock Advanced/PopoverViewModel.swift`): `os_log` from `os.log` is used instead since `ConcurrentLogManager` is a main-app actor.

**Debug-only console output:**
```swift
#if DEBUG
print(entry.compactFormat)
#endif
```

## Concurrency Patterns

**Main isolation:**
- Observable ViewModels and managers are `@MainActor class`: `AppFilterManager`, `ProtobufDataManager`, `ApplyChangesViewModel`
- UI state updates wrapped in `await MainActor.run { ... }`

**Background work:**
- `Task.detached(priority: .utility)` for CPU-heavy off-main work (file I/O, filter conversion)
- `withTaskGroup` for parallel work with bounded concurrency (content blocker reloads)
- `nonisolated` static methods for pure computation called from detached tasks

**Crossing actor boundaries:**
```swift
let result = await Task.detached {
    // off-main computation
}.value

await MainActor.run {
    self.someProperty = result
}
```

**Weak self in closures:**
```swift
source.setEventHandler { [weak self] in
    guard let self else { return }
    // ...
}
```

## Comments

**Doc comments:** Triple-slash `///` used for public API on computed properties and key methods:
```swift
/// Returns flag emojis for this filter's languages, or nil if none
public var flagEmojis: String? { ... }

/// Attempts to reload a content blocker with up to 5 retry attempts
/// Returns true if successful, false if all attempts failed
private func reloadContentBlockerWithRetry(...) async -> Bool { ... }
```

**Inline comments:** Explain non-obvious decisions, migration context, or why a workaround exists:
```swift
// WKErrorDomain error 6 is often transient right after writes.
// Yield to prevent main thread starvation on iOS
```

**Section headers:** `// MARK: - Name` for logical grouping within large files

## Module Design

**Exports:** `wBlockCoreService` uses `public` on everything intended for the main app. Private implementation helpers are `private`.

**Extensions:** Functionality split into extensions for large types: `ProtobufDataManager+Extensions.swift` adds all filter list, whitelist, and rule count management methods. `LiquidGlassDesignSystem.swift` adds `liquidGlass()` modifiers via `extension View`.

**Singletons:** Shared service objects expose `.shared` static property:
```swift
public static let shared = ConcurrentLogManager()
public static let shared = ProtobufDataManager()
public static let shared = GroupIdentifier()
```

**Design System:**
- `LiquidGlassDesignSystem` (`wBlock/LiquidGlassDesignSystem.swift`) is the shared design wrapper
- Views use `.liquidGlass()`, `.liquidGlassCapsule()`, `.liquidGlassInteractive()` modifiers
- Standard radii: `standardCornerRadius = 12`, `cardCornerRadius = 16`, `buttonCornerRadius = 12`

---

*Convention analysis: 2026-02-17*
