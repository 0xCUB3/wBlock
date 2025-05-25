//
//  AppFilterManager.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
import Combine
import wBlockCoreService

#if os(macOS)
let APP_CONTENT_BLOCKER_ID = "skula.wBlock.wBlock-Filters"
#else
let APP_CONTENT_BLOCKER_ID = "skula.wBlock.wBlock-Filters-iOS"
#endif

@MainActor
class AppFilterManager: ObservableObject {
    @Published var filterLists: [FilterList] = []
    @Published var isLoading: Bool = false
    @Published var statusDescription: String = "Ready."
    @Published var lastConversionTime: String = "N/A"
    @Published var lastReloadTime: String = "N/A"
    @Published var lastRuleCount: Int = 0
    @Published var hasError: Bool = false
    @Published var progress: Float = 0
    @Published var missingFilters: [FilterList] = []
    @Published var availableUpdates: [FilterList] = []
    @Published var showingUpdatePopup = false
    @Published var showingNoUpdatesAlert = false
    @Published var hasUnappliedChanges = false
    @Published var showMissingFiltersSheet = false
    @Published var showingApplyProgressSheet = false
    @Published var showingDownloadCompleteAlert = false
    @Published var downloadCompleteMessage = ""
    @Published var showingFilterLimitAlert = false
    
    // Detailed progress tracking
    @Published var sourceRulesCount: Int = 0
    @Published var conversionStageDescription: String = ""
    @Published var currentFilterName: String = ""
    @Published var processedFiltersCount: Int = 0
    @Published var totalFiltersCount: Int = 0
    @Published var isInConversionPhase: Bool = false
    @Published var isInSavingPhase: Bool = false
    @Published var isInEnginePhase: Bool = false
    @Published var isInReloadPhase: Bool = false
    @Published var currentPlatform: Platform

    // Dependencies
    private let loader: FilterListLoader
    private let updater: FilterListUpdater
    private let logManager: ConcurrentLogManager

    var customFilterLists: [FilterList] = []
    
    // Save filter lists
    func saveFilterLists() {
        loader.saveFilterLists(filterLists) // This will also save the sourceRuleCount if present
    }

    init() {
        self.logManager = ConcurrentLogManager.shared
        self.loader = FilterListLoader(logManager: self.logManager)
        self.updater = FilterListUpdater(loader: self.loader, logManager: self.logManager)
        
        #if os(macOS)
        self.currentPlatform = .macOS
        #else
        self.currentPlatform = .iOS
        #endif
        
        setup()
    }

    private func setup() {
        updater.filterListManager = self
        loader.checkAndCreateGroupFolder()
        filterLists = loader.loadFilterLists()
        customFilterLists = loader.loadCustomFilterLists()
        loader.loadSelectedState(for: &filterLists)
        checkAndEnableFilters() // This will eventually call applyChanges which might use rule counts
        statusDescription = "Initialized with \(filterLists.count) filter list(s)."
        // Call the new function to update versions and counts
        Task { await updateVersionsAndCounts() }
    }
    
    func updateVersionsAndCounts() async {
        let initiallyLoadedLists = self.filterLists
        let updatedListsFromServer = await updater.updateMissingVersionsAndCounts(filterLists: initiallyLoadedLists)
        
        var newFilterLists = self.filterLists
        for updatedListFromServer in updatedListsFromServer {
            if let index = newFilterLists.firstIndex(where: { $0.id == updatedListFromServer.id }) {
                let currentSelectionState = newFilterLists[index].isSelected
                newFilterLists[index] = updatedListFromServer
                newFilterLists[index].isSelected = currentSelectionState
            }
        }
        self.filterLists = newFilterLists
        saveFilterLists()
    }

    func doesFilterFileExist(_ filter: FilterList) -> Bool {
        return loader.filterFileExists(filter)
    }

