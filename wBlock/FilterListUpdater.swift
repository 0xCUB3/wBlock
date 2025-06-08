//
//  FilterListUpdater.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Foundation

class FilterListUpdater {
    private let loader: FilterListLoader
    private let logManager: ConcurrentLogManager
    
    weak var filterListManager: AppFilterManager?

    init(loader: FilterListLoader, logManager: ConcurrentLogManager) {
        self.loader = loader
        self.logManager = logManager
    }

    /// Counts effective rules in a given filter list content string.
    private func countRulesInContent(content: String) -> Int {
        return content.components(separatedBy: .newlines).filter { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedLine.isEmpty && !trimmedLine.hasPrefix("!") && !trimmedLine.hasPrefix("[") && !trimmedLine.hasPrefix("#")
        }.count
    }

    /// Updates missing versions for filter lists and returns a dictionary of indices and versions
    func updateMissingVersionsAndCounts(filterLists: [FilterList]) async -> [FilterList] {
        var updatedLists = filterLists // Create a mutable copy to return

        for (index, filter) in filterLists.enumerated() {
            var modifiedFilter = filter // Work with a mutable copy of the current filter
            var filterWasModifiedThisIteration = false

            // --- Update Version if needed ---
            if modifiedFilter.version.isEmpty && loader.filterFileExists(modifiedFilter) {
                if let newVersion = await fetchVersionFromURL(for: modifiedFilter) {
                    modifiedFilter.version = newVersion
                    filterWasModifiedThisIteration = true
                    await ConcurrentLogManager.shared.log("Fetched version for \(modifiedFilter.name): \(newVersion)")
                } else {
                    await ConcurrentLogManager.shared.log("Failed to fetch version for \(modifiedFilter.name)")
                }
            }

            // --- Update Source Rule Count if needed ---
            // Only attempt to count if the .txt file exists
            if modifiedFilter.sourceRuleCount == nil && loader.filterFileExists(modifiedFilter) {
                if let localContent = loader.readLocalFilterContent(modifiedFilter) {
                    let ruleCount = countRulesInContent(content: localContent)
                    modifiedFilter.sourceRuleCount = ruleCount
                    filterWasModifiedThisIteration = true
                    await ConcurrentLogManager.shared.log("Calculated source rule count for \(modifiedFilter.name): \(ruleCount)")
                } else {
                    await ConcurrentLogManager.shared.log("Failed to read local content for rule counting for \(modifiedFilter.name).")
                }
            }
            
            if filterWasModifiedThisIteration {
                updatedLists[index] = modifiedFilter // Update the list that will be returned
                // The actual update to filterListManager.filterLists will happen in AppFilterManager
            }
        }
        return updatedLists
    }

    /// Fetches version information from a filter list URL
    func fetchVersionFromURL(for filter: FilterList) async -> String? {
        do {
            let (data, response) = try await URLSession.shared.data(from: filter.url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await ConcurrentLogManager.shared.log("Failed to fetch version from URL for \(filter.name): Invalid response")
                return nil
            }
            guard let content = String(data: data, encoding: .utf8) else {
                await ConcurrentLogManager.shared.log("Unable to parse content from \(filter.url)")
                return nil
            }

            // Parse metadata for version
            let metadata = parseMetadata(from: content)
            return metadata.version ?? "Unknown"
        } catch {
            await ConcurrentLogManager.shared.log("Error fetching version from URL for \(filter.name): \(error.localizedDescription)")
            return nil
        }
    }

