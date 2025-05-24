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

    // Dependencies
    private let loader: FilterListLoader // Keep this private
    private let updater: FilterListUpdater
    private let logManager: ConcurrentLogManager

    var customFilterLists: [FilterList] = []
    
    // Save filter lists
    func saveFilterLists() {
        loader.saveFilterLists(filterLists) // This will also save the sourceRuleCount if present
    }

    init() {
        self.logManager = ConcurrentLogManager.shared // Use the existing shared instance
        self.loader = FilterListLoader(logManager: self.logManager) // Pass it here
        self.updater = FilterListUpdater(loader: self.loader, logManager: self.logManager) // And here
        
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
        
        // Reset detailed tracking
        sourceRulesCount = 0
        conversionStageDescription = ""
        currentFilterName = ""
        processedFiltersCount = 0
        isInConversionPhase = false
        isInSavingPhase = false
        isInEnginePhase = false
        isInReloadPhase = false

        let selectedFilters = filterLists.filter { $0.isSelected }
        totalFiltersCount = selectedFilters.count
        
        if selectedFilters.isEmpty {
            statusDescription = "No filter lists selected to apply."
            isLoading = false
            return
        }

        // Phase 1: Reading filter files (0-60% progress)
        conversionStageDescription = "Reading filter files..."
        var concatenatedRules = ""
        var totalRulesRead = 0
        
        for (index, filter) in selectedFilters.enumerated() {
            currentFilterName = filter.name
            processedFiltersCount = index
            progress = Float(index) / Float(selectedFilters.count) * 0.6
            
            guard let containerURL = loader.getSharedContainerURL() else {
                statusDescription = "Error: Unable to access shared container"
                hasError = true
                isLoading = false
                return
            }
            
            let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    // Use the stored sourceRuleCount if available, otherwise count on the fly
                    let ruleCount = filter.sourceRuleCount ?? content.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.hasPrefix("[") }.count
                    totalRulesRead += ruleCount
                    concatenatedRules += content + "\n"
                    
                    conversionStageDescription = "Read \(ruleCount) rules from \(filter.name)"
                    try? await Task.sleep(nanoseconds: 50_000_000) // Small delay for UI update
                } catch {
                    Task { await ConcurrentLogManager.shared.log("Error reading \(filter.name): \(error)") }
                }
            }
        }
        
        sourceRulesCount = totalRulesRead
        processedFiltersCount = selectedFilters.count
        progress = 0.6
        
        // Phase 2: Converting rules (60-75% progress)
        isInConversionPhase = true
        conversionStageDescription = "Converting \(sourceRulesCount) rules to Safari format..."
        let conversionStartTime = Date()
        
        progress = 0.65
        try? await Task.sleep(nanoseconds: 200_000_000) // Give UI more time to update before blocking call
        
        let ruleCount = ContentBlockerService.convertFilter(
            rules: concatenatedRules,
            groupIdentifier: GroupIdentifier.shared.value
        )
        
        // Check if we exceed Safari's 150k rule limit
        if ruleCount > 150000 {
            isLoading = false
            progress = 0
            await MainActor.run {
                showingApplyProgressSheet = false
                showingFilterLimitAlert = true
            }
            return
        }
        
        let conversionEndTime = Date()
        let conversionDuration = String(format: "%.2fs", conversionEndTime.timeIntervalSince(conversionStartTime))
        lastConversionTime = conversionDuration
        lastRuleCount = ruleCount
        
        isInConversionPhase = false
        progress = 0.75
        
        // Phase 3: Saving and building engine (75-90% progress)
        isInSavingPhase = true
        conversionStageDescription = "Saving content blocking rules..."
        progress = 0.8
        try? await Task.sleep(nanoseconds: 150_000_000) // Give UI time to update
        
        isInSavingPhase = false
        isInEnginePhase = true
        conversionStageDescription = "Building and saving filtering engine..."
        progress = 0.85
        try? await Task.sleep(nanoseconds: 150_000_000) // Give UI time to update
        
        isInEnginePhase = false
        progress = 0.9

        // Phase 4: Reloading Safari (90-100% progress)
        isInReloadPhase = true
        conversionStageDescription = "Reloading Safari content blocker..."
        let reloadStartTime = Date()
        
        print("Blocker ID: \(APP_CONTENT_BLOCKER_ID)")
        let result = ContentBlockerService.reloadContentBlocker(withIdentifier: APP_CONTENT_BLOCKER_ID)
        
        let reloadEndTime = Date()
        let reloadDuration = String(format: "%.2fs", reloadEndTime.timeIntervalSince(reloadStartTime))
        lastReloadTime = reloadDuration
        
        isInReloadPhase = false
        progress = 1.0

        switch result {
        case .success:
            conversionStageDescription = "Conversion completed successfully"
            statusDescription = "Successfully loaded \(ruleCount) rules from \(selectedFilters.count) list(s) to Safari."
            hasError = false
            hasUnappliedChanges = false
            Task { await ConcurrentLogManager.shared.log("ApplyChanges: SUCCESS - Loaded \(ruleCount) rules from \(selectedFilters.count) lists.") }
        case .failure(let error):
            conversionStageDescription = "Failed to reload Safari extension"
            statusDescription = "Failed to reload extension: \(error.localizedDescription)"
            hasError = true
            Task { await ConcurrentLogManager.shared.log("ApplyChanges: FAILURE - Failed to reload extension: \(error.localizedDescription)") }
        }

        isLoading = false
        // Don't reset progress here - keep it at 100% to show completion
        saveFilterLists() // Save any potential updates to sourceRuleCount from on-the-fly counting
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
                                   category: .custom,
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

        let essentialFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "EasyPrivacy",
            "Online Malicious URL Blocklist"
        ]

        for index in filterLists.indices {
            if essentialFilters.contains(filterLists[index].name) {
                filterLists[index].isSelected = true
            }
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
