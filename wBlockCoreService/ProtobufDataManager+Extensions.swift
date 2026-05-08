//
//  ProtobufDataManager+Extensions.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 5/23/25.
//

import Foundation
internal import SwiftProtobuf

// MARK: - Filter List Management
extension ProtobufDataManager {
    private static let adGuardMobileFilterName = "AdGuard Mobile Filter"
    private static let adGuardMobileLegacyURLFragment = "filter_11_Mobile"
    private static let adGuardMobileCurrentURL = "https://filters.adtidy.org/extension/ublock/filters/11.txt"
    private static let legacyFilterURLMigrations: [(fragment: String, url: String)] = [
        ("filter_11_Mobile", "https://filters.adtidy.org/extension/ublock/filters/11.txt"),
        ("filters.adtidy.org/ios/filters/11.txt", "https://filters.adtidy.org/extension/ublock/filters/11.txt"),
        ("filters/224_optimized.txt", "https://filters.adtidy.org/extension/ublock/filters/224.txt"),
        ("easylistchina/master/easylistchina.txt", "https://filters.adtidy.org/extension/ublock/filters/224.txt"),
        ("filters/8_optimized.txt", "https://filters.adtidy.org/extension/ublock/filters/8.txt"),
        ("easylistdutch.txt", "https://filters.adtidy.org/extension/ublock/filters/8.txt"),
        ("filters/16_optimized.txt", "https://filters.adtidy.org/extension/ublock/filters/16.txt"),
        ("liste_fr.txt", "https://filters.adtidy.org/extension/ublock/filters/16.txt"),
        ("filters/6_optimized.txt", "https://easylist.to/easylistgermany/easylistgermany.txt"),
        ("filters/7_optimized.txt", "https://filters.adtidy.org/extension/ublock/filters/7.txt"),
        ("filters/1_optimized.txt", "https://raw.githubusercontent.com/easylist/ruadlist/master/RuAdList-uBO.txt"),
        ("filters/9_optimized.txt", "https://filters.adtidy.org/extension/ublock/filters/9.txt"),
        ("easylistportuguese.txt", "https://filters.adtidy.org/extension/ublock/filters/9.txt"),
        ("filters/13_optimized.txt", "https://filters.adtidy.org/extension/ublock/filters/13.txt"),
        ("filters/23_optimized.txt", "https://filters.adtidy.org/extension/ublock/filters/23.txt"),
        ("filters/227_optimized.txt", "https://cdn.jsdelivr.net/npm/@list-kr/filterslists@latest/dist/filterslist-uBlockOrigin-classic.txt"),
        ("filter/abpvn_adguard.txt", "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn_ublock.txt"),
        ("hufilter-adguard.txt", "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter-ublock.txt"),
        ("NordicFiltersAdGuard.txt", "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianList.txt"),
        ("https://adblock.ee/list.txt", "https://ubo-et.lepik.io/list.txt"),
        ("https://adblock.gardar.net/is.abp.txt", "https://raw.githubusercontent.com/brave/adblock-lists/master/custom/is.txt"),
        ("RandomAdversary/Macedonian-adBlock-Filters/master/Filters", "https://raw.githubusercontent.com/DeepSpaceHarbor/Macedonian-adBlock-Filters/master/Filters"),
        ("easylist-downloads.adblockplus.org/cntblock.txt", "https://raw.githubusercontent.com/easylist/ruadlist/master/cntblock.txt"),
    ]

    private func isAdGuardMobileFilter(_ filter: Wblock_Data_FilterListData) -> Bool {
        filter.name == Self.adGuardMobileFilterName
            || filter.url.contains(Self.adGuardMobileLegacyURLFragment)
            || filter.url == Self.adGuardMobileCurrentURL
    }

