# Architecture

**Analysis Date:** 2026-02-17

## Pattern Overview

**Overall:** Multi-process Safari Content Blocker with shared framework

**Key Characteristics:**
- Strict separation between a shared service framework (`wBlockCoreService`) and the main app (`wBlock`)
- Up to 5 parallel Safari content blocker extensions per platform (macOS + iOS), each holding one slot of rules
- App Group container (`group.skula.wBlock`) is the inter-process data bus — written by the app, read by all extension processes
- Protocol Buffers replace UserDefaults/SwiftData for all persisted state
- `@MainActor` used throughout; heavy I/O delegated to Swift Actors/async tasks

## Layers

**Shared Service Framework (`wBlockCoreService`):**
- Purpose: All platform-agnostic business logic accessible to both the main app and extensions
- Location: `wBlockCoreService/`
- Contains: Data models (`FilterList`, `UserScript`), data manager (`ProtobufDataManager`), rule conversion (`ContentBlockerService`), extension request handling (`ContentBlockerExtensionRequestHandler`), target/slot mapping (`ContentBlockerTargetManager`, `ContentBlockerMappingService`), auto-update coordination (`SharedAutoUpdateManager`), userscript runtime (`UserScriptManager`), utility parsing (`FilterListMetadataParser`)
- Depends on: `ContentBlockerConverter`, `FilterEngine`, `SwiftProtobuf`, `ZIPFoundation`, `CryptoKit`, `SafariServices`
- Used by: Main app (`wBlock`), all content blocker extensions, `FilterUpdateService`

**Main Application (`wBlock`):**
- Purpose: SwiftUI UI layer + orchestration of filter management
- Location: `wBlock/`
- Contains: `AppFilterManager` (orchestrator), `FilterListLoader` (local file I/O), `FilterListUpdater` (network fetch + update detection), `CloudSyncManager` (iCloud sync), `ConcurrentLogManager`, views (`ContentView`, `OnboardingView`, `SettingsView`, etc.)
- Depends on: `wBlockCoreService`, SwiftUI, Combine, CloudKit
- Used by: Entry point `wBlockApp.swift`

**Content Blocker Extensions (5 slots × 2 platforms):**
- Purpose: Serve pre-built JSON rule files to Safari on demand
- Location: `wBlock Ads/`, `wBlock Privacy/`, `wBlock Security/`, `wBlock Foreign/`, `wBlock Custom/` (macOS); `wBlock Ads (iOS)/`, etc. (iOS)
- Contains: One `ContentBlockerRequestHandler.swift` per target — minimal, delegates to `ContentBlockerExtensionRequestHandler` in the framework
- Depends on: `wBlockCoreService` only
- Used by: Safari, via `SFContentBlockerManager`

**Advanced / Web Extension (`wBlock Advanced`):**
- Purpose: Safari toolbar popover, element zapper, userscript injection, blocked-count badge
- Location: `wBlock Advanced/`
- Contains: `SafariExtensionHandler.swift`, `PopoverViewModel.swift`, `PopoverView.swift`, `ToolbarData.swift`, `SafariExtensionViewController.swift`
- Depends on: `wBlockCoreService`, `FilterEngine`, `SafariServices`
- Used by: Safari (macOS); equivalent iOS target: `wBlock Scripts (iOS)`

**Background XPC Service (`FilterUpdateService`):**
- Purpose: macOS background filter update daemon triggered by `NSBackgroundActivityScheduler` or launch agent
- Location: `FilterUpdateService/`
- Contains: `main.swift` (XPC listener), `FilterUpdateService.swift` (implements `FilterUpdateProtocol`)
- Depends on: `wBlockCoreService`
- Used by: Main app (`FilterUpdateClient.shared.updateFilters(...)`) via XPC

## Data Flow

**Apply Changes (user-triggered):**

1. User taps "Apply" in `ContentView` → `AppFilterManager.applyChanges()` called
2. `FilterListUpdater.checkForUpdates()` downloads any changed filter files into App Group container
3. `FilterListLoader` reads local `.txt` filter files from App Group container
4. `ContentBlockerService.convertRules()` converts AdGuard syntax → Safari JSON (via `ContentBlockerConverter` + `FilterEngine`)
5. `ContentBlockerMappingService.distribute()` assigns filters across 5 extension slots by estimated source-rule count
6. `ContentBlockerService.saveContentBlocker()` writes per-slot JSON rule files to App Group container (`rules_ads_macos.json`, etc.)
7. `ContentBlockerService.reloadContentBlocker()` calls `SFContentBlockerManager.reloadContentBlocker` for each slot
8. Each extension's `ContentBlockerRequestHandler` is invoked by Safari → reads its JSON file from App Group and returns it

**Auto-Update (background):**

1. `AppDelegate` schedules `NSBackgroundActivityScheduler` (macOS) or `BGAppRefreshTask` (iOS)
2. On trigger: `SharedAutoUpdateManager.maybeRunAutoUpdate()` runs in `wBlockCoreService` actor
3. Conditional HTTP requests with `If-None-Match`/`If-Modified-Since` headers; only re-converts if content changed
4. Writes updated rule JSON files to App Group, reloads extensions

**Extension → Popover (blocked-count):**

