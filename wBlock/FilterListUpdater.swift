//
//  FilterListUpdater.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Foundation
import wBlockCoreService

final class FilterListUpdater: @unchecked Sendable {
    private enum FilterFetchResult {
        case unchanged
        case updated
        case unavailable
        case failed

        var succeeded: Bool {
            switch self {
            case .unchanged, .updated: true
            case .unavailable, .failed: false
            }
        }
    }

    private let loader: FilterListLoader

    weak var filterListManager: AppFilterManager?
    weak var userScriptManager: UserScriptManager?

    // Configured URLSession for better resource management
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 0, diskPath: nil)  // 2MB memory, no disk cache
        return URLSession(configuration: config)
    }()

    init(loader: FilterListLoader) {
        self.loader = loader
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
        FilterList.countRules(in: content)
    }

    /// Updates missing versions for filter lists and returns a dictionary of indices and versions
    func updateMissingVersionsAndCounts(filterLists: [FilterList]) async -> [FilterList] {
        var updatedLists = filterLists  // Create a mutable copy to return

        for (index, filter) in filterLists.enumerated() {
            var modifiedFilter = filter  // Work with a mutable copy of the current filter
            var filterWasModifiedThisIteration = false

            let shouldRead = (modifiedFilter.version.isEmpty || modifiedFilter.sourceRuleCount == nil)
                && loader.filterFileExists(modifiedFilter)
            let localContent = shouldRead ? loader.readLocalFilterContent(modifiedFilter) : nil

            if modifiedFilter.version.isEmpty, let localContent {
                let metadata = parseMetadata(from: localContent)
                if let newVersion = metadata.version {
                    modifiedFilter.version = newVersion
                    filterWasModifiedThisIteration = true
                    await ConcurrentLogManager.shared.info(
                        .filterUpdate, LocalizedStrings.text("Loaded local version for filter"),
                        metadata: ["filter": modifiedFilter.name, "version": newVersion])
                }
            }

            if modifiedFilter.sourceRuleCount == nil, let localContent {
                let ruleCount = countRulesInContent(content: localContent)
                modifiedFilter.sourceRuleCount = ruleCount
                filterWasModifiedThisIteration = true
                await ConcurrentLogManager.shared.info(
                    .filterUpdate, LocalizedStrings.text("Calculated source rule count for filter"),
                    metadata: ["filter": modifiedFilter.name, "ruleCount": "\(ruleCount)"])
            } else if modifiedFilter.sourceRuleCount == nil && shouldRead {
                await ConcurrentLogManager.shared.error(
                    .filterUpdate, LocalizedStrings.text("Failed to read local content for rule counting"),
                    metadata: ["filter": modifiedFilter.name])
            }

            if filterWasModifiedThisIteration {
                updatedLists[index] = modifiedFilter  // Update the list that will be returned
                // The actual update to filterListManager.filterLists will happen in AppFilterManager
            }
        }
        return updatedLists
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
            .map { sanitizeMetadata($0) }

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
        // Pre-fetch all validators on MainActor BEFORE entering the task group
        // to avoid deadlock (MainActor suspends waiting for group, child tasks
        // need MainActor to read validators).
        let eligibleFilters = filterLists
        var validatorsMap: [UUID: (etag: String?, lastModified: String?)] = [:]
        for filter in eligibleFilters {
            validatorsMap[filter.id] = await storedValidators(for: filter)
        }

        // Freeze the preflight map before capturing it in concurrent child tasks.
        let validatorsByID = validatorsMap

        // Collect validator updates to apply after the group completes
        // (writing to ProtobufDataManager requires MainActor).
        let pendingValidatorUpdates = PendingValidatorUpdates()
        // Keep preflight update checks bounded so Apply Changes doesn't burst
        // one URLSession task per selected filter on iOS.
        let filtersWithUpdates = await boundedConcurrentCompactMap(eligibleFilters) { filter in
            let validators = validatorsByID[filter.id] ?? (nil, nil)
            let hasUpdate = await self.hasUpdateNoMainActor(
                for: filter,
                validators: validators,
                pendingValidatorUpdates: pendingValidatorUpdates
            )
            return hasUpdate ? filter : nil
        }

        // Apply deferred validator updates now that we're back on the caller's context
        let updates = await pendingValidatorUpdates.drain()
        if !updates.isEmpty {
            await ProtobufDataManager.shared.setFilterValidators(updates)
        }

        return filtersWithUpdates
    }

    /// Actor-isolated storage for validator updates collected during concurrent checks.
    private actor PendingValidatorUpdates {
        var updates: [String: (etag: String?, lastModified: String?)] = [:]

        func add(uuid: String, etag: String?, lastModified: String?) {
            updates[uuid] = (etag, lastModified)
        }

        func drain() -> [String: (etag: String?, lastModified: String?)] {
            let result = updates
            updates.removeAll()
            return result
        }
    }

    /// Like hasUpdate but avoids MainActor calls inside the task group.
    /// Validators are passed in pre-fetched, and validator writes are deferred.
    private func hasUpdateNoMainActor(
        for filter: FilterList,
        validators: (etag: String?, lastModified: String?),
        pendingValidatorUpdates: PendingValidatorUpdates
    ) async -> Bool {
        guard filter.isRemoteURL else { return false }
        do {
            let result = try await FilterListFetchChain.fetch(
                session: urlSession, primaryURL: filter.url,
                fallbackURLs: FilterCatalogRemote.cached()?.fallbacks(for: filter) ?? FilterListURLMirror.fallbackURLs(for: filter.url),
                etag: validators.etag, lastModified: validators.lastModified, timeout: 12)
            let data = result.data
            let httpResponse = result.response
            let localData = localDataForComparison(filter: filter)
            let responseStatus = FilterUpdateResponseClassifier.classify(
                statusCode: httpResponse.statusCode, responseData: data, localData: localData)

            if result.servedFallback {
                await pendingValidatorUpdates.add(
                    uuid: filter.id.uuidString, etag: nil, lastModified: nil)
            }

            switch responseStatus {
            case .notModified:
                return false
            case .updatedContent:
                return true
            case .unchangedContent:
                // A successful primary response may refresh its validators.
                guard !result.servedFallback else { return false }
                let responseEtag = httpResponse.value(forHTTPHeaderField: "ETag")
                let responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")
                if responseEtag != nil || responseLastModified != nil {
                    await pendingValidatorUpdates.add(
                        uuid: filter.id.uuidString,
                        etag: responseEtag,
                        lastModified: responseLastModified
                    )
                }
                return false
            case .invalidContent:
                await ConcurrentLogManager.shared.debug(
                    .filterUpdate, LocalizedStrings.text("Skipping update signal due to non-filter response body"),
                    metadata: ["filter": filter.name]
                )
                return false
            case .unexpectedStatus:
                throw URLError(.badServerResponse)
            @unknown default:
                throw URLError(.badServerResponse)
            }
        } catch {
            await ConcurrentLogManager.shared.debug(
                .filterUpdate, LocalizedStrings.text("Conditional check failed"),
                metadata: ["filter": filter.name, "error": error.localizedDescription])
            return false
        }
    }

    /// Original hasUpdate kept for non-concurrent callers (e.g. auto-update).
    func hasUpdate(for filter: FilterList) async -> Bool {
        let validators = await storedValidators(for: filter)
        let updates = PendingValidatorUpdates()
        let result = await hasUpdateNoMainActor(for: filter, validators: validators, pendingValidatorUpdates: updates)
        let pending = await updates.drain()
        if !pending.isEmpty {
            await ProtobufDataManager.shared.setFilterValidators(pending)
        }
        return result
    }

    private func localDataForComparison(filter: FilterList) -> Data? {
        guard let containerURL = loader.getSharedContainerURL(),
              let localURL = ContentBlockerIncrementalCache.existingLocalFileURL(
                  for: filter,
                  containerURL: containerURL
              ) else { return nil }
        return try? Data(contentsOf: localURL)
    }

    /// Validates if content appears to be a valid filter list.
    private func isValidFilterContent(_ content: String) -> Bool {
        FilterListContentValidator.appearsToBeFilterList(content)
    }

    /// Strips unknown `!#` directives from downloaded filter content.
    /// Directives used by preprocessing and Safari content blocker affinity are preserved.
    /// Unknown directives (for example `!#diff-path`) are removed and logged.
    /// Comment lines such as `!##example` are preserved.
    private func stripUnknownDirectives(from content: String) async -> String {
        var result: [String] = []

        for line in content.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let originalLine = String(line)

            guard FilterDirectivePolicy.shouldStripUnsupportedDirective(trimmed) else {
                result.append(originalLine)
                continue
            }

            await ConcurrentLogManager.shared.debug(
                .filterUpdate,
                LocalizedStrings.text("Stripped unknown directive"),
                metadata: ["directive": String(trimmed.prefix(60))]
            )
            // Do NOT append — line is stripped from output
        }

        return result.joined(separator: "\n")
    }

    /// Fetches, processes, and saves a filter list.
    private func fetchAndProcessFilterResult(_ filter: FilterList) async -> FilterFetchResult {
        if !filter.isRemoteURL {
            // Local / inline user lists are already stored on disk.
            return loader.filterFileExists(filter) ? .unchanged : .failed
        }
        await MainActor.run {
            filterListManager?.applyProgressViewModel.updateCurrentFilter(filter.name)
        }
        do {
            let validators = await storedValidators(for: filter)
            
            let result = try await FilterListFetchChain.fetch(
                session: urlSession, primaryURL: filter.url,
                fallbackURLs: FilterCatalogRemote.cached()?.fallbacks(for: filter) ?? FilterListURLMirror.fallbackURLs(for: filter.url),
                etag: validators.etag, lastModified: validators.lastModified, timeout: 15)
            let data = result.data
            let httpResponse = result.response

            if httpResponse.statusCode == 304 {
                // No changes on the server.
                return .unchanged
            }

            guard httpResponse.statusCode == 200 else {
                await ConcurrentLogManager.shared.error(
                    .network, LocalizedStrings.text("Failed to fetch filter - HTTP error"),
                    metadata: [
                        "filter": filter.name,
                        "statusCode": "\(httpResponse.statusCode)",
                    ])
                return .unavailable
            }

            guard FilterUpdateResponseClassifier.looksLikeFilterListData(data) else {
                await ConcurrentLogManager.shared.error(
                    .network, LocalizedStrings.text("Ignoring invalid filter response"), metadata: ["filter": filter.name])
                return .unavailable
            }

            let uuid = filter.id.uuidString
            if result.servedFallback {
                await ProtobufDataManager.shared.setFilterValidators(uuid, etag: nil, lastModified: nil)
            }
            let responseEtag = result.servedFallback ? nil : httpResponse.value(forHTTPHeaderField: "ETag")
            let responseLastModified = result.servedFallback ? nil : httpResponse.value(forHTTPHeaderField: "Last-Modified")
            if !FilterUpdateResponseClassifier.contentDiffers(
                remoteData: data,
                localData: localDataForComparison(filter: filter)
            ) {
                if responseEtag != nil || responseLastModified != nil {
                    await ProtobufDataManager.shared.setFilterValidators(
                        uuid,
                        etag: responseEtag,
                        lastModified: responseLastModified
                    )
                }
                return .unchanged
            }

            guard let content = String(data: data, encoding: .utf8) else {
                await ConcurrentLogManager.shared.error(
                    .network, LocalizedStrings.text("Failed to decode filter content"), metadata: ["filter": filter.name])
                return .failed
            }

            // Strip unknown !# directives before validation and saving while preserving preprocessing and affinity directives.
            let processedContent = await stripUnknownDirectives(from: content)

            // Measure the pre-expansion rule count (before !#include resolution).
            let rawCount = countRulesInContent(content: processedContent)

            // Preprocess: expand !#include directives and evaluate !#if conditionals.
            // Skip for built-in optimized lists — they are already pre-expanded.
            let preprocessed: String
            if filter.isOptimizedBuiltin {
                preprocessed = processedContent
            } else {
                let filterName = filter.name
                let preprocessor = FilterPreprocessor(
                    urlSession: urlSession,
                    onFetchError: { subURL, statusCode in
                        let statusStr = statusCode.map { "\($0)" } ?? "network error"
                        await ConcurrentLogManager.shared.warning(
                            .filterUpdate,
                            LocalizedStrings.text("!#include fetch failed"),
                            metadata: [
                                "filter": filterName,
                                "subURL": subURL.absoluteString,
                                "status": statusStr,
                            ]
                        )
                    }
                )
                preprocessed = await preprocessor.preprocess(
                    content: processedContent,
                    listURL: result.sourceURL
                )
            }

            guard isValidFilterContent(preprocessed) else {
                await ConcurrentLogManager.shared.error(
                    .network, LocalizedStrings.text("Downloaded content does not appear to be a valid filter list"),
                    metadata: ["filter": filter.name, "contentLength": "\(preprocessed.count)"])
                return .failed
            }

            let metadata = parseMetadata(from: preprocessed)
            var updatedFilter = filter
            if filter.isCustom, !filter.hasUserProvidedName, let title = metadata.title, !title.isEmpty {
                updatedFilter.name = title
            }
            updatedFilter.version = metadata.version ?? "Unknown"
            if let description = metadata.description, !description.isEmpty {
                updatedFilter.description = description
            }
            updatedFilter.sourceRuleCount = countRulesInContent(content: preprocessed)
            updatedFilter.rawSourceRuleCount = rawCount
            updatedFilter.lastUpdated = Date()
            
            updatedFilter.etag = responseEtag
            updatedFilter.serverLastModified = responseLastModified
            
            guard let containerURL = loader.getSharedContainerURL() else {
                await ConcurrentLogManager.shared.error(
                    .system, LocalizedStrings.text("Unable to access shared container"), metadata: [:])
                return .failed
            }

            let fileURL = containerURL.appendingPathComponent(
                ContentBlockerIncrementalCache.localFilename(for: filter)
            )
            do {
                try preprocessed.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                await ConcurrentLogManager.shared.error(
                    .system,
                    LocalizedStrings.text("Failed to save downloaded filter"),
                    metadata: ["filter": filter.name, "error": error.localizedDescription]
                )
                return .failed
            }

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
                    // Apply converts the captured snapshot. Preserve live user
                    // configuration changed while the download was in flight.
                    var merged = finalFilter
                    let current = filterListManager!.filterLists[index]
                    merged.name = current.name
                    merged.url = current.url
                    merged.category = current.category
                    merged.isCustom = current.isCustom
                    merged.isSelected = current.isSelected
                    merged.hasUserProvidedName = current.hasUserProvidedName
                    merged.description = current.description
                    filterListManager?.filterLists[index] = merged
                    filterListManager?.objectWillChange.send()
                }
            }

            return .updated
        } catch {
            await ConcurrentLogManager.shared.error(
                .network, LocalizedStrings.text("Error fetching filter"),
                metadata: ["filter": filter.name, "error": "\(error)"])
            return .unavailable
        }
    }

    func fetchAndProcessFilter(_ filter: FilterList) async -> Bool {
        await fetchAndProcessFilterResult(filter).succeeded
    }

    private func refreshFilters(
        _ filters: [FilterList],
        progressCallback: @escaping (Float) async -> Void
    ) async -> [(FilterList, FilterFetchResult)] {
        guard !filters.isEmpty else {
            await progressCallback(1)
            return []
        }

        let totalSteps = Float(filters.count)
        var results: [(FilterList, FilterFetchResult)] = []

        await boundedConcurrentForEach(filters, operation: { filter in
            (filter, await self.fetchAndProcessFilterResult(filter))
        }, onResult: { result in
            results.append(result)
            await progressCallback(Float(results.count) / totalSteps)
        })

        return results
    }

    struct RefreshFiltersResult: Sendable {
        let updated: [FilterList]
        let failedCount: Int
    }

    /// Refreshes filters that need updates and continues even if some downloads fail.
    func refreshFiltersIfNeeded(
        _ filters: [FilterList],
        progressCallback: @escaping (Float) async -> Void
    ) async -> RefreshFiltersResult {
        let (lastSuccessfulCheck, interval) = await refreshFreshnessWindow()
        let filtersToRefresh = FilterRefreshPlanner.filtersRequiringNetworkRefresh(
            filters,
            fileExists: { loader.filterFileExists($0) },
            lastSuccessfulCheck: lastSuccessfulCheck,
            interval: interval
        )
        guard !filtersToRefresh.isEmpty else {
            await progressCallback(1)
            return RefreshFiltersResult(updated: [], failedCount: 0)
        }

        var updated: [FilterList] = []
        var failedCount = 0
        var allSucceeded = true
        for (filter, result) in await refreshFilters(filtersToRefresh, progressCallback: progressCallback) {
            switch result {
            case .updated:
                updated.append(filter)
            case .unchanged:
                break
            case .failed:
                failedCount += 1
                allSucceeded = false
            case .unavailable:
                allSucceeded = false
            }
        }
        let checkedAllExisting = lastSuccessfulCheck.map { Date().timeIntervalSince($0) >= interval } ?? true
        if checkedAllExisting && allSucceeded {
            await markRefreshCheckSuccessful()
        }
        return RefreshFiltersResult(updated: updated, failedCount: failedCount)
    }

    private func refreshFreshnessWindow() async -> (Date?, TimeInterval) {
        await ProtobufDataManager.shared.waitUntilLoaded()
        return await MainActor.run {
            let last = ProtobufDataManager.shared.autoUpdateLastSuccessfulTime
            let hours = ProtobufDataManager.shared.autoUpdateIntervalHours
            let intervalHours = hours.isFinite && hours > 0 ? min(max(hours, 1), 24 * 7) : 6
            let lastDate = last > 0 ? Date(timeIntervalSince1970: TimeInterval(last)) : nil
            return (lastDate, intervalHours * 3600)
        }
    }

    private func markRefreshCheckSuccessful() async {
        await ProtobufDataManager.shared.waitUntilLoaded()
        await ProtobufDataManager.shared.setAutoUpdateLastSuccessfulTime(Int64(Date().timeIntervalSince1970))
    }

    /// Updates selected filters and returns the list of successfully updated filters
    func updateSelectedFilters(
        _ selectedFilters: [FilterList], progressCallback: @escaping (Float) async -> Void
    ) async -> [FilterList] {
        await refreshFilters(selectedFilters, progressCallback: progressCallback).compactMap {
            $0.1.succeeded ? $0.0 : nil
        }
    }

    /// Checks for updates to userscripts and returns those with available updates
    func checkForScriptUpdates(scripts: [UserScript]) async -> [UserScript] {
        let eligibleScripts = scripts.filter {
            !$0.isLocal && $0.isDownloaded && $0.updateURL != nil && $0.updatesAutomatically
        }
        return await boundedConcurrentCompactMap(eligibleScripts) { script in
            let hasUpdate = await self.hasScriptUpdate(for: script)
            return hasUpdate ? script : nil
        }
    }

    /// Checks if a specific userscript has an update available
    private func hasScriptUpdate(for script: UserScript) async -> Bool {
        guard !script.isLocal,
              let updateURLString = script.updateURL,
            let updateURL = URL(string: updateURLString)
        else {
            return false
        }

        do {
            let (data, _) = try await urlSession.data(from: updateURL)
            guard let onlineContent = String(data: data, encoding: .utf8) else {
                return false
            }

            var tempScript = UserScript(name: script.name, content: onlineContent)
            tempScript.parseMetadata()

            // Compare versions numerically (remote must be strictly greater)
            if !tempScript.version.isEmpty && !script.version.isEmpty {
                return UserScript.isVersionNewer(tempScript.version, than: script.version)
            }

            // @updateURL may point to .meta.js (metadata only). Content comparison
            // against a meta-only response would always return true, so if we can't
            // compare versions from a meta source, we can't determine update status.
            let isMeta = updateURLString.hasSuffix(".meta.js")
            if isMeta {
                return false
            }

            // Full script URL: fall back to content comparison
            return onlineContent != script.content
        } catch {
            await ConcurrentLogManager.shared.error(
                .userScript, LocalizedStrings.text("Error checking update for script"),
                metadata: ["script": script.name, "error": error.localizedDescription])
            return false
        }
    }

    /// Fetches and processes a userscript
    func fetchAndProcessScript(_ script: UserScript) async -> (UserScript?, Bool) {
        guard !script.isLocal,
              let downloadURLString = script.downloadURL ?? script.updateURL,
            let downloadURL = URL(string: downloadURLString)
        else {
            await ConcurrentLogManager.shared.error(
                .userScript, LocalizedStrings.text("No download URL for script"), metadata: ["script": script.name])
            return (nil, false)
        }

        do {
            let (data, response) = try await urlSession.data(from: downloadURL)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200,
                let content = String(data: data, encoding: .utf8)
            else {
                await ConcurrentLogManager.shared.error(
                    .network, LocalizedStrings.text("Failed to fetch script"), metadata: ["script": script.name])
                return (nil, false)
            }

            var updatedScript = script
            updatedScript.content = content
            updatedScript.parseMetadata()

            return (updatedScript, true)
        } catch {
            await ConcurrentLogManager.shared.error(
                .network, LocalizedStrings.text("Error fetching script"),
                metadata: ["script": script.name, "error": "\(error)"])
            return (nil, false)
        }
    }

    /// Updates selected scripts and returns the list of successfully updated scripts
    func updateSelectedScripts(
        _ selectedScripts: [UserScript], progressCallback: @escaping (Float) async -> Void
    ) async -> [UserScript] {
        guard !selectedScripts.isEmpty else {
            await progressCallback(1.0)
            return []
        }

        let scriptsToUpdate = selectedScripts.filter { !$0.isLocal && $0.updatesAutomatically }
        guard !scriptsToUpdate.isEmpty else {
            await progressCallback(1.0)
            return []
        }
        let totalSteps = Float(scriptsToUpdate.count)
        #if os(macOS)
        let maxConcurrent = 4
        #else
        let maxConcurrent = 3
        #endif

        var completedSteps: Float = 0
        var updatedScripts: [UserScript] = []

        await boundedConcurrentForEach(scriptsToUpdate, maxConcurrent: maxConcurrent, operation: { script in
            let (updatedScript, success) = await self.fetchAndProcessScript(script)
            return (script, updatedScript, success)
        }, onResult: { (script, updatedScript, success) in
            if success, let updated = updatedScript {
                updatedScripts.append(updated)
                await ConcurrentLogManager.shared.info(
                    .userScript, LocalizedStrings.text("Successfully updated script"), metadata: ["script": script.name])

                if let manager = userScriptManager {
                    await manager.updateUserScript(updated)
                }
            } else {
                await ConcurrentLogManager.shared.error(
                    .userScript, LocalizedStrings.text("Failed to update script"), metadata: ["script": script.name])
            }

            completedSteps += 1
            await progressCallback(completedSteps / totalSteps)
        })

        return updatedScripts
    }
}
