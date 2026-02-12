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

// MARK: - Disk I/O (off MainActor)

/// Performs protobuf file reads/writes off the MainActor to avoid UI stalls.
/// An actor is used so reads/writes are serialized.
private actor ProtobufDiskStore {
    private let fileManager = FileManager.default

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func modificationDate(for url: URL) -> Date? {
        guard fileExists(at: url) else { return nil }
        return (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    func readAppData(from url: URL) throws -> (appData: Wblock_Data_AppData, rawData: Data, modificationDate: Date?) {
        let rawData = try Data(contentsOf: url)
        let appData = try Wblock_Data_AppData(serializedData: rawData)
        return (appData: appData, rawData: rawData, modificationDate: modificationDate(for: url))
    }

    func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func writeAppDataIfChanged(appData: Wblock_Data_AppData, previousData: Data?, to url: URL) throws -> (rawData: Data, modificationDate: Date?)? {
        let rawData = try appData.serializedData()
        if let previousData, previousData == rawData {
            return nil
        }
        try writeData(rawData, to: url)
        return (rawData: rawData, modificationDate: modificationDate(for: url))
    }

    func removeItemIfExists(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try fileManager.removeItem(at: url)
    }
}

/// Centralized data manager using Protocol Buffers for efficient, type-safe data storage
/// Replaces UserDefaults and SwiftData
@MainActor
public class ProtobufDataManager: ObservableObject {
    /// Publishes after a successful on-disk save of the protobuf file.
    /// Useful for cross-process features (e.g. sync) that should react only when data is persisted.
    public var didSaveData: AnyPublisher<Void, Never> {
        didSaveDataSubject.eraseToAnyPublisher()
    }

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
        await updateData { $0.settings.hasCompletedOnboarding_p = value }
    }

    @MainActor
    public func setSelectedBlockingLevel(_ value: String) async {
        await updateData { $0.settings.selectedBlockingLevel = value }
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
        await updateData { $0.settings.hasEnabledContentBlockers_p = value }
    }

    @MainActor
    public func setHasEnabledPlatformExtension(_ value: Bool) async {
        await updateData { $0.settings.hasEnabledPlatformExtension_p = value }
    }

    @MainActor
    public func setHasSetAllWebsitesPermission(_ value: Bool) async {
        await updateData { $0.settings.hasSetAllWebsitesPermission_p = value }
    }

    // MARK: - Filter UI State

    /// Indicates if the foreign filters section is expanded
    public var isForeignFiltersExpanded: Bool {
        appData.settings.isForeignFiltersExpanded
    }

    @MainActor
    public func setIsForeignFiltersExpanded(_ value: Bool) async {
        await updateData { $0.settings.isForeignFiltersExpanded = value }
    }

    // MARK: - Badge Counter Setting

    /// Indicates if badge counter is enabled
    public var isBadgeCounterEnabled: Bool {
        appData.settings.isBadgeCounterEnabled
    }

    @MainActor
    public func setIsBadgeCounterEnabled(_ value: Bool) async {
        await updateData { $0.settings.isBadgeCounterEnabled = value }
    }

    // MARK: - Auto-Update Settings

    /// Indicates if auto-update is enabled
    public var autoUpdateEnabled: Bool {
        appData.autoUpdate.enabled
    }

    @MainActor
    public func setAutoUpdateEnabled(_ value: Bool) async {
        await updateData { $0.autoUpdate.enabled = value }
    }

    /// Auto-update interval in hours
    public var autoUpdateIntervalHours: Double {
        appData.autoUpdate.intervalHours
    }

    @MainActor
    public func setAutoUpdateIntervalHours(_ value: Double) async {
        await updateData { $0.autoUpdate.intervalHours = value }
    }

    /// Last auto-update check time (Unix timestamp)
    public var autoUpdateLastCheckTime: Int64 {
        appData.autoUpdate.lastCheckTime
    }

    @MainActor
    public func setAutoUpdateLastCheckTime(_ value: Int64) async {
        await updateData { $0.autoUpdate.lastCheckTime = value }
    }

    /// Last successful auto-update time (Unix timestamp)
    public var autoUpdateLastSuccessfulTime: Int64 {
        appData.autoUpdate.lastSuccessfulTime
    }

    @MainActor
    public func setAutoUpdateLastSuccessfulTime(_ value: Int64) async {
        await updateData { $0.autoUpdate.lastSuccessfulTime = value }
    }

    /// Next eligible auto-update time (Unix timestamp)
    public var autoUpdateNextEligibleTime: Int64 {
        appData.autoUpdate.nextEligibleTime
    }

    @MainActor
    public func setAutoUpdateNextEligibleTime(_ value: Int64) async {
        await updateData { $0.autoUpdate.nextEligibleTime = value }
    }

    /// Force next auto-update
    public var autoUpdateForceNext: Bool {
        appData.autoUpdate.forceNext
    }

    @MainActor
    public func setAutoUpdateForceNext(_ value: Bool) async {
        await updateData { $0.autoUpdate.forceNext = value }
    }

    /// Indicates if auto-update is currently running
    public var autoUpdateIsRunning: Bool {
        appData.autoUpdate.isRunning
    }

    @MainActor
    public func setAutoUpdateIsRunning(_ value: Bool) async {
        let nowTimestamp = Int64(Date().timeIntervalSince1970)

        if appData.autoUpdate.isRunning == value {
            if value {
                appData.autoUpdate.runningSinceTimestamp = nowTimestamp
                await saveData()
            } else if appData.autoUpdate.runningSinceTimestamp != 0 {
                appData.autoUpdate.runningSinceTimestamp = 0
                await saveData()
            }
            return
        }

        var updatedData = await latestAppDataSnapshot()
        updatedData.autoUpdate.isRunning = value
        updatedData.autoUpdate.runningSinceTimestamp = value ? nowTimestamp : 0
        appData = updatedData
        await saveData()
    }

    /// Refreshes the running timestamp without re-writing unrelated auto-update fields.
    /// Used by heartbeat paths to avoid heavier state mutations.
    @MainActor
    public func refreshAutoUpdateRunningTimestamp(minimumIntervalSeconds: Int64 = 45) async {
        guard appData.autoUpdate.isRunning else { return }
        let nowTimestamp = Int64(Date().timeIntervalSince1970)
        let previous = appData.autoUpdate.runningSinceTimestamp
        if previous > 0 && (nowTimestamp - previous) < minimumIntervalSeconds {
            return
        }
        appData.autoUpdate.runningSinceTimestamp = nowTimestamp
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
        await setFilterValidators(uuid, etag: etag, lastModified: nil, updateLastModified: false)
    }

    /// Get Last-Modified header for a specific filter UUID
    public func getFilterLastModified(_ uuid: String) -> String? {
        appData.autoUpdate.filterLastModified[uuid]
    }

    @MainActor
    public func setFilterLastModified(_ uuid: String, lastModified: String?) async {
        await setFilterValidators(uuid, etag: nil, lastModified: lastModified, updateETag: false)
    }

    /// Sets both ETag and Last-Modified validators for a filter in a single write.
    @MainActor
    public func setFilterValidators(_ uuid: String, etag: String?, lastModified: String?) async {
        await setFilterValidators(uuid, etag: etag, lastModified: lastModified, updateETag: true, updateLastModified: true)
    }

    /// Batch-updates validators for multiple filters with one persisted write.
    @MainActor
    public func setFilterValidators(_ updates: [String: (etag: String?, lastModified: String?)]) async {
        guard !updates.isEmpty else { return }
        var updatedData = await latestAppDataSnapshot()
        for (uuid, update) in updates {
            if let etag = update.etag {
                updatedData.autoUpdate.filterEtags[uuid] = etag
            } else {
                updatedData.autoUpdate.filterEtags.removeValue(forKey: uuid)
            }

            if let lastModified = update.lastModified {
                updatedData.autoUpdate.filterLastModified[uuid] = lastModified
            } else {
                updatedData.autoUpdate.filterLastModified.removeValue(forKey: uuid)
            }
        }
        appData = updatedData
        await saveData()
    }

    @MainActor
    private func setFilterValidators(
        _ uuid: String,
        etag: String?,
        lastModified: String?,
        updateETag: Bool = true,
        updateLastModified: Bool = true
    ) async {
        var updatedData = await latestAppDataSnapshot()
        if updateETag {
            if let etag = etag {
                updatedData.autoUpdate.filterEtags[uuid] = etag
            } else {
                updatedData.autoUpdate.filterEtags.removeValue(forKey: uuid)
            }
        }
        if updateLastModified {
            if let lastModified = lastModified {
                updatedData.autoUpdate.filterLastModified[uuid] = lastModified
            } else {
                updatedData.autoUpdate.filterLastModified.removeValue(forKey: uuid)
            }
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
        await updateData { $0.autoUpdate.userscriptsInitialSetupCompleted = value }
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
        var updatedData = await latestAppDataSnapshot()
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
        var updatedData = await latestAppDataSnapshot()
        updatedData.extensionData.tabBlockedRequests.removeValue(forKey: tabId)
        updatedData.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        appData = updatedData
        await saveData()
    }

    @MainActor
    public func updateTabBlockedCount(_ tabId: String, host: String, increment: Int = 1) async {
        var updatedData = await latestAppDataSnapshot()
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
        var updatedData = await latestAppDataSnapshot()
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

    private let didSaveDataSubject = PassthroughSubject<Void, Never>()
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.skula.wBlock", category: "ProtobufDataManager")
    private let fileManager = FileManager.default
    private let diskStore = ProtobufDiskStore()
    private let dataFileName = "wblock_data.pb"
    private let backupFileName = "wblock_data_backup.pb"
    private let migrationFileName = "migration_completed.flag"
    private let terminologySanitizationVersion = 1 // Increment this to re-run sanitization
    private var lastLoadedDataFileModificationDate: Date?
    private var initialLoadTask: Task<Void, Never>?

    /// Returns the most recent app data snapshot from disk if available; otherwise, returns the in-memory value.
    /// This helps avoid clobbering concurrent writes from other processes that share the app group file.
    func latestAppDataSnapshot() async -> Wblock_Data_AppData {
        let currentModDate = await diskStore.modificationDate(for: dataFileURL)

        // If nothing changed on disk, avoid redundant decode work.
        if let currentModDate, currentModDate == lastLoadedDataFileModificationDate {
            return appData
        }

        // Try to read the persisted file first to incorporate recent writes from extensions or helper processes.
        if await diskStore.fileExists(at: dataFileURL),
           let loaded = try? await diskStore.readAppData(from: dataFileURL) {
            lastLoadedDataFileModificationDate = loaded.modificationDate ?? currentModDate
            lastSavedData = loaded.rawData
            return loaded.appData
        }

        // Fallback to current in-memory state if file is missing or unreadable.
        return appData
    }

    /// Reloads protobuf data from disk only if the underlying file has changed.
    /// Returns `true` when in-memory state was refreshed.
    @discardableResult
    public func refreshFromDiskIfModified() async -> Bool {
        guard let currentModDate = await diskStore.modificationDate(for: dataFileURL) else {
            return false
        }
        if let lastLoaded = lastLoadedDataFileModificationDate, lastLoaded == currentModDate {
            return false
        }

        do {
            let loaded = try await diskStore.readAppData(from: dataFileURL)
            appData = loaded.appData
            lastSavedData = loaded.rawData
            lastLoadedDataFileModificationDate = loaded.modificationDate ?? currentModDate
            lastError = nil
            return true
        } catch {
            lastError = error
            logger.error("❌ Failed to refresh protobuf data from disk: \(error.localizedDescription)")
            return false
        }
    }
    
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
        initialLoadTask = Task { [weak self] in
            await self?.loadData()
        }
    }

    /// Waits for the initial protobuf load to complete.
    public func waitUntilLoaded() async {
        if let task = initialLoadTask {
            await task.value
            return
        }

        // Fallback (shouldn't happen): suspend until initial load flips `isLoading`.
        while isLoading {
            await Task.yield()
        }
    }

    // MARK: - Helper Methods

    /// Generic helper method to reduce boilerplate in setter methods
    /// Updates appData using a closure and saves the changes
    @MainActor
    private func updateData(with block: (inout Wblock_Data_AppData) -> Void) async {
        var updatedData = await latestAppDataSnapshot()
        block(&updatedData)
        appData = updatedData
        await saveData()
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

    /// Returns the protobuf data directory in the shared app group container.
    /// Exposed for filesystem observation in clients that need cross-process change detection.
    public func protobufDataDirectoryURL() -> URL? {
        getDataDirectoryURL()
    }
    
    private func getDataDirectoryURL() -> URL {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
            return containerURL.appendingPathComponent("ProtobufData")
        } else {
            // Fallback to app support directory
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            return appSupport.appendingPathComponent("wBlock").appendingPathComponent("ProtobufData")
        }
    }

    // MARK: - Legacy Migration Sanitization

    private static let defaultAutoUpdateIntervalHours: Double = 6.0
    private static let minimumAutoUpdateIntervalHours: Double = 1.0
    private static let maximumAutoUpdateIntervalHours: Double = 24.0 * 7.0

    private static func sanitizeAutoUpdateIntervalHours(_ value: Double) -> Double {
        guard value.isFinite else { return defaultAutoUpdateIntervalHours }
        guard value > 0 else { return defaultAutoUpdateIntervalHours }
        return min(max(value, minimumAutoUpdateIntervalHours), maximumAutoUpdateIntervalHours)
    }

    private static func sanitizeEpochSecondsToInt64(_ value: Double) -> Int64 {
        guard value.isFinite else { return 0 }
        guard value > 0 else { return 0 }
        if value >= Double(Int64.max) { return Int64.max }
        return Int64(value)
    }
    
    // MARK: - Data Loading
    public func loadData() async {
        isLoading = true
        
        do {
            // Check if migration is needed
            if !(await diskStore.fileExists(at: migrationFlagURL)) {
                logger.info("🔄 Starting migration from UserDefaults/SwiftData...")
                await migrateFromLegacyStorage()
                try await diskStore.writeData(Data(), to: migrationFlagURL)
                logger.info("✅ Migration completed")
            }
            
            // Load protobuf data
            if await diskStore.fileExists(at: dataFileURL) {
                let loaded = try await diskStore.readAppData(from: dataFileURL)

                appData = loaded.appData
                lastSavedData = loaded.rawData
                lastLoadedDataFileModificationDate = loaded.modificationDate
                lastError = nil

                logger.info("✅ Loaded protobuf data (\(loaded.rawData.count) bytes)")

                // Check if terminology sanitization is needed
                if appData.settings.lastTerminologySanitizationVersion < terminologySanitizationVersion {
                    logger.info("🧹 Running terminology sanitization (version \(self.terminologySanitizationVersion))...")
                    await sanitizeStoredTerminology()
                }
            } else {
                logger.info("📝 No existing data file, creating default data")
                await createDefaultData()
            }
            
        } catch {
            logger.error("❌ Failed to load data: \(error)")
            lastError = error
            
            // Try to load backup
            await loadBackup()
        }
        
        isLoading = false
    }
    
    private func loadBackup() async {
        guard await diskStore.fileExists(at: backupFileURL) else {
            logger.info("📝 No backup file available, creating default data")
            await createDefaultData()
            return
        }
        
        do {
            let loaded = try await diskStore.readAppData(from: backupFileURL)

            appData = loaded.appData
            lastSavedData = loaded.rawData
            lastError = nil

            logger.info("✅ Loaded backup data (\(loaded.rawData.count) bytes)")
        } catch {
            logger.error("❌ Failed to load backup: \(error)")
            await createDefaultData()
        }
    }
    
    @MainActor
    public func resetToDefaultData() async {
        logger.info("🔄 Resetting protobuf data to default state")
        pendingSaveTask?.cancel()
        do {
            try await diskStore.removeItemIfExists(at: dataFileURL)
        } catch {
            logger.error("⚠️ Failed to remove data file during reset: \(error.localizedDescription)")
        }
        do {
            try await diskStore.removeItemIfExists(at: backupFileURL)
        } catch {
            logger.error("⚠️ Failed to remove backup file during reset: \(error.localizedDescription)")
        }
        lastSavedData = nil
        lastLoadedDataFileModificationDate = nil
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

        appData = defaultData
        await saveDataImmediately()
        logger.info("✅ Created default data")
    }
    
    // MARK: - Data Saving (debounced)
    private var pendingSaveTask: Task<Void, Never>?
    private let saveDebounceDelay: Duration = .milliseconds(500)
    private var lastSavedData: Data?

    public func saveData() {
        pendingSaveTask?.cancel()
        let delay = saveDebounceDelay
        pendingSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self else { return }
            await self.performSaveData()
        }
    }

    /// Saves data immediately without debounce delay
    /// Use when changes must be persisted before other cross-process actions
    @MainActor
    public func saveDataImmediately() async {
        pendingSaveTask?.cancel()
        await performSaveData()
    }

    private func performSaveData() async {
        let snapshot = appData
        let previous = lastSavedData

        do {
            if let result = try await diskStore.writeAppDataIfChanged(
                appData: snapshot,
                previousData: previous,
                to: dataFileURL
            ) {
                lastSavedData = result.rawData
                lastLoadedDataFileModificationDate = result.modificationDate
                lastError = nil
                logger.info("✅ Saved protobuf data (\(result.rawData.count) bytes)")
                didSaveDataSubject.send()
            }
        } catch {
            logger.error("❌ Failed to save data: \(error)")
            lastError = error
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
        await saveDataImmediately()
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

        migratedData.autoUpdate.intervalHours = Self.sanitizeAutoUpdateIntervalHours(
            groupDefaults.object(forKey: "autoUpdateIntervalHours") as? Double
                ?? Self.defaultAutoUpdateIntervalHours
        )
        migratedData.autoUpdate.lastCheckTime = Self.sanitizeEpochSecondsToInt64(
            groupDefaults.double(forKey: "autoUpdateLastCheckTime")
        )
        migratedData.autoUpdate.lastSuccessfulTime = Self.sanitizeEpochSecondsToInt64(
            groupDefaults.double(forKey: "autoUpdateLastSuccessful")
        )
        migratedData.autoUpdate.nextEligibleTime = Self.sanitizeEpochSecondsToInt64(
            groupDefaults.double(forKey: "autoUpdateNextEligibleTime")
        )
        migratedData.autoUpdate.forceNext = groupDefaults.bool(forKey: "autoUpdateForceNext")
        migratedData.autoUpdate.isRunning = groupDefaults.bool(forKey: "autoUpdateIsRunning")
        migratedData.autoUpdate.runningSinceTimestamp = Self.sanitizeEpochSecondsToInt64(
            groupDefaults.double(forKey: "autoUpdateIsRunningTimestamp")
        )

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
                let inferredIsCustom = inferLegacyCustomStatus(for: filterList)

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
                protoFilterList.isCustom = inferredIsCustom

                appendOrMergeMigratedFilterList(protoFilterList, to: &appData)
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

                appendOrMergeMigratedFilterList(protoFilterList, to: &appData)
            }
        }
    }

    private func appendOrMergeMigratedFilterList(
        _ protoFilterList: Wblock_Data_FilterListData,
        to appData: inout Wblock_Data_AppData
    ) {
        if let existingIndex = appData.filterLists.firstIndex(where: { $0.id == protoFilterList.id }) {
            if protoFilterList.isCustom {
                appData.filterLists[existingIndex].isCustom = true
            }
            return
        }

        appData.filterLists.append(protoFilterList)
    }

    private func inferLegacyCustomStatus(for filterList: LegacyFilterList) -> Bool {
        if filterList.isCustom == true || filterList.category == .custom {
            return true
        }

        if isInlineUserListURL(filterList.url) {
            return true
        }

        let normalizedDescription = filterList.description
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedDescription == "user-added filter list."
            || normalizedDescription == "user-added filter list"
            || normalizedDescription == "user list."
            || normalizedDescription == "user list"
    }

    private func isInlineUserListURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "wblock"
            && url.host?.lowercased() == "userlist"
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
    var isCustom: Bool?
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
