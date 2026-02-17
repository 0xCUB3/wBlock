# Architecture

**Analysis Date:** 2026-02-17

## Pattern Overview

**Overall:** Multi-layer, platform-adaptive Safari content blocker with distributed rule application across 5 content blocker extensions per platform (macOS/iOS).

**Key Characteristics:**
- **Separation of concerns**: UI app (`wBlock/`) uses shared core service (`wBlockCoreService/`) for business logic
- **Multi-extension architecture**: 5 content blocker extensions per platform (Ads, Privacy, Security, Foreign, Custom) + 1 web extension (Scripts)
- **Shared container communication**: Main app distributes compiled JSON rules to extension targets via app group container
- **Protobuf-based persistence**: All data (filters, userscripts, settings, rule counts) stored as Protocol Buffers for efficient cross-process access
- **Platform-specific**: Conditional compilation allows iOS and macOS to share most code while maintaining native features

## Layers

**UI Layer:**
- Purpose: SwiftUI-based app interface for filter management, userscript management, settings, and onboarding
- Location: `wBlock/`
- Contains: Views (ContentView, OnboardingView, SettingsView, UserScriptManagerView), UI state management (AppFilterManager)
- Depends on: wBlockCoreService for data models and persistence
- Used by: End users via macOS/iOS app

**Application State & Business Logic Layer:**
- Purpose: Manages filter lists, rule compilation, extension communication, and user preferences
- Location: `wBlock/AppFilterManager.swift`, `wBlock/FilterListUpdater.swift`, `wBlock/FilterListLoader.swift`
- Contains: Filter list operations, rule generation, update checking, distribution to extensions
- Depends on: wBlockCoreService (data models, protobuf manager), background task infrastructure
- Key responsibilities:
  - `AppFilterManager`: Main state controller; maintains @Published filter lists, handles apply/update operations
  - `FilterListUpdater`: Handles HTTP fetching, delta updates via ETags, rule counting
  - `FilterListLoader`: Manages built-in filter lists, URL migrations, file I/O

**Core Service Layer (Shared Framework):**
- Purpose: Shared business logic and data models used by main app and all extensions
- Location: `wBlockCoreService/`
- Contains: Data models, persistence, extension communication protocols, content blocker targets
- Depends on: SwiftProtobuf (protobuf deserialization), Foundation
- Key abstractions:
  - `ProtobufDataManager`: Centralized state via protobuf (replaces UserDefaults/SwiftData)
  - `FilterList`, `UserScript`: Core data models
  - `ContentBlockerTargetManager`: Manages 5 extension slots per platform
  - `ContentBlockerMappingService`: Distributes filters to extension slots by estimated rule count

**Content Blocker Extensions (Per-Platform):**
- Purpose: Load compiled JSON rules from shared container and provide to Safari
- Location: `wBlock Ads/`, `wBlock Privacy/`, `wBlock Security/`, `wBlock Foreign/`, `wBlock Custom/` (and iOS variants)
- Contains: ContentBlockerRequestHandler implementations, bundled fallback rules
- Depends on: wBlockCoreService
- Mechanism: Each extension loads target-specific JSON (e.g., `rules_ads_macos.json`) from shared container or uses bundled fallback

**Web Extension (Scripts):**
- Purpose: Inject and run user scripts in web pages
- Location: `wBlock Scripts (iOS)/`
- Contains: SafariWebExtensionHandler, JavaScript execution bridge
- Depends on: wBlockCoreService

**Data Persistence Layer:**
- Purpose: Efficient, type-safe data storage using Protocol Buffers
- Location: `wBlockCoreService/ProtobufDataManager.swift`, `wBlockCoreService/DataModels.pb.swift`
- Contains: Protobuf schema definitions, disk I/O actor, data serialization
- Key data structures:
  - `Wblock_Data_AppData`: Root protobuf containing all app state
  - `Wblock_Data_FilterListData[]`: Serialized filter list metadata
  - `Wblock_Data_RuleCountData`: Per-extension and total rule counts
  - `Wblock_Data_WhitelistData`: Per-site disable list
  - `Wblock_Data_UserScriptData[]`: Userscript metadata and content

