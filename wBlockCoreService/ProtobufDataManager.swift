//
//  ProtobufDataManager.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 8/13/25.
//

import Foundation
internal import SwiftProtobuf
import Combine
import os.log

/// Centralized data manager using Protocol Buffers for efficient, type-safe data storage
/// Replaces UserDefaults and SwiftData
@MainActor
public class ProtobufDataManager: ObservableObject {
    public var lastRuleCount: Int {
        Int(appData.ruleCounts.lastRuleCount)
    }

    public var ruleCountsByCategory: [String: Int32] {
        appData.ruleCounts.ruleCountsByCategory
    }

    public var categoriesApproachingLimit: [String] {
        appData.ruleCounts.categoriesApproachingLimit
    }

    public var disabledSites: [String] {
        appData.whitelist.disabledSites
    }

    public var whitelistLastUpdated: Int64 {
        appData.whitelist.lastUpdated
    }
    public var selectedBlockingLevel: String {
        appData.settings.selectedBlockingLevel
    }

    @MainActor
    public func setHasCompletedOnboarding(_ value: Bool) async {
        var updatedData = appData
        updatedData.settings.hasCompletedOnboarding_p = value
        appData = updatedData
        await saveData()
    }

    @MainActor
    public func setSelectedBlockingLevel(_ value: String) async {
        var updatedData = appData
        updatedData.settings.selectedBlockingLevel = value
        appData = updatedData
        await saveData()
    }
    public var hasCompletedOnboarding: Bool {
        appData.settings.hasCompletedOnboarding_p
    }

    // MARK: - Critical Setup State

    /// Indicates if all content blocker extensions have been enabled
    public var hasEnabledContentBlockers: Bool {
        appData.settings.hasEnabledContentBlockers_p
    }

    /// Indicates if wBlock Advanced (macOS) or wBlock Scripts (iOS) has been enabled
    public var hasEnabledPlatformExtension: Bool {
        appData.settings.hasEnabledPlatformExtension_p
    }

    /// Indicates if all extensions have been set to "Allow on All Websites"
    public var hasSetAllWebsitesPermission: Bool {
        appData.settings.hasSetAllWebsitesPermission_p
    }

    /// Indicates if the critical setup checklist has been completed
    public var hasCompletedCriticalSetup: Bool {
        hasEnabledContentBlockers && hasEnabledPlatformExtension && hasSetAllWebsitesPermission
    }

    @MainActor
    public func setHasEnabledContentBlockers(_ value: Bool) async {
        var updatedData = appData
        updatedData.settings.hasEnabledContentBlockers_p = value
        appData = updatedData
        await saveData()
    }

    @MainActor
    public func setHasEnabledPlatformExtension(_ value: Bool) async {
        var updatedData = appData
        updatedData.settings.hasEnabledPlatformExtension_p = value
        appData = updatedData
        await saveData()
    }

    @MainActor
    public func setHasSetAllWebsitesPermission(_ value: Bool) async {
        var updatedData = appData
        updatedData.settings.hasSetAllWebsitesPermission_p = value
        appData = updatedData
        await saveData()
    }

    // MARK: - Filter UI State

    /// Indicates if the foreign filters section is expanded
    public var isForeignFiltersExpanded: Bool {
        appData.settings.isForeignFiltersExpanded
    }

    @MainActor
    public func setIsForeignFiltersExpanded(_ value: Bool) async {
        var updatedData = appData
        updatedData.settings.isForeignFiltersExpanded = value
        appData = updatedData
        await saveData()
    }

    // MARK: - Badge Counter Setting

    /// Indicates if badge counter is enabled
    public var isBadgeCounterEnabled: Bool {
        appData.settings.isBadgeCounterEnabled
    }

    @MainActor
    public func setIsBadgeCounterEnabled(_ value: Bool) async {
        var updatedData = appData
        updatedData.settings.isBadgeCounterEnabled = value
        appData = updatedData
        await saveData()
    }

    // MARK: - Auto-Update Settings

