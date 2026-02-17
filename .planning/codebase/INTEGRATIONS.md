# External Integrations

**Analysis Date:** 2025-02-17

## APIs & External Services

**Filter List Sources:**
- AdGuard Filter Registry (multiple filters) - Blocks ads, trackers, cookie notices, popups, annoyances
  - Base URL: https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/
  - Examples: `filters/18_optimized.txt` (cookies), `19_optimized.txt` (popups), etc.
  - Protocol: HTTPS, conditional requests with If-Modified-Since/ETag
  - Implementation: `SharedAutoUpdateManager.swift`, `FilterListUpdater.swift`

**Userscript Sources:**
- GitHub (raw content) - Return YouTube Dislike userscript
  - URL: https://raw.githubusercontent.com/Anarios/return-youtube-dislike/main/Extensions/UserScript/Return%20Youtube%20Dislike.user.js
- Gitflic (Russian CDN) - Bypass Paywalls Clean userscript
  - URL: https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=userscript%2Fbpc.en.user.js
  - Note: Alternative source for mirror redundancy
- jsDelivr (global CDN) - YouTube Classic userscript
  - URL: https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/greasemonkey/youtube-classic.user.js
- AdTidy (Adguard userscript repository) - AdGuard Extra userscript
  - URL: https://userscripts.adtidy.org/release/adguard-extra/1.0/adguard-extra.user.js

**Custom Filter List URLs:**
- Support for any URL hosting AdGuard-syntax filter lists
- Validated and loaded via `FilterListUpdater.swift`, stored in Protobuf
- No hardcoded authentication required - public URLs only

## Data Storage

**Databases:**
- Not applicable - No traditional SQL/NoSQL database used

**Cloud Storage:**
- CloudKit (private database) - Primary cloud sync mechanism
  - Provider: Apple iCloud
  - Container: Default CKContainer
  - Database: Private database (CKContainer.default().privateCloudDatabase)
  - Record type: "wBlockSync"
  - Record ID: "wblock-sync-config"
  - Implementation: `CloudSyncManager.swift`
  - Syncs: Filter selections, custom lists, userscripts, whitelist, deleted URL markers
  - Credentials: User's iCloud account (automatic)

**Local File Storage:**
- FileManager (app group container) - All application data
  - Path: Secured app group container via `GroupIdentifier.shared.value`
  - Formats: Protobuf binary (AppData), raw filter files, userscript content, logs
  - Contains: `appdata.pb`, filter list files, userscript cache

## Authentication & Identity

**Auth Provider:**
- iCloud (CloudKit) - Automatic via user's Apple ID
  - Implementation: CloudKit uses device-level authentication (no explicit API key)
  - Scope: Private database only (user's own records)
  - Setup: `CloudSyncManager.swift` initializes `CKContainer.default().privateCloudDatabase`

**User Account:**
- No explicit user registration - App uses iCloud user identity implicitly
- No login/logout required for cloud sync - Tied to device Apple ID

## Monitoring & Observability

**Error Tracking:**
- Not integrated with third-party error tracking (Sentry, Crashlytics, etc.)
- Local error logging to file system via `ConcurrentLogManager.swift`

**Logs:**
- Local file-based logging with telemetry support
  - Log file: Stored in app group container
  - Formats: Plain text with timestamps and metadata
  - Manager: `ConcurrentLogManager.swift` - Thread-safe concurrent logging
  - Telemetry lines prefixed with "telemetry " for parsing
  - Includes auto-update events, sync status, conversion progress
  - Accessible via SettingsView > Logs

**OSLog Integration:**
- OS unified logging for debugging
  - Subsystem: "wBlockCoreService" (framework logs), "skula.wBlock" (app logs)
  - Categories: "SharedAutoUpdate", "CloudSync", "FilterUpdate", etc.
  - Visible via Xcode console and macOS Console.app

## CI/CD & Deployment

**Hosting:**
- App Store - Primary distribution channel
  - Platform: Apple App Store (macOS + iOS)
  - URL: https://apps.apple.com/app/wblock/id6746388723
  - Build ID: 108 (CURRENT_PROJECT_VERSION)

**CI Pipeline:**
- Not detected - No CI config files (GitHub Actions, Jenkins, etc.)
- Manual testing and release process (git-based workflow)

**GitHub Integration:**
- Repository: Public GitHub (0xCUB3/wBlock)
- Discord community: https://discord.gg/Y3yTFPpbXr (support/announcements)

## Environment Configuration

**Required Environment Variables:**
- Not applicable - No external APIs with credentials
- All configuration is compile-time or runtime-determined

**Secrets Location:**
- Not applicable - App uses only public filter list URLs and iCloud authentication

**Security Notes:**
- No API keys, tokens, or credentials in code or config files
- CloudKit uses automatic device authentication (secure enclave-backed)
- App group entitlements control data sharing between app and extensions

## Webhooks & Callbacks

**Incoming:**
- Not applicable - App doesn't expose webhook endpoints

**Outgoing:**
- Filter update checks - Outbound HTTPS to filter list URLs (on-demand or scheduled)
- iCloud sync - Outbound to CloudKit (automatic, background-safe)
- Userscript auto-updates - Outbound HTTPS to userscript sources

## Update Mechanisms

**Auto-Update:**
- Scheduled via `SharedAutoUpdateManager` - Configurable interval (default 6 hours)
- Triggered by: App launch, app activation, background task, XPC service
- Mechanism: Parallel HTTP conditional requests to filter list sources
- Conditional headers: If-Modified-Since, ETag (cached in Protobuf)
- Failure handling: Graceful fallback, retries on network errors

**Background Updates (macOS):**
- XPC Service: `FilterUpdateService.xpc` for background refresh
- Launch Agent: Can invoke app with `--background-filter-update` flag
- Enables updates without keeping app in foreground

**Userscript Updates:**
- Per-script update URLs stored in Protobuf (`UserScriptData.update_url`, `download_url`)
- Auto-check on app launch via `UserScriptManager.swift`
- User can manually refresh via UI

## Data Sync

**iCloud Sync Strategy:**
- Push: App detects local changes → CloudKit record update
- Pull: On app activation, checks for remote changes → applies to local Protobuf
- Conflict resolution: Timestamp-based (latest wins) for filter selections
- Deleted marker TTL: 90 days for custom lists (prevents re-sync of old deletions)

**Cross-Device Sync:**
- Syncs across all user's Apple devices via CloudKit
- Data: Filter selections, custom lists, userscripts, whitelist
- Implementation: `CloudSyncManager.swift` with conflict resolution

---

*Integration audit: 2025-02-17*