**Background Update Layer:**
- Purpose: Automatic filter updates outside foreground app
- Location: `FilterUpdateService/`, `wBlockCoreService/SharedAutoUpdateManager.swift`
- Contains: Launch agent (macOS), background task handlers (iOS)
- Mechanism: Scheduled updates check for new filter versions, update shared container rules

## Data Flow

**Initial App Launch Flow:**

1. `wBlockApp.swift` entry point initializes `AppDelegate` and `AppFilterManager`
2. `AppFilterManager` reads protobuf data via `ProtobufDataManager.shared` (off-MainActor disk I/O)
3. `FilterListLoader.getDefaultFilterLists()` returns 13+ built-in filter lists
4. Loads user-saved selections and custom filters from protobuf
5. Updates filter list metadata (versions, rule counts) via `FilterListUpdater`
6. `ContentView` renders filters grouped by `FilterListCategory` (ads, privacy, security, annoyances, foreign, scripts, custom)

**Apply Changes Flow (checkAndEnableFilters):**

1. User toggles filter selections or taps "Apply Changes" button
2. `AppFilterManager.checkAndEnableFilters(forceReload:)` triggered
3. Compiles rules from selected filters:
   - Fetches content from URLs or local storage
   - Parses rules (filters out comments and blank lines)
   - Counts rules per filter (stored in `sourceRuleCount`)
4. Distributes rules across 5 content blocker targets using `ContentBlockerMappingService.distribute()`
   - Uses least-filled strategy based on estimated source rule counts
   - Balances 150,000 rule limit per extension
5. Converts rules to Safari's JSON Declarative Net Request format
6. Writes compiled JSON to shared container files:
   - `rules_ads_macos.json`, `rules_privacy_macos.json`, etc.
7. Updates `ProtobufDataManager` with:
   - Per-extension rule counts
   - Total rule count (`lastRuleCount`)
   - Categories approaching limit
   - Auto-disabled filters (if limit exceeded)
8. Extensions read updated JSON from shared container on next Safari request
9. Updates `ApplyChangesProgressView` with step-by-step progress
10. Auto-disables filters that cause limit overrun (with user alert)

**Filter Update Flow:**

1. Manual: User taps "Check for Updates" button → `AppFilterManager.checkForUpdates()`
2. Automatic: `SharedAutoUpdateManager` scheduled check or `FilterUpdateService` background task
3. For each enabled filter:
   - `FilterListUpdater.updateFilter()` fetches URL with ETags/Last-Modified headers
   - If no change (HTTP 304 or matching ETag), skip
   - If changed, download and parse new content
   - Update `sourceRuleCount`, version, `lastUpdated`
4. If any filter changed, trigger apply flow (step 5-10 above)
5. Save updated filter metadata to protobuf

**Onboarding Flow:**

1. First launch: `ContentModifiers` detects `!hasCompletedOnboarding`
2. Shows `OnboardingView` with steps:
   - Protection level selection (Minimal/Recommended)
   - Language-based regional filter selection (constructs from filter metadata `languages: [String]`)
   - Userscript opt-in with featured scripts
   - Cloud sync opt-in
   - Safari extension setup confirmation
3. On completion, sets `hasCompletedOnboarding = true`, selects appropriate filter presets
4. Triggers initial apply

**Cloud Sync Flow:**

1. `CloudSyncManager` monitors `ProtobufDataManager.didSaveData` publisher
2. On data change, uploads filter selections + userscript list to remote config
3. On app foreground, syncs remote changes to local via `CloudSyncManager.syncNow()`
4. Merges remote selections with local state (conflict resolution: timestamp-based)

## Key Abstractions

**Filter List (FilterList struct):**
- Purpose: Represents a single blocklist with metadata, URL, selection state
- Examples: AdGuard Base Filter, AdGuard Tracking Protection Filter
- Pattern: Value type (struct) with `@Published` wrapper in manager for observation
- Key computed property: `flagEmojis` returns language flag emojis from ISO 639-1 codes

**User Script (UserScript struct):**
- Purpose: Represents an injectable script with metadata and run conditions
- Contains: name, URL, matches/excludeMatches patterns, @grant declarations
- Pattern: Codable for serialization, parsed from script headers or metadata
- Lifecycle: Imported by user, downloaded to shared container, injected by web extension

