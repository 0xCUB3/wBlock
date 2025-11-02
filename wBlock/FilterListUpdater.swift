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
    
    // Configured URLSession for better resource management
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 0, diskPath: nil) // 2MB memory, no disk cache
        return URLSession(configuration: config)
    }()

    init(loader: FilterListLoader, logManager: ConcurrentLogManager) {
        self.loader = loader
        self.logManager = logManager
    }

    /// Counts effective rules in a given filter list content string.
    private func countRulesInContent(content: String) -> Int {
        var count = 0
        // More efficient than components(separatedBy:) which creates an array
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("!") && !trimmed.hasPrefix("[") && !trimmed.hasPrefix("#") {
                count += 1
            }
        }
        return count
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
                    await ConcurrentLogManager.shared.info(.filterUpdate, "Fetched version for filter", metadata: ["filter": modifiedFilter.name, "version": newVersion])
                } else {
                    await ConcurrentLogManager.shared.error(.filterUpdate, "Failed to fetch version for filter", metadata: ["filter": modifiedFilter.name])
                }
            }

            // --- Update Source Rule Count if needed ---
            // Only attempt to count if the .txt file exists
            if modifiedFilter.sourceRuleCount == nil && loader.filterFileExists(modifiedFilter) {
                if let localContent = loader.readLocalFilterContent(modifiedFilter) {
                    let ruleCount = countRulesInContent(content: localContent)
                    modifiedFilter.sourceRuleCount = ruleCount
                    filterWasModifiedThisIteration = true
                    await ConcurrentLogManager.shared.info(.filterUpdate, "Calculated source rule count for filter", metadata: ["filter": modifiedFilter.name, "ruleCount": "\(ruleCount)"])
                } else {
                    await ConcurrentLogManager.shared.error(.filterUpdate, "Failed to read local content for rule counting", metadata: ["filter": modifiedFilter.name])
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
            let (data, response) = try await urlSession.data(from: filter.url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await ConcurrentLogManager.shared.error(.network, "Failed to fetch version from URL", metadata: ["filter": filter.name, "reason": "Invalid response"])
                return nil
            }
            guard let content = String(data: data, encoding: .utf8) else {
                await ConcurrentLogManager.shared.error(.network, "Unable to parse content from URL", metadata: ["url": filter.url.absoluteString])
                return nil
            }

            // Parse metadata for version
            let metadata = parseMetadata(from: content)
            return metadata.version ?? "Unknown"
        } catch {
            await ConcurrentLogManager.shared.error(.network, "Error fetching version from URL", metadata: ["filter": filter.name, "error": error.localizedDescription])
            return nil
        }
    }

    // Pre-compiled regex patterns for efficiency (compiled once, reused many times)
    private static let sanitizationRegexes: [(regex: NSRegularExpression, replacement: String)] = {
        let patterns: [(pattern: String, replacement: String)] = [
            ("malicious", "suspicious"),
            ("malware", "unwanted software"),
            ("spyware", "tracking software"),
            ("harmful", "unwanted"),
            ("dangerous", "risky")
        ]

        return patterns.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(pattern)\\b",
                options: [.caseInsensitive]
            ) else { return nil }
            return (regex, replacement)
        }
    }()

    /// Sanitizes filter list metadata to remove Apple App Store flagged terminology
    private func sanitizeMetadata(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var sanitized = text
        for (regex, replacement) in Self.sanitizationRegexes {
            let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: replacement
            )
        }

        return sanitized
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

                    // Sanitize flagged terminology
                    let sanitizedValue = sanitizeMetadata(cleanValue)

                    switch key {
                    case "Title":
                        title = sanitizedValue
                    case "Description":
                        description = sanitizedValue
                    case "Version":
                        // Filter out placeholder values like %timestamp% or similar build-time variables
                        if sanitizedValue.contains("%") && (sanitizedValue.contains("timestamp") || sanitizedValue.contains("date")) {
                            version = nil
                        } else {
                            version = sanitizedValue
                        }
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

    func checkForUpdates(filterLists: [FilterList]) async -> [FilterList] {
        var filtersWithUpdates: [FilterList] = []

        await withTaskGroup(of: (FilterList, Bool).self) { group in
            for filter in filterLists {
                if filter.limitExceededReason != nil {
                    continue
                }

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

    /// Checks if a filter has an update by comparing lightweight metadata before falling back to full downloads
    func hasUpdate(for filter: FilterList) async -> Bool {
        do {
            var headRequest = URLRequest(url: filter.url)
            headRequest.httpMethod = "HEAD"

            if let etag = filter.etag, !etag.isEmpty {
                headRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            if let lastModified = filter.serverLastModified, !lastModified.isEmpty {
                headRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }

            let (_, response) = try await urlSession.data(for: headRequest)

            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 304:
                    return false
                case 200:
                    let remoteETag = httpResponse.value(forHTTPHeaderField: "ETag")
                    if let remoteETag, let localETag = filter.etag, remoteETag == localETag {
                        return false
                    }

                    let remoteLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
                    if let remoteLastModified,
                       let localLastModified = filter.serverLastModified,
                       remoteLastModified == localLastModified {
                        return false
                    }

                    // Metadata indicates a potential update; confirm by inspecting content when needed
                    return try await compareRemoteToLocal(filter: filter)
                default:
                    break
                }
            }
        } catch {
            // Some providers reject HEAD or conditional requests; fall back to a direct comparison
            await ConcurrentLogManager.shared.debug(.filterUpdate, "HEAD check failed, falling back to full comparison", metadata: ["filter": filter.name, "error": error.localizedDescription])
        }

        do {
            return try await compareRemoteToLocal(filter: filter)
        } catch {
            await ConcurrentLogManager.shared.error(.filterUpdate, "Error checking update for filter", metadata: ["filter": filter.name, "error": error.localizedDescription])
            return false
        }
    }

    /// Downloads remote content and compares it against the locally cached version
    private func compareRemoteToLocal(filter: FilterList) async throws -> Bool {
        let (data, response) = try await urlSession.data(from: filter.url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let onlineContent = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        if let localContent = loader.readLocalFilterContent(filter) {
            return onlineContent != localContent
        }

        // If we do not have a local copy yet, treat it as needing an update
        return true
    }

    /// Validates if content appears to be a valid filter list
    private func isValidFilterContent(_ content: String) -> Bool {
        let lines = content.components(separatedBy: .newlines)
        var ruleCount = 0
        var hasComments = false

        for line in lines.prefix(100) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Only lines starting with "!" are comments in AdGuard filter syntax
            // Lines starting with "#", "##", "###" etc. are valid CSS selector rules
            if trimmed.hasPrefix("!") {
                hasComments = true
                continue
            }

            if !trimmed.isEmpty && !trimmed.hasPrefix("[") {
                ruleCount += 1
            }
        }

        return ruleCount >= 3 || (hasComments && ruleCount >= 1)
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
                (data, response) = try await urlSession.data(for: request)
            } else {
                (data, response) = try await urlSession.data(from: filter.url)
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await ConcurrentLogManager.shared.error(.network, "Failed to fetch filter - HTTP error", metadata: ["filter": filter.name, "statusCode": "\((response as? HTTPURLResponse)?.statusCode ?? 0)"])
                return false
            }

            guard let content = String(data: data, encoding: .utf8) else {
                await ConcurrentLogManager.shared.error(.network, "Failed to decode filter content", metadata: ["filter": filter.name])
                return false
            }

            guard isValidFilterContent(content) else {
                await ConcurrentLogManager.shared.error(.network, "Downloaded content does not appear to be a valid filter list", metadata: ["filter": filter.name, "contentLength": "\(content.count)"])
                return false
            }

            let metadata = parseMetadata(from: content)
            var updatedFilter = filter
            updatedFilter.version = metadata.version ?? "Unknown"
            if let description = metadata.description, !description.isEmpty {
                updatedFilter.description = description
            }
            updatedFilter.sourceRuleCount = countRulesInContent(content: content)
            updatedFilter.lastUpdated = Date()
            if let httpResponse = response as? HTTPURLResponse {
                updatedFilter.etag = httpResponse.value(forHTTPHeaderField: "ETag")
                updatedFilter.serverLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
            }

            let finalFilter = updatedFilter
            await MainActor.run {
                if let index = filterListManager?.filterLists.firstIndex(where: {$0.id == finalFilter.id}) {
                    filterListManager?.filterLists[index] = finalFilter
                    filterListManager?.objectWillChange.send()
                }
            }

            guard let containerURL = loader.getSharedContainerURL() else {
                await ConcurrentLogManager.shared.error(.system, "Unable to access shared container", metadata: [:])
                return false
            }

            try? content.write(to: containerURL.appendingPathComponent("\(filter.name).txt"), atomically: true, encoding: .utf8)

            return true
        } catch {
            await ConcurrentLogManager.shared.error(.network, "Error fetching filter", metadata: ["filter": filter.name, "error": "\(error)"])
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
            await ConcurrentLogManager.shared.info(.filterUpdate, "Found updates for filters", metadata: ["filters": updatedFilters.map { $0.name }.joined(separator: ", "), "count": "\(updatedFilters.count)"])
        } else {
            await ConcurrentLogManager.shared.info(.filterUpdate, "No updates found for current filters", metadata: [:])
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
                await ConcurrentLogManager.shared.info(.filterUpdate, "Successfully updated filter", metadata: ["filter": filter.name])
            } else {
                await ConcurrentLogManager.shared.error(.filterUpdate, "Failed to update filter", metadata: ["filter": filter.name])
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
            let (data, _) = try await urlSession.data(from: updateURL)
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
            await ConcurrentLogManager.shared.error(.userScript, "Error checking update for script", metadata: ["script": script.name, "error": error.localizedDescription])
            return false
        }
    }
    
    /// Fetches and processes a userscript
    func fetchAndProcessScript(_ script: UserScript) async -> (UserScript?, Bool) {
        guard let downloadURLString = script.downloadURL ?? script.updateURL,
              let downloadURL = URL(string: downloadURLString) else {
            await ConcurrentLogManager.shared.error(.userScript, "No download URL for script", metadata: ["script": script.name])
            return (nil, false)
        }
        
        do {
            let (data, response) = try await urlSession.data(from: downloadURL)
            
            guard let httpResponse = response as? HTTPURLResponse, 
                  httpResponse.statusCode == 200,
                  let content = String(data: data, encoding: .utf8) else {
                await ConcurrentLogManager.shared.error(.network, "Failed to fetch script", metadata: ["script": script.name])
                return (nil, false)
            }
            
            var updatedScript = script
            updatedScript.content = content
            updatedScript.parseMetadata()
            
            return (updatedScript, true)
        } catch {
            await ConcurrentLogManager.shared.error(.network, "Error fetching script", metadata: ["script": script.name, "error": "\(error)"])
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
                await ConcurrentLogManager.shared.info(.userScript, "Successfully updated script", metadata: ["script": script.name])
                
                // Update the script in the userScriptManager
                if let manager = userScriptManager {
                    await manager.updateUserScript(updated)
                }
            } else {
                await ConcurrentLogManager.shared.error(.userScript, "Failed to update script", metadata: ["script": script.name])
            }
            completedSteps += 1
            progressCallback(completedSteps / totalSteps)
        }
        
        return updatedScripts
    }
}
