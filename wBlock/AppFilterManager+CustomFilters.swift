import SwiftUI
import wBlockCoreService

extension AppFilterManager {
    // MARK: - List Management
    func addFilterList(name: String, urlString: String, category: FilterListCategory = .custom, hasUserProvidedName: Bool = false) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            statusDescription = LocalizedStrings.format(
                "Invalid URL provided: %@",
                comment: "Custom filter validation error",
                urlString
            )
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system, "Invalid URL provided for new filter list",
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
                    .system, "Filter list with URL already exists",
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
            isSelected: true,
            description: LocalizedStrings.text("User-added filter list.", comment: "Default custom filter description"),
            sourceRuleCount: nil,
            hasUserProvidedName: hasUserProvidedName)
        addCustomFilterList(newFilter)
    }

    func addUserList(name: String, description: String? = nil, content: String, isSelected: Bool = true) {
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

        let lower = trimmedContent.lowercased()
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") {
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
            category: .custom,
            isCustom: true,
            isSelected: isSelected,
            description: trimmedDescription?.isEmpty == false
                ? trimmedDescription!
                : LocalizedStrings.text("User list.", comment: "Default user list description"),
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
                    "Failed saving user list",
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

    func addUserListFromFile(_ fileURL: URL, nameOverride: String?, description: String? = nil, isSelected: Bool = true) {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let name = nameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            addUserList(name: name, description: description, content: content, isSelected: isSelected)
        } catch {
            statusDescription = LocalizedStrings.text("Failed to read file.", comment: "File read error")
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system,
                    "Failed reading user list file",
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
        if !customFilterLists.contains(where: { $0.url == filter.url }) {
            let newFilterToAdd = filter

            filterLists.append(newFilterToAdd)
            saveFilterListsCoalesced()
            refreshPendingChanges()

            Task {
                await ConcurrentLogManager.shared.info(
                    .system, "Added custom filter", metadata: ["filter": newFilterToAdd.name])
            }

            Task {
                let success = await filterUpdater.fetchAndProcessFilter(newFilterToAdd)
                if success {
                    let currentName = await MainActor.run {
                        self.filterLists.first(where: { $0.id == newFilterToAdd.id })?.name ?? newFilterToAdd.name
                    }
                    await ConcurrentLogManager.shared.info(
                        .filterUpdate, "Successfully downloaded custom filter",
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
                        .filterUpdate, "Failed to download custom filter",
                        metadata: ["filter": newFilterToAdd.name])
                    await MainActor.run {
                        removeCustomFilterList(newFilterToAdd)
                        self.statusDescription = LocalizedStrings.text(
                            "Failed to add filter. The URL may be invalid or the content is not a valid filter list.",
                            comment: "Custom filter add failure"
                        )
                        self.hasError = true
                    }
                }
            }
        } else {
            Task {
                await ConcurrentLogManager.shared.warning(
                    .system, "Custom filter with URL already exists",
                    metadata: ["url": filter.url.absoluteString])
            }
        }
    }

    internal func addCustomFilterListWithoutFetch(_ filter: FilterList) {
        guard !customFilterLists.contains(where: { $0.url == filter.url }) else { return }

        filterLists.append(filter)
        saveFilterListsCoalesced()
        refreshPendingChanges()

        Task {
            await ConcurrentLogManager.shared.info(
                .system, "Added user list",
                metadata: ["filter": filter.name, "url": filter.url.absoluteString]
            )
        }
    }

    func removeCustomFilterList(_ filter: FilterList) {
        if filter.isCustom {
            CloudSyncManager.shared.recordDeletedCustomListURL(filter.url.absoluteString)
        }

        filterLists.removeAll { $0.id == filter.id }
        saveFilterListsCoalesced()
        refreshPendingChanges()

        if let containerURL = loader.getSharedContainerURL() {
            let idFileURL = containerURL.appendingPathComponent(
                ContentBlockerIncrementalCache.localFilename(for: filter)
            )
            try? FileManager.default.removeItem(at: idFileURL)
            // Clean up any legacy name-based file.
            let legacyFileURL = containerURL.appendingPathComponent("\(filter.name).txt")
            try? FileManager.default.removeItem(at: legacyFileURL)
        }
        Task {
            await ConcurrentLogManager.shared.info(
                .system, "Removed custom filter", metadata: ["filter": filter.name])
        }
    }

    nonisolated private static func countRulesInUserListContent(_ content: String) -> Int {
        FilterList.countRules(in: content)
    }

    func updateCustomFilterListName(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let index = filterListIndexByID[id], filterLists[index].isCustom else {
            return
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
            return
        }

        filterLists[index].name = trimmed
        filterLists[index].hasUserProvidedName = true
        saveFilterListsCoalesced()

        Task {
            await ConcurrentLogManager.shared.info(
                .system, "Renamed custom filter list",
                metadata: ["filterId": id.uuidString, "name": trimmed]
            )
        }
    }

    func updateUserList(id: UUID, name: String, description: String, content: String) {
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
                    "Failed saving user list edits",
                    metadata: ["error": error.localizedDescription]
                )
            }
            return
        }

        filterLists[index].name = trimmedName
        filterLists[index].description = trimmedDescription
        filterLists[index].sourceRuleCount = Self.countRulesInUserListContent(trimmedContent)

        saveFilterListsCoalesced()
        markNonSelectionChangesPending()
        statusDescription = LocalizedStrings.text(
            "User list updated. Apply changes to enable it.",
            comment: "User list updated status"
        )
        hasError = false
    }

    func revertToRecommendedFilters() async {
        for index in filterLists.indices {
            filterLists[index].isSelected = false
        }

        #if os(iOS)
            let essentialFilters = [
                "AdGuard Base Filter",
                "EasyPrivacy",
            ]
        #else
            let essentialFilters = [
                "AdGuard Base Filter",
                "AdGuard Tracking Protection Filter",
                "EasyPrivacy",
                "Online Security Filter",
            ]
        #endif

        for index in filterLists.indices {
            filterLists[index].isSelected = essentialFilters.contains(filterLists[index].name)
        }

        saveFilterListsCoalesced()
        statusDescription = LocalizedStrings.text(
            "Reverted to essential filters to stay under Safari's 150k rule limit.",
            comment: "Essential filter reset status"
        )

        await MainActor.run {
            self.prepareApplyRunState()
            showingApplyProgressSheet = true
        }
        await applyChanges()
    }

    // Set the UserScriptManager for the filter updater
    public func setUserScriptManager(_ userScriptManager: UserScriptManager) {
        filterUpdater.userScriptManager = userScriptManager
    }
}