1. `SafariExtensionHandler` (Advanced) receives page load events from Safari
2. Reads/writes per-tab blocked count + host state into `ProtobufDataManager` (App Group)
3. `PopoverViewModel` reads that state on popover open to display blocked count

**State Management:**
- All persistent state lives in a single protobuf file (`AppData`) in the App Group container, managed by `ProtobufDataManager.shared` (singleton, `@MainActor`)
- `ProtobufDiskStore` actor serializes all disk reads/writes off the main thread
- `ProtobufDataManager` publishes `didSaveData` via Combine for cross-process sync triggers

## Key Abstractions

**`FilterList` (`wBlockCoreService/FilterList.swift`):**
- Purpose: Value type representing one filter list (built-in or custom)
- Pattern: `struct` conforming to `Identifiable, Codable, Hashable`; carries `languages: [String]` and `flagEmojis` computed property

**`FilterListCategory` (`wBlockCoreService/FilterListCategory.swift`):**
- Purpose: Enum categorizing filters into UI sections and extension slot assignments
- Examples: `.ads`, `.privacy`, `.security`, `.annoyances`, `.foreign`, `.custom`, `.scripts`

**`ContentBlockerTargetInfo` / `ContentBlockerTargetManager` (`wBlockCoreService/ContentBlockerTargets.swift`):**
- Purpose: Maps slot numbers (1–5) to bundle identifiers and rule JSON filenames for each platform
- Pattern: Singleton `ContentBlockerTargetManager.shared`; used by both app and extensions to resolve filenames without duplication

**`ContentBlockerMappingService` (`wBlockCoreService/ContentBlockerMappingService.swift`):**
- Purpose: Distributes selected filters across available extension slots by least-filled estimated source-rule count (greedy bin-packing)
- Pattern: Stateless `enum` with a single `static func distribute(...)`; shared between app layer and `SharedAutoUpdateManager`

**`ProtobufDataManager` (`wBlockCoreService/ProtobufDataManager.swift` + `ProtobufDataManager+Extensions.swift`):**
- Purpose: Single source of truth for all app data; replaces UserDefaults and SwiftData
- Pattern: `@MainActor` `ObservableObject` singleton; mutations go through `updateData { }` closures; extensions file adds domain-specific accessors

**`AppFilterManager` (`wBlock/AppFilterManager.swift`):**
- Purpose: App-layer orchestrator for filter state, apply flow, and update detection
- Pattern: `@MainActor` `ObservableObject`; owns `FilterListLoader`, `FilterListUpdater`; main entry points are `checkAndEnableFilters(forceReload:)` and `applyChanges(allowUserInteraction:)`

**`UserScriptManager` (`wBlockCoreService/UserScriptManager.swift`):**
- Purpose: Manages lifecycle of userscripts (install, update, inject, deduplicate)
- Pattern: `@MainActor` `ObservableObject` singleton; backed by `ProtobufDataManager` for metadata, flat files for script content in App Group container

## Entry Points

**Main App:**
- Location: `wBlock/wBlockApp.swift`
- Triggers: User launch, `--background-filter-update` launch argument (headless update mode)
- Responsibilities: Creates `AppFilterManager`, attaches `CloudSyncManager`, drives onboarding, registers background tasks, runs data migrations

**Content Blocker Extensions:**
- Location: e.g. `wBlock Ads/ContentBlockerRequestHandler.swift` (one per slot per platform)
- Triggers: Safari reloads the extension (via `SFContentBlockerManager.reloadContentBlocker`)
- Responsibilities: Look up the per-slot JSON filename from `ContentBlockerTargetManager`, read it from App Group container, return it to Safari

**Advanced Extension:**
- Location: `wBlock Advanced/SafariExtensionHandler.swift`
- Triggers: Safari page events, toolbar popover open
- Responsibilities: Count blocked requests, inject userscripts, serve element-zapper rules, manage per-site disable state

**Background XPC Service:**
- Location: `FilterUpdateService/main.swift`
- Triggers: XPC connection from main app (`FilterUpdateClient`) or system scheduler
- Responsibilities: Runs `SharedAutoUpdateManager.maybeRunAutoUpdate()` and exits

## Error Handling

**Strategy:** Result types for expected failures; `os_log` for diagnostics; user-visible errors surfaced through `@Published` properties on ObservableObjects

**Patterns:**
- `ContentBlockerService` methods return `Result<Void, Error>` for reload operations
- `AppFilterManager` sets `hasError: Bool` + `statusDescription: String` for UI feedback
- Extension handlers fall back to empty JSON `[]` on any file-read failure rather than crashing
- `SharedAutoUpdateManager` uses staleness detection to clear stuck `isRunning` flags

## Cross-Cutting Concerns

**Logging:** `ConcurrentLogManager` (`wBlock/ConcurrentLogManager.swift`) — structured `LogEntry` with `LogLevel` and `LogCategory`; also `os_log` in framework layer
**Validation:** Filter content validated by `FilterListMetadataParser` (regex-based, in `wBlockCoreService/Utils.swift`); rule counts tracked before/after conversion
**Authentication:** No in-app auth; iCloud sync uses `CKContainer.default().privateCloudDatabase` (user's own iCloud account)

---

*Architecture analysis: 2026-02-17*
