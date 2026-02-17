# Technology Stack

**Analysis Date:** 2025-02-17

## Languages

**Primary:**
- Swift 5.x - All application and framework code, macOS and iOS targets
- Protobuf 3 - Data serialization format (DataModels.proto) compiled to Swift

**Secondary:**
- Shell - Build scripts and automation (`scripts/` directory)

## Runtime

**Environment:**
- Swift Runtime (native iOS/macOS)
- macOS 14.0+ (deployment target for all macOS targets)
- iOS 17.0+ (deployment target for all iOS targets)
- visionOS support via iOS extensions

**Package Manager:**
- Swift Package Manager (SPM) - Primary dependency management via Xcode
- No CocoaPods or external package managers

## Frameworks

**Core Apple Frameworks:**
- SwiftUI - UI framework for all views across macOS and iOS
- Combine - Reactive data binding and async operations
- CloudKit - iCloud sync infrastructure (`CloudSyncManager.swift`)
- SafariServices - Safari content blocker API integration
- CryptoKit - Cryptographic operations for data integrity and sync
- FileManager - Local file system operations
- UserNotifications - Push notifications and user alerts
- Foundation - Core Swift utilities (URLSession, UserDefaults via app groups)
- Cocoa (macOS only) - Native macOS UI integration (AppKit)
- UIKit (iOS only) - Native iOS UI integration

**SPM Dependencies:**
- ContentBlockerConverter (from SafariConverterLib) - Converts filter lists to Safari format
  - Repository: https://github.com/AdguardTeam/SafariConverterLib
  - Purpose: Transforms AdGuard-syntax filter lists to Safari JSON format
- ZIPFoundation - ZIP archive handling for compressed data
  - Repository: https://github.com/weichsel/ZIPFoundation
  - Purpose: Compression/decompression of filter data
- SwiftProtobuf - Protocol Buffers compiler and runtime
  - Repository: https://github.com/apple/swift-protobuf.git
  - Purpose: Type-safe serialization via DataModels.proto

**Build/Development:**
- Xcode 15.0+ (implied from Swift 5 and modern SPM usage)
- Xcode build system (xcodebuild)

## Key Dependencies

**Critical:**
- ContentBlockerConverter - Enables AdGuard filter syntax conversion to Safari-compatible JSON rules
- SwiftProtobuf - Enables efficient type-safe data storage and cross-process messaging
- ZIPFoundation - Enables filter list compression to reduce storage and network footprint

**Infrastructure:**
- CloudKit - iCloud data sync for cross-device configuration and userscript sync
- SafariServices - Direct integration with Safari extension system

## Configuration

**Environment:**
- App Group identifier via `GroupIdentifier.swift` - Enables data sharing between main app and extensions
- No environment files (.env) detected - Configuration is code-based and compile-time
- Entitlements files present for app group access (`wBlock.entitlements`, `FilterUpdateService.entitlements`)

**Build:**
- `wBlock.xcodeproj/project.pbxproj` - Main Xcode project configuration
- Defines 15+ targets: main app, 5 macOS content blocker extensions, 6 iOS content blocker extensions, 1 XPC service
- MARKETING_VERSION = 2.0.1
- CURRENT_PROJECT_VERSION = 108 (for app), 1 (for extensions)
- Code signing enabled with entitlements

**Build Parameters:**
- CODE_SIGNING_ALLOWED=NO for unsigned builds (development only)
- Multiple platform-specific build configurations (macOS, iOS, visionOS)

## Platform Requirements

**Development:**
- macOS 14.0+
- Xcode 15.0+
- Swift 5.x toolchain
- Apple Developer account for signing and App Store

**Production:**
- macOS 14.0+ - Main app and content blocker extensions
- iOS 17.0+ - App and iOS-specific extensions
- visionOS - Via iOS extensions (platformFilters: ios, xros)
- iCloud account for sync features (optional but recommended)

## Data Storage & Persistence

**Local Storage:**
- Protobuf binary files - Primary application state (app group container)
  - Format: `DataModels.proto` compiled to Swift via SwiftProtobuf
  - Contains: filter lists, userscripts, settings, rule counts, whitelist, auto-update metadata
  - File I/O: Off MainActor via `ProtobufDiskStore` actor
- UserDefaults (app group) - Legacy key-value storage, being deprecated in favor of Protobuf
- FileManager - Filter list files, userscript content, logs

**Network & Sync:**
- CloudKit (private database) - iCloud sync with record type "wBlockSync"
  - Syncs: filter selections, custom lists, userscripts, whitelist, deleted URLs
  - TTL: 90 days for deleted custom list markers
- HTTP(S) conditional requests - Filter list updates via If-Modified-Since/ETag headers

## Caching

**Memory Cache:**
- URLSession memory cache: 4MB in wBlockCoreService, 2MB in FilterListUpdater
- No disk cache for network requests (performance-focused, all filters reloaded fresh)
- URLSessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData

**Update Throttling:**
- Default 6-hour interval for auto-updates (configurable per filter list)
- Conditional requests only download if ETag/Last-Modified changed
- ETag and Last-Modified stored per filter UUID in AutoUpdateMetadata

## Interprocess Communication

**XPC Service:**
- FilterUpdateService.xpc - Dedicated macOS XPC service for background filter updates
- Protocol: NSXPCConnection with `FilterUpdateProtocol` interface
- Enables long-running updates without blocking extensions
- Timeout: 30s per request, 120s per resource

**App Groups:**
- Suite name: `GroupIdentifier.shared.value` (app-specific)
- Shared between main app and all extensions
- Enables real-time data access across app and Safari

**Notifications:**
- NSNotificationCenter - `.applyWBlockChangesNotification` triggers content blocker reload
- Used for extension-to-app and app-to-extension signaling

## Performance Optimizations

**Streaming I/O:**
- Protocol Buffers with streaming - Converts large filter lists without full memory load

**Parallel Operations:**
- TaskGroup for concurrent filter list downloads
- Actor-based serialization of disk I/O

**Resource Constraints:**
- Safari content blocker limit: 150,000 rules per extension (5 extensions = 750,000 total)
- Automatic rule distribution across extensions to stay within limits
- Extension processes run out-of-process from main app (native Safari optimization)

---

*Stack analysis: 2025-02-17*
