# Codebase Structure

**Analysis Date:** 2026-02-17

## Directory Layout

```
wBlock/                                 # Xcode project root
├── wBlock/                              # Main app (macOS/iOS SwiftUI)
│   ├── wBlockApp.swift                  # App entry point
│   ├── AppDelegate.swift                # Background task scheduling
│   ├── ContentView.swift                # Main filter/userscript/settings tabs
│   ├── AppFilterManager.swift           # State management for filters (82KB)
│   ├── FilterListUpdater.swift          # Filter fetching and parsing
│   ├── FilterListLoader.swift           # Default filter lists and migrations
│   ├── OnboardingView.swift             # First-launch wizard
│   ├── SettingsView.swift               # Auto-update, sync, display settings
│   ├── UserScriptManagerView.swift      # Userscript UI
│   ├── WhitelistView.swift              # Per-site disable UI
│   ├── CloudSyncManager.swift           # iCloud sync orchestration
│   ├── ConcurrentLogManager.swift       # Async logging
│   ├── ApplyChangesProgressView.swift   # Apply step-by-step progress modal
│   ├── UpdatePopupView.swift            # Available updates notification
│   ├── LogsView.swift                   # Debug log viewer
│   ├── LiquidGlassDesignSystem.swift    # Glass morphism design tokens
│   ├── SheetDesignSystem.swift          # Sheet container and toolbar components
│   ├── StatCard.swift                   # Summary stat displays
│   ├── LocalizationHelpers.swift        # Localization utilities
│   ├── Resources/                       # App assets (images, icons)
│   ├── [language].lproj/                # Localization (ar, de, en, es, fr, it, ja, ko, pl, pt-BR, ro, ru, zh-Hans, zh-Hant)
│   ├── Protos/                          # .proto source files
│   ├── wBlock.entitlements              # App group and sandbox entitlements
│   └── Info.plist
│
├── wBlockCoreService/                   # Shared framework used by all targets
│   ├── wBlockCoreService.swift          # Module definition
│   ├── ProtobufDataManager.swift        # Centralized protobuf-based data store (MainActor + ProtobufDiskStore actor)
│   ├── ProtobufDataManager+Extensions.swift  # Update/query helper methods
│   ├── DataModels.pb.swift              # Auto-generated protobuf model classes
│   ├── FilterList.swift                 # FilterList struct with language → flag emoji mapping
│   ├── FilterListCategory.swift         # Category enum (ads, privacy, security, etc.)
│   ├── UserScript.swift                 # UserScript struct with matching patterns
│   ├── UserScriptManager.swift          # Userscript lifecycle and injection
│   ├── ContentBlockerTargets.swift      # Platform, ContentBlockerTargetInfo, ContentBlockerTargetManager (5 slots each)
│   ├── ContentBlockerExtensionRequestHandler.swift  # Loads JSON from shared container for extensions
│   ├── ContentBlockerMappingService.swift  # Distributes filters to targets by least-filled rule count
│   ├── FilterUpdateXPC.swift            # XPC protocol for background updates
│   ├── FilterUpdateResponseClassifier.swift  # HTTP response classification
│   ├── SharedAutoUpdateManager.swift    # Triggers background update checks
│   ├── Constants.swift                  # Shared constants (timeouts, URLs, etc.)
│   ├── GroupIdentifier.swift            # App group identifier
│   ├── Utils.swift                      # Shared utilities
│   ├── wBlock/wBlock/Protos/            # .proto definitions (compiled to DataModels.pb.swift)
│   ├── wBlockCoreService.docc/          # Documentation catalog
│   └── [iOS/macOS specific handlers]
│
├── wBlock Ads/                          # Content blocker extension (macOS)
│   └── ContentBlockerRequestHandler.swift  # Loads rules_ads_macos.json
├── wBlock Ads (iOS)/                    # Content blocker extension (iOS)
│   └── ContentBlockerRequestHandler.swift  # Loads rules_ads_ios.json
│
├── wBlock Privacy/                      # Content blocker extension (macOS)
├── wBlock Privacy (iOS)/                # Content blocker extension (iOS)
├── wBlock Security/                     # Content blocker extension (macOS)
├── wBlock Security (iOS)/               # Content blocker extension (iOS)
├── wBlock Foreign/                      # Content blocker extension (macOS)
├── wBlock Foreign (iOS)/                # Content blocker extension (iOS)
├── wBlock Custom/                       # Content blocker extension (macOS)
├── wBlock Custom (iOS)/                 # Content blocker extension (iOS)
│
├── wBlock Scripts (iOS)/                # Web extension for script injection
│   ├── SafariWebExtensionHandler.swift
│   └── Resources/
│       ├── _locales/                    # Localization
│       └── Assets.xcassets/
│
├── wBlock Advanced/                     # Safari toolbar extension (macOS)
│   ├── SafariExtensionHandler.swift
│   ├── SafariExtensionViewController.swift
│   ├── PopoverView.swift
│   ├── PopoverViewModel.swift
│   ├── ToolbarData.swift
│   └── Resources/
│
├── FilterUpdateService/                 # Background update helper (macOS)
│   ├── main.swift                       # LaunchAgent entry point
│   ├── FilterUpdateService.swift        # Update logic
│   └── FilterUpdateServiceProtocol.swift  # XPC protocol
│
├── wBlock.xcodeproj/                    # Xcode project configuration
│   └── project.pbxproj                  # 38 occurrences of MARKETING_VERSION for versioning
│
├── .planning/codebase/                  # GSD planning documents
│   ├── ARCHITECTURE.md
│   └── STRUCTURE.md
│
├── .github/                             # GitHub workflows
├── scripts/                             # Build and utility scripts
├── docs/                                # User-facing documentation
├── Casks/                               # Homebrew Cask definitions
└── [README, LICENSE, CHANGELOG, etc.]
```

