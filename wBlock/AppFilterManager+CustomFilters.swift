import SwiftUI
import wBlockCoreService

extension AppFilterManager {
    // MARK: - List Management
    func addFilterList(
        name: String,
        urlString: String,
        category: FilterListCategory = .custom,
        hasUserProvidedName: Bool = false,
        hasUserProvidedDescription: Bool = false,
        isSelected: Bool = true,
        description: String? = nil,
        languages: [String] = []
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

        if filterLists.contains(where: { FilterListURLSupport.isSameList($0.url, url) }) {
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

        let newName = Self.singleLineUserMetadata(name)
        let trimmedDescription = description.map(Self.singleLineUserMetadata)
        let newFilter = FilterList(
            id: UUID(),
            name: newName.isEmpty ? (url.host ?? LocalizedStrings.text("Custom Filter", comment: "Default custom filter name")) : newName,
            url: url,
            category: category,
            isCustom: true,
            isSelected: isSelected,
            // A user-provided empty description is an intentional choice.
            description: trimmedDescription?.isEmpty == false || hasUserProvidedDescription
                ? trimmedDescription ?? ""
                : LocalizedStrings.text("User-added filter list.", comment: "Default custom filter description"),
            sourceRuleCount: nil,
            languages: Self.regionalLanguages(languages, category: category),
            hasUserProvidedName: hasUserProvidedName,
            hasUserProvidedDescription: hasUserProvidedDescription)
        addCustomFilterList(newFilter)
    }

    /// Only Regional lists carry languages; they drive the flags and the
    /// Regional recommendations (#921).
    static func regionalLanguages(_ languages: [String], category: FilterListCategory) -> [String] {
        category == .foreign ? Array(Set(languages.map { $0.lowercased() })).sorted() : []
    }

    private static func singleLineUserMetadata(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func addUserList(
        name: String,
        description: String? = nil,
        content: String,
        category: FilterListCategory = .custom,
        isSelected: Bool = true,
        lastUpdated: Date = Date(),
        languages: [String] = []
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = FilterListContentProcessing.normalizedContent(
            from: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )

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

        if let message = Self.userListContentError(content) {
            statusDescription = message
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
            sourceRuleCount: Self.countRulesInUserListContent(trimmedContent),
            lastUpdated: lastUpdated,
            languages: Self.regionalLanguages(languages, category: category)
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
                    metadata: ["error": LogErrorDescriber.describe(error)]
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

    func removeFilterList(_ listToRemove: FilterList) {
        removeCustomFilterList(listToRemove)
    }

    func toggleFilter(list: FilterList) {
        toggleFilterListSelection(id: list.id)
    }

    func addCustomFilterList(_ filter: FilterList) {
        if !filterLists.contains(where: { FilterListURLSupport.isSameList($0.url, filter.url) }) {
            let newFilterToAdd = filter

            filterLists.append(newFilterToAdd)
            filterLists = deduplicateFilterIDs(filterLists)
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
                        self.acknowledgeUndownloadedFilter(newFilterToAdd.id)
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
        guard !filterLists.contains(where: { FilterListURLSupport.isSameList($0.url, filter.url) }) else { return }
        filterLists.append(filter)
        filterLists = deduplicateFilterIDs(filterLists)
        saveFilterListsCoalesced()
        refreshPendingChanges()

        Task {
            await ConcurrentLogManager.shared.info(
                .system, LocalizedStrings.text("Added user list"),
                metadata: ["filter": filter.name, "url": filter.url.absoluteString]
            )
        }
    }

    /// Drops downloaded state only after a remote filter or userscript is disabled and applied.
    /// The definition metadata remains so re-enabling can fetch the same source again.
    @discardableResult
    func clearDownloadedStateForDeselectedRemoteFilters(
        appliedFilters: [FilterList],
        disabledScriptIDs: Set<UUID>
    ) async -> Bool {
        let scriptsCleared = await (filterUpdater.userScriptManager ?? UserScriptManager.shared)
            .removeDisabledRemoteScriptDownloads(disabledScriptIDs: disabledScriptIDs)
        if !scriptsCleared {
            await recordDownloadedStateCleanupFailure(filters: [], error: "Remote userscript cache cleanup failed")
            return false
        }
        let deselectedIDs = Set(appliedFilters.filter { !$0.isSelected }.map(\.id))
        let filtersToClear = filterLists.filter {
            deselectedIDs.contains($0.id) && !$0.isSelected && $0.isRemoteURL
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
        for filter in filtersToClear {
            do {
                try ContentBlockerIncrementalCache.removeFilterCacheFiles(
                    for: filter,
                    containerURL: containerURL
                )
            } catch {
                failures.append("\(filter.name): \(LogErrorDescriber.describe(error))")
            }
        }

        guard failures.isEmpty else {
            await recordDownloadedStateCleanupFailure(
                filters: filtersToClear,
                error: failures.joined(separator: "; ")
            )
            return false
        }

        // Every field write on the published array re-renders the whole list, and
        // seven per disabled filter froze the UI after each Apply. Publish once.
        var lists = filterLists
        for filter in filtersToClear {
            guard let index = lists.firstIndex(where: { $0.id == filter.id }) else { continue }
            lists[index].version = ""
            lists[index].sourceRuleCount = nil
            lists[index].rawSourceRuleCount = nil
            lists[index].lastUpdated = nil
            lists[index].etag = nil
            lists[index].serverLastModified = nil
            lists[index].limitExceededReason = nil
        }
        if lists != filterLists { filterLists = lists }
        await dataManager.setFilterValidators(Dictionary(uniqueKeysWithValues: filtersToClear.map {
            ($0.id.uuidString, (etag: String?.none, lastModified: String?.none))
        }))

        await saveFilterLists()
        publishDownloadedFilter()
        return true
    }

    private func recordDownloadedStateCleanupFailure(filters: [FilterList], error: String) async {
        let names = filters.map(\.name).joined(separator: ", ")
        let message = LocalizedStrings.text(
            "Failed to clear downloaded content; apply again to retry.",
            comment: "Remote filter or userscript download cleanup failure status"
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

        let removedIDs = filterLists.compactMap { existing -> UUID? in
            guard existing.id == filter.id || (existing.isCustom && existing.url == filter.url) else {
                return nil
            }
            return existing.id
        }
        filterLists.removeAll { $0.id == filter.id || ($0.isCustom && $0.url == filter.url) }
        PendingFilterUpdateRevisions.remove(filterIDs: Set(removedIDs.map { $0.uuidString }))
        refreshPendingChanges()
        Task { @MainActor [weak self] in
            guard let self else { return }
            for id in removedIDs {
                await self.dataManager.removeFilterList(withId: id)
            }
            await self.saveFilterLists()
        }

        if let containerURL = loader.getSharedContainerURL() {
            _ = try? ContentBlockerIncrementalCache.removeFilterCacheFiles(
                for: filter,
                containerURL: containerURL
            )
        }
        Task {
            await ConcurrentLogManager.shared.info(
                .system, LocalizedStrings.text("Removed custom filter"), metadata: ["filter": filter.name])
        }
    }

    /// Why pasted, imported, or edited rules can't be saved, or nil. Every
    /// line must be a rule, not just one of them (#943).
    nonisolated static func userListContentError(_ content: String) -> String? {
        if let line = FilterListContentValidator.firstInvalidRuleLine(in: content) {
            return LocalizedStrings.format(
                "Line %d isn’t a valid filter rule.", comment: "User list validation error", line)
        }
        guard FilterListContentValidator.appearsToBeFilterList(content) else {
            return LocalizedStrings.text("That doesn't look like a filter list.", comment: "User list validation error")
        }
        return nil
    }

    nonisolated private static func countRulesInUserListContent(_ content: String) -> Int {
        FilterList.countRules(in: content)
    }

    @discardableResult
    func updateCustomFilterList(
        id: UUID, name: String, category: FilterListCategory, description: String? = nil, languages: [String] = []
    ) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let index = filterListIndex(for: id), filterLists[index].isCustom else {
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
        let oldLanguages = filterLists[index].languages
        filterLists[index].name = trimmed
        filterLists[index].category = category
        filterLists[index].languages = Self.regionalLanguages(languages, category: category)
        filterLists[index].hasUserProvidedName = true
        if let description {
            filterLists[index].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
            filterLists[index].hasUserProvidedDescription = true
        }
        saveFilterListsCoalesced()

        if oldCategory != category || oldLanguages != filterLists[index].languages {
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
        let trimmedContent = FilterListContentProcessing.normalizedContent(
            from: content.trimmingCharacters(in: .whitespacesAndNewlines)
        )

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

        if let message = Self.userListContentError(content) {
            statusDescription = message
            hasError = true
            return
        }

        guard let index = filterListIndex(for: id), filterLists[index].isCustom else {
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
                    metadata: ["error": LogErrorDescriber.describe(error)]
                )
            }
            return
        }

        filterLists[index].name = trimmedName
        filterLists[index].description = trimmedDescription
        filterLists[index].category = category
        filterLists[index].sourceRuleCount = Self.countRulesInUserListContent(trimmedContent)
        filterLists[index].lastUpdated = Date()

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
