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
    private static let adGuardMobileCurrentURL = "https://filters.adtidy.org/ios/filters/11_optimized.txt"

    // Filter lists that unblock/whitelist content rather than block it. These belong in the
    // dedicated "Allowlists" category so they are not mistaken for blocklists.
    private static let allowlistFilterURLFragments = [
        "whitelist-referral.txt",  // HaGeZi Referral Allowlist
    ]

    private func isAllowlistFilter(_ filter: Wblock_Data_FilterListData) -> Bool {
        Self.allowlistFilterURLFragments.contains { fragment in
            filter.url.contains(fragment)
        }
    }

    private func isAdGuardMobileFilter(_ filter: Wblock_Data_FilterListData) -> Bool {
        filter.name == Self.adGuardMobileFilterName
            || filter.url.contains(Self.adGuardMobileLegacyURLFragment)
            || filter.url == Self.adGuardMobileCurrentURL
    }

    public func updateFilterLists(_ filterLists: [FilterList]) async {
        let incomingIDs = Set(filterLists.map { $0.id.uuidString })
        let snapshot = await latestAppDataSnapshot()
        let deletedIDs = Set(snapshot.filterLists.map(\.id)).subtracting(incomingIDs)
        let protoFilterLists = filterLists.map { filter -> Wblock_Data_FilterListData in
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
            protoFilterList.excludedSites = filter.excludedSites
            if let uniqueRuleCount = filter.uniqueRuleCount {
                protoFilterList.uniqueRuleCount = Int32(uniqueRuleCount)
            }
            return protoFilterList
        }
        _ = await updateDataImmediately(explicitlyDeletedFilterIDs: deletedIDs) { data in
            data.filterLists = protoFilterLists
        }
    }

    // MARK: - Data Migration
    public func migrateLegacyFilterURLs() async {
        var updatedData = appData
        var needsSave = false

        for i in 0..<updatedData.filterLists.count {
            if updatedData.filterLists[i].url.contains(Self.adGuardMobileLegacyURLFragment) {
                updatedData.filterLists[i].url = Self.adGuardMobileCurrentURL
                needsSave = true
            }
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

    /// Moves allowlist (exception/unblocking) filter lists out of blocklist categories such as
    /// "Privacy" and into the dedicated "Allowlists" category so their inverse purpose is clear.
    public func migrateAllowlistsToDedicatedCategory() async {
        var updatedData = appData
        var needsSave = false

        for i in 0..<updatedData.filterLists.count {
            if isAllowlistFilter(updatedData.filterLists[i]) && updatedData.filterLists[i].category != .allowlists {
                updatedData.filterLists[i].category = .allowlists
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
                sourceRuleCount: protoData.hasSourceRuleCount ? Int(protoData.sourceRuleCount) : nil,
                excludedSites: Array(protoData.excludedSites),
                uniqueRuleCount: protoData.hasUniqueRuleCount ? Int(protoData.uniqueRuleCount) : nil
            )
        }
    }
    
    public func removeFilterList(withId id: UUID) async {
        _ = await updateDataImmediately(explicitlyDeletedFilterIDs: [id.uuidString]) { data in
            data.filterLists.removeAll { $0.id == id.uuidString }
        }
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
            // Legacy local records sometimes retained metadata URLs. Never expose
            // those endpoints to the updater after the record is classified local.
            script.updateURL = script.isLocal || protoData.updateURL.isEmpty ? nil : protoData.updateURL
            script.downloadURL = script.isLocal || protoData.downloadURL.isEmpty ? nil : protoData.downloadURL
            script.updatesAutomatically = protoData.hasUpdatesAutomatically ? protoData.updatesAutomatically : true
            script.isUserStyle = protoData.isUserStyle
            script.category = protoData.category == .unspecified ? .scripts : mapProtoToFilterListCategory(protoData.category)
            script.localImportIdentity = protoData.hasLocalImportIdentity
                ? UserScriptImportIdentity.normalized(protoData.localImportIdentity)
                : nil
            return script
        }
    }
    
    public func updateUserScript(_ userScript: UserScript) async {
        await updateUserScripts([userScript])
    }
    
    public func removeUserScript(withId id: UUID) async {
        let changed = await updateDataImmediately(userScriptsAreAuthoritative: true) { data in
            guard let script = data.userScripts.first(where: { $0.id == id.uuidString }),
                  !BuiltInUserScripts.allProtectedURLs.contains(script.url)
            else { return }
            data.userScripts.removeAll { $0.id == id.uuidString }
            data.userScriptDisabledHosts.removeValue(forKey: id.uuidString)
        }
        if changed {
            UserScriptManager.invalidateDocumentStartExecutionCache()
        }
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
        UserScriptManager.invalidateDocumentStartExecutionCache()
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

    public func setFilterDisabledDomains(_ domains: [String]) async {
        let normalized = DisabledSitesNormalizer.normalizedDomains(from: domains)
        await updateDataImmediately { data in
            data.whitelist.filterDisabledSites = normalized
            data.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    public var isNoAutoplayEnabled: Bool {
        appData.whitelist.noAutoplayEnabled
    }

    public var noAutoplayAllowedSites: [String] {
        appData.whitelist.noAutoplayAllowedSites
    }

    @discardableResult
    public func setNoAutoplayEnabled(_ enabled: Bool) async -> Bool {
        return await updateDataImmediately { data in
            data.whitelist.noAutoplayEnabled = enabled
            data.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    @discardableResult
    public func setNoAutoplayAllowedSites(_ sites: [String]) async -> Bool {
        let normalized = DisabledSitesNormalizer.normalizedDomains(from: sites)
        return await updateDataImmediately { data in
            data.whitelist.noAutoplayAllowedSites = normalized
            data.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    @discardableResult
    public func setNoAutoplaySiteAllowed(_ allowed: Bool, onHost host: String) async -> Bool {
        guard let normalizedHost = DisabledSitesNormalizer.normalizedDomain(host) else {
            return false
        }

        return await updateDataImmediately { data in
            var sites = Set(DisabledSitesNormalizer.normalizedDomains(
                from: data.whitelist.noAutoplayAllowedSites
            ))
            if allowed {
                sites.insert(normalizedHost)
            } else {
                sites.remove(normalizedHost)
            }
            data.whitelist.noAutoplayAllowedSites = Array(sites).sorted()
            data.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    public func isNoAutoplayAllowed(onHost host: String) -> Bool {
        guard let normalizedHost = DisabledSitesNormalizer.normalizedDomain(host) else {
            return false
        }
        return DisabledSitesNormalizer.normalizedDomains(from: noAutoplayAllowedSites)
            .contains(normalizedHost)
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
        case .allowlists: return .allowlists
        case .scriptBlocking: return .scriptBlocking
        case .scriptFunctionality: return .scriptFunctionality
        case .scriptAppearance: return .scriptAppearance
        case .scriptOther: return .scriptOther
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
        case .allowlists: return .allowlists
        case .scriptBlocking: return .scriptBlocking
        case .scriptFunctionality: return .scriptFunctionality
        case .scriptAppearance: return .scriptAppearance
        case .scriptOther: return .scriptOther
        }
    }
    
    public func updateUserScripts(
        _ userScripts: [UserScript],
        explicitEnabledStates: [UUID: Bool] = [:]
    ) async {
        let incoming = userScripts.map { userScript -> Wblock_Data_UserScriptData in
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
            protoUserScript.updateURL = protoUserScript.isLocal ? "" : (userScript.updateURL ?? "")
            protoUserScript.downloadURL = protoUserScript.isLocal ? "" : (userScript.downloadURL ?? "")
            protoUserScript.updatesAutomatically = userScript.updatesAutomatically
            protoUserScript.isUserStyle = userScript.isUserStyle
            protoUserScript.category = mapFilterListCategoryToProto(userScript.category)
            if let identity = UserScriptImportIdentity.normalized(userScript.localImportIdentity) {
                protoUserScript.localImportIdentity = identity
            } else {
                protoUserScript.clearLocalImportIdentity()
            }
            protoUserScript.lastUpdated = Int64(Date().timeIntervalSince1970)
            return protoUserScript
        }
        let explicit = Dictionary(uniqueKeysWithValues: explicitEnabledStates.map { ($0.key.uuidString, $0.value) })
        let knownIDs = Set(appData.userScripts.map(\.id))
        let allowedInsertIDs = Set(incoming.map(\.id).filter { !knownIDs.contains($0) })

        _ = await updateDataImmediately { data in
            data.userScripts = UserScriptPersistence.merge(
                persisted: data.userScripts,
                incoming: incoming,
                explicitEnabledStates: explicit,
                allowedInsertIDs: allowedInsertIDs
            )
        }
    }

    /// Replaces the userscript collection intentionally. Ordinary upserts must use
    /// `updateUserScripts` so records written by another process are not deleted.
    public func replaceUserScripts(_ userScripts: [UserScript]) async {
        let incoming = userScripts.map { userScript -> Wblock_Data_UserScriptData in
            var record = Wblock_Data_UserScriptData()
            record.id = userScript.id.uuidString
            record.name = userScript.name
            record.url = userScript.url?.absoluteString ?? ""
            record.isEnabled = userScript.isEnabled
            record.description_p = userScript.description
            record.version = userScript.version
            record.matches = userScript.matches
            record.excludeMatches = userScript.excludeMatches
            record.includes = userScript.includes
            record.excludes = userScript.excludes
            record.runAt = userScript.runAt
            record.injectInto = userScript.injectInto
            record.grant = userScript.grant
            record.isLocal = userScript.isLocal || userScript.url == nil || userScript.url?.isFileURL == true
            record.updateURL = record.isLocal ? "" : (userScript.updateURL ?? "")
            record.downloadURL = record.isLocal ? "" : (userScript.downloadURL ?? "")
            record.updatesAutomatically = userScript.updatesAutomatically
            record.isUserStyle = userScript.isUserStyle
            record.category = mapFilterListCategoryToProto(userScript.category)
            if let identity = UserScriptImportIdentity.normalized(userScript.localImportIdentity) {
                record.localImportIdentity = identity
            } else {
                record.clearLocalImportIdentity()
            }
            record.lastUpdated = Int64(Date().timeIntervalSince1970)
            return record
        }
        _ = await updateDataImmediately(userScriptsAreAuthoritative: true) { data in
            data.userScripts = UserScriptPersistence.replace(with: incoming)
        }
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
        var updatedData = appData
        guard !updatedData.settings.excludedDefaultUserscriptUrls.contains(url) else { return }
        updatedData.settings.excludedDefaultUserscriptUrls.append(url)
        appData = updatedData
        Task { saveData() }
    }

    public func removeExcludedDefaultUserScriptURL(_ url: String) {
        var updatedData = appData
        updatedData.settings.excludedDefaultUserscriptUrls.removeAll { $0 == url }
        appData = updatedData
        Task { saveData() }
    }

    // MARK: - UserScript UI State

    public func getUserScriptShowEnabledOnly() -> Bool {
        return appData.settings.userscriptShowEnabledOnly
    }

    public func setUserScriptShowEnabledOnly(_ value: Bool) {
        var updatedData = appData
        updatedData.settings.userscriptShowEnabledOnly = value
        appData = updatedData
        Task { saveData() }
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
