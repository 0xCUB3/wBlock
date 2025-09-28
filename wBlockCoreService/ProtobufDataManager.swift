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
    
    // MARK: - Migration from Legacy Storage
    private func migrateFromLegacyStorage() async {
        logger.info("🔄 Migrating from UserDefaults and SwiftData...")
        
        let groupDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
        var migratedData = Wblock_Data_AppData()
        
        // Migrate app settings
        migratedData.settings.hasCompletedOnboarding_p = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        migratedData.settings.selectedBlockingLevel = UserDefaults.standard.string(forKey: "selectedBlockingLevel") ?? "recommended"
        
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