    public func updateFilterLists(_ filterLists: [FilterList]) async {
        var updatedData = await latestAppDataSnapshot()
        updatedData.filterLists = filterLists.map { filter in
            var protoFilterList = Wblock_Data_FilterListData()
            protoFilterList.id = filter.id.uuidString
            protoFilterList.name = filter.name
            protoFilterList.url = filter.url.absoluteString
            protoFilterList.category = mapFilterListCategoryToProto(filter.category)
            protoFilterList.isSelected = filter.isSelected
            protoFilterList.description_p = filter.description
            protoFilterList.version = filter.version
            if let sourceRuleCount = filter.sourceRuleCount {
                protoFilterList.sourceRuleCount = Int32(sourceRuleCount)
            }
            protoFilterList.lastUpdated = Int64(Date().timeIntervalSince1970)
            protoFilterList.isCustom = shouldPersistCustomFlag(for: filter)
            return protoFilterList
        }
        appData = updatedData
        saveData()
    }

    // MARK: - Data Migration
    public func migrateLegacyFilterURLs() async {
        var updatedData = appData
        var needsSave = false

        for i in 0..<updatedData.filterLists.count {
            guard let migration = Self.legacyFilterURLMigrations.first(where: {
                updatedData.filterLists[i].url.contains($0.fragment)
            }) else { continue }
            guard updatedData.filterLists[i].url != migration.url else { continue }
            updatedData.filterLists[i].url = migration.url
            needsSave = true
        }

        if needsSave {
            appData = updatedData
            saveData()
        }
    }

    public func migrateMultipurposeToAnnoyances() async {
        var updatedData = appData
        var needsSave = false

        // Migrate filter lists
        for i in 0..<updatedData.filterLists.count {
            if updatedData.filterLists[i].category == .multipurpose {
                // AdGuard Mobile Filter should be in "ads" category, not "annoyances"
                if isAdGuardMobileFilter(updatedData.filterLists[i]) {
                    updatedData.filterLists[i].category = .ads
                } else {
                    updatedData.filterLists[i].category = .annoyances
                }
                needsSave = true
            }
        }

        if needsSave {
            appData = updatedData
            saveData()
        }
    }

    /// Migrates AdGuard Mobile Filter to the correct "ads" category if it's in the wrong category
    public func migrateMobileFilterToAdsCategory() async {
        var updatedData = appData
        var needsSave = false

        for i in 0..<updatedData.filterLists.count {
            if isAdGuardMobileFilter(updatedData.filterLists[i]) && updatedData.filterLists[i].category != .ads {
                updatedData.filterLists[i].category = .ads
                needsSave = true
            }
        }

        if needsSave {
            appData = updatedData
            saveData()
        }
    }

    /// Migrates users from the old combined AdGuard Annoyances Filter (filter 14) to the new split filters (18-22).
    public func migrateAnnoyancesFilterToSplitFilters() async {
        var updatedData = appData
        let oldFilterURL = "14_optimized.txt"

        // Find the old combined Annoyances filter
        guard let oldFilterIndex = updatedData.filterLists.firstIndex(where: { $0.url.contains(oldFilterURL) }) else {
            return // Old filter not found, no migration needed
        }

        let wasSelected = updatedData.filterLists[oldFilterIndex].isSelected

        // Remove the old filter
        updatedData.filterLists.remove(at: oldFilterIndex)

        // Define the new split filters
        let newFilters: [(name: String, url: String, description: String)] = [
            ("AdGuard Cookie Notices", "https://filters.adtidy.org/extension/ublock/filters/18.txt", "Blocks cookie consent notices on web pages."),
            ("AdGuard Popups", "https://filters.adtidy.org/extension/ublock/filters/19.txt", "Blocks promotional pop-ups, newsletter sign-ups, and notification requests."),
            ("AdGuard Mobile App Banners", "https://filters.adtidy.org/extension/ublock/filters/20.txt", "Blocks banners promoting mobile app downloads."),
            ("AdGuard Other Annoyances", "https://filters.adtidy.org/extension/ublock/filters/21.txt", "Blocks miscellaneous irritating elements not covered by other filters."),
            ("AdGuard Widgets", "https://filters.adtidy.org/extension/ublock/filters/22.txt", "Blocks third-party widgets, chat assistants, and support widgets.")
        ]

        // Add the new filters (only if they don't already exist)
        for filter in newFilters {
            let alreadyExists = updatedData.filterLists.contains { $0.url.contains(filter.url) }
            if !alreadyExists {
                var protoFilter = Wblock_Data_FilterListData()
                protoFilter.id = UUID().uuidString
                protoFilter.name = filter.name
                protoFilter.url = filter.url
                protoFilter.category = .annoyances
                protoFilter.isSelected = wasSelected
                protoFilter.description_p = filter.description
                protoFilter.lastUpdated = Int64(Date().timeIntervalSince1970)
                updatedData.filterLists.append(protoFilter)
            }
        }

        appData = updatedData
        saveData()
    }

