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
            protoFilterList.isCustom = filter.isCustom
            return protoFilterList
        }
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
    }

    // MARK: - Data Migration
    public func migrateMultipurposeToAnnoyances() async {
        var updatedData = appData
        var needsSave = false

        // Migrate filter lists
        for i in 0..<updatedData.filterLists.count {
            if updatedData.filterLists[i].category == .multipurpose {
                // AdGuard Mobile Filter should be in "ads" category, not "annoyances"
                if updatedData.filterLists[i].url.contains("filter_11_Mobile") {
                    updatedData.filterLists[i].category = .ads
                } else {
                    updatedData.filterLists[i].category = .annoyances
                }
                needsSave = true
            }
        }

        if needsSave {
            await MainActor.run {
                appData = updatedData
            }
            await saveData()
        }
    }

    /// Migrates AdGuard Mobile Filter to the correct "ads" category if it's in the wrong category
    public func migrateMobileFilterToAdsCategory() async {
        var updatedData = appData
        var needsSave = false

        for i in 0..<updatedData.filterLists.count {
            if updatedData.filterLists[i].url.contains("filter_11_Mobile") && updatedData.filterLists[i].category != .ads {
                updatedData.filterLists[i].category = .ads
                needsSave = true
            }
        }

        if needsSave {
            await MainActor.run {
                appData = updatedData
            }
            await saveData()
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
            ("AdGuard Cookie Notices", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/18_optimized.txt", "Blocks cookie consent notices on web pages."),
            ("AdGuard Popups", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/19_optimized.txt", "Blocks promotional pop-ups, newsletter sign-ups, and notification requests."),
            ("AdGuard Mobile App Banners", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/20_optimized.txt", "Blocks banners promoting mobile app downloads."),
            ("AdGuard Other Annoyances", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/21_optimized.txt", "Blocks miscellaneous irritating elements not covered by other filters."),
            ("AdGuard Widgets", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/22_optimized.txt", "Blocks third-party widgets, chat assistants, and support widgets.")
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

        await MainActor.run {
            appData = updatedData
        }
        await saveData()
    }

    // MARK: - Filter Lists
    public func getFilterLists() -> [FilterList] {
        return appData.filterLists.map { protoData in
            let category = mapProtoToFilterListCategory(protoData.category)
            let isCustom = protoData.isCustom || category == .custom

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
            protoFilterList.isCustom = filterList.isCustom
            
            updatedData.filterLists.append(protoFilterList)
        }
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
    }
    
    public func removeFilterList(withId id: UUID) async {
        var updatedData = await latestAppDataSnapshot()
        updatedData.filterLists.removeAll { $0.id == id.uuidString }
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
    }
    
    public func updateFilterListSelection(_ filterLists: [FilterList]) async {
        var updatedData = await latestAppDataSnapshot()
        
        for filterList in filterLists {
            if let index = updatedData.filterLists.firstIndex(where: { $0.id == filterList.id.uuidString }) {
                updatedData.filterLists[index].isSelected = filterList.isSelected
                updatedData.filterLists[index].lastUpdated = Int64(Date().timeIntervalSince1970)
            }
        }
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
    }
    
    // MARK: - Userscripts
    public func getUserScripts() -> [UserScript] {
        return appData.userScripts.map { protoData in
            var script = UserScript(
                id: UUID(uuidString: protoData.id) ?? UUID(),
                name: protoData.name,
                url: protoData.url.isEmpty ? nil : URL(string: protoData.url),
                content: protoData.content
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
            script.isLocal = protoData.isLocal
            script.updateURL = protoData.updateURL.isEmpty ? nil : protoData.updateURL
            script.downloadURL = protoData.downloadURL.isEmpty ? nil : protoData.downloadURL
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
            protoUserScript.isLocal = userScript.isLocal
            protoUserScript.updateURL = userScript.updateURL ?? ""
            protoUserScript.downloadURL = userScript.downloadURL ?? ""
            protoUserScript.content = userScript.content
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
            protoUserScript.isLocal = userScript.isLocal
            protoUserScript.updateURL = userScript.updateURL ?? ""
            protoUserScript.downloadURL = userScript.downloadURL ?? ""
            protoUserScript.content = userScript.content
            protoUserScript.lastUpdated = Int64(Date().timeIntervalSince1970)
            
            updatedData.userScripts.append(protoUserScript)
        }
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
    }
    
    public func removeUserScript(withId id: UUID) async {
        var updatedData = appData
        
        // Prevent removal of built-in default userscripts.
        if let script = updatedData.userScripts.first(where: { $0.id == id.uuidString }) {
            let protectedDefaultURLs: Set<String> = [
                "https://raw.githubusercontent.com/Anarios/return-youtube-dislike/main/Extensions/UserScript/Return%20Youtube%20Dislike.user.js",
                "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=userscript%2Fbpc.en.user.js",
                "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/greasemonkey/youtube-classic.user.js",
                "https://userscripts.adtidy.org/release/adguard-extra/1.0/adguard-extra.user.js",
            ]
            if protectedDefaultURLs.contains(script.url) {
                return
            }
        }
        
        updatedData.userScripts.removeAll { $0.id == id.uuidString }
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
    }
    
    // MARK: - Whitelist Management
    public func getWhitelistedDomains() -> [String] {
        return appData.whitelist.disabledSites
    }
    
    public func addWhitelistedDomain(_ domain: String) async {
        var updatedData = appData
        if !updatedData.whitelist.disabledSites.contains(domain) {
            updatedData.whitelist.disabledSites.append(domain)
            updatedData.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)
            
            await MainActor.run {
                appData = updatedData
            }
            await saveData()
        }
    }
    
    public func removeWhitelistedDomain(_ domain: String) async {
        var updatedData = appData
        updatedData.whitelist.disabledSites.removeAll { $0 == domain }
        updatedData.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
    }
    
    public func setWhitelistedDomains(_ domains: [String]) async {
        var updatedData = appData
        updatedData.whitelist.disabledSites = domains
        updatedData.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
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
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
    }
    
    // MARK: - Rule Count Management
    public func updateRuleCounts(
        lastRuleCount: Int? = nil,
        ruleCountsByCategory: [FilterListCategory: Int]? = nil,
        categoriesApproachingLimit: Set<FilterListCategory>? = nil
    ) async {
        var updatedData = appData
        
        if let lastRuleCount = lastRuleCount {
            updatedData.ruleCounts.lastRuleCount = Int32(lastRuleCount)
        }
        
        if let ruleCountsByCategory = ruleCountsByCategory {
            updatedData.ruleCounts.ruleCountsByCategory.removeAll()
            for (category, count) in ruleCountsByCategory {
                updatedData.ruleCounts.ruleCountsByCategory[category.rawValue] = Int32(count)
            }
        }
        
        if let categoriesApproachingLimit = categoriesApproachingLimit {
            updatedData.ruleCounts.categoriesApproachingLimit = categoriesApproachingLimit.map { $0.rawValue }
        }
        
        updatedData.ruleCounts.lastUpdated = Int64(Date().timeIntervalSince1970)
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
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
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
    }
    
    // MARK: - Helper Methods
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
        return appData.filterLists.filter { $0.isCustom }.map { protoData in
            let category = mapProtoToFilterListCategory(protoData.category)

            return FilterList(
                id: UUID(uuidString: protoData.id) ?? UUID(),
                name: protoData.name,
                url: URL(string: protoData.url) ?? URL(string: "https://example.com")!,
                category: category,
                isCustom: true,
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
        updatedData.filterLists.removeAll { $0.isCustom }
        
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
            protoFilterList.isCustom = true
            
            updatedData.filterLists.append(protoFilterList)
        }
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
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
            protoUserScript.isLocal = userScript.isLocal
            protoUserScript.updateURL = userScript.updateURL ?? ""
            protoUserScript.downloadURL = userScript.downloadURL ?? ""
            protoUserScript.content = userScript.content
            protoUserScript.lastUpdated = Int64(Date().timeIntervalSince1970)
            
            updatedData.userScripts.append(protoUserScript)
        }
        
        await MainActor.run {
            appData = updatedData
        }
        await saveData()
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
                await saveData()
            }
        }
    }

    public func removeExcludedDefaultUserScriptURL(_ url: String) {
        Task { @MainActor in
            var updatedData = appData
            updatedData.settings.excludedDefaultUserscriptUrls.removeAll { $0 == url }
            appData = updatedData
            await saveData()
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
            await saveData()
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
