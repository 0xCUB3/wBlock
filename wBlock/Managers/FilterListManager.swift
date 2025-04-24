//
//  FilterListManager.swift
//  wBlock
//
//  Created by Alexander Skula on 7/17/24.
//

import Foundation
import Combine
import SafariServices
import ContentBlockerConverter
import UserNotifications
import os.log

@MainActor
class FilterListManager: ObservableObject {
    @Published var filterLists: [FilterList] = []
    @Published var isUpdating = false
    @Published var progress: Float = 0
    @Published var missingFilters: [FilterList] = []
    @Published var logs: String = ""
    @Published var showProgressView = false
    @Published var availableUpdates: [FilterList] = []
    @Published var showingUpdatePopup = false
    @Published var hasUnappliedChanges = false
    @Published var showMissingFiltersSheet = false
    @Published var showRecommendedFiltersAlert = false
    @Published var showResetToDefaultAlert = false
    @Published var showingNoUpdatesAlert = false
    @Published var ruleCounts: [UUID: Int] = [:]

    // Dependencies
    private let loader: FilterListLoader
    private let updater: FilterListUpdater
    private let converter: FilterListConverter
    private let applier: FilterListApplier
    private let logManager: ConcurrentLogManager

    var customFilterLists: [FilterList] = []

    init() {
        self.logManager = ConcurrentLogManager()
        self.loader = FilterListLoader(logManager: logManager)
        self.converter = FilterListConverter(logManager: logManager)
        self.applier = FilterListApplier(logManager: logManager)
        self.updater = FilterListUpdater(
            loader: loader,
            converter: converter,
            applier: applier,
            logManager: logManager
        )

        setup()
    }

    private func setup() {
        loader.checkAndCreateGroupFolder()
        filterLists = loader.loadFilterLists()
        customFilterLists = loader.loadCustomFilterLists() // Add this line
        loader.loadSelectedState(for: &filterLists)
        Task {
            await applier.checkAndCreateBlockerList(filterLists: filterLists)
        }
        checkAndEnableFilters()
        clearLogs()
        Task { await updateMissingVersions() }
    }

    // MARK: - Core functionality

    /// Checks if selected filters exist, downloads if missing
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
        showProgressView = true
        isUpdating = true
        progress = 0

        await applier.applyChanges(
            filterLists: filterLists,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )

