//
//  FilterListUpdater.swift
//  wBlock
//
//  Created by Alexander Skula on 7/17/24.
//

import Foundation

class FilterListUpdater {
    private let loader: FilterListLoader
    private let converter: FilterListConverter
    private let applier: FilterListApplier
    private let logManager: ConcurrentLogManager
    
    weak var filterListManager: FilterListManager? // Add a weak reference

    init(loader: FilterListLoader, converter: FilterListConverter, applier: FilterListApplier, logManager: ConcurrentLogManager) {
        self.loader = loader
        self.converter = converter
        self.applier = applier
        self.logManager = logManager
    }

    /// Updates missing versions for filter lists and returns a dictionary of indices and versions
    func updateMissingVersions(filterLists: [FilterList]) async -> [(Int, String)] {
        var updatedVersions: [(Int, String)] = []

        for (index, filter) in filterLists.enumerated() {
            if filter.version.isEmpty && loader.filterFileExists(filter) {
                if let newVersion = await fetchVersionFromURL(for: filter) {
                    updatedVersions.append((index, newVersion))
                    await ConcurrentLogManager.shared.log("Fetched version for \(filter.name): \(newVersion)")

                    // Update the filter and notify changes:
                    await MainActor.run {
                        var updatedFilter = filterLists[index]
                        updatedFilter.version = newVersion
                        self.filterListManager?.filterLists[index] = updatedFilter // Directly update
                        self.filterListManager?.objectWillChange.send() //Crucial
                    }
                } else {
                    await ConcurrentLogManager.shared.log("Failed to fetch version for \(filter.name)")
                }
            }
        }

        return updatedVersions
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
            let (data, response) = try await URLSession.shared.data(from: filter.url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let content = String(data: data, encoding: .utf8) else {
                await ConcurrentLogManager.shared.log("Failed to fetch \(filter.name)") // More concise logging
                return false
            }

            let metadata = parseMetadata(from: content)
            var updatedFilter = filter
            updatedFilter.version = metadata.version ?? "Unknown"
            if let description = metadata.description, !description.isEmpty {
                updatedFilter.description = description
            }

            await MainActor.run {
                if let index = filterListManager?.filterLists.firstIndex(where: {$0.id == updatedFilter.id}) {
                    filterListManager?.filterLists[index] = updatedFilter
                    filterListManager?.objectWillChange.send() // Notify
                }
            }

            guard let containerURL = loader.getSharedContainerURL() else {
                await ConcurrentLogManager.shared.log("Error: Unable to access shared container")
                return false
            }

            try? content.write(to: containerURL.appendingPathComponent("\(filter.name).txt"), atomically: true, encoding: .utf8)

            let filteredRules = content.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.hasPrefix("[") }

            await converter.convertAndSaveRules(filteredRules, for: filter)
            return true
        } catch {
            await ConcurrentLogManager.shared.log("Error fetching \(filter.name): \(error)") // More concise logging
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
                        return (filter, false)
                    }
                }
            }

            for await (filter, success) in group {
                if success {
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