    // MARK: - Filter Lists
    public func getFilterLists() -> [FilterList] {
        return appData.filterLists.map { protoData in
            let category = mapProtoToFilterListCategory(protoData.category)
            let isCustom = normalizedCustomStatus(for: protoData, category: category)

            return FilterList(
                id: UUID(uuidString: protoData.id) ?? UUID(),
                name: protoData.name,
                url: URL(string: protoData.url) ?? URL(string: "https://example.com")!,
                category: category,
                isCustom: isCustom,
                isSelected: protoData.isSelected,
                description: protoData.description_p,
                version: protoData.version,
                sourceRuleCount: protoData.hasSourceRuleCount ? Int(protoData.sourceRuleCount) : nil
            )
        }
    }
    
    public func updateFilterList(_ filterList: FilterList) async {
        var updatedData = await latestAppDataSnapshot()
        
        if let index = updatedData.filterLists.firstIndex(where: { $0.id == filterList.id.uuidString }) {
            var protoFilterList = updatedData.filterLists[index]
            protoFilterList.name = filterList.name
            protoFilterList.url = filterList.url.absoluteString
            protoFilterList.category = mapFilterListCategoryToProto(filterList.category)
            protoFilterList.isSelected = filterList.isSelected
            protoFilterList.description_p = filterList.description
            protoFilterList.version = filterList.version
            if let sourceRuleCount = filterList.sourceRuleCount {
                protoFilterList.sourceRuleCount = Int32(sourceRuleCount)
            }
            protoFilterList.lastUpdated = Int64(Date().timeIntervalSince1970)
            protoFilterList.isCustom = shouldPersistCustomFlag(for: filterList)
            
            updatedData.filterLists[index] = protoFilterList
        } else {
            // Add new filter list
            var protoFilterList = Wblock_Data_FilterListData()
            protoFilterList.id = filterList.id.uuidString
            protoFilterList.name = filterList.name
            protoFilterList.url = filterList.url.absoluteString
            protoFilterList.category = mapFilterListCategoryToProto(filterList.category)
            protoFilterList.isSelected = filterList.isSelected
            protoFilterList.description_p = filterList.description
            protoFilterList.version = filterList.version
            if let sourceRuleCount = filterList.sourceRuleCount {
                protoFilterList.sourceRuleCount = Int32(sourceRuleCount)
            }
            protoFilterList.lastUpdated = Int64(Date().timeIntervalSince1970)
            protoFilterList.isCustom = shouldPersistCustomFlag(for: filterList)
            
            updatedData.filterLists.append(protoFilterList)
        }
        
        appData = updatedData
        saveData()
    }
    
    public func removeFilterList(withId id: UUID) async {
        var updatedData = await latestAppDataSnapshot()
        updatedData.filterLists.removeAll { $0.id == id.uuidString }
        
        appData = updatedData
        saveData()
    }
    
    public func updateFilterListSelection(_ filterLists: [FilterList]) async {
        var updatedData = await latestAppDataSnapshot()
        
        for filterList in filterLists {
            if let index = updatedData.filterLists.firstIndex(where: { $0.id == filterList.id.uuidString }) {
                updatedData.filterLists[index].isSelected = filterList.isSelected
                updatedData.filterLists[index].lastUpdated = Int64(Date().timeIntervalSince1970)
            }
        }
        
        appData = updatedData
        saveData()
    }
    