    /// Parses metadata from filter list content
    func parseMetadata(from content: String) -> (title: String?, description: String?, version: String?) {
        var title: String?
        var description: String?
        var version: String?

        let regexPatterns = [
            "Title": "^!\\s*Title\\s*:?\\s*(.*)$",
            "Description": "^!\\s*Description\\s*:?\\s*(.*)$",
            "Version": "^!\\s*(?:version|last modified|updated)\\s*:?\\s*(.*)$"
        ]

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            for (key, pattern) in regexPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.utf16.count)),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: trimmedLine) {
                    // Raw metadata capture
                    let value = String(trimmedLine[range]).trimmingCharacters(in: .whitespaces)
                    
                    // Clean up forward slashes
                    let cleanValue = value.replacingOccurrences(of: "/", with: " & ")
                    
                    switch key {
                    case "Title":
                        title = cleanValue
                    case "Description":
                        description = cleanValue
                    case "Version":
                        version = cleanValue
                    default:
                        break
                    }
                }
            }

            // Break early if all metadata are found
            if title != nil, description != nil, version != nil {
                break
            }
        }

        return (title, description, version)
    }

    /// Checks for updates and returns a list of filters that have updates
    func checkForUpdates(filterLists: [FilterList]) async -> [FilterList] {
        var filtersWithUpdates: [FilterList] = []

        await withTaskGroup(of: (FilterList, Bool).self) { group in
            for filter in filterLists {
                group.addTask {
                    let hasUpdate = await self.hasUpdate(for: filter)
                    return (filter, hasUpdate)
                }
            }

            for await (filter, hasUpdate) in group {
                if hasUpdate {
                    filtersWithUpdates.append(filter)
                }
            }
        }

        return filtersWithUpdates
    }

    /// Checks if a filter has an update by comparing online content with local content
    func hasUpdate(for filter: FilterList) async -> Bool {
        guard let containerURL = loader.getSharedContainerURL() else { return false }
        let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")

        do {
            let (data, _) = try await URLSession.shared.data(from: filter.url)
            let onlineContent = String(data: data, encoding: .utf8) ?? ""

            if FileManager.default.fileExists(atPath: fileURL.path) {
                let localContent = try String(contentsOf: fileURL, encoding: .utf8)
                return onlineContent != localContent
            } else {
                return true // If local file doesn't exist, consider it as needing an update
            }
        } catch {
            await ConcurrentLogManager.shared.log("Error checking update for \(filter.name): \(error.localizedDescription)")
            return false
        }
    }

    /// Fetches, processes, and saves a filter list
    func fetchAndProcessFilter(_ filter: FilterList) async -> Bool {
        do {
            // Special handling for GitFlic URLs which may be blocked by Cloudflare
            let (data, response): (Data, URLResponse)
            if filter.url.host?.contains("gitflic.ru") == true {
                var request = URLRequest(url: filter.url)
                // Try to mimic a more complete browser request
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                request.setValue("text/plain,*/*", forHTTPHeaderField: "Accept")
                request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("gitflic.ru", forHTTPHeaderField: "Host")
                request.setValue("https://gitflic.ru", forHTTPHeaderField: "Referer")
                request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
                request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
                request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
                request.setValue("?1", forHTTPHeaderField: "Sec-Fetch-User")
                request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
                request.setValue("max-age=0", forHTTPHeaderField: "Cache-Control")
                request.timeoutInterval = 30
                (data, response) = try await URLSession.shared.data(for: request)
            } else {
                (data, response) = try await URLSession.shared.data(from: filter.url)
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let content = String(data: data, encoding: .utf8) else {
                await ConcurrentLogManager.shared.log("Failed to fetch \(filter.name)")
                return false
            }

            let metadata = parseMetadata(from: content)
            var updatedFilter = filter
            updatedFilter.version = metadata.version ?? "Unknown"
            if let description = metadata.description, !description.isEmpty {
                updatedFilter.description = description
            }
            updatedFilter.sourceRuleCount = countRulesInContent(content: content)


            await MainActor.run {
                if let index = filterListManager?.filterLists.firstIndex(where: {$0.id == updatedFilter.id}) {
                    filterListManager?.filterLists[index] = updatedFilter
                    filterListManager?.objectWillChange.send()
                }
            }

            guard let containerURL = loader.getSharedContainerURL() else {
                await ConcurrentLogManager.shared.log("Error: Unable to access shared container")
                return false
            }

            try? content.write(to: containerURL.appendingPathComponent("\(filter.name).txt"), atomically: true, encoding: .utf8)

            return true
        } catch {
            await ConcurrentLogManager.shared.log("Error fetching \(filter.name): \(error)")
            return false
        }
    }

    /// Automatically updates filters and returns the list of updated filters
    func autoUpdateFilters(filterLists: [FilterList], progressCallback: @escaping (Float) -> Void) async -> [FilterList] {
        var updatedFilters: [FilterList] = []

        let enabledFilters = filterLists
        let totalSteps = Float(enabledFilters.count)
        var completedSteps: Float = 0

        await withTaskGroup(of: (FilterList, Bool).self) { group in
            for filter in enabledFilters {
                group.addTask {
                    if await self.hasUpdate(for: filter) {
                        let success = await self.fetchAndProcessFilter(filter)
                        return (filter, success)
                    } else {
                        // If no update, still ensure count is populated if missing
                        var currentFilter = filter
                        if currentFilter.sourceRuleCount == nil, self.loader.filterFileExists(currentFilter) {
                            if let localContent = self.loader.readLocalFilterContent(currentFilter) {
                                currentFilter.sourceRuleCount = self.countRulesInContent(content: localContent)
                                // This change needs to be propagated back to AppFilterManager
                                await MainActor.run {
                                     if let index = self.filterListManager?.filterLists.firstIndex(where: {$0.id == currentFilter.id}) {
                                         self.filterListManager?.filterLists[index] = currentFilter
                                         self.filterListManager?.objectWillChange.send()
                                     }
                                 }
                            }
                        }
                        return (currentFilter, false) // Return false for success as no update was *fetched*
                    }
                }
            }

            for await (filter, success) in group {
                if success { // True if filter was *fetched* and processed
                    updatedFilters.append(filter)
                }
                completedSteps += 1
                progressCallback(completedSteps / totalSteps)
            }
        }

        if !updatedFilters.isEmpty {
            await ConcurrentLogManager.shared.log("Found updates for filters: \(updatedFilters.map { $0.name }.joined(separator: ", "))")
        } else {
            await ConcurrentLogManager.shared.log("No updates found for current filters.")
        }

        return updatedFilters
    }

    /// Updates selected filters and returns the list of successfully updated filters
    func updateSelectedFilters(_ selectedFilters: [FilterList], progressCallback: @escaping (Float) -> Void) async -> [FilterList] {
        let totalSteps = Float(selectedFilters.count)
        var completedSteps: Float = 0
        var updatedFilters: [FilterList] = []

        for filter in selectedFilters {
            let success = await fetchAndProcessFilter(filter)
            if success {
                updatedFilters.append(filter)
                await ConcurrentLogManager.shared.log("Successfully updated \(filter.name)")
            } else {
                await ConcurrentLogManager.shared.log("Failed to update \(filter.name)")
            }
            completedSteps += 1
            progressCallback(completedSteps / totalSteps)
        }

        return updatedFilters
    }
}