## Directory Purposes

**wBlock/:**
- Purpose: Main app UI and application logic
- Contains: SwiftUI views, state managers, filter operations, cloud sync
- Key files: `AppFilterManager.swift` (main state), `ContentView.swift` (tabs), `OnboardingView.swift`

**wBlockCoreService/:**
- Purpose: Shared business logic and models used by app and all extensions
- Contains: Protobuf data model, extension communication, filter distribution logic
- Key files: `ProtobufDataManager.swift` (persistence), `ContentBlockerTargets.swift` (extension slots)

**Extension Directories (wBlock Ads, wBlock Privacy, etc.):**
- Purpose: Per-extension content blocker implementations
- Contains: `ContentBlockerRequestHandler.swift` per directory
- One directory per extension per platform (e.g., `wBlock Ads/` and `wBlock Ads (iOS)/`)

**wBlock Scripts (iOS)/:**
- Purpose: Web extension for injecting and running userscripts
- Contains: SafariWebExtensionHandler, JavaScript bridge

**wBlock Advanced/:**
- Purpose: Safari toolbar icon extension (macOS only)
- Contains: PopoverView for quick access

**FilterUpdateService/:**
- Purpose: Separate executable for background filter updates (invoked by LaunchAgent on macOS)
- Contains: Update logic shared with main app

## Key File Locations

**Entry Points:**
- `wBlock/wBlockApp.swift`: SwiftUI app entry point with @main
- `FilterUpdateService/main.swift`: Background update service entry point
- `wBlock Ads/ContentBlockerRequestHandler.swift`: Content blocker extension handler (Ads slot)

**Configuration:**
- `wBlock.xcodeproj/project.pbxproj`: Build settings (MARKETING_VERSION = version for all targets)
- `wBlock/wBlock.entitlements`: App groups, sandbox settings
- `wBlockCoreService/Protos/wblock_data.proto`: Protobuf schema source

**Core Logic:**
- `wBlock/AppFilterManager.swift`: Main state container with apply, update, and disable logic
- `wBlockCoreService/ProtobufDataManager.swift`: Data persistence via protobuf
- `wBlock/FilterListUpdater.swift`: HTTP fetching with ETags and rule parsing
- `wBlockCoreService/ContentBlockerMappingService.swift`: Filter distribution algorithm

**UI:**
- `wBlock/ContentView.swift`: Tab-based navigation (Filters, Userscripts, Settings)
- `wBlock/OnboardingView.swift`: First-launch wizard with language/regional filter selection
- `wBlock/SettingsView.swift`: Auto-update interval, cloud sync, badge display
- `wBlock/UserScriptManagerView.swift`: Userscript list, import, enable/disable

**Testing:**
- No dedicated test files in codebase (quality focus TBD)
- Some test scripts in `scripts/` (e.g., `test_filter_update_http.swift`)

**Data Storage:**
- `~/Library/Group Containers/group.skula.wBlock/` (shared container):
  - `wblock.protobuf`: Main data file
  - `rules_ads_macos.json`, `rules_privacy_macos.json`, etc.: Compiled rules for each extension
  - `custom-{uuid}.txt`: Custom filter list content

## Naming Conventions