    // MARK: - Userscripts
    public func getUserScripts(includePersistedContent: Bool = false) -> [UserScript] {
        return appData.userScripts.map { protoData in
            let rawURLString = protoData.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedURL = rawURLString.isEmpty ? nil : URL(string: rawURLString)

            // Treat userscripts with no URL (or file URLs) as local imports.
            // This also acts as a migration for older stored entries where `isLocal` may be unset
            // (protobuf defaults booleans to `false` when the field wasn't written).
            let inferredIsLocalFromURL = rawURLString.isEmpty || (parsedURL?.isFileURL == true)
            var script = UserScript(
                id: UUID(uuidString: protoData.id) ?? UUID(),
                name: protoData.name,
                url: parsedURL,
                content: includePersistedContent ? protoData.content : ""
            )
            script.isEnabled = protoData.isEnabled
            script.description = protoData.description_p
            script.version = protoData.version
            script.matches = protoData.matches
            script.excludeMatches = protoData.excludeMatches
            script.includes = protoData.includes
            script.excludes = protoData.excludes
            script.runAt = protoData.runAt
            script.injectInto = protoData.injectInto
            script.grant = protoData.grant
            script.isLocal = protoData.isLocal || inferredIsLocalFromURL
            script.updateURL = protoData.updateURL.isEmpty ? nil : protoData.updateURL
            script.downloadURL = protoData.downloadURL.isEmpty ? nil : protoData.downloadURL
            script.updatesAutomatically = protoData.hasUpdatesAutomatically ? protoData.updatesAutomatically : true
            return script
        }
    }
    
    public func updateUserScript(_ userScript: UserScript) async {
        var updatedData = appData
        
        if let index = updatedData.userScripts.firstIndex(where: { $0.id == userScript.id.uuidString }) {
            var protoUserScript = updatedData.userScripts[index]
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
            protoUserScript.isLocal =
                userScript.isLocal || (userScript.url == nil) || (userScript.url?.isFileURL == true)
            protoUserScript.updateURL = userScript.updateURL ?? ""
            protoUserScript.downloadURL = userScript.downloadURL ?? ""
            protoUserScript.updatesAutomatically = userScript.updatesAutomatically
            protoUserScript.content = ""
            protoUserScript.lastUpdated = Int64(Date().timeIntervalSince1970)
            
            updatedData.userScripts[index] = protoUserScript
        } else {
            // Add new userscript
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
            protoUserScript.isLocal =
                userScript.isLocal || (userScript.url == nil) || (userScript.url?.isFileURL == true)
            protoUserScript.updateURL = userScript.updateURL ?? ""
            protoUserScript.downloadURL = userScript.downloadURL ?? ""
            protoUserScript.updatesAutomatically = userScript.updatesAutomatically
            protoUserScript.content = ""
            protoUserScript.lastUpdated = Int64(Date().timeIntervalSince1970)
            
            updatedData.userScripts.append(protoUserScript)
        }
        
        appData = updatedData
        saveData()
    }
    
    public func removeUserScript(withId id: UUID) async {
        var updatedData = appData
        
        // Prevent removal of built-in default userscripts.
        if let script = updatedData.userScripts.first(where: { $0.id == id.uuidString }) {
            if BuiltInUserScripts.allProtectedURLs.contains(script.url) {
                return
            }
        }
        
        updatedData.userScripts.removeAll { $0.id == id.uuidString }
        
        appData = updatedData
        saveData()
    }
    
    // MARK: - Whitelist Management
    public func getWhitelistedDomains() -> [String] {
        return appData.whitelist.disabledSites
    }
    
