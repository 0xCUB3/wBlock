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

    func checkForUpdates() async {
        isLoading = true
        statusDescription = LocalizedStrings.text("Checking for updates...", comment: "Update check status")
        // Ensure counts are up-to-date before checking for updates
        await updateVersionsAndCounts()

        let enabledFilters = filterLists.filter { $0.isSelected }
        let updatedFilters = await filterUpdater.checkForUpdates(filterLists: enabledFilters)

        availableUpdates = updatedFilters

        if let userScriptManager = filterUpdater.userScriptManager {
            availableScriptUpdates = await filterUpdater.checkForScriptUpdates(scripts: userScriptManager.userScripts)
        } else {
            availableScriptUpdates = []
        }

        let totalUpdates = availableUpdates.count + availableScriptUpdates.count
        if totalUpdates > 0 {
            applyProgressViewModel.presentReview()
            showingApplyProgressSheet = true
            statusDescription = LocalizedStrings.format(
                "Found %d update(s) available.",
                comment: "Updates found status",
                totalUpdates
            )
        } else {
            showingNoUpdatesAlert = true
            statusDescription = LocalizedStrings.text("No updates available.", comment: "No updates status")
            Task {
                await ConcurrentLogManager.shared.info(
                    .autoUpdate, LocalizedStrings.text("No updates available"), metadata: [:])
            }
        }

        isLoading = false
    }

    /// Downloads the selected filter/script updates, then runs the shared apply pipeline.
    func downloadAndApplySelectedUpdates(
        filters selectedFilters: [FilterList],
        scripts selectedScripts: [UserScript]
    ) async {
        let started = await performExclusiveApply {
            self.prepareApplyRunState()
            self.showingApplyProgressSheet = true

            let downloadingStatus = LocalizedStrings.text(
                "Downloading selected updates...",
                comment: "Selected update download status"
            )
            self.statusDescription = downloadingStatus
            self.applyProgressViewModel.updateStageDescription(downloadingStatus)

            var successfullyUpdatedFilters: [FilterList] = []
            if !selectedFilters.isEmpty {
                successfullyUpdatedFilters = await self.filterUpdater.updateSelectedFilters(
                    selectedFilters,
                    progressCallback: { newProgress in
                        Task { @MainActor in
                            self.progress = newProgress * 0.2
                            self.applyProgressViewModel.updateProgress(Float(newProgress * 0.2))
                            self.applyProgressViewModel.updateStageDescription(downloadingStatus)
                        }
                    }
                )

                self.saveFilterListsCoalesced()

                for filter in successfullyUpdatedFilters {
                    self.availableUpdates.removeAll { $0.id == filter.id }
                }
            }

            var successfullyUpdatedScripts: [UserScript] = []
            if !selectedScripts.isEmpty {
                self.applyProgressViewModel.updatePhaseCompletion(updating: true, scripts: false)

                let scriptsStatus = LocalizedStrings.text(
                    "Downloading selected scripts...",
                    comment: "Selected script download status"
                )
                self.statusDescription = scriptsStatus
                self.applyProgressViewModel.updateStageDescription(scriptsStatus)

                successfullyUpdatedScripts = await self.filterUpdater.updateSelectedScripts(selectedScripts) {
                    newProgress in
                    Task { @MainActor in
                        // Keep some headroom for the shared apply pipeline after downloads.
                        let mapped = 0.2 + (newProgress * 0.1)
                        self.progress = mapped
                        self.applyProgressViewModel.updateProgress(mapped)
                        self.applyProgressViewModel.updateStageDescription(scriptsStatus)
                    }
                }

                let updatedIDs = Set(successfullyUpdatedScripts.map(\.id))
                self.availableScriptUpdates.removeAll { updatedIDs.contains($0.id) }

                let failedCount = selectedScripts.count - successfullyUpdatedScripts.count
                self.applyProgressViewModel.updateScriptsUpdateResult(
                    updated: successfullyUpdatedScripts.count,
                    failed: max(0, failedCount)
                )
            }

            self.applyProgressViewModel.updateUpdatesFound(
                successfullyUpdatedFilters.count + successfullyUpdatedScripts.count
            )

            // Continue into the normal apply pipeline (convert / save / reload).
            // Keep the existing progress sheet state so review → progress feels continuous,
            // and skip the automatic pre-apply update pass so the user's selection is respected.
            await self.applyChanges(prepareState: false, skipPreApplyUpdates: true)
        }

        if !started {
            statusDescription = LocalizedStrings.text(
                "Apply already in progress.",
                comment: "Apply pipeline concurrency guard status"
            )
        }
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