**Content Blocker Target (ContentBlockerTargetInfo struct):**
- Purpose: Static configuration for each extension slot
- Examples: slot 1 = Ads, slot 2 = Privacy, etc.
- Pattern: Immutable configuration with platform, bundle ID, rules filename
- Singleton manager: `ContentBlockerTargetManager.shared.allTargets(forPlatform:)`

**Protobuf Data Manager (ProtobufDataManager class):**
- Purpose: Central data access point with change notifications
- Pattern: MainActor singleton with off-MainActor disk I/O via private `ProtobufDiskStore` actor
- Key methods:
  - `updateData { closure }`: Modify protobuf, save, and publish `didSaveData` on change
  - `waitUntilLoaded()`: Async barrier for initial data load
- Publishes `@Published` properties (but internal; consumers use computed properties)

**Extension Request Handlers:**
- Purpose: Per-extension entry points that load and return rules to Safari
- Examples: `wBlock Ads/ContentBlockerRequestHandler.swift`
- Pattern: Receive NSExtensionContext, load JSON from shared container, attach to response
- Fallback: Use bundled `blockerList.json` if shared container file missing

## Entry Points

**Main App (macOS/iOS):**
- Location: `wBlock/wBlockApp.swift`
- Triggers: App launch
- Responsibilities:
  - Initializes `AppDelegate` for background task scheduling
  - Creates `AppFilterManager` as `@StateObject`
  - Handles launch arguments (e.g., `--background-filter-update` for background task)
  - Runs data migrations on first launch
  - Sets up `CloudSyncManager` syncing

**Content Blocker Extension (macOS/iOS):**
- Location: `wBlock Ads/ContentBlockerRequestHandler.swift` (per extension)
- Triggers: Safari requests rules for content blocker
- Responsibilities:
  - Calls `ContentBlockerExtensionRequestHandler.handleRequest()`
  - Loads target-specific JSON from shared container
  - Falls back to bundled rules if missing
  - Attaches JSON to extension context

**Web Extension Handler (iOS):**
- Location: `wBlock Scripts (iOS)/SafariWebExtensionHandler.swift`
- Triggers: Web extension lifecycle events
- Responsibilities: Inject scripts, forward userscript requests

**Background Update Service (macOS):**
- Location: `FilterUpdateService/main.swift`
- Triggers: LaunchAgent scheduled events
- Responsibilities: Check for updates, apply if available, exit

**Background Update Service (iOS):**
- Location: `wBlock/AppDelegate.swift` (BGTaskScheduler handlers)
- Triggers: iOS background app refresh
- Responsibilities: Schedule and execute background filter checks

## Error Handling

**Strategy:** Progressive degradation with user-facing alerts

**Patterns:**
- **Filter download failure**: Log error, skip filter in apply step, continue with others
- **Rule compilation failure**: Show alert with filter name, auto-disable and retry
- **Extension communication**: Write empty `[]` JSON if shared container inaccessible (extensions fall back to bundled rules)
- **Protobuf corruption**: Re-initialize with defaults, preserve user selections where possible
- **Background task timeout**: Stop in-progress work, defer to next scheduled attempt

## Cross-Cutting Concerns

**Logging:**
- Framework: `ConcurrentLogManager` (custom, in-process)
- Approach: Async actor-based logging to avoid main thread blocking
- Categories: `.startup`, `.system`, `.network`, `.parsing`
- Example: `await ConcurrentLogManager.shared.info(.system, "Applied filters", metadata: [:])`

**Validation:**
- Filter URLs: Must be http/https, not duplicate
- Rule counts: Validated against 150k per-extension limit
- Userscript patterns: Regex validation for matches/excludeMatches
- Custom filter syntax: Validates AdGuard/uBlock syntax

**Authentication:**
- No user authentication; local-only app
- Cloud sync uses user's iCloud KeyChain (managed by `CloudSyncManager`)
- App group entitlements enable cross-process access

**Threading:**
- MainActor: All UI updates and state mutations
- Off-MainActor: Disk I/O via `ProtobufDiskStore` actor, network requests on background URLSession
- Sendable types: Used for protobuf models and key value objects

**State Synchronization:**
- Main app ↔ Extensions: Shared container files (write by main app, read by extensions)
- Main app ↔ Background task: Protobuf data persistence
- Main app ↔ UI: SwiftUI `@Published` in `AppFilterManager`

---

*Architecture analysis: 2026-02-17*