    // MARK: - Core functionality
    func checkAndEnableFilters() {
        missingFilters.removeAll()
        for filter in filterLists where filter.isSelected {
            if !loader.filterFileExists(filter) {
                missingFilters.append(filter)
            }
        }
        if !missingFilters.isEmpty {
            showMissingFiltersSheet = true
        } else {
            showingApplyProgressSheet = true
            Task {
                await applyChanges()
            }
        }
    }

    func toggleFilterListSelection(id: UUID) {
        if let index = filterLists.firstIndex(where: { $0.id == id }) {
            filterLists[index].isSelected.toggle()
            loader.saveSelectedState(for: filterLists)
            hasUnappliedChanges = true
        }
    }

    func filterLists(for category: FilterListCategory) -> [FilterList] {
        category == .all ? filterLists : filterLists.filter { $0.category == category }
    }

    func resetToDefaultLists() {
        // Reset all filters to unselected first
        for index in filterLists.indices {
            filterLists[index].isSelected = false
        }

        // Enable only the recommended filters
        let recommendedFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "AdGuard Annoyances Filter",
            "EasyPrivacy",
            "Online Malicious URL Blocklist",
            "d3Host List by d3ward",
            "Anti-Adblock List"
        ]

        for index in filterLists.indices {
            if recommendedFilters.contains(filterLists[index].name) {
                filterLists[index].isSelected = true
            }
        }

