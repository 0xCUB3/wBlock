//
//  FilterListUpdater.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Foundation
import wBlockCoreService

class FilterListUpdater {
    private let loader: FilterListLoader
    private let logManager: ConcurrentLogManager
    
    weak var filterListManager: AppFilterManager?
    weak var userScriptManager: UserScriptManager?

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

            let finalFilter = updatedFilter
            await MainActor.run {
                if let index = filterListManager?.filterLists.firstIndex(where: {$0.id == finalFilter.id}) {
                    filterListManager?.filterLists[index] = finalFilter
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
                        var mutableFilter = filter
                        if mutableFilter.sourceRuleCount == nil, self.loader.filterFileExists(mutableFilter) {
                            if let localContent = self.loader.readLocalFilterContent(mutableFilter) {
                                mutableFilter.sourceRuleCount = self.countRulesInContent(content: localContent)
                                // This change needs to be propagated back to AppFilterManager
                                let finalFilter = mutableFilter
                                await MainActor.run {
                                     if let index = self.filterListManager?.filterLists.firstIndex(where: {$0.id == finalFilter.id}) {
                                         self.filterListManager?.filterLists[index] = finalFilter
                                         self.filterListManager?.objectWillChange.send()
                                     }
                                 }
                            }
                        }
                        return (mutableFilter, false)
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
    
    /// Checks for updates to userscripts and returns those with available updates
    func checkForScriptUpdates(scripts: [UserScript]) async -> [UserScript] {
        var scriptsWithUpdates: [UserScript] = []
        
        await withTaskGroup(of: (UserScript, Bool).self) { group in
            for script in scripts.filter({ $0.isDownloaded && $0.updateURL != nil }) {
                group.addTask {
                    let hasUpdate = await self.hasScriptUpdate(for: script)
                    return (script, hasUpdate)
                }
            }
            
            for await (script, hasUpdate) in group {
                if hasUpdate {
                    scriptsWithUpdates.append(script)
                }
            }
        }
        
        return scriptsWithUpdates
    }
    
    /// Checks if a specific userscript has an update available
    private func hasScriptUpdate(for script: UserScript) async -> Bool {
        guard let updateURLString = script.updateURL, 
              let updateURL = URL(string: updateURLString) else {
            return false
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: updateURL)
            guard let onlineContent = String(data: data, encoding: .utf8) else {
                return false
            }
            
            // Create a temporary script to parse the metadata
            var tempScript = UserScript(name: script.name, content: onlineContent)
            tempScript.parseMetadata()
            
            // Compare versions (if version is empty, assume update is needed)
            if !tempScript.version.isEmpty && !script.version.isEmpty {
                return tempScript.version != script.version
            } else {
                // If we can't compare versions, check if content differs
                return onlineContent != script.content
            }
        } catch {
            await ConcurrentLogManager.shared.log("Error checking update for script \(script.name): \(error.localizedDescription)")
            return false
        }
    }
    
    /// Fetches and processes a userscript
    func fetchAndProcessScript(_ script: UserScript) async -> (UserScript?, Bool) {
        guard let downloadURLString = script.downloadURL ?? script.updateURL,
              let downloadURL = URL(string: downloadURLString) else {
            await ConcurrentLogManager.shared.log("Error: No download URL for script \(script.name)")
            return (nil, false)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: downloadURL)
            
            guard let httpResponse = response as? HTTPURLResponse, 
                  httpResponse.statusCode == 200,
                  let content = String(data: data, encoding: .utf8) else {
                await ConcurrentLogManager.shared.log("Failed to fetch script \(script.name)")
                return (nil, false)
            }
            
            var updatedScript = script
            updatedScript.content = content
            updatedScript.parseMetadata()
            
            return (updatedScript, true)
        } catch {
            await ConcurrentLogManager.shared.log("Error fetching script \(script.name): \(error)")
            return (nil, false)
        }
    }
    
    /// Updates selected scripts and returns the list of successfully updated scripts
    func updateSelectedScripts(_ selectedScripts: [UserScript], progressCallback: @escaping (Float) -> Void) async -> [UserScript] {
        let totalSteps = Float(selectedScripts.count)
        var completedSteps: Float = 0
        var updatedScripts: [UserScript] = []
        
        for script in selectedScripts {
            let (updatedScript, success) = await fetchAndProcessScript(script)
            if success, let updated = updatedScript {
                updatedScripts.append(updated)
                await ConcurrentLogManager.shared.log("Successfully updated script \(script.name)")
                
                // Update the script in the userScriptManager
                if let manager = userScriptManager {
                    await manager.updateUserScript(updated)
                }
            } else {
                await ConcurrentLogManager.shared.log("Failed to update script \(script.name)")
            }
            completedSteps += 1
            progressCallback(completedSteps / totalSteps)
        }
        
        return updatedScripts
    }
}
