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
                let current = newFilterLists[index]
                var merged = updatedListFromServer
                // Metadata refreshes must not overwrite selection or other live
                // configuration changes made while the request was in flight.
                merged.name = current.name
                merged.url = current.url
                merged.category = current.category
                merged.isCustom = current.isCustom
                merged.isSelected = current.isSelected
                merged.hasUserProvidedName = current.hasUserProvidedName
                merged.description = current.description
                newFilterLists[index] = merged
            }
        }
        self.filterLists = newFilterLists
        saveFilterListsCoalesced()
    }

    enum UpdateCheckScope {
        case filters
        case scripts
        case all
    }

    enum UpdateCheckPresentation {
        case blocking
        case refresh
    }

    func checkForUpdates(
        scope: UpdateCheckScope = .all,
        presentation: UpdateCheckPresentation = .blocking
    ) async {
        if presentation == .refresh {
            suppressBlockingOverlay = true
        }
        isLoading = true
        defer {
            isLoading = false
            if presentation == .refresh {
                suppressBlockingOverlay = false
            }
        }

        statusDescription = LocalizedStrings.text("Checking for updates...", comment: "Update check status")
        progress = 0

        switch scope {
        case .filters:
            await checkEnabledFilterUpdates()
            availableScriptUpdates = []
        case .scripts:
            availableUpdates = []
            await checkUserScriptUpdates()
        case .all:
            await checkEnabledFilterUpdates()
            await checkUserScriptUpdates()
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
            if presentation == .blocking {
                showingNoUpdatesAlert = true
            }
            statusDescription = LocalizedStrings.text("No updates available.", comment: "No updates status")
            Task {
                await ConcurrentLogManager.shared.info(
                    .autoUpdate, LocalizedStrings.text("No updates available"), metadata: [:])
            }
        }
    }

    private func checkEnabledFilterUpdates() async {
        await updateVersionsAndCounts()
        let enabledFilters = filterLists.filter { $0.isSelected }
        availableUpdates = await filterUpdater.checkForUpdates(
            filterLists: enabledFilters,
            progressCallback: { checkProgress in
                await MainActor.run {
                    self.progress = checkProgress.fraction
                    self.statusDescription = Self.checkingStatus(for: checkProgress)
                }
            }
        )
    }

    /// "Checking for updates... (12/87)" while a manual check walks the lists.
    static func checkingStatus(for checkProgress: FilterListUpdater.FilterRefreshProgress) -> String {
        guard checkProgress.total > 0 else {
            return LocalizedStrings.text("Checking for updates...", comment: "Update check status")
        }
        return LocalizedStrings.format(
            "Checking for updates... (%d/%d)",
            comment: "Update check status with checked/total list counts",
            checkProgress.completed,
            checkProgress.total
        )
    }

    private func checkUserScriptUpdates() async {
        let userScriptManager = filterUpdater.userScriptManager ?? UserScriptManager.shared
        await userScriptManager.waitUntilReady()
        if filterUpdater.userScriptManager == nil {
            setUserScriptManager(userScriptManager)
        }
        availableScriptUpdates = await filterUpdater.checkForScriptUpdates(scripts: userScriptManager.userScripts)
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
                        await MainActor.run {
                            self.progress = newProgress.fraction * 0.2
                            self.applyProgressViewModel.updateFiltersChecked(
                                newProgress.completed, total: newProgress.total
                            )
                            self.applyProgressViewModel.updateStageDescription(downloadingStatus)
                        }
                        await Self.allowProgressUIRefresh()
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
                    await MainActor.run {
                        // Keep some headroom for the shared apply pipeline after downloads.
                        let mapped = 0.2 + (newProgress * 0.1)
                        self.progress = mapped
                        self.applyProgressViewModel.updatePhaseProgress(Double(newProgress))
                        self.applyProgressViewModel.updateStageDescription(scriptsStatus)
                    }
                    await Self.allowProgressUIRefresh()
                }

                let updatedIDs = Set(successfullyUpdatedScripts.map(\.id))
                self.availableScriptUpdates.removeAll { updatedIDs.contains($0.id) }

                let failedCount = selectedScripts.count - successfullyUpdatedScripts.count
                self.applyProgressViewModel.updateScriptsUpdateResult(
                    updated: successfullyUpdatedScripts.count,
                    failed: max(0, failedCount)
                )
            }

            self.applyProgressViewModel.updateFilterUpdatesFound(successfullyUpdatedFilters.count)

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
