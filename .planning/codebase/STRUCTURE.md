# Codebase Structure

**Analysis Date:** 2026-02-17

## Directory Layout

```
wBlock/                                    # Project root
├── wBlock.xcodeproj/                      # Xcode project (all targets)
├── wBlockCoreService/                     # Shared framework (models, managers, converters)
├── wBlock/                                # Main app (SwiftUI UI + orchestration)
├── wBlock Ads/                            # macOS content blocker slot 1
├── wBlock Privacy/                        # macOS content blocker slot 2
├── wBlock Security/                       # macOS content blocker slot 3 (security + annoyances)
├── wBlock Foreign/                        # macOS content blocker slot 4 (foreign + experimental)
├── wBlock Custom/                         # macOS content blocker slot 5 (custom filters)
├── wBlock Ads (iOS)/                      # iOS content blocker slot 1
├── wBlock Privacy (iOS)/                  # iOS content blocker slot 2
├── wBlock Security (iOS)/                 # iOS content blocker slot 3
├── wBlock Foreign (iOS)/                  # iOS content blocker slot 4
├── wBlock Custom (iOS)/                   # iOS content blocker slot 5
├── wBlock Advanced/                       # macOS Safari web extension (popover + element zapper)
├── wBlock Scripts (iOS)/                  # iOS Safari web extension (userscript injection)
├── FilterUpdateService/                   # macOS background XPC update daemon
├── scripts/                               # Build/dev utility scripts
├── docs/                                  # Project documentation assets
├── Casks/                                 # Homebrew Cask formula
├── .github/                               # CI workflows and issue templates
└── .planning/                             # GSD planning docs (gitignored)
```

## Directory Purposes

**`wBlockCoreService/`:**
- Purpose: Shared Swift framework imported by all targets
- Contains: Data models, protobuf schema + generated code, data manager, rule converter, extension request handler, target mapping, auto-update manager, userscript manager, utilities
- Key files:
  - `wBlockCoreService.swift` — `ContentBlockerService` (rule conversion, file I/O)
  - `ProtobufDataManager.swift` + `ProtobufDataManager+Extensions.swift` — all persistent state
  - `DataModels.proto` + `DataModels.pb.swift` — protobuf schema and generated Swift bindings
  - `FilterList.swift` — core `FilterList` struct
  - `FilterListCategory.swift` — `FilterListCategory` enum
  - `ContentBlockerTargets.swift` — slot/bundle ID mapping (`ContentBlockerTargetManager`)
  - `ContentBlockerMappingService.swift` — filter-to-slot distribution algorithm
  - `ContentBlockerExtensionRequestHandler.swift` — shared extension request logic
  - `SharedAutoUpdateManager.swift` — background auto-update actor
  - `UserScriptManager.swift` + `UserScript.swift` — userscript lifecycle
  - `GroupIdentifier.swift` — App Group ID singleton (`group.skula.wBlock`)
  - `FilterUpdateXPC.swift` — XPC protocol + client for macOS background service
  - `Utils.swift` — `FilterListMetadataParser`
  - `Constants.swift` — shared constants

**`wBlock/`:**
- Purpose: Main app target — SwiftUI views + app-layer orchestration
- Contains: Entry point, views, orchestration managers, localization `.lproj` directories
- Key files:
  - `wBlockApp.swift` — `@main` entry point
  - `AppDelegate.swift` — background task scheduling (macOS `NSBackgroundActivityScheduler`, iOS `BGAppRefreshTask`)
  - `AppFilterManager.swift` — filter orchestrator (`ObservableObject`); `applyChanges()` + `checkAndEnableFilters(forceReload:)` are main entry points
  - `FilterListLoader.swift` — reads/writes filter `.txt` files from App Group container
  - `FilterListUpdater.swift` — network fetch + update detection with `ETag`/`Last-Modified`
  - `CloudSyncManager.swift` — iCloud sync via `CloudKit`
  - `ConcurrentLogManager.swift` — structured in-app log manager
  - `ContentView.swift` — main filter list UI
  - `OnboardingView.swift` — multi-step onboarding
  - `SettingsView.swift` — settings page
  - `UserScriptManagerView.swift` — userscript management UI
  - `WhitelistManagerView.swift` + `WhitelistView.swift` — per-site disable UI
  - `ApplyChangesViewModel.swift` + `ApplyChangesProgressView.swift` — apply flow progress sheet
  - `UpdatePopupView.swift` — filter update available popup
  - `LogsView.swift` — in-app log viewer
  - `LiquidGlassDesignSystem.swift` — `liquidGlass(style:)` view modifier design system
  - `SheetDesignSystem.swift` — sheet-style design tokens
  - `StatCard.swift` — reusable stat display card