    private func persistWhitelistedDomains(_ update: @escaping @Sendable (inout [String]) -> Bool) async {
        await updateDataImmediately { data in
            guard update(&data.whitelist.disabledSites) else { return }
            data.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }
    
    public func addWhitelistedDomain(_ domain: String) async {
        await persistWhitelistedDomains { disabledSites in
            guard !disabledSites.contains(domain) else { return false }
            disabledSites.append(domain)
            return true
        }
    }
    
    public func removeWhitelistedDomain(_ domain: String) async {
        await persistWhitelistedDomains { disabledSites in
            disabledSites.removeAll { $0 == domain }
            return true
        }
    }
    
    public func setWhitelistedDomains(_ domains: [String]) async {
        await persistWhitelistedDomains { disabledSites in
            disabledSites = domains
            return true
        }
    }
    
    // MARK: - App Settings
    public func updateAppSettings(
        hasCompletedOnboarding: Bool? = nil,
        selectedBlockingLevel: String? = nil,
        showAdvancedFeatures: Bool? = nil
    ) async {
        var updatedData = appData
        
        if let hasCompletedOnboarding = hasCompletedOnboarding {
            updatedData.settings.hasCompletedOnboarding_p = hasCompletedOnboarding
        }
        
        if let selectedBlockingLevel = selectedBlockingLevel {
            updatedData.settings.selectedBlockingLevel = selectedBlockingLevel
        }
        
        if let showAdvancedFeatures = showAdvancedFeatures {
            updatedData.settings.showAdvancedFeatures = showAdvancedFeatures
        }
        
        appData = updatedData
        saveData()
    }
    
    public var uBlockDefaultCatalogMigrationVersion: Int {
        Int(appData.settings.ublockDefaultCatalogMigrationVersion)
    }

    public var uBlockDefaultCatalogMigrationState: String {
        appData.settings.ublockDefaultCatalogMigrationState
    }

    @MainActor
    public func setUBlockDefaultCatalogMigrationInMemory(version: Int? = nil, state: String? = nil) {
        if let version {
            appData.settings.ublockDefaultCatalogMigrationVersion = Int32(version)
        }
        if let state {
            appData.settings.ublockDefaultCatalogMigrationState = state
        }
    }

    public func updateUBlockDefaultCatalogMigration(version: Int? = nil, state: String? = nil) async {
        await updateDataImmediately { data in
            if let version {
                data.settings.ublockDefaultCatalogMigrationVersion = Int32(version)
            }
            if let state {
                data.settings.ublockDefaultCatalogMigrationState = state
            }
        }
    }

    public var nativeDefaultFiltersAppliedVersion: Int {
        Int(appData.settings.nativeDefaultFiltersAppliedVersion)
    }

    @MainActor
    public func setNativeDefaultFiltersAppliedVersionInMemory(_ version: Int) {
        appData.settings.nativeDefaultFiltersAppliedVersion = Int32(version)
    }

    public func updateNativeDefaultFiltersAppliedVersion(_ version: Int) async {
        await updateDataImmediately { data in
            data.settings.nativeDefaultFiltersAppliedVersion = Int32(version)
        }
    }

    // MARK: - Rule Count Management
    public func updateRuleCounts(
        lastRuleCount: Int? = nil,
        ruleCountsByIdentifier: [String: Int]? = nil,
        identifiersApproachingLimit: Set<String>? = nil
    ) async {
        var updatedData = appData
        
        if let lastRuleCount = lastRuleCount {
            updatedData.ruleCounts.lastRuleCount = Int32(lastRuleCount)
        }
        
        if let ruleCountsByIdentifier = ruleCountsByIdentifier {
            updatedData.ruleCounts.ruleCountsByCategory.removeAll()
            for (identifier, count) in ruleCountsByIdentifier {
                updatedData.ruleCounts.ruleCountsByCategory[identifier] = Int32(count)
            }
        }
        
        if let identifiersApproachingLimit = identifiersApproachingLimit {
            updatedData.ruleCounts.categoriesApproachingLimit = Array(identifiersApproachingLimit)
        }
        
        updatedData.ruleCounts.lastUpdated = Int64(Date().timeIntervalSince1970)
        
        appData = updatedData
        saveData()
    }
    
    // MARK: - Performance Data
    public func updatePerformanceData(
        lastConversionTime: String? = nil,
        lastReloadTime: String? = nil,
        lastFastUpdateTime: String? = nil,
        fastUpdateCount: Int? = nil,
        sourceRulesCount: Int? = nil,
        conversionStageDescription: String? = nil,
        currentFilterName: String? = nil,
        processedFiltersCount: Int? = nil,
        totalFiltersCount: Int? = nil
    ) async {
        var updatedData = appData
        
        if let lastConversionTime = lastConversionTime {
            updatedData.performance.lastConversionTime = lastConversionTime
        }
        
        if let lastReloadTime = lastReloadTime {
            updatedData.performance.lastReloadTime = lastReloadTime
        }
        
        if let lastFastUpdateTime = lastFastUpdateTime {
            updatedData.performance.lastFastUpdateTime = lastFastUpdateTime
        }
        
        if let fastUpdateCount = fastUpdateCount {
            updatedData.performance.fastUpdateCount = Int32(fastUpdateCount)
        }
        
        if let sourceRulesCount = sourceRulesCount {
            updatedData.performance.sourceRulesCount = Int32(sourceRulesCount)
        }
        
        if let conversionStageDescription = conversionStageDescription {
            updatedData.performance.conversionStageDescription = conversionStageDescription
        }
        
        if let currentFilterName = currentFilterName {
            updatedData.performance.currentFilterName = currentFilterName
        }
        
        if let processedFiltersCount = processedFiltersCount {
            updatedData.performance.processedFiltersCount = Int32(processedFiltersCount)
        }
        
        if let totalFiltersCount = totalFiltersCount {
            updatedData.performance.totalFiltersCount = Int32(totalFiltersCount)
        }
        
        appData = updatedData
        saveData()
    }
    
    // MARK: - Helper Methods
    private func normalizedCustomStatus(
        for protoData: Wblock_Data_FilterListData,
        category: FilterListCategory? = nil
    ) -> Bool {
        if protoData.isCustom {
            return true
        }

        let resolvedCategory = category ?? mapProtoToFilterListCategory(protoData.category)
        if resolvedCategory == .custom {
            return true
        }

        if isInlineUserListURL(protoData.url) {
            return true
        }

        return hasLegacyCustomDescription(protoData.description_p)
    }

    private func shouldPersistCustomFlag(for filter: FilterList) -> Bool {
        if filter.isCustom || filter.category == .custom {
            return true
        }

        if isInlineUserListURL(filter.url.absoluteString) {
            return true
        }

        return hasLegacyCustomDescription(filter.description)
    }

    private func isInlineUserListURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme?.lowercased() == "wblock"
            && url.host?.lowercased() == "userlist"
    }

