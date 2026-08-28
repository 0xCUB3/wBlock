import SwiftUI
import wBlockCoreService

extension AppFilterManager {
    // MARK: - List Management
    func addFilterList(
        name: String,
        urlString: String,
        category: FilterListCategory = .custom,
        hasUserProvidedName: Bool = false,
        isSelected: Bool = true
    ) {
        guard let url = FilterListURLSupport.validatedRemoteURL(from: urlString)
        else {
            statusDescription = LocalizedStrings.format(
                "Invalid URL provided: %@",
                comment: "Custom filter validation error",
                urlString
            )
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system, LocalizedStrings.text("Invalid URL provided for new filter list"),
                    metadata: ["url": urlString])
            }
            return
        }

        if filterLists.contains(where: { $0.url == url }) {
            statusDescription = LocalizedStrings.format(
                "Filter list with this URL already exists: %@",
                comment: "Custom filter duplicate URL error",
                url.absoluteString
            )
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system, LocalizedStrings.text("Filter list with URL already exists"),
                    metadata: ["url": url.absoluteString])
            }
            return
        }

        CloudSyncManager.shared.clearDeletedCustomListURL(url.absoluteString)

        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newFilter = FilterList(
            id: UUID(),
            name: newName.isEmpty ? (url.host ?? LocalizedStrings.text("Custom Filter", comment: "Default custom filter name")) : newName,
            url: url,
            category: category,
            isCustom: true,
            isSelected: isSelected,
            description: LocalizedStrings.text("User-added filter list.", comment: "Default custom filter description"),
            sourceRuleCount: nil,
            hasUserProvidedName: hasUserProvidedName)
        addCustomFilterList(newFilter)
    }

    func addUserList(name: String, description: String? = nil, content: String, category: FilterListCategory = .custom, isSelected: Bool = true) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            statusDescription = LocalizedStrings.text("Title is required.", comment: "User list validation error")
            hasError = true
            return
        }

        guard !trimmedContent.isEmpty else {
            statusDescription = LocalizedStrings.text("User list is empty.", comment: "User list validation error")
            hasError = true
            return
        }

        guard FilterListContentValidator.appearsToBeFilterList(trimmedContent) else {
            statusDescription = LocalizedStrings.text(
                "That doesn't look like a filter list.",
                comment: "User list validation error"
            )
            hasError = true
            return
        }

        let id = UUID()
        let url = URL(string: "wblock://userlist/\(id.uuidString)")!
        let finalName = trimmedName

        let newFilter = FilterList(
            id: id,
            name: finalName,
            url: url,
            category: category,
            isCustom: true,
            isSelected: isSelected,
            description: trimmedDescription?.isEmpty == false ? trimmedDescription! : "",
            sourceRuleCount: Self.countRulesInUserListContent(trimmedContent)
        )

        guard let destinationURL = loader.localFileURL(for: newFilter) else {
            statusDescription = LocalizedStrings.text(
                "Failed to access shared storage.",
                comment: "Shared storage access error"
            )
            hasError = true
            return
        }

        do {
            try trimmedContent.write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            statusDescription = LocalizedStrings.text("Failed to save user list.", comment: "User list save error")
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system,
                    LocalizedStrings.text("Failed saving user list"),
                    metadata: ["error": error.localizedDescription]
                )
            }
            return
        }

        addCustomFilterListWithoutFetch(newFilter)
        refreshPendingChanges()
        statusDescription = LocalizedStrings.text(
            "User list added. Apply changes to enable it.",
            comment: "User list added status"
        )
        hasError = false
    }

    func addUserListFromFile(
        _ fileURL: URL,
        nameOverride: String?,
        description: String? = nil,
        category: FilterListCategory = .custom,
        isSelected: Bool = true
    ) {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let name = nameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            addUserList(
                name: name,
                description: description,
                content: content,
                category: category,
                isSelected: isSelected
            )
        } catch {
            statusDescription = LocalizedStrings.text("Failed to read file.", comment: "File read error")
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system,
                    LocalizedStrings.text("Failed reading user list file"),
                    metadata: ["error": error.localizedDescription]
                )
            }
        }
    }

    func removeFilterList(_ listToRemove: FilterList) {
        removeCustomFilterList(listToRemove)
    }

    func toggleFilter(list: FilterList) {
        toggleFilterListSelection(id: list.id)
    }

    func addCustomFilterList(_ filter: FilterList) {
        if !filterLists.contains(where: { $0.url == filter.url }) {
            let newFilterToAdd = filter

            filterLists.append(newFilterToAdd)
            saveFilterListsCoalesced()
            refreshPendingChanges()

            Task {
                await ConcurrentLogManager.shared.info(
                    .system, LocalizedStrings.text("Added custom filter"), metadata: ["filter": newFilterToAdd.name])
            }

            Task {
                let success = await filterUpdater.fetchAndProcessFilter(newFilterToAdd)
                if success {
                    let currentName = await MainActor.run {
                        self.filterLists.first(where: { $0.id == newFilterToAdd.id })?.name ?? newFilterToAdd.name
                    }
                    await ConcurrentLogManager.shared.info(
                        .filterUpdate, LocalizedStrings.text("Successfully downloaded custom filter"),
                        metadata: ["filter": currentName])
                        await MainActor.run {
                            self.refreshPendingChanges()
                            self.statusDescription = LocalizedStrings.format(
                                "Filter '%@' added successfully. Apply changes to enable it.",
                                comment: "Custom filter added status",
                                currentName
                            )
                            self.hasError = false
                        }
                    saveFilterListsCoalesced()
                } else {
                    await ConcurrentLogManager.shared.error(
                        .filterUpdate, LocalizedStrings.text("Failed to download custom filter"),
                        metadata: ["filter": newFilterToAdd.name])
                    // Keep the list. Auto-removing it made the add sheet say
                    // "already added" while the row was still in memory, then
                    // the list vanished. Apply retries selected lists that
                    // have no local file.
                    await MainActor.run {
                        self.refreshPendingChanges()
                        self.statusDescription = LocalizedStrings.text(
                            "Couldn't download this filter list. It was kept as not downloaded.",
                            comment: "Custom filter download failure; list is retained"
                        )
                        self.hasError = true
                    }
                }
            }
        } else {
            Task {
                await ConcurrentLogManager.shared.warning(
                    .system, LocalizedStrings.text("Custom filter with URL already exists"),
                    metadata: ["url": filter.url.absoluteString])
            }
        }
    }

    internal func addCustomFilterListWithoutFetch(_ filter: FilterList) {
        guard !filterLists.contains(where: { $0.url == filter.url }) else { return }

        filterLists.append(filter)
        saveFilterListsCoalesced()
        refreshPendingChanges()

        Task {
            await ConcurrentLogManager.shared.info(
                .system, LocalizedStrings.text("Added user list"),
                metadata: ["filter": filter.name, "url": filter.url.absoluteString]
            )
        }
    }

    /// Drops downloaded state only after a remote custom filter is deselected and applied.
    /// The definition metadata remains so re-enabling can fetch the same source again.
    @discardableResult
    func clearDownloadedStateForDeselectedRemoteFilters(
        previouslyAppliedFilterIDs: Set<UUID>? = nil
    ) async -> Bool {
        let appliedIDs = previouslyAppliedFilterIDs ?? appliedSelectedFilterIDs
        let filtersToClear = filterLists.filter { filter in
            guard appliedIDs.contains(filter.id), !filter.isSelected,
                  filter.isCustom, !filter.isInlineUserList
            else { return false }
            let scheme = filter.url.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }
        guard !filtersToClear.isEmpty else { return true }

        guard let containerURL = loader.getSharedContainerURL() else {
            await recordDownloadedStateCleanupFailure(
                filters: filtersToClear,
                error: "Shared app-group directory is unavailable"
            )
            return false
        }

        var failures: [String] = []
        let fileManager = FileManager.default
        for filter in filtersToClear {
            let filename = ContentBlockerIncrementalCache.localFilename(for: filter)
            var urls = [
                containerURL.appendingPathComponent(filename),
                containerURL.appendingPathComponent("diff-baseline-\(filename)")
            ]
            if let legacyURL = ContentBlockerIncrementalCache.safeLegacyFileURL(
                name: filter.name,
                containerURL: containerURL
            ) {
                urls.append(legacyURL)
            }
            if let legacyBaselineURL = ContentBlockerIncrementalCache.safeLegacyFileURL(
                name: filter.name,
                containerURL: containerURL,
                prefix: "diff-baseline-"
            ) {
                urls.append(legacyBaselineURL)
            }

            for url in urls where fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    // A concurrent cleanup may have removed the file; every other
                    // deletion failure must keep metadata and the retry marker intact.
                    if (error as NSError).code != NSFileNoSuchFileError {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
        }

        guard failures.isEmpty else {
            await recordDownloadedStateCleanupFailure(
                filters: filtersToClear,
                error: failures.joined(separator: "; ")
            )
            return false
        }

        for filter in filtersToClear {
            guard let index = filterLists.firstIndex(where: { $0.id == filter.id }) else { continue }
            filterLists[index].version = ""
            filterLists[index].sourceRuleCount = nil
            filterLists[index].rawSourceRuleCount = nil
            filterLists[index].lastUpdated = nil
            filterLists[index].etag = nil
            filterLists[index].serverLastModified = nil
            filterLists[index].limitExceededReason = nil
            await dataManager.setFilterValidators(filter.id.uuidString, etag: nil, lastModified: nil)
        }

        await saveFilterLists()
        return true
    }

    private func recordDownloadedStateCleanupFailure(filters: [FilterList], error: String) async {
        let names = filters.map(\.name).joined(separator: ", ")
        let message = LocalizedStrings.text(
            "Failed to clear downloaded custom filter state; apply again to retry.",
            comment: "Remote custom filter cleanup failure status"
        )
        hasError = true
        statusDescription = message
        applyProgressViewModel.markFailed(message: message)
        applyProgressViewModel.updateIsLoading(false)
        markNonSelectionChangesPending()
        await ConcurrentLogManager.shared.error(
            .filterApply,
            message,
            metadata: ["filters": names, "error": error, "action": "Apply again to retry"]
        )
    }

    func removeCustomFilterList(_ filter: FilterList, recordDeletion: Bool = true) {
        if filter.isCustom && recordDeletion {
            CloudSyncManager.shared.recordDeletedCustomListURL(filter.url.absoluteString)
        }

        filterLists.removeAll { $0.id == filter.id || ($0.isCustom && $0.url == filter.url) }
        saveFilterListsCoalesced()
        refreshPendingChanges()

        if let containerURL = loader.getSharedContainerURL() {
            let idFileURL = containerURL.appendingPathComponent(
                ContentBlockerIncrementalCache.localFilename(for: filter)
            )
            try? FileManager.default.removeItem(at: idFileURL)
            if let legacyFileURL = ContentBlockerIncrementalCache.safeLegacyFileURL(
                name: filter.name,
                containerURL: containerURL
            ) {
                try? FileManager.default.removeItem(at: legacyFileURL)
            }
            if let legacyBaselineURL = ContentBlockerIncrementalCache.safeLegacyFileURL(
                name: filter.name,
                containerURL: containerURL,
                prefix: "diff-baseline-"
            ) {
                try? FileManager.default.removeItem(at: legacyBaselineURL)
            }
        }
        Task {
            await ConcurrentLogManager.shared.info(
                .system, LocalizedStrings.text("Removed custom filter"), metadata: ["filter": filter.name])
        }
    }

    nonisolated private static func countRulesInUserListContent(_ content: String) -> Int {
        FilterList.countRules(in: content)
    }

    @discardableResult
    func updateCustomFilterList(id: UUID, name: String, category: FilterListCategory) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let index = filterListIndexByID[id], filterLists[index].isCustom else {
            statusDescription = LocalizedStrings.text(
                "Filter list not found.",
                comment: "Custom filter lookup error"
            )
            hasError = true
            return false
        }

        // Avoid confusing duplicate names in the UI.
        if filterLists.contains(where: {
            $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            statusDescription = LocalizedStrings.text(
                "A filter list with this name already exists.",
                comment: "Custom filter duplicate name error"
            )
            hasError = true
            return false
        }

        let oldCategory = filterLists[index].category
        filterLists[index].name = trimmed
        filterLists[index].category = category
        filterLists[index].hasUserProvidedName = true
        saveFilterListsCoalesced()

        if oldCategory != category {
            markNonSelectionChangesPending()
            statusDescription = LocalizedStrings.text(
                "Filter list updated. Apply changes to enable it.",
                comment: "Custom filter updated status"
            )
        }
        hasError = false

        Task {
            await ConcurrentLogManager.shared.info(
                .system, LocalizedStrings.text("Updated custom filter list"),
                metadata: [
                    "filterId": id.uuidString,
                    "name": trimmed,
                    "category": category.rawValue,
                ]
            )
        }
        return true
    }

    func updateUserList(id: UUID, name: String, description: String, category: FilterListCategory, content: String) {
        guard !isApplyInFlight else {
            statusDescription = LocalizedStrings.text(
                "Apply already in progress.",
                comment: "User list edit blocked during apply"
            )
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            statusDescription = LocalizedStrings.text("Title is required.", comment: "User list validation error")
            hasError = true
            return
        }

        guard !trimmedContent.isEmpty else {
            statusDescription = LocalizedStrings.text("User list is empty.", comment: "User list validation error")
            hasError = true
            return
        }

        guard let index = filterListIndexByID[id], filterLists[index].isCustom else {
            statusDescription = LocalizedStrings.text("User list not found.", comment: "User list lookup error")
            hasError = true
            return
        }

        let filter = filterLists[index]
        guard filter.isInlineUserList else {
            statusDescription = LocalizedStrings.text(
                "Only pasted user lists can be edited.",
                comment: "User list edit restriction"
            )
            hasError = true
            return
        }

        if filterLists.contains(where: {
            $0.id != id && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            statusDescription = LocalizedStrings.text(
                "A filter list with this name already exists.",
                comment: "Custom filter duplicate name error"
            )
            hasError = true
            return
        }

        loader.migrateCustomFilterFileIfNeeded(filter)
        guard let destinationURL = loader.localFileURL(for: filter) else {
            statusDescription = LocalizedStrings.text(
                "Failed to access shared storage.",
                comment: "Shared storage access error"
            )
            hasError = true
            return
        }

        do {
            try trimmedContent.write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            statusDescription = LocalizedStrings.text("Failed to save user list.", comment: "User list save error")
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system,
                    LocalizedStrings.text("Failed saving user list edits"),
                    metadata: ["error": error.localizedDescription]
                )
            }
            return
        }

        filterLists[index].name = trimmedName
        filterLists[index].description = trimmedDescription
        filterLists[index].category = category
        filterLists[index].sourceRuleCount = Self.countRulesInUserListContent(trimmedContent)

        saveFilterListsCoalesced()
        markNonSelectionChangesPending()
        statusDescription = LocalizedStrings.text(
            "User list updated. Apply changes to enable it.",
            comment: "User list updated status"
        )
        hasError = false
    }

    // Set the UserScriptManager for the filter updater
    public func setUserScriptManager(_ userScriptManager: UserScriptManager) {
        filterUpdater.userScriptManager = userScriptManager
    }
}