    /// Indicates if auto-update is enabled
    public var autoUpdateEnabled: Bool {
        appData.autoUpdate.enabled
    }

    @MainActor
    public func setAutoUpdateEnabled(_ value: Bool) async {
        var updatedData = appData
        updatedData.autoUpdate.enabled = value
        appData = updatedData
        await saveData()
    }

    /// Auto-update interval in hours
    public var autoUpdateIntervalHours: Double {
        appData.autoUpdate.intervalHours
    }

    @MainActor
    public func setAutoUpdateIntervalHours(_ value: Double) async {
        var updatedData = appData
        updatedData.autoUpdate.intervalHours = value
        appData = updatedData
        await saveData()
    }

    /// Last auto-update check time (Unix timestamp)
    public var autoUpdateLastCheckTime: Int64 {
        appData.autoUpdate.lastCheckTime
    }

    @MainActor
    public func setAutoUpdateLastCheckTime(_ value: Int64) async {
        var updatedData = appData
        updatedData.autoUpdate.lastCheckTime = value
        appData = updatedData
        await saveData()
    }

    /// Last successful auto-update time (Unix timestamp)
    public var autoUpdateLastSuccessfulTime: Int64 {
        appData.autoUpdate.lastSuccessfulTime
    }

    @MainActor
    public func setAutoUpdateLastSuccessfulTime(_ value: Int64) async {
        var updatedData = appData
        updatedData.autoUpdate.lastSuccessfulTime = value
        appData = updatedData
        await saveData()
    }

    /// Next eligible auto-update time (Unix timestamp)
    public var autoUpdateNextEligibleTime: Int64 {
        appData.autoUpdate.nextEligibleTime
    }

    @MainActor
    public func setAutoUpdateNextEligibleTime(_ value: Int64) async {
        var updatedData = appData
        updatedData.autoUpdate.nextEligibleTime = value
        appData = updatedData
        await saveData()
    }

    /// Force next auto-update
    public var autoUpdateForceNext: Bool {
        appData.autoUpdate.forceNext
    }

    @MainActor
    public func setAutoUpdateForceNext(_ value: Bool) async {
        var updatedData = appData
        updatedData.autoUpdate.forceNext = value
        appData = updatedData
        await saveData()
    }

    /// Indicates if auto-update is currently running
    public var autoUpdateIsRunning: Bool {
        appData.autoUpdate.isRunning
    }

    @MainActor
    public func setAutoUpdateIsRunning(_ value: Bool) async {
        var updatedData = appData
        updatedData.autoUpdate.isRunning = value
        updatedData.autoUpdate.runningSinceTimestamp = value ? Int64(Date().timeIntervalSince1970) : 0
        appData = updatedData
        await saveData()
    }

    /// Timestamp when auto-update started running
    public var autoUpdateRunningSinceTimestamp: Int64 {
        appData.autoUpdate.runningSinceTimestamp
    }

    /// Get ETag for a specific filter UUID
    public func getFilterEtag(_ uuid: String) -> String? {
        appData.autoUpdate.filterEtags[uuid]
    }

    @MainActor
    public func setFilterEtag(_ uuid: String, etag: String?) async {
        var updatedData = appData
        if let etag = etag {
            updatedData.autoUpdate.filterEtags[uuid] = etag
        } else {
            updatedData.autoUpdate.filterEtags.removeValue(forKey: uuid)
        }
        appData = updatedData
        await saveData()
    }

    /// Get Last-Modified header for a specific filter UUID
    public func getFilterLastModified(_ uuid: String) -> String? {
        appData.autoUpdate.filterLastModified[uuid]
    }

    @MainActor
    public func setFilterLastModified(_ uuid: String, lastModified: String?) async {
        var updatedData = appData
        if let lastModified = lastModified {
            updatedData.autoUpdate.filterLastModified[uuid] = lastModified
        } else {
            updatedData.autoUpdate.filterLastModified.removeValue(forKey: uuid)
        }
        appData = updatedData
        await saveData()
    }

