# Technology Stack

**Analysis Date:** 2026-02-17

## Languages

**Primary:**
- Swift 5.0 - All application and framework code
- JavaScript - Userscript injection via Safari Web Extension (`wBlock Scripts (iOS)`)

**Secondary:**
- Protocol Buffers (proto3) - Data serialization schema (`wBlockCoreService/DataModels.proto`, `wBlock/Protos/wblock_data.proto`)
- Shell/Python - Dev tooling only (`scripts/build-dmg.sh`, `scripts/mock_filter_server.py`)

## Runtime

**Environment:**
- macOS 14.0+ (Sonoma minimum)
- iOS 17.0+ minimum

**Package Manager:**
- Swift Package Manager (SPM)
- Lockfile: `wBlock.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (present)

## Frameworks

**Core UI:**
- SwiftUI - All views (macOS and iOS share the same view code where possible)
- Combine - Reactive state management (`@Published`, `ObservableObject`)

**Safari Integration:**
- SafariServices - Content blocker reloading and extension management
- `SFContentBlockerManager.reloadContentBlocker` - used in `wBlockCoreService/wBlockCoreService.swift`

**Background Tasks:**
- `NSBackgroundActivityScheduler` (macOS) - Periodic filter update scheduler
- `BGAppRefreshTask` + `BGProcessingTask` (iOS) - Background filter updates
- Both implemented in `wBlock/AppDelegate.swift`

**macOS XPC:**
- `NSXPCConnection` - Background filter update service
- Client: `wBlockCoreService/FilterUpdateXPC.swift`
- Service target: `FilterUpdateService/` (bundle ID: `skula.wBlock.FilterUpdateService`)

**Build/Dev:**
- Xcode 16.3+ (required for unified app group IDs across macOS/iOS)

## Key Dependencies

**Critical (via SPM):**
- `AdguardTeam/SafariConverterLib` v4.1.0 - Converts AdGuard/ABP filter rules to Safari content blocker JSON format. Imported as `ContentBlockerConverter` and `FilterEngine` in `wBlockCoreService/wBlockCoreService.swift`
- `apple/swift-protobuf` v1.30.0 - Protocol Buffers runtime for data persistence. Used in `wBlockCoreService/ProtobufDataManager.swift` as `internal import SwiftProtobuf`
- `weichsel/ZIPFoundation` v0.9.19 - ZIP archive handling. Imported in `wBlockCoreService/wBlockCoreService.swift` as `internal import ZIPFoundation`

**Supporting (via SPM):**
- `gumob/PunycodeSwift` v3.0.0 - Punycode encoding/decoding for internationalized domain names
- `ameshkov/swift-psl` v1.1.27 - Public Suffix List for domain classification
- `apple/swift-argument-parser` v1.5.0 - CLI argument parsing (used in `FilterUpdateService/main.swift`)

## Apple Platform Frameworks Used

- `CloudKit` - iCloud sync (`wBlock/CloudSyncManager.swift`)
- `CryptoKit` - SHA-256 hashing for cache fingerprints and sync content hashes
- `BackgroundTasks` - iOS background refresh
- `UserNotifications` - iOS push/local notifications
- `UniformTypeIdentifiers` - File type identification
- `os.log` / `Logger` - Structured logging throughout

## Configuration

**Environment:**
- No `.env` files - app is sandboxed; all configuration is stored in `UserDefaults` (suite: `group.skula.wBlock`) and the protobuf data file
- App Group ID: `group.skula.wBlock` (shared container between app and all extensions)
- iCloud Container: `iCloud.skula.wBlock` (CloudKit sync)

**Build:**
- `wBlock.xcodeproj/project.pbxproj` - Single project, multiple targets
- No separate scheme files; uses default Xcode scheme `wBlock`
- Version: `MARKETING_VERSION = 2.0.1`, `CURRENT_PROJECT_VERSION = 108`

## Platform Requirements

**Development:**
- Xcode 16.3 or later
- Apple Developer account with App Groups, CloudKit, and Push Notifications capabilities
- macOS 14+ development machine recommended

**Production:**
- macOS target: `MACOSX_DEPLOYMENT_TARGET = 14.0`
- iOS target: `IPHONEOS_DEPLOYMENT_TARGET = 17.0`
- Distributed via App Store (sandboxed with entitlements)
- Build verification: `xcodebuild -scheme wBlock -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`

---

*Stack analysis: 2026-02-17*
