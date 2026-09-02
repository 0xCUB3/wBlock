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

    /// Body from a successful update check, reused by Update & Apply so the
    /// second pass does not fetch the same list again.
    private struct CachedFilterDownload: Sendable {
        let data: Data
        let sourceURL: URL
        let servedFallback: Bool
        let etag: String?
        let lastModified: String?

        init(from result: FilterListFetchResult) {
            data = result.data
            sourceURL = result.sourceURL
            servedFallback = result.servedFallback
            if result.servedFallback {
                etag = nil
                lastModified = nil
            } else {
                etag = result.response.value(forHTTPHeaderField: "ETag")
                lastModified = result.response.value(forHTTPHeaderField: "Last-Modified")
            }
        }
    }

    private actor PendingFilterDownloads {
        private struct Entry {
            let download: CachedFilterDownload
            let storedAt: Date
        }

        private var entries: [UUID: Entry] = [:]

        func removeAll() {
            entries.removeAll()
        }

        func store(_ id: UUID, download: CachedFilterDownload) {
            entries[id] = Entry(download: download, storedAt: Date())
        }

        func take(_ id: UUID, maxAge: TimeInterval = 15 * 60) -> CachedFilterDownload? {
            guard let entry = entries.removeValue(forKey: id) else { return nil }
            guard Date().timeIntervalSince(entry.storedAt) <= maxAge else { return nil }
            return entry.download
        }
    }

    private let loader: FilterListLoader
    private let pendingDownloads = PendingFilterDownloads()

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
            guard filter.isSelected else { continue }
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

    /// Parses metadata from filter list content
    func parseMetadata(from content: String) -> (
        title: String?, description: String?, version: String?
    ) {
        FilterListContentProcessing.parseMetadata(from: content, sanitize: true)
    }

    /// Progress of a filter check or download pass, reported per finished list so
    /// the UI can show "12/87" instead of a bare percentage.
    struct FilterRefreshProgress: Sendable, Equatable {
        let completed: Int
        let total: Int

        var fraction: Float {
            guard total > 0 else { return 1 }
            return min(1, Float(min(completed, total)) / Float(total))
        }
    }

    func checkForUpdates(
        filterLists: [FilterList],
        progressCallback: (@Sendable (FilterRefreshProgress) async -> Void)? = nil
    ) async -> [FilterList] {
        await pendingDownloads.removeAll()
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
        var filtersWithUpdates: [FilterList] = []
        var checkedCount = 0
        let totalCount = eligibleFilters.count
        await progressCallback?(FilterRefreshProgress(completed: 0, total: totalCount))
        await boundedConcurrentForEach(eligibleFilters, operation: { filter in
            let validators = validatorsByID[filter.id] ?? (nil, nil)
            let hasUpdate = await self.hasUpdateNoMainActor(
                for: filter,
                validators: validators,
                pendingValidatorUpdates: pendingValidatorUpdates
            )
            return hasUpdate ? filter : nil
        }, onResult: { (filter: FilterList?) in
            if let filter { filtersWithUpdates.append(filter) }
            checkedCount += 1
            await progressCallback?(FilterRefreshProgress(completed: checkedCount, total: totalCount))
        })

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
                fallbackURLs: FilterCatalogRemote.fallbacks(for: filter),
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
                await pendingDownloads.store(
                    filter.id, download: CachedFilterDownload(from: result))
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
                metadata: ["filter": filter.name, "error": LogErrorDescriber.describe(error)])
            return false
        }
    }

    private func localDataForComparison(filter: FilterList) -> Data? {
        guard let containerURL = loader.getSharedContainerURL() else { return nil }
        return FilterListContentProcessing.localDataForComparison(
            filter: filter,
            containerURL: containerURL
        )
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
        var stripped: [String] = []
        let processed = FilterListContentProcessing.stripUnknownDirectives(from: content) { directive in
            stripped.append(directive)
        }
        for directive in stripped {
            await ConcurrentLogManager.shared.debug(
                .filterUpdate,
                LocalizedStrings.text("Stripped unknown directive"),
                metadata: ["directive": directive]
            )
        }
        return processed
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
        if let cached = await pendingDownloads.take(filter.id) {
            return await processDownloadedFilter(filter, download: cached)
        }
        do {
            let validators = await storedValidators(for: filter)
            
            let result = try await FilterListFetchChain.fetch(
                session: urlSession, primaryURL: filter.url,
                fallbackURLs: FilterCatalogRemote.fallbacks(for: filter),
                etag: validators.etag, lastModified: validators.lastModified, timeout: 15)
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

            return await processDownloadedFilter(filter, download: CachedFilterDownload(from: result))
        } catch {
            await ConcurrentLogManager.shared.error(
                .network, LocalizedStrings.text("Error fetching filter"),
                metadata: ["filter": filter.name, "error": LogErrorDescriber.describe(error)])
            return .unavailable
        }
    }

    /// Saves a fetched (or previously checked) filter body. Shared by the
    /// review-sheet apply path so the second pass can skip another GET.
    private func processDownloadedFilter(
        _ filter: FilterList,
        download: CachedFilterDownload
    ) async -> FilterFetchResult {
        guard FilterUpdateResponseClassifier.looksLikeFilterListData(download.data) else {
            await ConcurrentLogManager.shared.error(
                .network, LocalizedStrings.text("Ignoring invalid filter response"), metadata: ["filter": filter.name])
            return .unavailable
        }

        let uuid = filter.id.uuidString
        if download.servedFallback {
            await ProtobufDataManager.shared.setFilterValidators(uuid, etag: nil, lastModified: nil)
        }
        let responseEtag = download.etag
        let responseLastModified = download.lastModified
        if !FilterUpdateResponseClassifier.contentDiffers(
            remoteData: download.data,
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

        guard let content = String(data: download.data, encoding: .utf8) else {
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
                listURL: download.sourceURL
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
                metadata: ["filter": filter.name, "error": LogErrorDescriber.describe(error)]
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
    }

    func fetchAndProcessFilter(_ filter: FilterList) async -> Bool {
        await fetchAndProcessFilterResult(filter).succeeded
    }

    private func refreshFilters(
        _ filters: [FilterList],
        progressCallback: @escaping (FilterRefreshProgress) async -> Void
    ) async -> [(FilterList, FilterFetchResult)] {
        guard !filters.isEmpty else {
            await progressCallback(FilterRefreshProgress(completed: 0, total: 0))
            return []
        }

        let total = filters.count
        var resultsByID: [UUID: (FilterList, FilterFetchResult)] = [:]
        // Counts distinct lists that have a result, so the retry pass does not
        // push the counter past the total.
        await progressCallback(FilterRefreshProgress(completed: 0, total: total))

        func runDownloadPass(_ passFilters: [FilterList]) async {
            await boundedConcurrentForEach(passFilters, operation: { filter in
                (filter, await self.fetchAndProcessFilterResult(filter))
            }, onResult: { result in
                resultsByID[result.0.id] = result
                await progressCallback(
                    FilterRefreshProgress(completed: min(resultsByID.count, total), total: total)
                )
            })
        }

        await runDownloadPass(filters)
        let filtersToRetry = filters.filter { resultsByID[$0.id]?.1.succeeded != true }
        if !filtersToRetry.isEmpty, !Task.isCancelled {
            await runDownloadPass(filtersToRetry)
        }
        await progressCallback(FilterRefreshProgress(completed: total, total: total))

        return filters.map { filter in
            resultsByID[filter.id] ?? (filter, .unavailable)
        }
    }

    struct RefreshFiltersResult: Sendable {
        let updated: [FilterList]
        let failedCount: Int
    }

    /// Refreshes filters that need updates and continues even if some downloads fail.
    /// Every list that is verified gets its own check time, so when a run fails
    /// partway a retry resumes with only the lists that were not verified
    /// instead of starting over from the first list.
    func refreshFiltersIfNeeded(
        _ filters: [FilterList],
        progressCallback: @escaping (FilterRefreshProgress) async -> Void
    ) async -> RefreshFiltersResult {
        let (lastSuccessfulCheck, interval) = await refreshFreshnessWindow()
        let lastCheckedByID = await perFilterLastChecked(for: filters)
        let filtersToRefresh = FilterRefreshPlanner.filtersRequiringNetworkRefresh(
            filters,
            fileExists: { loader.filterFileExists($0) },
            lastSuccessfulCheck: lastSuccessfulCheck,
            lastChecked: { lastCheckedByID[$0.id] },
            interval: interval
        )
        guard !filtersToRefresh.isEmpty else {
            await progressCallback(FilterRefreshProgress(completed: 0, total: 0))
            return RefreshFiltersResult(updated: [], failedCount: 0)
        }

        var updated: [FilterList] = []
        var failedCount = 0
        var allSucceeded = true
        var verifiedTimes: [String: Int64] = [:]
        let now = Int64(Date().timeIntervalSince1970)
        for (filter, result) in await refreshFilters(filtersToRefresh, progressCallback: progressCallback) {
            switch result {
            case .updated:
                updated.append(filter)
                verifiedTimes[filter.id.uuidString] = now
            case .unchanged:
                verifiedTimes[filter.id.uuidString] = now
            case .failed:
                failedCount += 1
                allSucceeded = false
            case .unavailable:
                allSucceeded = false
            }
        }
        await ProtobufDataManager.shared.setFilterLastChecked(verifiedTimes)
        let checkedAllExisting = lastSuccessfulCheck.map { Date().timeIntervalSince($0) >= interval } ?? true
        if checkedAllExisting && allSucceeded {
            await markRefreshCheckSuccessful()
        }
        return RefreshFiltersResult(updated: updated, failedCount: failedCount)
    }

    private func perFilterLastChecked(for filters: [FilterList]) async -> [UUID: Date] {
        await ProtobufDataManager.shared.waitUntilLoaded()
        return await MainActor.run {
            var result: [UUID: Date] = [:]
            for filter in filters {
                if let time = ProtobufDataManager.shared.getFilterLastChecked(filter.id.uuidString) {
                    result[filter.id] = Date(timeIntervalSince1970: TimeInterval(time))
                }
            }
            return result
        }
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
        _ selectedFilters: [FilterList],
        progressCallback: @escaping (FilterRefreshProgress) async -> Void
    ) async -> [FilterList] {
        await refreshFilters(selectedFilters, progressCallback: progressCallback).compactMap {
            $0.1.succeeded ? $0.0 : nil
        }
    }

    /// Checks for updates to userscripts and returns those with available updates
    func checkForScriptUpdates(scripts: [UserScript]) async -> [UserScript] {
        let eligibleScripts = scripts.filter {
            !$0.isLocal && $0.isDownloaded && $0.isEligibleForUpdateCheck
        }
        return await boundedConcurrentCompactMap(eligibleScripts) { script in
            let hasUpdate = await self.hasScriptUpdate(for: script)
            return hasUpdate ? script : nil
        }
    }

    /// Checks if a specific userscript has an update available
    private func hasScriptUpdate(for script: UserScript) async -> Bool {
        guard !script.isLocal, script.isDownloaded, script.updatesAutomatically else {
            return false
        }

        let metaURL = script.resolvedMetaURL
        let downloadURL = script.resolvedDownloadURL

        // Phase 1: Try checking metadata URL if available
        if let metaURL = metaURL {
            do {
                let (data, _) = try await urlSession.data(from: metaURL)
                if let onlineContent = String(data: data, encoding: .utf8) {
                    var tempScript = UserScript(name: script.name, content: onlineContent)
                    tempScript.parseMetadata()

                    // If remote version is available, compare versions or treat missing local version as needing update
                    if !tempScript.version.isEmpty {
                        if script.version.isEmpty { return true }
                        return UserScript.isVersionNewer(tempScript.version, than: script.version)
                    }

                    // If the meta URL was the same as the full download URL, compare content directly
                    if metaURL == downloadURL {
                        return onlineContent != script.content
                    }
                }
            } catch {
                await ConcurrentLogManager.shared.error(
                    .userScript, LocalizedStrings.text("Error checking update for script"),
                    metadata: ["script": script.name, "error": LogErrorDescriber.describe(error)])
            }
        }

        // Phase 2: Inconclusive meta check or separate download URL: fall back to full download + content comparison
        guard let downloadURL = downloadURL, downloadURL != metaURL else {
            return false
        }

        do {
            let (data, response) = try await urlSession.data(from: downloadURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let onlineContent = String(data: data, encoding: .utf8) else {
                return false
            }

            var tempScript = UserScript(name: script.name, content: onlineContent)
            tempScript.parseMetadata()

            if !tempScript.version.isEmpty {
                if script.version.isEmpty { return true }
                return UserScript.isVersionNewer(tempScript.version, than: script.version)
            }

            return onlineContent != script.content
        } catch {
            await ConcurrentLogManager.shared.error(
                .userScript, LocalizedStrings.text("Error checking update for script"),
                metadata: ["script": script.name, "error": LogErrorDescriber.describe(error)])
            return false
        }
    }

    /// Fetches and processes a userscript
    func fetchAndProcessScript(_ script: UserScript) async -> (UserScript?, Bool) {
        guard !script.isLocal,
              let downloadURL = script.resolvedDownloadURL
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
                metadata: ["script": script.name, "error": LogErrorDescriber.describe(error)])
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
