import SwiftUI
import wBlockCoreService

extension AppFilterManager {
    func updateVersionsAndCounts() async {
        let initiallyLoadedLists = self.filterLists
        let updater = self.filterUpdater
        let updatedListsFromServer = await Task.detached(priority: .utility) {
            await updater.updateMissingVersionsAndCounts(filterLists: initiallyLoadedLists)
        }.value

        var newFilterLists = self.filterLists
        for updatedListFromServer in updatedListsFromServer {
            if let index = newFilterLists.firstIndex(where: { $0.id == updatedListFromServer.id }) {
                let currentSelectionState = newFilterLists[index].isSelected
                newFilterLists[index] = updatedListFromServer
                newFilterLists[index].isSelected = currentSelectionState
            }
        }
        self.filterLists = newFilterLists
        saveFilterListsCoalesced()
    }

    /// Updates version and count for a single filter instead of all filters
    func updateSingleFilterVersionAndCount(_ filter: FilterList) async {
        let updater = self.filterUpdater
        let updatedFilters = await Task.detached(priority: .utility) {
            await updater.updateMissingVersionsAndCounts(filterLists: [filter])
        }.value

        guard let updatedFilter = updatedFilters.first,
            let index = self.filterListIndexByID[filter.id]
        else {
            return
        }

        var newFilterLists = self.filterLists
        let currentSelectionState = newFilterLists[index].isSelected
        newFilterLists[index] = updatedFilter
        newFilterLists[index].isSelected = currentSelectionState
        self.filterLists = newFilterLists
        saveFilterListsCoalesced()
    }

    func doesFilterFileExist(_ filter: FilterList) -> Bool {
        return loader.filterFileExists(filter)
    }

    func checkForUpdates() async {
        isLoading = true
        statusDescription = LocalizedStrings.text("Checking for updates...", comment: "Update check status")
        // Ensure counts are up-to-date before checking for updates
        await updateVersionsAndCounts()

        let enabledFilters = filterLists.filter { $0.isSelected }
        let updatedFilters = await filterUpdater.checkForUpdates(filterLists: enabledFilters)

        availableUpdates = updatedFilters

        // Also check for userscript updates
        if let userScriptManager = filterUpdater.userScriptManager {
            let downloadedScripts = userScriptManager.userScripts.filter { $0.isDownloaded }
            for script in downloadedScripts {
                await userScriptManager.updateUserScript(script)
            }
        }

        if !availableUpdates.isEmpty {
            showingUpdatePopup = true
            statusDescription = LocalizedStrings.format(
                "Found %d update(s) available.",
                comment: "Updates found status",
                availableUpdates.count
            )
        } else {
            showingNoUpdatesAlert = true
            statusDescription = LocalizedStrings.text("No updates available.", comment: "No updates status")
            Task {
                await ConcurrentLogManager.shared.info(
                    .autoUpdate, "No updates available", metadata: [:])
            }
        }

        isLoading = false
    }

    func downloadAndApplySelectedFilters(_ selectedFilters: [FilterList], showProgressSheet: Bool = false) async {
        isLoading = true
        progress = 0
        if showProgressSheet {
            statusDescription = LocalizedStrings.text(
                "Downloading filter updates...",
                comment: "Filter update download status"
            )
        }

        let successfullyUpdatedFilters = await filterUpdater.updateSelectedFilters(
            selectedFilters,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )

        saveFilterListsCoalesced()

        for filter in successfullyUpdatedFilters {
            availableUpdates.removeAll { $0.id == filter.id }
        }

        isLoading = false
        progress = 0

        if showProgressSheet {
            showingUpdatePopup = false
            prepareApplyRunState()
            showingApplyProgressSheet = true
        }

        await applyChanges()
    }

    func downloadMissingItemsSilently() async {
        for filter in missingFilters {
            if await filterUpdater.fetchAndProcessFilter(filter) {
                await MainActor.run { self.missingFilters.removeAll { $0.id == filter.id } }
            }
        }

        if let userScriptManager = filterUpdater.userScriptManager {
            for script in missingUserScripts where script.url != nil {
                let downloaded = await userScriptManager.downloadUserScript(script)
                if downloaded {
                    await MainActor.run { self.missingUserScripts.removeAll { $0.id == script.id } }
                }
            }
        }

        saveFilterListsCoalesced()
    }
}