    private func hasLegacyCustomDescription(_ description: String) -> Bool {
        let normalized = description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "user-added filter list."
            || normalized == "user-added filter list"
            || normalized == "user list."
            || normalized == "user list"
    }

    private func mapProtoToFilterListCategory(_ protoCategory: Wblock_Data_FilterListCategory) -> FilterListCategory {
        switch protoCategory {
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
        case .UNRECOGNIZED(_), .unspecified: return .all
        }
    }
    
    private func mapFilterListCategoryToProto(_ category: FilterListCategory) -> Wblock_Data_FilterListCategory {
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
    
    public func getCustomFilterLists() -> [FilterList] {
        return appData.filterLists.compactMap { protoData in
            let category = mapProtoToFilterListCategory(protoData.category)
            let isCustom = normalizedCustomStatus(for: protoData, category: category)
            guard isCustom else { return nil }

            return FilterList(
                id: UUID(uuidString: protoData.id) ?? UUID(),
                name: protoData.name,
                url: URL(string: protoData.url) ?? URL(string: "https://example.com")!,
                category: category,
                isCustom: isCustom,
                isSelected: protoData.isSelected,
                description: protoData.description_p,
                version: protoData.version,
                sourceRuleCount: protoData.hasSourceRuleCount ? Int(protoData.sourceRuleCount) : nil
            )
        }
    }
    
    public func updateCustomFilterLists(_ customFilterLists: [FilterList]) async {
        var updatedData = await latestAppDataSnapshot()
        
        // Remove existing custom filter lists
        updatedData.filterLists.removeAll { protoData in
            normalizedCustomStatus(for: protoData)
        }
        
        // Add updated custom filter lists
        for filterList in customFilterLists {
            var protoFilterList = Wblock_Data_FilterListData()
            protoFilterList.id = filterList.id.uuidString
            protoFilterList.name = filterList.name
            protoFilterList.url = filterList.url.absoluteString
            protoFilterList.category = mapFilterListCategoryToProto(filterList.category)
            protoFilterList.isSelected = filterList.isSelected
            protoFilterList.description_p = filterList.description
            protoFilterList.version = filterList.version
            if let sourceRuleCount = filterList.sourceRuleCount {
                protoFilterList.sourceRuleCount = Int32(sourceRuleCount)
            }
            protoFilterList.lastUpdated = Int64(Date().timeIntervalSince1970)
            protoFilterList.isCustom = shouldPersistCustomFlag(for: filterList)
            
            updatedData.filterLists.append(protoFilterList)
        }
        
        appData = updatedData
        saveData()
    }
    
    public func updateUserScripts(_ userScripts: [UserScript]) async {
        // Refresh from disk to avoid overwriting changes written by other processes (app/extension).
        var updatedData = await latestAppDataSnapshot()
        updatedData.userScripts.removeAll()
        
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
            protoUserScript.isLocal =
                userScript.isLocal || (userScript.url == nil) || (userScript.url?.isFileURL == true)
            protoUserScript.updateURL = userScript.updateURL ?? ""
            protoUserScript.downloadURL = userScript.downloadURL ?? ""
            protoUserScript.updatesAutomatically = userScript.updatesAutomatically
            protoUserScript.content = ""
            protoUserScript.lastUpdated = Int64(Date().timeIntervalSince1970)
            
            updatedData.userScripts.append(protoUserScript)
        }
        
        appData = updatedData
        saveData()
    }