    /// Indicates if userscripts initial setup has been completed
    public var userscriptsInitialSetupCompleted: Bool {
        appData.autoUpdate.userscriptsInitialSetupCompleted
    }

    @MainActor
    public func setUserscriptsInitialSetupCompleted(_ value: Bool) async {
        var updatedData = appData
        updatedData.autoUpdate.userscriptsInitialSetupCompleted = value
        appData = updatedData
        await saveData()
    }

    // MARK: - Extension Data (Tab Tracking)

    /// Get blocked count for a specific tab ID
    public func getTabBlockedCount(_ tabId: String) -> Int {
        Int(appData.extensionData.tabBlockedRequests[tabId]?.blockedCount ?? 0)
    }

    /// Get host for a specific tab ID
    public func getTabHost(_ tabId: String) -> String {
        appData.extensionData.tabBlockedRequests[tabId]?.host ?? ""
    }

    /// Check if a tab is disabled
    public func isTabDisabled(_ tabId: String) -> Bool {
        appData.extensionData.tabBlockedRequests[tabId]?.isDisabled ?? false
    }

    @MainActor
    public func setTabDisabled(_ tabId: String, isDisabled: Bool) async {
        var updatedData = appData
        var tabData = updatedData.extensionData.tabBlockedRequests[tabId] ?? Wblock_Data_TabData()
        tabData.isDisabled = isDisabled
        tabData.lastUpdated = Int64(Date().timeIntervalSince1970)
        updatedData.extensionData.tabBlockedRequests[tabId] = tabData
        updatedData.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        appData = updatedData
        await saveData()
    }

    @MainActor
    public func removeTabData(_ tabId: String) async {
        var updatedData = appData
        updatedData.extensionData.tabBlockedRequests.removeValue(forKey: tabId)
        updatedData.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        appData = updatedData
        await saveData()
    }

    @MainActor
    public func updateTabBlockedCount(_ tabId: String, host: String, increment: Int = 1) async {
        var updatedData = appData
        var tabData = updatedData.extensionData.tabBlockedRequests[tabId] ?? Wblock_Data_TabData()
        tabData.blockedCount += Int32(increment)
        tabData.host = host
        tabData.lastUpdated = Int64(Date().timeIntervalSince1970)
        updatedData.extensionData.tabBlockedRequests[tabId] = tabData
        updatedData.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        appData = updatedData
        await saveData()
    }

    @MainActor
    public func clearOldTabData(olderThan: TimeInterval) async {
        var updatedData = appData
        let cutoffTime = Int64(Date().timeIntervalSince1970 - olderThan)
        updatedData.extensionData.tabBlockedRequests = updatedData.extensionData.tabBlockedRequests.filter { _, tabData in
            tabData.lastUpdated >= cutoffTime
        }
        updatedData.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        appData = updatedData
        await saveData()
    }

    /// Get all tab IDs that have data
    public var allTabIds: [String] {
        Array(appData.extensionData.tabBlockedRequests.keys)
    }

    // MARK: - Singleton
    public static let shared = ProtobufDataManager()
    
    // MARK: - Published Properties
    @Published var appData = Wblock_Data_AppData()
    
    var publicAppData: Wblock_Data_AppData {
        appData
    }
    @Published public private(set) var isLoading = true
    @Published public private(set) var lastError: Error?
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.skula.wBlock", category: "ProtobufDataManager")
    private let fileManager = FileManager.default
    private let dataFileName = "wblock_data.pb"
    private let backupFileName = "wblock_data_backup.pb"
    private let migrationFileName = "migration_completed.flag"
    private let terminologySanitizationVersion = 1 // Increment this to re-run sanitization
    
    // File URLs
    private lazy var dataFileURL: URL = {
        getDataDirectoryURL().appendingPathComponent(dataFileName)
    }()
    
    private lazy var backupFileURL: URL = {
        getDataDirectoryURL().appendingPathComponent(backupFileName)
    }()
    
