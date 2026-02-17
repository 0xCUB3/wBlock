# External Integrations

**Analysis Date:** 2026-02-17

## APIs & External Services

**Filter List Providers:**
- AdGuard Filters Registry (`raw.githubusercontent.com/AdguardTeam/FiltersRegistry`) - Primary source for most built-in filter lists (AdGuard Base, Privacy, Annoyances, Cookie Notices, Popups, Widgets, etc.)
  - Example URL pattern: `https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/<N>_optimized.txt`
- AdGuard CDN (`filters.adtidy.org`) - Mirror/CDN for some filter lists
  - Example: `https://filters.adtidy.org/extension/safari/filters/227_optimized.txt`
- AdGuard Userscripts CDN (`userscripts.adtidy.org`) - Default userscript: AdGuard Extra
  - URL: `https://userscripts.adtidy.org/release/adguard-extra/1.0/adguard-extra.user.js`
- Various third-party filter list hosts (EasyList, Online Security Filter, d3ward, etc.) - URLs stored in filter list data, loaded via `FilterListLoader`

**Userscript Hosts (built-in defaults, defined in `wBlockCoreService/UserScriptManager.swift`):**
- GitHub Raw (`raw.githubusercontent.com`) - Return YouTube Dislike userscript
- jsDelivr CDN (`cdn.jsdelivr.net`) - YouTube Classic userscript
- Gitflic (`gitflic.ru`) - Bypass Paywalls Clean userscript (requires special User-Agent handling; see `createGitflicRequest` in `wBlockCoreService/UserScriptManager.swift`)

**Network Client:**
- All HTTP requests use `URLSession` with custom config: 30s request timeout, 120s resource timeout, 2MB in-memory URL cache (no disk cache)
- Conditional requests use `ETag` and `Last-Modified` headers for bandwidth-efficient updates
- Implemented in `wBlockCoreService/SharedAutoUpdateManager.swift` and `wBlock/FilterListUpdater.swift`

## Data Storage

**Primary Persistence:**
- Protocol Buffers binary file in the App Group shared container
- File path: `group.skula.wBlock` container → protobuf data file
- Managed by `wBlockCoreService/ProtobufDataManager.swift` (singleton, `@MainActor`)
- Schema defined in `wBlockCoreService/DataModels.proto`
- Replaces legacy `UserDefaults` and `SwiftData` (migration code present in `wBlock/DataMigration.swift`)

**Shared Container (App Group `group.skula.wBlock`):**
- Filter list `.txt` files - one per filter, named by UUID (e.g., `custom-<uuid>.txt` for user lists)
- Converted Safari content blocker JSON (`blockerList.json`) per extension target
- Incremental cache signatures and base rules cache
- Shared `UserDefaults` (suite: `group.skula.wBlock`) for sync state keys

**File Storage:**
- Local filesystem only (App Group shared container)
- No remote file storage; filter content is downloaded and stored locally

**Caching:**
- Incremental conversion cache: `ContentBlockerIncrementalCache` in `wBlockCoreService/`
  - Stores SHA-256 input signatures per content blocker target to skip re-conversion when filter inputs are unchanged
  - Stores cached advanced rules text per target for fast whitelist-only updates

## Authentication & Identity

**Auth Provider:**
- None - no user accounts or authentication
- App is fully local/offline except for filter downloads (unauthenticated HTTP GET) and optional iCloud sync

## Monitoring & Observability

**Error Tracking:**
- None (no Crashlytics, Sentry, or similar)

**Logs:**
- `ConcurrentLogManager` (`wBlock/ConcurrentLogManager.swift`) - custom actor-based structured log manager
- Categories: `.system`, `.filterApply`, `.filterUpdate`, `.autoUpdate`, `.whitelist`
- Logs visible in `wBlock/LogsView.swift` (in-app log viewer)
- Also uses `os.log` / `Logger` (Apple Unified Logging) throughout, subsystem `skula.wBlock`

## CI/CD & Deployment

**Hosting:**
- App Store (macOS and iOS)
- macOS also distributed as DMG (build script: `scripts/build-dmg.sh`, Homebrew Cask in `Casks/`)

**CI Pipeline:**
- None detected in repository

## Cloud Sync

**Provider:** Apple CloudKit (Private Database)
- Container: `iCloud.skula.wBlock`
- Record type: `wBlockSync`, record ID: `wblock-sync-config`
- Payload stored as `CKAsset` (JSON file attached to the CloudKit record)
- Entitlement: `com.apple.developer.icloud-services: CloudKit`
- Implemented in `wBlock/CloudSyncManager.swift`

**What syncs:**
- Filter list selection state (selected/deselected URLs)
- Custom filter lists (URL-based and inline user lists with content)
- Userscripts (remote URL-based and local content-based)
- Whitelist/disabled domains
- App settings (blocking level, badge counter, auto-update interval)

**Sync strategy:**
- Two-way: compares `updatedAt` timestamps; newer side wins
- Hash-based change detection to avoid unnecessary uploads
- Debounced local saves trigger upload after 1.5s idle + 2s delay

## Background Update Integration

**macOS:**
- `NSBackgroundActivityScheduler` with identifier `com.alexanderskula.wblock.filterupdate`
- 30-minute periodic timer (`periodicUpdateTimer`) in `wBlock/AppDelegate.swift`
- XPC service `FilterUpdateService` (bundle: `skula.wBlock.FilterUpdateService`) for background execution

**iOS:**
- `BGAppRefreshTask` - identifier: `com.alexanderskula.wblock.filter-update`
- `BGProcessingTask` - identifier: `com.alexanderskula.wblock.filter-processing`
- Both registered and handled in `wBlock/AppDelegate.swift`

## Safari Extension IPC

**App → Extension communication:**
- Shared App Group container (`group.skula.wBlock`) for passing `blockerList.json` rule files
- `SFContentBlockerManager.reloadContentBlocker(withIdentifier:)` to tell Safari to reload rules

**Extension → App (Advanced Extension only):**
- `wBlock Advanced` uses `NSExtensionContext` and `SFSafariApplication` APIs
- `wBlock Scripts (iOS)` uses Safari Web Extension messaging (`manifest.json` in `wBlock Scripts (iOS)/Resources/`)

## Webhooks & Callbacks

**Incoming:** None

**Outgoing:** None

---

*Integration audit: 2026-02-17*
