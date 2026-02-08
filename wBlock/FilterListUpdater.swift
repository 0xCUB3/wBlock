//
//  FilterListUpdater.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Foundation
import wBlockCoreService

final class FilterListUpdater: @unchecked Sendable {
    private let loader: FilterListLoader
    private let logManager: ConcurrentLogManager

    weak var filterListManager: AppFilterManager?
    weak var userScriptManager: UserScriptManager?

    // Configured URLSession for better resource management
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 0, diskPath: nil)  // 2MB memory, no disk cache
        return URLSession(configuration: config)
    }()

    init(loader: FilterListLoader, logManager: ConcurrentLogManager) {
        self.loader = loader
        self.logManager = logManager
    }
    
    private func storedValidators(for filter: FilterList) async -> (etag: String?, lastModified: String?) {
        await ProtobufDataManager.shared.waitUntilLoaded()
        let uuid = filter.id.uuidString
        return await MainActor.run {
            (ProtobufDataManager.shared.getFilterEtag(uuid), ProtobufDataManager.shared.getFilterLastModified(uuid))
        }
    }

    /// Counts effective rules in a given filter list content string.
    private func countRulesInContent(content: String) -> Int {
        var count = 0
        // More efficient than components(separatedBy:) which creates an array
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("!") && !trimmed.hasPrefix("[")
                && !trimmed.hasPrefix("#")
            {
                count += 1
            }
        }
        return count
    }

    /// Updates missing versions for filter lists and returns a dictionary of indices and versions
    func updateMissingVersionsAndCounts(filterLists: [FilterList]) async -> [FilterList] {
        var updatedLists = filterLists  // Create a mutable copy to return

        for (index, filter) in filterLists.enumerated() {
            var modifiedFilter = filter  // Work with a mutable copy of the current filter
            var filterWasModifiedThisIteration = false

            // --- Update Version if needed ---
            if modifiedFilter.version.isEmpty && loader.filterFileExists(modifiedFilter) {
                if let localContent = loader.readLocalFilterContent(modifiedFilter) {
                    let metadata = parseMetadata(from: localContent)
                    if let newVersion = metadata.version {
                        modifiedFilter.version = newVersion
                        filterWasModifiedThisIteration = true
                        await ConcurrentLogManager.shared.info(
                            .filterUpdate, "Loaded local version for filter",
                            metadata: ["filter": modifiedFilter.name, "version": newVersion])
                    }
                }
            }

            // --- Update Source Rule Count if needed ---
            // Only attempt to count if the .txt file exists
            if modifiedFilter.sourceRuleCount == nil && loader.filterFileExists(modifiedFilter) {
                if let localContent = loader.readLocalFilterContent(modifiedFilter) {
                    let ruleCount = countRulesInContent(content: localContent)
                    modifiedFilter.sourceRuleCount = ruleCount
                    filterWasModifiedThisIteration = true
                    await ConcurrentLogManager.shared.info(
                        .filterUpdate, "Calculated source rule count for filter",
                        metadata: ["filter": modifiedFilter.name, "ruleCount": "\(ruleCount)"])
                } else {
                    await ConcurrentLogManager.shared.error(
                        .filterUpdate, "Failed to read local content for rule counting",
                        metadata: ["filter": modifiedFilter.name])
                }
            }

            if filterWasModifiedThisIteration {
                updatedLists[index] = modifiedFilter  // Update the list that will be returned
                // The actual update to filterListManager.filterLists will happen in AppFilterManager
            }
        }
        return updatedLists
    }

    /// Fetches version information from a filter list URL
    func fetchVersionFromURL(for filter: FilterList) async -> String? {
        do {
            let (data, response) = try await urlSession.data(from: filter.url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                await ConcurrentLogManager.shared.error(
                    .network, "Failed to fetch version from URL",
                    metadata: ["filter": filter.name, "reason": "Invalid response"])
                return nil
            }
            guard let content = String(data: data, encoding: .utf8) else {
                await ConcurrentLogManager.shared.error(
                    .network, "Unable to parse content from URL",
                    metadata: ["url": filter.url.absoluteString])
                return nil
            }

            // Parse metadata for version
            let metadata = parseMetadata(from: content)
            return metadata.version ?? "Unknown"
        } catch {
            await ConcurrentLogManager.shared.error(
                .network, "Error fetching version from URL",
                metadata: ["filter": filter.name, "error": error.localizedDescription])
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
            ("dangerous", "risky"),
        ]

        return patterns.compactMap { pattern, replacement in
            guard
                let regex = try? NSRegularExpression(
                    pattern: "\\b\(pattern)\\b",
                    options: [.caseInsensitive]
                )
            else { return nil }
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
    func parseMetadata(from content: String) -> (
        title: String?, description: String?, version: String?
    ) {
        let rawMetadata = FilterListMetadataParser.parse(from: content, maxLines: 120)

        let title =
            rawMetadata.title
            .map { sanitizeMetadata($0.replacingOccurrences(of: "/", with: " & ")) }
        let description =
            rawMetadata.description
            .map { sanitizeMetadata($0.replacingOccurrences(of: "/", with: " & ")) }
        let normalizedVersion =
            rawMetadata.version
            .map { sanitizeMetadata($0.replacingOccurrences(of: "/", with: " & ")) }

        let version: String?
        if let normalizedVersion,
            normalizedVersion.contains("%")
                && (normalizedVersion.contains("timestamp")
                    || normalizedVersion.contains("date"))
        {
            version = nil
        } else {
            version = normalizedVersion
        }

        return (title: title, description: description, version: version)
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
        if let scheme = filter.url.scheme?.lowercased(), scheme != "http" && scheme != "https" {
            // Local / inline user lists don't have remote updates.
            return false
        }
        do {
            let validators = await storedValidators(for: filter)
            var headRequest = URLRequest(url: filter.url, cachePolicy: .reloadIgnoringLocalCacheData)
            headRequest.httpMethod = "HEAD"

            if let etag = validators.etag, !etag.isEmpty {
                headRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            if let lastModified = validators.lastModified, !lastModified.isEmpty {
                headRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }

            let (_, response) = try await urlSession.data(for: headRequest)

            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 304:
                    return false
                case 200:
                    let remoteETag = httpResponse.value(forHTTPHeaderField: "ETag")
                    let remoteLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
                    
                    if let remoteETag,
                       let localETag = validators.etag,
                       !localETag.isEmpty
                    {
                        let changed = remoteETag != localETag
                        if changed {
                            await ConcurrentLogManager.shared.debug(
                                .filterUpdate, "Filter update available (ETag changed)",
                                metadata: ["filter": filter.name]
                            )
                        }
                        return changed
                    }
                    
                    if let remoteLastModified,
                       let localLastModified = validators.lastModified,
                       !localLastModified.isEmpty
                    {
                        let changed = remoteLastModified != localLastModified
                        if changed {
                            await ConcurrentLogManager.shared.debug(
                                .filterUpdate, "Filter update available (Last-Modified changed)",
                                metadata: ["filter": filter.name]
                            )
                        }
                        return changed
                    }
                    
                    // No validators available; confirm by inspecting content when needed
                    return try await compareRemoteToLocal(filter: filter)
                default:
                    break
                }
            }
        } catch {
            // Some providers reject HEAD or conditional requests; fall back to a direct comparison
            await ConcurrentLogManager.shared.debug(
                .filterUpdate, "HEAD check failed, falling back to full comparison",
                metadata: ["filter": filter.name, "error": error.localizedDescription])
        }

        do {
            return try await compareRemoteToLocal(filter: filter)
        } catch {
            await ConcurrentLogManager.shared.error(
                .filterUpdate, "Error checking update for filter",
                metadata: ["filter": filter.name, "error": error.localizedDescription])
            return false
        }
    }

    /// Downloads remote content and compares it against the locally cached version
    private func compareRemoteToLocal(filter: FilterList) async throws -> Bool {
        let request = URLRequest(url: filter.url, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        if let localURL = loader.localFileURL(for: filter),
           let localData = try? Data(contentsOf: localURL) {
            return data != localData
        }

        if filter.isCustom, let containerURL = loader.getSharedContainerURL() {
            // Backward compatibility: legacy custom filters were stored as "<name>.txt".
            let legacyURL = containerURL.appendingPathComponent("\(filter.name).txt")
            if let legacyData = try? Data(contentsOf: legacyURL) {
                return data != legacyData
            }
        }

        // If we do not have a local copy yet, treat it as needing an update
        return true
    }

    /// Validates if content appears to be a valid filter list
    private func isValidFilterContent(_ content: String) -> Bool {
        // Check for DDoS protection pages by looking at the structure, not keywords
        // (filter lists legitimately contain rules with "ddos-guard" etc.)
        let trimmedContent = String(content.prefix(2048)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmedContent.hasPrefix("<!doctype html") || trimmedContent.hasPrefix("<html") {
            // This is an HTML page, not a filter list - likely a DDoS protection/challenge page
            return false
        }

        var ruleCount = 0
        var hasComments = false
        var scannedLines = 0

        content.enumerateLines { line, stop in
            if scannedLines >= 100 {
                stop = true
                return
            }
            scannedLines += 1

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Only lines starting with "!" are comments in AdGuard filter syntax
            // Lines starting with "#", "##", "###" etc. are valid CSS selector rules
            if trimmed.hasPrefix("!") {
                hasComments = true
                return
            }

            if !trimmed.isEmpty && !trimmed.hasPrefix("[") {
                ruleCount += 1
            }
        }

        return ruleCount >= 3 || (hasComments && ruleCount >= 1)
    }

    /// Fetches, processes, and saves a filter list
    func fetchAndProcessFilter(_ filter: FilterList) async -> Bool {
        if let scheme = filter.url.scheme?.lowercased(), scheme != "http" && scheme != "https" {
            // Local / inline user lists are already stored on disk.
            return loader.filterFileExists(filter)
        }
        do {
            let validators = await storedValidators(for: filter)
            
            // Special handling for GitFlic URLs which may be blocked by Cloudflare
            let (data, response): (Data, URLResponse)
            if filter.url.host?.contains("gitflic.ru") == true {
                let request = NetworkRequestFactory.makeGitflicRequest(
                    url: filter.url,
                    etag: validators.etag,
                    lastModified: validators.lastModified,
                    timeout: 30
                )
                (data, response) = try await urlSession.data(for: request)
            } else {
                let request = NetworkRequestFactory.makeConditionalRequest(
                    url: filter.url,
                    etag: validators.etag,
                    lastModified: validators.lastModified,
                    timeout: 30
                )
                (data, response) = try await urlSession.data(for: request)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                await ConcurrentLogManager.shared.error(
                    .network, "Failed to fetch filter - HTTP error",
                    metadata: [
                        "filter": filter.name,
                        "statusCode": "0",
                    ])
                return false
            }
            
            if httpResponse.statusCode == 304 {
                // No changes on the server.
                return true
            }

            guard httpResponse.statusCode == 200 else {
                await ConcurrentLogManager.shared.error(
                    .network, "Failed to fetch filter - HTTP error",
                    metadata: [
                        "filter": filter.name,
                        "statusCode": "\(httpResponse.statusCode)",
                    ])
                return false
            }

            guard let content = String(data: data, encoding: .utf8) else {
                await ConcurrentLogManager.shared.error(
                    .network, "Failed to decode filter content", metadata: ["filter": filter.name])
                return false
            }

            guard isValidFilterContent(content) else {
                await ConcurrentLogManager.shared.error(
                    .network, "Downloaded content does not appear to be a valid filter list",
                    metadata: ["filter": filter.name, "contentLength": "\(content.count)"])
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
            
            let uuid = filter.id.uuidString
            let responseEtag = httpResponse.value(forHTTPHeaderField: "ETag")
            let responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
            updatedFilter.etag = responseEtag
            updatedFilter.serverLastModified = responseLastModified
            
            // Persist validators so update checks can be lightweight across app launches.
            if responseEtag != nil || responseLastModified != nil {
                await ProtobufDataManager.shared.setFilterValidators(
                    uuid,
                    etag: responseEtag,
                    lastModified: responseLastModified
                )
            }

            let finalFilter = updatedFilter
            await MainActor.run {
                if let index = filterListManager?.filterLists.firstIndex(where: {
                    $0.id == finalFilter.id
                }) {
                    filterListManager?.filterLists[index] = finalFilter
                    filterListManager?.objectWillChange.send()
                }
            }

            guard let containerURL = loader.getSharedContainerURL() else {
                await ConcurrentLogManager.shared.error(
                    .system, "Unable to access shared container", metadata: [:])
                return false
            }

            let fileURL =
                loader.localFileURL(for: filter)
                ?? containerURL.appendingPathComponent(loader.filename(for: filter))
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)

            return true
        } catch {
            await ConcurrentLogManager.shared.error(
                .network, "Error fetching filter",
                metadata: ["filter": filter.name, "error": "\(error)"])
            return false
        }
    }

    /// Updates selected filters and returns the list of successfully updated filters
    func updateSelectedFilters(
        _ selectedFilters: [FilterList], progressCallback: @escaping (Float) -> Void
    ) async -> [FilterList] {
        guard !selectedFilters.isEmpty else {
            progressCallback(1.0)
            return []
        }

        let totalSteps = Float(selectedFilters.count)
        #if os(macOS)
        let maxConcurrent = 4
        #else
        let maxConcurrent = 3
        #endif

        var updatedFilters: [FilterList] = []
        var completedSteps: Float = 0
        var iterator = selectedFilters.makeIterator()

        await withTaskGroup(of: (FilterList, Bool).self) { group in
            func startNext() {
                guard let filter = iterator.next() else { return }
                group.addTask {
                    let success = await self.fetchAndProcessFilter(filter)
                    return (filter, success)
                }
            }

            for _ in 0..<min(maxConcurrent, selectedFilters.count) {
                startNext()
            }

            while let (filter, success) = await group.next() {
                if success {
                    updatedFilters.append(filter)
                    await ConcurrentLogManager.shared.info(
                        .filterUpdate, "Successfully updated filter", metadata: ["filter": filter.name])
                } else {
                    await ConcurrentLogManager.shared.error(
                        .filterUpdate, "Failed to update filter", metadata: ["filter": filter.name])
                }
                completedSteps += 1
                progressCallback(completedSteps / totalSteps)
                startNext()
            }
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
            let updateURL = URL(string: updateURLString)
        else {
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
            await ConcurrentLogManager.shared.error(
                .userScript, "Error checking update for script",
                metadata: ["script": script.name, "error": error.localizedDescription])
            return false
        }
    }

    /// Fetches and processes a userscript
    func fetchAndProcessScript(_ script: UserScript) async -> (UserScript?, Bool) {
        guard let downloadURLString = script.downloadURL ?? script.updateURL,
            let downloadURL = URL(string: downloadURLString)
        else {
            await ConcurrentLogManager.shared.error(
                .userScript, "No download URL for script", metadata: ["script": script.name])
            return (nil, false)
        }

        do {
            let (data, response) = try await urlSession.data(from: downloadURL)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200,
                let content = String(data: data, encoding: .utf8)
            else {
                await ConcurrentLogManager.shared.error(
                    .network, "Failed to fetch script", metadata: ["script": script.name])
                return (nil, false)
            }

            var updatedScript = script
            updatedScript.content = content
            updatedScript.parseMetadata()

            return (updatedScript, true)
        } catch {
            await ConcurrentLogManager.shared.error(
                .network, "Error fetching script",
                metadata: ["script": script.name, "error": "\(error)"])
            return (nil, false)
        }
    }

    /// Updates selected scripts and returns the list of successfully updated scripts
    func updateSelectedScripts(
        _ selectedScripts: [UserScript], progressCallback: @escaping (Float) -> Void
    ) async -> [UserScript] {
        guard !selectedScripts.isEmpty else {
            progressCallback(1.0)
            return []
        }

        let totalSteps = Float(selectedScripts.count)
        #if os(macOS)
        let maxConcurrent = 4
        #else
        let maxConcurrent = 3
        #endif

        var completedSteps: Float = 0
        var updatedScripts: [UserScript] = []
        var iterator = selectedScripts.makeIterator()

        await withTaskGroup(of: (UserScript, UserScript?, Bool).self) { group in
            func startNext() {
                guard let script = iterator.next() else { return }
                group.addTask {
                    let (updatedScript, success) = await self.fetchAndProcessScript(script)
                    return (script, updatedScript, success)
                }
            }

            for _ in 0..<min(maxConcurrent, selectedScripts.count) {
                startNext()
            }

            while let (script, updatedScript, success) = await group.next() {
                if success, let updated = updatedScript {
                    updatedScripts.append(updated)
                    await ConcurrentLogManager.shared.info(
                        .userScript, "Successfully updated script", metadata: ["script": script.name])

                    // Update the script in the userScriptManager
                    if let manager = userScriptManager {
                        await manager.updateUserScript(updated)
                    }
                } else {
                    await ConcurrentLogManager.shared.error(
                        .userScript, "Failed to update script", metadata: ["script": script.name])
                }

                completedSteps += 1
                progressCallback(completedSteps / totalSteps)
                startNext()
            }
        }

        return updatedScripts
    }
}