**`wBlock Ads/` (and all other content blocker slot dirs):**
- Purpose: Thin Safari content blocker extension — one per slot per platform
- Contains: Single `ContentBlockerRequestHandler.swift`, `Info.plist`, entitlements, fallback `blockerList.json`, localization `.lproj` dirs
- Key file: `ContentBlockerRequestHandler.swift` — looks up its slot filename from `ContentBlockerTargetManager`, calls `ContentBlockerExtensionRequestHandler.handleRequest(...)`

**`wBlock Advanced/`:**
- Purpose: macOS Safari web extension with toolbar popover, element zapper, userscript injection
- Contains: `SafariExtensionHandler.swift`, `PopoverViewModel.swift`, `PopoverView.swift`, `SafariExtensionViewController.swift`, `ToolbarData.swift`, localization `.lproj` dirs, `Resources/`
- Key file: `SafariExtensionHandler.swift` — `SFSafariExtensionHandler` subclass; handles page events, blocked counts, userscript injection

**`wBlock Scripts (iOS)/`:**
- Purpose: iOS Safari web extension (equivalent to wBlock Advanced for iOS)
- Contains: `SafariWebExtensionHandler.swift`, web assets (`Resources/pages/popup/popup.{html,css,js}`, `_locales/`)
- Key file: `SafariWebExtensionHandler.swift` — routes messages between web extension JS and native code

**`FilterUpdateService/`:**
- Purpose: macOS-only XPC background service for filter updates
- Contains: `main.swift` (XPC listener), `FilterUpdateService.swift` (implements `FilterUpdateProtocol`), `FilterUpdateServiceProtocol.swift` (stub), `Info.plist`, entitlements
- Key file: `main.swift` — sets up `NSXPCListener.service()`, accepts connections, hands off to `FilterUpdateService`

**`scripts/`:**
- Purpose: Developer utilities (not part of the app)
- Contains: `build-dmg.sh`, `mock_filter_server.py`, `run_filter_update_integration_tests.sh`, `test_filter_update_http.swift`

## Key File Locations

**Entry Points:**
- `wBlock/wBlockApp.swift`: `@main` app struct; creates `AppFilterManager`, starts `CloudSyncManager`
- `wBlock/AppDelegate.swift`: Background task scheduling and `applyWBlockChangesNotification` handling

**Configuration:**
- `wBlockCoreService/DataModels.proto`: Protobuf schema for all app state
- `wBlockCoreService/ContentBlockerTargets.swift`: Slot → bundle ID → JSON filename mapping
- `wBlockCoreService/GroupIdentifier.swift`: App Group identifier (`group.skula.wBlock`)
- `wBlock.xcodeproj/project.pbxproj`: `MARKETING_VERSION` controls app version (38 occurrences)

**Core Logic:**
- `wBlock/AppFilterManager.swift`: Filter orchestration; `applyChanges()` is the main apply entry point
- `wBlockCoreService/wBlockCoreService.swift`: Rule conversion (`ContentBlockerService`)
- `wBlockCoreService/ProtobufDataManager.swift`: Single source of truth for all state
- `wBlockCoreService/SharedAutoUpdateManager.swift`: Background auto-update scheduling + execution
- `wBlockCoreService/ContentBlockerMappingService.swift`: Filter-to-slot distribution