        loader.saveSelectedState(for: filterLists)
        hasUnappliedChanges = true
    }

    // MARK: - Delegated methods

    func applyChanges() async {
        isLoading = true
        hasError = false
        progress = 0
        statusDescription = "Preparing to apply selected filters..."
        await ConcurrentLogManager.shared.log("ApplyChanges: Started on \(currentPlatform == .macOS ? "macOS" : "iOS").")

        sourceRulesCount = 0
        conversionStageDescription = ""
        currentFilterName = ""
        processedFiltersCount = 0
        totalFiltersCount = 0
        isInConversionPhase = false
        isInSavingPhase = false
        isInEnginePhase = false // Keep for global advanced rules if still used
        isInReloadPhase = false

        let allSelectedFilters = filterLists.filter { $0.isSelected }

        if allSelectedFilters.isEmpty {
            statusDescription = "No filter lists selected. Clearing rules from all extensions."
            await ConcurrentLogManager.shared.log("ApplyChanges: No filters selected. Clearing all target extensions.")
            // Clear rules for all relevant extensions
            let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
            for targetInfo in platformTargets {
                _ = ContentBlockerService.convertFilter(rules: "[]", groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: targetInfo.rulesFilename)
                _ = ContentBlockerService.reloadContentBlocker(withIdentifier: targetInfo.bundleIdentifier)
            }
            isLoading = false; showingApplyProgressSheet = false; hasUnappliedChanges = false; lastRuleCount = 0
            return
        }
        
        // Group filters by their target ContentBlockerTargetInfo
        var rulesByTargetInfo: [ContentBlockerTargetInfo: String] = [:]
        var sourceRulesByTargetInfo: [ContentBlockerTargetInfo: Int] = [:]

        for filter in allSelectedFilters {
            guard let targetInfo = ContentBlockerTargetManager.shared.targetInfo(forCategory: filter.category, platform: currentPlatform) else {
                await ConcurrentLogManager.shared.log("Warning: No target extension found for category \(filter.category.rawValue) on \(currentPlatform == .macOS ? "macOS" : "iOS"). Skipping filter: \(filter.name)")
                continue
            }

            guard let containerURL = loader.getSharedContainerURL() else {
                statusDescription = "Error: Unable to access shared container for \(filter.name)"
                hasError = true; isLoading = false; showingApplyProgressSheet = false; return
            }
            let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
            var contentToAppend = ""
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    contentToAppend = try String(contentsOf: fileURL, encoding: .utf8) + "\n"
                } catch {
                    await ConcurrentLogManager.shared.log("Error reading \(filter.name): \(error)")
                }
            } else {
                await ConcurrentLogManager.shared.log("Warning: Filter file for \(filter.name) not found locally.")
            }
            
            rulesByTargetInfo[targetInfo, default: ""] += contentToAppend
            sourceRulesByTargetInfo[targetInfo, default: 0] += filter.sourceRuleCount ?? contentToAppend.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.hasPrefix("[") }.count
        }
        
        sourceRulesCount = sourceRulesByTargetInfo.values.reduce(0, +) // Sum of all source rules for UI
        totalFiltersCount = rulesByTargetInfo.keys.count // Number of unique extensions to process

        if totalFiltersCount == 0 {
            statusDescription = "No matching extensions for selected filters."
            isLoading = false; showingApplyProgressSheet = false; return
        }
        
        var overallSafariRulesApplied = 0
        let overallConversionStartTime = Date()
        processedFiltersCount = 0 // Use this to track processed targets for progress

        isInConversionPhase = true
        for (targetInfo, rulesString) in rulesByTargetInfo {
            processedFiltersCount += 1
            progress = Float(processedFiltersCount) / Float(totalFiltersCount) * 0.7 // Up to 70% for conversion

            currentFilterName = targetInfo.primaryCategory.rawValue // More user-friendly
            conversionStageDescription = "Converting for \(targetInfo.primaryCategory.rawValue)..."
            await ConcurrentLogManager.shared.log("ApplyChanges: Converting rules for \(targetInfo.bundleIdentifier) (\(targetInfo.rulesFilename)). Source lines: \(rulesString.components(separatedBy: .newlines).count)")
            
            try? await Task.sleep(nanoseconds: 50_000_000) // UI update chance

            let ruleCountForThisTarget = ContentBlockerService.convertFilter(
                rules: rulesString.isEmpty ? "[]" : rulesString, // Ensure "[]" for empty
                groupIdentifier: GroupIdentifier.shared.value,
                targetRulesFilename: targetInfo.rulesFilename
            )
            overallSafariRulesApplied += ruleCountForThisTarget
            await ConcurrentLogManager.shared.log("ApplyChanges: Converted \(ruleCountForThisTarget) Safari rules for \(targetInfo.bundleIdentifier).")

            let ruleLimit = currentPlatform == .iOS ? 50000 : 150000
            if ruleCountForThisTarget > ruleLimit {
                await ConcurrentLogManager.shared.log("CRITICAL: Rule limit \(ruleLimit) exceeded for \(targetInfo.bundleIdentifier) with \(ruleCountForThisTarget) rules.")
                statusDescription = "Rule limit exceeded for \(targetInfo.primaryCategory.rawValue) extension (\(ruleCountForThisTarget)/\(ruleLimit))."
                hasError = true; isLoading = false;
                await MainActor.run { // Ensure UI updates on main thread
                    self.showingApplyProgressSheet = false
                    self.showingFilterLimitAlert = true
                }
                return
            }
        }
        isInConversionPhase = false
        lastRuleCount = overallSafariRulesApplied
        lastConversionTime = String(format: "%.2fs", Date().timeIntervalSince(overallConversionStartTime))
        progress = 0.7
        await ConcurrentLogManager.shared.log("ApplyChanges: All conversions finished. Total Safari rules: \(overallSafariRulesApplied). Time: \(lastConversionTime)")

        // Reloading phase
        conversionStageDescription = "Reloading Safari extensions..."
        isInReloadPhase = true
        let overallReloadStartTime = Date()
        var allReloadsSuccessful = true
        
        processedFiltersCount = 0
        for targetInfo in rulesByTargetInfo.keys { // Reload only affected targets
            processedFiltersCount += 1
            progress = 0.7 + (Float(processedFiltersCount) / Float(totalFiltersCount) * 0.3) // 70% to 100%
            currentFilterName = targetInfo.primaryCategory.rawValue
            await ConcurrentLogManager.shared.log("ApplyChanges: Reloading \(targetInfo.bundleIdentifier)...")

            let reloadResult = ContentBlockerService.reloadContentBlocker(withIdentifier: targetInfo.bundleIdentifier)
            if case .failure(let error) = reloadResult {
                allReloadsSuccessful = false
                await ConcurrentLogManager.shared.log("ApplyChanges: FAILED to reload \(targetInfo.bundleIdentifier): \(error.localizedDescription)")
                if !hasError { statusDescription = "Failed to reload \(targetInfo.primaryCategory.rawValue) extension." }
                hasError = true // Mark that at least one error occurred
            } else {
                 await ConcurrentLogManager.shared.log("ApplyChanges: Successfully reloaded \(targetInfo.bundleIdentifier).")
            }
            try? await Task.sleep(nanoseconds: 20_000_000) // Small delay
        }
        
        // Reload any other extensions that might have had their rules implicitly cleared (if no selected filters mapped to them)
        let allPlatformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        let affectedTargetBundleIDs = Set(rulesByTargetInfo.keys.map { $0.bundleIdentifier })
        for targetInfo in allPlatformTargets {
            if !affectedTargetBundleIDs.contains(targetInfo.bundleIdentifier) {
                 await ConcurrentLogManager.shared.log("ApplyChanges: Ensuring \(targetInfo.bundleIdentifier) (no selected rules) is also reloaded to apply empty list.")
                 _ = ContentBlockerService.convertFilter(rules: "[]", groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: targetInfo.rulesFilename) // Ensure it has an empty list
                 _ = ContentBlockerService.reloadContentBlocker(withIdentifier: targetInfo.bundleIdentifier)
            }
        }

        isInReloadPhase = false
        lastReloadTime = String(format: "%.2fs", Date().timeIntervalSince(overallReloadStartTime))
        progress = 1.0
        await ConcurrentLogManager.shared.log("ApplyChanges: All reloads finished. Time: \(lastReloadTime). All successful: \(allReloadsSuccessful)")

        if allReloadsSuccessful && !hasError {
            conversionStageDescription = "Process completed successfully!"
            statusDescription = "Applied rules to \(rulesByTargetInfo.keys.count) blocker(s). Total: \(overallSafariRulesApplied) Safari rules."
            hasUnappliedChanges = false
        } else if !hasError { // Implies reload issue was the only problem
            statusDescription = "Converted rules, but one or more extensions failed to reload."
        } // If hasError was already true, statusDescription would reflect the earlier error.

        isLoading = false
        // Keep showingApplyProgressSheet = true until user dismisses it if it was successful or had errors.
        // Or: showingApplyProgressSheet = false // if you want it to auto-dismiss on error

        saveFilterLists() // Save any state like sourceRuleCount if updated
        await ConcurrentLogManager.shared.log("ApplyChanges: Finished. Final Status: \(statusDescription)")
    }

    func updateMissingFilters() async { // This is for when the "Missing Filters" sheet is shown
        isLoading = true
        progress = 0

        let totalSteps = Float(missingFilters.count)
        var completedSteps: Float = 0
        var tempMissingFilters = self.missingFilters // Work on a temporary copy

        for filter in tempMissingFilters {
            let success = await updater.fetchAndProcessFilter(filter) // This now updates sourceRuleCount
            if success {
                // If successful, the filterListManager?.filterLists is updated by fetchAndProcessFilter
                // We should remove it from our local 'missingFilters' tracking state
                await MainActor.run {
                    self.missingFilters.removeAll { $0.id == filter.id }
                }
            }
            completedSteps += 1
            await MainActor.run {
                self.progress = completedSteps / totalSteps
            }
        }
        
        saveFilterLists() // Save lists as fetchAndProcessFilter might have updated counts/versions

        // Show apply progress sheet for the subsequent apply operation
        await MainActor.run {
            showingApplyProgressSheet = true
        }
        
        await applyChanges()
        isLoading = false
        progress = 0 // Reset progress after completion
    }

    func checkForUpdates() async {
        isLoading = true
        statusDescription = "Checking for updates..."
        // Ensure counts are up-to-date before checking for updates
        await updateVersionsAndCounts()
        
        let enabledFilters = filterLists.filter { $0.isSelected }
        let updatedFilters = await updater.checkForUpdates(filterLists: enabledFilters)

        availableUpdates = updatedFilters

        if !availableUpdates.isEmpty {
            showingUpdatePopup = true
            statusDescription = "Found \(availableUpdates.count) update(s) available."
        } else {
            showingNoUpdatesAlert = true
            statusDescription = "No updates available."
            Task { await ConcurrentLogManager.shared.log("No updates available.") }
        }
        
        isLoading = false
    }

    func autoUpdateFilters() async -> [FilterList] {
        isLoading = true
        progress = 0
        
        // Ensure counts and versions are fresh before auto-update logic
        await updateVersionsAndCounts()

        let updatedFilters = await updater.autoUpdateFilters(
            filterLists: filterLists.filter { $0.isSelected },
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )
        
        saveFilterLists() // Save lists as autoUpdateFilters calls fetchAndProcessFilter

        if !updatedFilters.isEmpty {
            await applyChanges()
        }

        isLoading = false
        progress = 0 // Reset progress after completion
        return updatedFilters
    }

    func updateSelectedFilters(_ selectedFilters: [FilterList]) async { // From UpdatePopupView
        isLoading = true
        progress = 0

        let updatedSuccessfullyFilters = await updater.updateSelectedFilters(
            selectedFilters,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )
        
        await MainActor.run {
            for filter in updatedSuccessfullyFilters {
                 self.availableUpdates.removeAll { $0.id == filter.id }
            }
        }
        
        saveFilterLists()

        await applyChanges()
        isLoading = false
        progress = 0
    }

    func downloadSelectedFilters(_ selectedFilters: [FilterList]) async {
        isLoading = true
        progress = 0
        statusDescription = "Downloading filter updates..."

        let successfullyUpdatedFilters = await updater.updateSelectedFilters(
            selectedFilters,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )
        
        saveFilterLists()
        
        await MainActor.run {
            for filter in successfullyUpdatedFilters {
                self.availableUpdates.removeAll { $0.id == filter.id }
            }
        }

        isLoading = false
        progress = 0
        
        await MainActor.run {
            showingUpdatePopup = false
            downloadCompleteMessage = "Downloaded \(successfullyUpdatedFilters.count) filter update(s). Would you like to apply them now?"
            showingDownloadCompleteAlert = true
        }
    }
    
    func downloadMissingFilters() async {
        isLoading = true
        progress = 0
        statusDescription = "Downloading missing filters..."

        let totalSteps = Float(missingFilters.count)
        var completedSteps: Float = 0
        var downloadedCount = 0
        
        var tempMissingFilters = self.missingFilters

        for filter in tempMissingFilters {
            let success = await updater.fetchAndProcessFilter(filter)
            if success {
                await MainActor.run {
                    self.missingFilters.removeAll { $0.id == filter.id }
                }
                downloadedCount += 1
            }
            completedSteps += 1
            await MainActor.run {
                self.progress = completedSteps / totalSteps
            }
        }
        
        saveFilterLists()

        isLoading = false
        progress = 0
        
        await MainActor.run {
            showMissingFiltersSheet = false
            downloadCompleteMessage = "Downloaded \(downloadedCount) missing filter(s). Would you like to apply them now?"
            showingDownloadCompleteAlert = true
        }
    }
    
    func applyDownloadedChanges() async {
        await MainActor.run {
            showingApplyProgressSheet = true
        }
        await applyChanges()
    }

    // MARK: - List Management
    func addFilterList(name: String, urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusDescription = "Invalid URL provided: \(urlString)"
            hasError = true
            Task { await ConcurrentLogManager.shared.log("Error: Invalid URL provided for new filter list - \(urlString)") }
            return
        }
        
        if filterLists.contains(where: { $0.url == url }) {
            statusDescription = "Filter list with this URL already exists: \(url.absoluteString)"
            hasError = true
            Task { await ConcurrentLogManager.shared.log("Error: Filter list with URL \(url.absoluteString) already exists.") }
            return
        }
        
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newFilter = FilterList(id: UUID(),
                                   name: newName.isEmpty ? (url.host ?? "Custom Filter") : newName,
                                   url: url,
                                   category: FilterListCategory.custom,
                                   isSelected: true,
                                   description: "User-added filter list.",
                                   sourceRuleCount: nil)
        addCustomFilterList(newFilter)
    }
    
    func removeFilterList(at offsets: IndexSet) {
        let removedNames = offsets.map { filterLists[$0].name }.joined(separator: ", ")
        filterLists.remove(atOffsets: offsets)
        loader.saveFilterLists(filterLists)
        statusDescription = "Removed filter(s): \(removedNames)"
        hasError = false
        Task { await ConcurrentLogManager.shared.log("Removed filter(s) at offsets: \(removedNames)") }
    }
    
    func removeFilterList(_ listToRemove: FilterList) {
        removeCustomFilterList(listToRemove)
    }

    func toggleFilter(list: FilterList) {
        toggleFilterListSelection(id: list.id)
    }

    func addCustomFilterList(_ filter: FilterList) {
        if !customFilterLists.contains(where: { $0.url == filter.url }) {
            var newFilterToAdd = filter

            customFilterLists.append(newFilterToAdd)
            loader.saveCustomFilterLists(customFilterLists)

            filterLists.append(newFilterToAdd)
            
            Task {
                await ConcurrentLogManager.shared.log("Added custom filter: \(newFilterToAdd.name)")
            }

            Task {
                let success = await updater.fetchAndProcessFilter(newFilterToAdd)
                if success {
                    await ConcurrentLogManager.shared.log("Successfully downloaded custom filter: \(newFilterToAdd.name)")
                    hasUnappliedChanges = true
                    saveFilterLists()
                } else {
                    await ConcurrentLogManager.shared.log("Failed to download custom filter: \(newFilterToAdd.name)")
                    await MainActor.run {
                        removeCustomFilterList(newFilterToAdd)
                    }
                }
            }
        } else {
            Task {
                await ConcurrentLogManager.shared.log("Custom filter with URL \(filter.url) already exists")
            }
        }
    }

    func removeCustomFilterList(_ filter: FilterList) {
        customFilterLists.removeAll { $0.id == filter.id }
        loader.saveCustomFilterLists(customFilterLists)

        filterLists.removeAll { $0.id == filter.id }
        loader.saveFilterLists(filterLists)

        if let containerURL = loader.getSharedContainerURL() {
            let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
            try? FileManager.default.removeItem(at: fileURL)
        }
        Task {
            await ConcurrentLogManager.shared.log("Removed custom filter: \(filter.name)")
        }
        hasUnappliedChanges = true
    }

    func revertToRecommendedFilters() async {
        for index in filterLists.indices {
            filterLists[index].isSelected = false
        }


        #if os(iOS)
        let essentialFilters = [
            "AdGuard Base Filter"
        ]
        #else
        let essentialFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "EasyPrivacy",
            "Online Malicious URL Blocklist"
        ]
        #endif

        for index in filterLists.indices {
            filterLists[index].isSelected = essentialFilters.contains(filterLists[index].name)
        }

        loader.saveSelectedState(for: filterLists)
        hasUnappliedChanges = false
        statusDescription = "Reverted to essential filters to stay under Safari's 150k rule limit."
        
        await MainActor.run {
            showingApplyProgressSheet = true
        }
        await applyChanges()
    }
}