        self.hasUnappliedChanges = false
        self.isUpdating = false
        self.showProgressView = false
    }

    func updateMissingFilters() async {
        showProgressView = true
        isUpdating = true
        progress = 0

        let totalSteps = Float(missingFilters.count)
        var completedSteps: Float = 0

        for filter in missingFilters {
            let success = await updater.fetchAndProcessFilter(filter)
            if success {
                await MainActor.run {
                    missingFilters.removeAll { $0.id == filter.id }
                }
            }
            completedSteps += 1
            await MainActor.run {
                progress = completedSteps / totalSteps
            }
        }

        await applyChanges()
        isUpdating = false
    }

    func updateMissingVersions() async {
        let updatedVersions = await updater.updateMissingVersions(filterLists: filterLists)

        await MainActor.run {
            for (index, version) in updatedVersions {
                if index < filterLists.count {
                    filterLists[index].version = version
                }
            }
            loader.saveFilterLists(filterLists)
        }
    }

    func checkForUpdates() async {
        let enabledFilters = filterLists.filter { $0.isSelected }
        let updatedFilters = await updater.checkForUpdates(filterLists: enabledFilters)

        await MainActor.run {
            availableUpdates = updatedFilters

            if !availableUpdates.isEmpty {
                showingUpdatePopup = true
            } else {
                showingNoUpdatesAlert = true
                appendLog("No updates available.")
            }
        }
    }

    func autoUpdateFilters() async -> [FilterList] {
        await MainActor.run {
            isUpdating = true
            showProgressView = true
            progress = 0
        }

        let updatedFilters = await updater.autoUpdateFilters(
            filterLists: filterLists.filter { $0.isSelected },
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )

        if !updatedFilters.isEmpty {
            await applyChanges()
        }

        await MainActor.run {
            isUpdating = false
            showProgressView = false
        }

        return updatedFilters
    }

    func updateSelectedFilters(_ selectedFilters: [FilterList]) async {
        await MainActor.run {
            showProgressView = true
            isUpdating = true
            progress = 0
        }

        let updatedFilters = await updater.updateSelectedFilters(
            selectedFilters,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )

        await MainActor.run {
            // Remove updated filters from availableUpdates
            for filter in updatedFilters {
                availableUpdates.removeAll { $0.id == filter.id }
            }
        }

        await applyChanges()

        await MainActor.run {
            isUpdating = false
            showProgressView = false
        }
    }

    // MARK: - Logging

    func appendLog(_ message: String) {
        Task {
            await ConcurrentLogManager.shared.log(message)
            logs = await ConcurrentLogManager.shared.getAllLogs()
        }
    }

    func clearLogs() {
        Task {
            await ConcurrentLogManager.shared.clearLogs()
            logs = await ConcurrentLogManager.shared.getAllLogs() // Should now be empty
        }
    }

    func loadLogsFromFile() async {
        logs = await ConcurrentLogManager.shared.getAllLogs()
    }
    
    /// Adds a custom filter list
    func addCustomFilterList(_ filter: FilterList) {
        // Check if a filter with the same URL already exists
        if !customFilterLists.contains(where: { $0.url == filter.url }) {
            var newFilter = filter

            // Add to custom filter lists
            customFilterLists.append(newFilter)
            loader.saveCustomFilterLists(customFilterLists)

            // Also add to main filter lists
            filterLists.append(newFilter)
            loader.saveFilterLists(filterLists)

            Task {
                await ConcurrentLogManager.shared.log("Added custom filter: \(newFilter.name)")
            }

            // Download the filter
            Task {
                let success = await updater.fetchAndProcessFilter(newFilter)
                if success {
                    await ConcurrentLogManager.shared.log("Successfully downloaded custom filter: \(newFilter.name)")
                    hasUnappliedChanges = true
                } else {
                    await ConcurrentLogManager.shared.log("Failed to download custom filter: \(newFilter.name)")

                    // If download fails, remove the filter
                    await MainActor.run {
                        removeCustomFilterList(newFilter)
                    }
                }
            }
        } else {
            Task {
                await ConcurrentLogManager.shared.log("Custom filter with URL \(filter.url) already exists")
            }
        }
    }

    
    /// Removes a custom filter list
    func removeCustomFilterList(_ filter: FilterList) {
        customFilterLists.removeAll { $0.id == filter.id }
        loader.saveCustomFilterLists(customFilterLists)

        // Also remove from main filter lists if present
        filterLists.removeAll { $0.id == filter.id }
        loader.saveFilterLists(filterLists)

        // Remove any files associated with this filter
        if let containerURL = loader.getSharedContainerURL() {
            let fileURLs = [
                containerURL.appendingPathComponent("\(filter.name).json"),
                containerURL.appendingPathComponent("\(filter.name)_advanced.json"),
                containerURL.appendingPathComponent("\(filter.name).txt")
            ]

            for url in fileURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }
        Task {
            await ConcurrentLogManager.shared.log("Removed custom filter: \(filter.name)")
        }
        hasUnappliedChanges = true
    }
    
    /// Loads custom filter lists from UserDefaults
    func loadCustomFilterLists() -> [FilterList] {
        if let data = UserDefaults.standard.data(forKey: "customFilterLists") {
            do {
                let decoder = JSONDecoder()
                let customLists = try decoder.decode([FilterList].self, from: data)
                return customLists
            } catch {
                Task {
                    await ConcurrentLogManager.shared.log("Error loading custom filter lists: \(error)")
                }
            }
        }
        return []
    }

    /// Saves custom filter lists to UserDefaults
    func saveCustomFilterLists(_ customFilterLists: [FilterList]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(customFilterLists)
            UserDefaults.standard.set(data, forKey: "customFilterLists")
        } catch {
            Task {
                await ConcurrentLogManager.shared.log("Error saving custom filter lists: \(error)")
            }
        }
    }

    /// Make sure you're not running the app without filters on!
    func checkForEnabledFilters() {
        let enabledFilters = filterLists.filter { $0.isSelected }
        if enabledFilters.isEmpty {
            showRecommendedFiltersAlert = true
        }
    }
}