**UI:**
- `wBlock/ContentView.swift`: Main filter list screen
- `wBlock/OnboardingView.swift`: First-run wizard
- `wBlock/LiquidGlassDesignSystem.swift`: Design system (`liquidGlass(style:)` modifier)

**Testing:**
- `scripts/test_filter_update_http.swift`: Integration test for filter HTTP update logic
- `scripts/run_filter_update_integration_tests.sh`: Test runner

## Naming Conventions

**Files:**
- Swift source: `PascalCase.swift` (e.g. `AppFilterManager.swift`, `FilterListUpdater.swift`)
- Protobuf: `DataModels.proto` and generated `DataModels.pb.swift`
- Extension targets: dir name matches Xcode target name (e.g. `wBlock Ads/`, `wBlock Privacy/`)
- Localization: `<lang>.lproj/` (e.g. `en.lproj/`, `zh-Hans.lproj/`)

**Types:**
- Classes and structs: `PascalCase`
- Enums: `PascalCase` with `camelCase` cases
- Protocols: `PascalCase` ending in `-Protocol` or descriptive noun (e.g. `FilterUpdateProtocol`)
- Generated protobuf types: `Wblock_Data_<MessageName>` (e.g. `Wblock_Data_AppData`)

**Directories:**
- Framework target: `wBlockCoreService/` (no spaces)
- App target: `wBlock/` (no spaces)
- Extension targets: `wBlock <SlotName>/` (with space, matches Xcode target name)

## Where to Add New Code

**New filter list category:**
- Add case to `wBlockCoreService/FilterListCategory.swift`
- Update `ContentBlockerTargets.swift` if a new slot is needed
- Update `ContentBlockerMappingService.swift` if distribution logic changes
- Add category section in `wBlock/ContentView.swift`

**New persistent data field:**
- Add field to `wBlockCoreService/DataModels.proto`
- Regenerate `DataModels.pb.swift` (run protoc)
- Add accessor/mutator to `wBlockCoreService/ProtobufDataManager.swift` or its extension
- Add migration in `wBlockCoreService/ProtobufDataManager+Extensions.swift` if needed

**New UI view or screen:**
- Implementation: `wBlock/<ViewName>.swift`
- If the view needs a dedicated model: `wBlock/<ViewName>ViewModel.swift`
- Use `liquidGlass(style:)` modifier from `wBlock/LiquidGlassDesignSystem.swift` for cards/materials

**New service/manager in framework:**
- Implementation: `wBlockCoreService/<ManagerName>.swift`
- Add to `wBlockCoreService` Xcode target membership
- Use `@MainActor` + `ObservableObject` for UI-observable managers; Swift `actor` for background-safe services

**New content blocker slot:**
- Add `ContentBlockerTargetInfo` entry to `ContentBlockerTargetManager` in `wBlockCoreService/ContentBlockerTargets.swift`
- Create new Xcode extension target following the pattern of `wBlock Ads/`
- Add `ContentBlockerRequestHandler.swift` (copy from existing slot)

**Utility/helper functions:**
- Shared parsing utilities: `wBlockCoreService/Utils.swift`
- App-layer helpers without UI: `wBlock/` top level if no better home exists

## Special Directories

**`wBlock Advanced/Resources/`:**
- Purpose: Web extension JavaScript, CSS, and HTML assets for the macOS popover
- Generated: No
- Committed: Yes

**`wBlock Scripts (iOS)/Resources/`:**
- Purpose: Web extension assets (popup UI, locales) for iOS Safari extension
- Generated: No
- Committed: Yes

**`wBlockCoreService/wBlockCoreService.docc/`:**
- Purpose: DocC documentation catalog for the framework
- Generated: No
- Committed: Yes

**`.planning/`:**
- Purpose: GSD planning documents (phases, codebase analysis)
- Generated: No
- Committed: No (`.gitignore`d)

---

*Structure analysis: 2026-02-17*