    /// Drops legacy embedded userscript source bodies from protobuf once they have
    /// been migrated to file-backed storage.
    @discardableResult
    public func clearEmbeddedUserScriptContentIfPresent() async -> Bool {
        var updatedData = await latestAppDataSnapshot()
        var didChange = false

        for index in updatedData.userScripts.indices {
            if !updatedData.userScripts[index].content.isEmpty {
                updatedData.userScripts[index].content = ""
                didChange = true
            }
        }

        guard didChange else { return false }

        appData = updatedData
        saveData()
        return true
    }

    // MARK: - Excluded Default UserScript URLs

    public func getExcludedDefaultUserScriptURLs() -> [String] {
        return appData.settings.excludedDefaultUserscriptUrls
    }

    public func addExcludedDefaultUserScriptURL(_ url: String) {
        Task { @MainActor in
            var updatedData = appData
            if !updatedData.settings.excludedDefaultUserscriptUrls.contains(url) {
                updatedData.settings.excludedDefaultUserscriptUrls.append(url)
                appData = updatedData
                saveData()
            }
        }
    }

    public func removeExcludedDefaultUserScriptURL(_ url: String) {
        Task { @MainActor in
            var updatedData = appData
            updatedData.settings.excludedDefaultUserscriptUrls.removeAll { $0 == url }
            appData = updatedData
            saveData()
        }
    }

    // MARK: - UserScript UI State

    public func getUserScriptShowEnabledOnly() -> Bool {
        return appData.settings.userscriptShowEnabledOnly
    }

    public func setUserScriptShowEnabledOnly(_ value: Bool) {
        Task { @MainActor in
            var updatedData = appData
            updatedData.settings.userscriptShowEnabledOnly = value
            appData = updatedData
            saveData()
        }
    }
}

// MARK: - UserScript Extension Helper
private extension UserScript {
    func applying(_ configure: (inout UserScript) -> Void) -> UserScript {
        var copy = self
        configure(&copy)
        return copy
    }
}