    private lazy var migrationFlagURL: URL = {
        getDataDirectoryURL().appendingPathComponent(migrationFileName)
    }()
    
    // MARK: - Initialization
    private init() {
        logger.info("🔧 ProtobufDataManager initializing...")
        setupDataDirectory()
        Task {
            await loadData()
        }
    }
    
    // MARK: - Data Directory Setup
    private func setupDataDirectory() {
        let dataDir = getDataDirectoryURL()
        if !fileManager.fileExists(atPath: dataDir.path) {
            do {
                try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)
                logger.info("✅ Created data directory: \(dataDir.path)")
            } catch {
                logger.error("❌ Failed to create data directory: \(error)")
            }
        }
    }
    
    private func getDataDirectoryURL() -> URL {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
            return containerURL.appendingPathComponent("ProtobufData")
        } else {
            // Fallback to app support directory
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("wBlock").appendingPathComponent("ProtobufData")
        }
    }
    
    // MARK: - Data Loading
    public func loadData() async {
        await MainActor.run { isLoading = true }
        
        do {
            // Check if migration is needed
            if !fileManager.fileExists(atPath: migrationFlagURL.path) {
                logger.info("🔄 Starting migration from UserDefaults/SwiftData...")
                await migrateFromLegacyStorage()
                try Data().write(to: migrationFlagURL)
                logger.info("✅ Migration completed")
            }
            
            // Load protobuf data
            if fileManager.fileExists(atPath: dataFileURL.path) {
                let data = try Data(contentsOf: dataFileURL)
                let loadedData = try Wblock_Data_AppData(serializedData: data)

                await MainActor.run {
                    self.appData = loadedData
                    self.lastError = nil
                }

                logger.info("✅ Loaded protobuf data (\(data.count) bytes)")

                // Check if terminology sanitization is needed (must check on MainActor)
                let needsSanitization = await MainActor.run {
                    appData.settings.lastTerminologySanitizationVersion < terminologySanitizationVersion
                }

                if needsSanitization {
                    logger.info("🧹 Running terminology sanitization (version \(self.terminologySanitizationVersion))...")
                    await sanitizeStoredTerminology()
                }
            } else {
                logger.info("📝 No existing data file, creating default data")
                await createDefaultData()
            }
            
        } catch {
            logger.error("❌ Failed to load data: \(error)")
            await MainActor.run { self.lastError = error }
            
            // Try to load backup
            await loadBackup()
        }
        
        await MainActor.run { isLoading = false }
    }
    
    private func loadBackup() async {
        guard fileManager.fileExists(atPath: backupFileURL.path) else {
            logger.info("📝 No backup file available, creating default data")
            await createDefaultData()
            return
        }
        
        do {
            let backupData = try Data(contentsOf: backupFileURL)
            let loadedData = try Wblock_Data_AppData(serializedData: backupData)
            
            await MainActor.run {
                self.appData = loadedData
                self.lastError = nil
            }
            
            logger.info("✅ Loaded backup data (\(backupData.count) bytes)")
        } catch {
            logger.error("❌ Failed to load backup: \(error)")
            await createDefaultData()
        }
    }
    
    @MainActor
    public func resetToDefaultData() async {
        logger.info("🔄 Resetting protobuf data to default state")
        pendingSaveWorkItem?.cancel()
        do {
            if fileManager.fileExists(atPath: dataFileURL.path) {
                try fileManager.removeItem(at: dataFileURL)
            }
        } catch {
            logger.error("⚠️ Failed to remove data file during reset: \(error.localizedDescription)")
        }
        do {
            if fileManager.fileExists(atPath: backupFileURL.path) {
                try fileManager.removeItem(at: backupFileURL)
            }
        } catch {
            logger.error("⚠️ Failed to remove backup file during reset: \(error.localizedDescription)")
        }
        lastSavedData = nil
        await createDefaultData()
    }

    private func createDefaultData() async {
        var defaultData = Wblock_Data_AppData()

        // Initialize default settings
        defaultData.settings.hasCompletedOnboarding_p = false
        defaultData.settings.selectedBlockingLevel = "recommended"
        defaultData.settings.lastUpdateCheck = Int64(Date().timeIntervalSince1970)
        defaultData.settings.showAdvancedFeatures = false
        defaultData.settings.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        defaultData.settings.isBadgeCounterEnabled = true

        // Initialize default auto-update settings
        defaultData.autoUpdate.enabled = true
        defaultData.autoUpdate.intervalHours = 6.0
        defaultData.autoUpdate.lastCheckTime = 0
        defaultData.autoUpdate.lastSuccessfulTime = 0
        defaultData.autoUpdate.nextEligibleTime = 0
        defaultData.autoUpdate.forceNext = false
        defaultData.autoUpdate.isRunning = false
        defaultData.autoUpdate.runningSinceTimestamp = 0
        defaultData.autoUpdate.userscriptsInitialSetupCompleted = false

        // Initialize default performance data
        #if os(macOS)
        defaultData.performance.currentPlatform = .macos
        #else
        defaultData.performance.currentPlatform = .ios
        #endif

        defaultData.performance.lastConversionTime = "N/A"
        defaultData.performance.lastReloadTime = "N/A"
        defaultData.performance.lastFastUpdateTime = "N/A"

        await MainActor.run {
            self.appData = defaultData
        }

        await saveData()
        logger.info("✅ Created default data")
    }
    
    // MARK: - Data Saving (debounced)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.5
    private let ioQueue = DispatchQueue(label: "com.skula.wBlock.dataIO", qos: .utility)
    private var lastSavedData: Data?

    public func saveData() {
        // Cancel previous pending save
        pendingSaveWorkItem?.cancel()
        // Schedule new save
        let work = DispatchWorkItem { [weak self] in
            Task.detached { [weak self] in
                await self?.performSaveData()
            }
        }
    pendingSaveWorkItem = work
    // Schedule on dedicated I/O queue to ensure serialized file operations
    ioQueue.asyncAfter(deadline: .now() + saveDebounceInterval, execute: work)
    }

    // Perform serialization and file I/O off the main actor to avoid blocking UI
    private func performSaveData() async {
        // Snapshot appData on main actor, then serialize in background
        let snapshot = await MainActor.run { appData }
        do {
            // Serialize new data from snapshot
            let data = try snapshot.serializedData()
            // Skip save if data hasn't changed since last write
            let previous = await MainActor.run { lastSavedData }
            if let previous = previous, previous == data {
                return
            }
                try data.write(to: dataFileURL, options: .atomic)
        logger.info("✅ Saved protobuf data (\(data.count) bytes)")
        await MainActor.run {
            lastSavedData = data
            lastError = nil
        }
        } catch {
            logger.error("❌ Failed to save data: \(error)")
            await MainActor.run { lastError = error }
        }
    }
    
    // MARK: - Terminology Sanitization

    // Pre-compiled regex patterns for efficiency (compiled once, reused many times)
    private static let sanitizationRegexes: [(regex: NSRegularExpression, replacement: String)] = {
        let patterns: [(pattern: String, replacement: String)] = [
            ("malicious", "suspicious"),
            ("malware", "unwanted software"),
            ("spyware", "tracking software"),
            ("harmful", "unwanted"),
            ("dangerous", "risky")
        ]

        return patterns.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(pattern)\\b",
                options: [.caseInsensitive]
            ) else { return nil }
            return (regex, replacement)
        }
    }()

    /// Efficiently sanitizes stored filter list names and descriptions to remove Apple-flagged terminology
    private func sanitizeStoredTerminology() async {
        let startTime = Date()

        // Work directly on MainActor to avoid full copy
        await MainActor.run {
            var modifiedCount = 0

            // Sanitize filter list names AND descriptions
            for index in appData.filterLists.indices {
                // Sanitize name/title
                let originalName = appData.filterLists[index].name
                let sanitizedName = sanitizeText(originalName)
                if sanitizedName != originalName {
                    appData.filterLists[index].name = sanitizedName
                    modifiedCount += 1
                }

                // Sanitize description
                let originalDescription = appData.filterLists[index].description_p
                let sanitizedDescription = sanitizeText(originalDescription)
                if sanitizedDescription != originalDescription {
                    appData.filterLists[index].description_p = sanitizedDescription
                    modifiedCount += 1
                }
            }

            // Sanitize userscript names AND descriptions
            for index in appData.userScripts.indices {
                // Sanitize name/title
                let originalName = appData.userScripts[index].name
                let sanitizedName = sanitizeText(originalName)
                if sanitizedName != originalName {
                    appData.userScripts[index].name = sanitizedName
                    modifiedCount += 1
                }

                // Sanitize description
                let originalDescription = appData.userScripts[index].description_p
                let sanitizedDescription = sanitizeText(originalDescription)
                if sanitizedDescription != originalDescription {
                    appData.userScripts[index].description_p = sanitizedDescription
                    modifiedCount += 1
                }
            }

            // Update sanitization version
            appData.settings.lastTerminologySanitizationVersion = Int32(terminologySanitizationVersion)

            let duration = Date().timeIntervalSince(startTime)
            logger.info("✅ Terminology sanitization completed in \(String(format: "%.2f", duration))s (\(modifiedCount) items updated)")
        }

        // Save once after all modifications
        await saveData()
    }

    /// Sanitizes text by replacing Apple-flagged terminology using pre-compiled regexes
    private func sanitizeText(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var sanitized = text
        for (regex, replacement) in Self.sanitizationRegexes {
            let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: replacement
            )
        }

        return sanitized
    }

    // MARK: - Migration from Legacy Storage
    private func migrateFromLegacyStorage() async {
        logger.info("🔄 Migrating from UserDefaults and SwiftData...")

        let groupDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
        var migratedData = Wblock_Data_AppData()

        // Migrate app settings
        migratedData.settings.hasCompletedOnboarding_p = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        migratedData.settings.selectedBlockingLevel = UserDefaults.standard.string(forKey: "selectedBlockingLevel") ?? "recommended"

        // Migrate badge counter setting (from App Group UserDefaults)
        if groupDefaults.object(forKey: "isBadgeCounterEnabled") != nil {
            migratedData.settings.isBadgeCounterEnabled = groupDefaults.bool(forKey: "isBadgeCounterEnabled")
        } else {
            migratedData.settings.isBadgeCounterEnabled = true  // Default to enabled
        }

        // Migrate auto-update settings (from App Group UserDefaults)
        if groupDefaults.object(forKey: "autoUpdateEnabled") != nil {
            migratedData.autoUpdate.enabled = groupDefaults.bool(forKey: "autoUpdateEnabled")
        } else {
            migratedData.autoUpdate.enabled = true  // Default to enabled
        }

        migratedData.autoUpdate.intervalHours = groupDefaults.object(forKey: "autoUpdateIntervalHours") as? Double ?? 6.0
        migratedData.autoUpdate.lastCheckTime = Int64(groupDefaults.double(forKey: "autoUpdateLastCheckTime"))
        migratedData.autoUpdate.lastSuccessfulTime = Int64(groupDefaults.double(forKey: "autoUpdateLastSuccessful"))
        migratedData.autoUpdate.nextEligibleTime = Int64(groupDefaults.double(forKey: "autoUpdateNextEligibleTime"))
        migratedData.autoUpdate.forceNext = groupDefaults.bool(forKey: "autoUpdateForceNext")
        migratedData.autoUpdate.isRunning = groupDefaults.bool(forKey: "autoUpdateIsRunning")
        migratedData.autoUpdate.runningSinceTimestamp = Int64(groupDefaults.double(forKey: "autoUpdateIsRunningTimestamp"))

        // Migrate userscripts initial setup flag (from standard UserDefaults)
        migratedData.autoUpdate.userscriptsInitialSetupCompleted = UserDefaults.standard.bool(forKey: "userScriptsInitialSetupCompleted")

        // Migrate filter ETags and Last-Modified headers
        // Scan through all keys looking for filterEtag_ and filterLastModified_ prefixes
        for key in groupDefaults.dictionaryRepresentation().keys {
            if key.hasPrefix("filterEtag_") {
                let uuid = String(key.dropFirst("filterEtag_".count))
                if let etag = groupDefaults.string(forKey: key) {
                    migratedData.autoUpdate.filterEtags[uuid] = etag
                }
            } else if key.hasPrefix("filterLastModified_") {
                let uuid = String(key.dropFirst("filterLastModified_".count))
                if let lastModified = groupDefaults.string(forKey: key) {
                    migratedData.autoUpdate.filterLastModified[uuid] = lastModified
                }
            }
        }

        // Migrate tab blocked requests (from App Group UserDefaults)
        if let tabDataJSON = groupDefaults.data(forKey: "tabBlockedRequests"),
           let tabDataDict = try? JSONDecoder().decode([String: LegacyTabData].self, from: tabDataJSON) {
            for (tabId, legacyTab) in tabDataDict {
                var tabData = Wblock_Data_TabData()
                tabData.blockedCount = Int32(legacyTab.blockedCount)
                tabData.isDisabled = legacyTab.isDisabled
                tabData.host = legacyTab.host
                tabData.lastUpdated = Int64(Date().timeIntervalSince1970)
                migratedData.extensionData.tabBlockedRequests[tabId] = tabData
            }
            migratedData.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }

        // Migrate filter lists
        await migrateFilterLists(from: groupDefaults, to: &migratedData)

        // Migrate userscripts
        await migrateUserScripts(from: groupDefaults, to: &migratedData)

        // Migrate whitelist data
        migratedData.whitelist.disabledSites = groupDefaults.stringArray(forKey: "disabledSites") ?? []
        migratedData.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)

        // Migrate rule counts
        migratedData.ruleCounts.lastRuleCount = Int32(groupDefaults.integer(forKey: "lastRuleCount"))

        if let ruleCountsData = groupDefaults.data(forKey: "ruleCountsByCategory"),
           let ruleCounts = try? JSONDecoder().decode([String: Int].self, from: ruleCountsData) {
            for (category, count) in ruleCounts {
                migratedData.ruleCounts.ruleCountsByCategory[category] = Int32(count)
            }
        }

        if let categoriesData = groupDefaults.data(forKey: "categoriesApproachingLimit"),
           let categories = try? JSONDecoder().decode([String].self, from: categoriesData) {
            migratedData.ruleCounts.categoriesApproachingLimit = categories
        }

        await MainActor.run {
            self.appData = migratedData
        }

        await saveData()
        logger.info("✅ Migration completed successfully")
    }
    
    private func migrateFilterLists(from userDefaults: UserDefaults, to appData: inout Wblock_Data_AppData) async {
        // Migrate main filter lists
        if let data = userDefaults.data(forKey: "filterLists"),
           let filterLists = try? JSONDecoder().decode([LegacyFilterList].self, from: data) {
            
            for filterList in filterLists {
                var protoFilterList = Wblock_Data_FilterListData()
                protoFilterList.id = filterList.id.uuidString
                protoFilterList.name = filterList.name
                protoFilterList.url = filterList.url.absoluteString
                protoFilterList.category = mapFilterListCategory(filterList.category)
                protoFilterList.isSelected = filterList.isSelected
                protoFilterList.description_p = filterList.description
                protoFilterList.version = filterList.version
                if let sourceRuleCount = filterList.sourceRuleCount {
                protoFilterList.sourceRuleCount = Int32(sourceRuleCount)
            }
                protoFilterList.lastUpdated = Int64(Date().timeIntervalSince1970)
                protoFilterList.isCustom = false
                
                appData.filterLists.append(protoFilterList)
            }
        }
        
        // Migrate custom filter lists
        if let data = userDefaults.data(forKey: "customFilterLists"),
           let customFilterLists = try? JSONDecoder().decode([LegacyFilterList].self, from: data) {
            
            for filterList in customFilterLists {
                var protoFilterList = Wblock_Data_FilterListData()
                protoFilterList.id = filterList.id.uuidString
                protoFilterList.name = filterList.name
                protoFilterList.url = filterList.url.absoluteString
                protoFilterList.category = mapFilterListCategory(filterList.category)
                protoFilterList.isSelected = filterList.isSelected
                protoFilterList.description_p = filterList.description
                protoFilterList.version = filterList.version
                if let sourceRuleCount = filterList.sourceRuleCount {
                protoFilterList.sourceRuleCount = Int32(sourceRuleCount)
            }
                protoFilterList.lastUpdated = Int64(Date().timeIntervalSince1970)
                protoFilterList.isCustom = true
                
                appData.filterLists.append(protoFilterList)
            }
        }
    }
    
    private func migrateUserScripts(from userDefaults: UserDefaults, to appData: inout Wblock_Data_AppData) async {
        if let data = userDefaults.data(forKey: "userScripts"),
           let userScripts = try? JSONDecoder().decode([LegacyUserScript].self, from: data) {
            
            for userScript in userScripts {
                var protoUserScript = Wblock_Data_UserScriptData()
                protoUserScript.id = userScript.id.uuidString
                protoUserScript.name = userScript.name
                protoUserScript.url = userScript.url?.absoluteString ?? ""
                protoUserScript.isEnabled = userScript.isEnabled
                protoUserScript.description_p = userScript.description
                protoUserScript.version = userScript.version
                protoUserScript.matches = userScript.matches
                protoUserScript.excludeMatches = userScript.excludeMatches
                protoUserScript.includes = userScript.includes
                protoUserScript.excludes = userScript.excludes
                protoUserScript.runAt = userScript.runAt
                protoUserScript.injectInto = userScript.injectInto
                protoUserScript.grant = userScript.grant
                protoUserScript.isLocal = userScript.isLocal
                protoUserScript.updateURL = userScript.updateURL ?? ""
                protoUserScript.downloadURL = userScript.downloadURL ?? ""
                protoUserScript.content = userScript.content
                protoUserScript.lastUpdated = Int64(Date().timeIntervalSince1970)
                
                appData.userScripts.append(protoUserScript)
            }
        }
    }
    
    private func mapFilterListCategory(_ category: LegacyFilterListCategory) -> Wblock_Data_FilterListCategory {
        switch category {
        case .all: return .all
        case .ads: return .ads
        case .privacy: return .privacy
        case .security: return .security
        case .multipurpose: return .multipurpose
        case .annoyances: return .annoyances
        case .experimental: return .experimental
        case .custom: return .custom
        case .foreign: return .foreign
        case .scripts: return .scripts
        }
    }
}

// MARK: - Legacy Data Structures for Migration
private struct LegacyFilterList: Codable {
    let id: UUID
    var name: String
    var url: URL
    var category: LegacyFilterListCategory
    var isSelected: Bool
    var description: String
    var version: String
    var sourceRuleCount: Int?
}

private enum LegacyFilterListCategory: String, Codable, CaseIterable {
    case all = "All"
    case ads = "Ads"
    case privacy = "Privacy"
    case security = "Security"
    case multipurpose = "Multipurpose"
    case annoyances = "Annoyances"
    case experimental = "Experimental"
    case custom = "Custom"
    case foreign = "Foreign"
    case scripts = "Scripts"
}

private struct LegacyUserScript: Codable {
    let id: UUID
    var name: String
    var url: URL?
    var isEnabled: Bool
    var description: String
    var version: String
    var matches: [String]
    var excludeMatches: [String]
    var includes: [String]
    var excludes: [String]
    var runAt: String
    var injectInto: String
    var grant: [String]
    var isLocal: Bool
    var updateURL: String?
    var downloadURL: String?
    var content: String
}

private struct LegacyTabData: Codable {
    var blockedCount: Int
    var isDisabled: Bool
    var host: String
}