**Files:**
- Views: PascalCase.swift (e.g., `ContentView.swift`, `OnboardingView.swift`)
- Managers/Services: PascalCaseManager.swift or PascalCaseService.swift (e.g., `AppFilterManager.swift`, `CloudSyncManager.swift`)
- Models: PascalCase.swift (e.g., `FilterList.swift`, `UserScript.swift`)
- Handlers: Handler suffixes (e.g., `ContentBlockerRequestHandler.swift`, `SafariExtensionHandler.swift`)
- Utilities: UtilityName.swift (e.g., `ConcurrentLogManager.swift`, `LocalizationHelpers.swift`)

**Directories:**
- Extension targets: `wBlock {Category}` and `wBlock {Category} (iOS)` pattern
- Localization: `{language}.lproj` (POSIX locale, e.g., `pt-BR.lproj`)
- Generated files: `.pb.swift` suffix for protobuf models

**Code Style:**
- camelCase for functions and variables
- PascalCase for types and constants
- Trailing closures for SwiftUI view builders
- MainActor annotation for UI-safe methods

## Where to Add New Code

**New Filter List Feature:**
- Add UI controls to `wBlock/SettingsView.swift` or `wBlock/OnboardingView.swift`
- Add data properties to `wBlockCoreService/FilterList.swift`
- Update `wBlockCoreService/DataModels.pb.swift` schema and `Protos/wblock_data.proto`
- Add persistence methods to `wBlockCoreService/ProtobufDataManager.swift`

**New View/Component:**
- Create in `wBlock/{ComponentName}.swift` (co-located with related files)
- Import `wBlockCoreService` for data models
- For design system: Use `LiquidGlassDesignSystem` wrapper or `SheetDesignSystem` helpers
- Add localization keys to all `.lproj/Localizable.strings` files

**New Userscript Feature:**
- Add properties to `wBlockCoreService/UserScript.swift`
- Update UI in `wBlock/UserScriptManagerView.swift`
- Update protobuf schema in `Protos/wblock_data.proto`
- Add serialization in `wBlockCoreService/ProtobufDataManager+Extensions.swift`

**New Extension:**
- Create `wBlock {Category}/` and `wBlock {Category} (iOS)/` directories
- Add entry in `wBlockCoreService/ContentBlockerTargets.swift` (ContentBlockerTargetManager)
- Implement `ContentBlockerRequestHandler.swift` (standard pattern, copy from existing)
- Create bundled `blockerList.json` as fallback

**New Background Task:**
- Add handler in `wBlock/AppDelegate.swift` (iOS) or `FilterUpdateService/main.swift` (macOS)
- Use `SharedAutoUpdateManager.maybeRunAutoUpdate()` for orchestration
- Implement XPC communication via `FilterUpdateXPC.swift` protocol

**New Setting:**
- Add @Published property to `ProtobufDataManager`
- Add protobuf field in `Protos/wblock_data.proto`
- Add getter/setter in `ProtobufDataManager+Extensions.swift`
- Add UI control to `wBlock/SettingsView.swift`

**New Utility/Helper:**
- Place in `wBlockCoreService/Utils.swift` if shared across targets
- Place in `wBlock/{UtilityName}.swift` if app-specific (e.g., `ConcurrentLogManager.swift`)
- Use extension methods on existing types where appropriate

## Special Directories

**Resources/:**
- Purpose: App assets (icons, images)
- Generated: No
- Committed: Yes
- Includes: `Assets.xcassets`, localization bundles

**Protos/:**
- Purpose: Protocol Buffer schema source files
- Generated: `DataModels.pb.swift` is auto-generated from `.proto`
- Committed: Source `.proto` committed; `DataModels.pb.swift` generated via build phase

**{language}.lproj/:**
- Purpose: Localized strings
- Generated: No
- Committed: Yes
- Format: `Localizable.strings` with key-value pairs for each language

**wBlock.xcodeproj/xcshareddata/xcschemes/:**
- Purpose: Xcode scheme definitions (shared across developers)
- Generated: No
- Committed: Yes
- Schemes: One per build target (wBlock, wBlock Ads, etc.)

**FilterUpdateService/**
- Purpose: Separate executable for background updates
- Generated: Build products in DerivedData
- Committed: Source code only

## Important Build Configuration

**Version Management:**
- Stored in: `wBlock.xcodeproj/project.pbxproj`
- Pattern: MARKETING_VERSION set to same value across all 12 targets
- Must be updated consistently before release (used by GSD commands)

**App Groups:**
- Group ID: `group.skula.wBlock`
- Used by: Main app, all extensions, background service
- Shared storage location: `~/Library/Group Containers/group.skula.wBlock/`

**Code Signing:**
- Entitlements: `wBlock/wBlock.entitlements`
- Team ID: `DQN6XE3T8J` (or user's own for local builds)

---

*Structure analysis: 2026-02-17*
