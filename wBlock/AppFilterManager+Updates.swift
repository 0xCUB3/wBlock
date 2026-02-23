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
        statusDescription = "Checking for updates..."
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
            statusDescription = "Found \(availableUpdates.count) update(s) available."
        } else {
            showingNoUpdatesAlert = true
            statusDescription = "No updates available."
            Task {
                await ConcurrentLogManager.shared.info(
                    .autoUpdate, "No updates available", metadata: [:])
            }
        }

        isLoading = false
    }

    func updateSelectedFilters(_ selectedFilters: [FilterList]) async {  // From UpdatePopupView
        isLoading = true
        progress = 0

        let updatedSuccessfullyFilters = await filterUpdater.updateSelectedFilters(
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

        saveFilterListsCoalesced()

        await applyChanges()
        isLoading = false
        progress = 0
    }

    func downloadSelectedFilters(_ selectedFilters: [FilterList]) async {
        isLoading = true
        progress = 0
        statusDescription = "Downloading filter updates..."

        let successfullyUpdatedFilters = await filterUpdater.updateSelectedFilters(
            selectedFilters,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )

        saveFilterListsCoalesced()

        await MainActor.run {
            for filter in successfullyUpdatedFilters {
                self.availableUpdates.removeAll { $0.id == filter.id }
            }
        }

        isLoading = false
        progress = 0

        // Close the update popup and show apply progress sheet
        await MainActor.run {
            showingUpdatePopup = false
            self.prepareApplyRunState()
            showingApplyProgressSheet = true
        }

        // Automatically apply changes after download
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
