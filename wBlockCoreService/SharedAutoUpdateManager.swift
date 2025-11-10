//
//  SharedAutoUpdateManager.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 8/22/25.
//
//  This lightweight manager runs inside extension processes (Safari WebExtension /
//  SFSafariExtensionHandler) to opportunistically check for filter list updates
//  using the shared App Group. When updates are detected it performs a minimal
//  conversion + reload cycle without needing the full UI "applyChanges" flow.
//  It is heavily throttled (default every 6 hours) and designed to minimize
//  data & energy usage:
//    * Conditional requests via If-None-Match / If-Modified-Since when possible
//    * Parallel network checks with TaskGroup
//    * Only performs full conversion if at least one filter actually changed
//
//  NOTE: This intentionally duplicates a subset of logic from AppFilterManager /
//  FilterListUpdater to avoid pulling SwiftUI / app-layer dependencies into
//  extensions. Keep this file pure Foundation + wBlockCoreService.

import Foundation
import os.log
import SafariServices
#if canImport(UIKit)
import UIKit
#endif

/// Actor to ensure we don't run overlapping auto-updates from multiple extension
/// entry points concurrently.
public actor SharedAutoUpdateManager {
    public static let shared = SharedAutoUpdateManager()

    // MARK: - Cached Status for Performance
    /// Public struct to hold auto-update status with named properties for clarity and safety.
    public struct AutoUpdateStatus {
        public let scheduledAt: Date?
        public let remaining: TimeInterval?
        public let intervalHours: Double
        public let lastCheckTime: Date?
        public let lastSuccessful: Date?
        public let isRunning: Bool
        public let isOverdue: Bool

        public init(scheduledAt: Date?, remaining: TimeInterval?, intervalHours: Double, lastCheckTime: Date?, lastSuccessful: Date?, isRunning: Bool, isOverdue: Bool) {
            self.scheduledAt = scheduledAt
            self.remaining = remaining
            self.intervalHours = intervalHours
            self.lastCheckTime = lastCheckTime
            self.lastSuccessful = lastSuccessful
            self.isRunning = isRunning
            self.isOverdue = isOverdue
        }
    }
    private var cachedStatus: AutoUpdateStatus?
    private var lastStatusCheck: Date?
    private let statusCacheTTL: TimeInterval = 5.0 // 5 seconds cache

    // MARK: Configuration Keys
    private let lastCheckKey = "autoUpdateLastCheck" // Double (timeIntervalSince1970) - renamed to lastCheckTime
    private let lastCheckTimeKey = "autoUpdateLastCheckTime" // Double (timeIntervalSince1970) - last time we checked for updates
    private let lastSuccessfulUpdateKey = "autoUpdateLastSuccessful" // Double (timeIntervalSince1970) - last time filters actually changed
    private let nextEligibleKey = "autoUpdateNextEligibleTime" // Double (abs timestamp for next scheduled update)
    private let intervalHoursKey = "autoUpdateIntervalHours" // Double
    private let enabledKey = "autoUpdateEnabled" // Bool
    private let forceNextUpdateKey = "autoUpdateForceNext" // Bool - force update on next trigger
    private let isCurrentlyRunningKey = "autoUpdateIsRunning" // Bool - prevent overlapping runs
    private let runningStateTimestampKey = "autoUpdateIsRunningTimestamp" // Double - timestamp when running flag was set
    private let etagStoreKeyPrefix = "filterEtag_" // + filter UUID
    private let lastModifiedStoreKeyPrefix = "filterLastModified_" // + filter UUID
    private let advancedRulesFilenamePrefix = "advanced_" // + bundleIdentifier + .txt
    private let sharedAutoUpdateLogFilename = "auto_update.log"

    // Staleness threshold: if running flag is set for longer than this, it's considered stuck
    private let runningFlagStalenessThreshold: TimeInterval = 180 // 3 minutes (reduced from 10)

    // Default interval (6 hours) — conservative to limit energy usage
    private let defaultIntervalHours: Double = 6

    private let log = OSLog(subsystem: "wBlockCoreService", category: "SharedAutoUpdate")

    // Configured URLSession for better resource management
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, diskPath: nil) // 4MB memory, no disk cache
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Protobuf Data Access Helpers

    private func getDataManager() async -> ProtobufDataManager {
        await MainActor.run { ProtobufDataManager.shared }
    }

    private func getAutoUpdateEnabled() async -> Bool {
        let manager = await getDataManager()
        return await MainActor.run { manager.autoUpdateEnabled }
    }

    private func getAutoUpdateIntervalHours() async -> Double {
        let manager = await getDataManager()
        return await MainActor.run { manager.autoUpdateIntervalHours }
    }

    private func getAutoUpdateLastCheckTime() async -> Int64 {
        let manager = await getDataManager()
        return await MainActor.run { manager.autoUpdateLastCheckTime }
    }

    private func getAutoUpdateLastSuccessfulTime() async -> Int64 {
        let manager = await getDataManager()
        return await MainActor.run { manager.autoUpdateLastSuccessfulTime }
    }

    private func getAutoUpdateNextEligibleTime() async -> Int64 {
        let manager = await getDataManager()
        return await MainActor.run { manager.autoUpdateNextEligibleTime }
    }

    private func getAutoUpdateForceNext() async -> Bool {
        let manager = await getDataManager()
        return await MainActor.run { manager.autoUpdateForceNext }
    }

    private func getAutoUpdateIsRunning() async -> Bool {
        let manager = await getDataManager()
        return await MainActor.run { manager.autoUpdateIsRunning }
    }

    private func getAutoUpdateRunningSinceTimestamp() async -> Int64 {
        let manager = await getDataManager()
        return await MainActor.run { manager.autoUpdateRunningSinceTimestamp }
    }

    private func getFilterEtag(_ uuid: String) async -> String? {
        let manager = await getDataManager()
        return await MainActor.run { manager.getFilterEtag(uuid) }
    }

    private func getFilterLastModified(_ uuid: String) async -> String? {
        let manager = await getDataManager()
        return await MainActor.run { manager.getFilterLastModified(uuid) }
    }

    // Public entry point invoked by extensions.
    public func maybeRunAutoUpdate(trigger: String, force: Bool = false) async {
        await runIfNeeded(trigger: trigger, force: force)
    }

    /// Returns status about the next eligible auto-update time for UI/logging.
    /// - Returns: AutoUpdateStatus struct containing all scheduling information
    /// Uses 5-second cache to reduce protobuf reads in hot paths (extension triggers)
    public func nextScheduleStatus() async -> AutoUpdateStatus {
        let now = Date()

        // Check cache validity
        if let lastCheck = lastStatusCheck,
           now.timeIntervalSince(lastCheck) < statusCacheTTL,
           let cached = cachedStatus {
            return cached
        }

        // Cache miss - recompute from protobuf
        // Check for and clear stale running flags
        await checkAndClearStaleRunningFlag()

        let interval = await getAutoUpdateIntervalHours()
        let nowTimestamp = now.timeIntervalSince1970
        let isRunning = await getAutoUpdateIsRunning()

        // Get last check time timestamp (when we last attempted an update check)
        let lastCheckTimeInt64 = await getAutoUpdateLastCheckTime()
        let lastCheckTime: Date? = lastCheckTimeInt64 > 0 ? Date(timeIntervalSince1970: TimeInterval(lastCheckTimeInt64)) : nil

        // Get last successful update timestamp (when filters actually changed)
        let lastSuccessfulInt64 = await getAutoUpdateLastSuccessfulTime()
        let lastSuccessful: Date? = lastSuccessfulInt64 > 0 ? Date(timeIntervalSince1970: TimeInterval(lastSuccessfulInt64)) : nil

        let result: AutoUpdateStatus

        let nextEligibleInt64 = await getAutoUpdateNextEligibleTime()
        if nextEligibleInt64 > 0 {
            let nextEligible = TimeInterval(nextEligibleInt64)
            let remaining = max(0, nextEligible - nowTimestamp)
            let isOverdue = remaining == 0 && !isRunning
            result = AutoUpdateStatus(
                scheduledAt: Date(timeIntervalSince1970: nextEligible),
                remaining: remaining,
                intervalHours: interval,
                lastCheckTime: lastCheckTime,
                lastSuccessful: lastSuccessful,
                isRunning: isRunning,
                isOverdue: isOverdue
            )
        } else if let lastCheckTime = lastCheckTime {
            // Fallback: derive from lastCheck if present, but no scheduled time yet
            let lastCheck = lastCheckTime.timeIntervalSince1970
            let theoretical = lastCheck + interval * 3600
            if theoretical <= nowTimestamp { // already due, but no trigger yet
                let isOverdue = !isRunning
                result = AutoUpdateStatus(
                    scheduledAt: Date(timeIntervalSince1970: nowTimestamp),
                    remaining: 0,
                    intervalHours: interval,
                    lastCheckTime: lastCheckTime,
                    lastSuccessful: lastSuccessful,
                    isRunning: isRunning,
                    isOverdue: isOverdue
                )
            } else {
                result = AutoUpdateStatus(
                    scheduledAt: Date(timeIntervalSince1970: theoretical),
                    remaining: theoretical - nowTimestamp,
                    intervalHours: interval,
                    lastCheckTime: lastCheckTime,
                    lastSuccessful: lastSuccessful,
                    isRunning: isRunning,
                    isOverdue: false
                )
            }
        } else {
            // No prior run – return nil schedule
            result = AutoUpdateStatus(
                scheduledAt: nil,
                remaining: nil,
                intervalHours: interval,
                lastCheckTime: lastCheckTime,
                lastSuccessful: lastSuccessful,
                isRunning: isRunning,
                isOverdue: false
            )
        }

        // Update cache
        cachedStatus = result
        lastStatusCheck = now

        return result
    }

    /// Invalidates the status cache (call after state changes)
    private func invalidateStatusCache() {
        cachedStatus = nil
        lastStatusCheck = nil
    }

    /// Forces the next update to run immediately regardless of throttling
    /// Must be called from within actor context to safely invalidate cache
    public func forceNextUpdate() async {
        await MainActor.run {
            Task {
                await ProtobufDataManager.shared.setAutoUpdateForceNext(true)
            }
        }
        invalidateStatusCache()
    }

    /// Clears the cached auto-update window so future runs re-evaluate scheduling.
    public func resetScheduleAfterConfigurationChange() async {
        await MainActor.run {
            Task {
                await ProtobufDataManager.shared.setAutoUpdateNextEligibleTime(0)
            }
        }
        invalidateStatusCache()
    }

    // MARK: - State Management Helpers

    /// Checks if the running flag is stale (stuck) and clears it if necessary.
    /// Returns true if the flag was cleared due to staleness.
    /// Note: Caller should invalidate status cache if this returns true
    private func checkAndClearStaleRunningFlag() async -> Bool {
        let isRunning = await getAutoUpdateIsRunning()
        guard isRunning else {
            return false // Not running, nothing to do
        }

        // Check if we have a timestamp for when the flag was set
        let timestamp = await getAutoUpdateRunningSinceTimestamp()
        guard timestamp > 0 else {
            // No timestamp but flag is set - likely from old version or corruption
            // Clear it to be safe
            os_log("Running flag set without timestamp - clearing potentially stuck state", log: log, type: .info)
            await MainActor.run {
                Task {
                    await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
                }
            }
            appendSharedLog("Cleared stuck running flag (no timestamp)")
            return true
        }

        let now = Date().timeIntervalSince1970
        let age = now - TimeInterval(timestamp)

        if age > runningFlagStalenessThreshold {
            // Flag has been set for too long - clear it
            os_log("Running flag stale (%.1f seconds old, threshold %.1f) - clearing stuck state", log: log, type: .info, age, runningFlagStalenessThreshold)
            await MainActor.run {
                Task {
                    await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
                }
            }
            appendSharedLog("Cleared stale running flag (age: \(Int(age))s, threshold: \(Int(runningFlagStalenessThreshold))s)")
            return true
        }

        return false
    }

    // MARK: - Core Logic
    private func runIfNeeded(trigger: String, force: Bool = false) async {
        let now = Date().timeIntervalSince1970

        // Respect enable flag
        let enabled = await getAutoUpdateEnabled()
        if !enabled {
            return
        }

        // Check for and clear stale running flags
        let wasStale = await checkAndClearStaleRunningFlag()
        if wasStale {
            invalidateStatusCache()
        }

        // Prevent overlapping runs (after staleness check)
        let isRunning = await getAutoUpdateIsRunning()
        if isRunning {
            os_log("Auto-update already running, skipping trigger: %{public}@", log: log, type: .info, trigger)
            return
        }

        let interval = await getAutoUpdateIntervalHours()

        // Check if force flag was set externally
        let forceFlag = await getAutoUpdateForceNext()
        let shouldForce = force || forceFlag

        // Skip throttling if force is true or forceNextUpdateKey is set
        if !shouldForce {
            // New jitter-aware scheduling: prefer nextEligibleTime if present
            let nextEligibleInt64 = await getAutoUpdateNextEligibleTime()
            if nextEligibleInt64 > 0 {
                let nextEligible = TimeInterval(nextEligibleInt64)
                if now < nextEligible {
                    return // Still inside jittered window
                }
            } else {
                // Backward compatibility: if nextEligible not set, fall back to lastCheck logic once
                let lastCheckInt64 = await getAutoUpdateLastCheckTime()
                if lastCheckInt64 > 0 {
                    let lastCheck = TimeInterval(lastCheckInt64)
                    if now - lastCheck < interval * 3600 {
                        return
                    }
                }
            }
        }

        // Clear force flag if it was set
        if forceFlag {
            await MainActor.run {
                Task {
                    await ProtobufDataManager.shared.setAutoUpdateForceNext(false)
                }
            }
        }

        // Mark as running with timestamp and invalidate cache
        let startTimestamp = Date().timeIntervalSince1970
        await MainActor.run {
            Task {
                await ProtobufDataManager.shared.setAutoUpdateIsRunning(true)
            }
        }
        invalidateStatusCache()
        os_log("Auto-update started at %.0f (trigger: %{public}@, forced: %d)", log: log, type: .info, startTimestamp, trigger, shouldForce)

        // Ensure flag is ALWAYS cleared on exit (success, failure, or early return)
        defer {
            let endTimestamp = Date().timeIntervalSince1970
            let duration = endTimestamp - startTimestamp
            Task {
                await MainActor.run {
                    Task {
                        await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
                    }
                }
            }
            invalidateStatusCache()
            os_log("Auto-update completed at %.0f (duration: %.1fs)", log: log, type: .info, endTimestamp, duration)
        }

        // Compute next eligible time (exactly interval hours from now)
        let nextEligibleTime = now + interval * 3600
        await MainActor.run {
            Task {
                await ProtobufDataManager.shared.setAutoUpdateNextEligibleTime(Int64(nextEligibleTime))
                await ProtobufDataManager.shared.setAutoUpdateLastCheckTime(Int64(now))
            }
        }
        appendSharedLog("Auto-update started (trigger: \(trigger), forced: \(shouldForce))")

        do {
            let (allFilters, selectedFilters) = await loadFilterListsFromProtobuf()
            guard !selectedFilters.isEmpty else {
                // Still record check time even though no filters selected
                invalidateStatusCache()
                return
            }

            let updates = try await checkForUpdates(filters: selectedFilters)
            guard !updates.isEmpty else {
                // No updates found - still update check time to show we checked successfully
                invalidateStatusCache()
                appendSharedLog("No updates found - filters are up to date")
                return
            }

            // Only log when updates are actually found
            os_log("Found %d filter updates — applying", log: log, type: .info, updates.count)
            appendSharedLog("Updates found: \(updates.map { $0.name }.joined(separator: ", "))")

            // Fetch & store updated content
            let updatedFilterSet = try await fetchAndStoreFilters(updates)

            // Merge updated filters back into full list model
            var merged = allFilters
            for updated in updatedFilterSet {
                if let idx = merged.firstIndex(where: { $0.id == updated.id }) {
                    merged[idx] = updated
                }
            }

            // Persist metadata (versions, counts)
            await saveFilterListsToProtobuf(merged)

            // Determine impacted categories for partial target reconversion
            let updatedCategorySet = Set(updatedFilterSet.map { $0.category })

            // Re-convert & reload only impacted targets; rebuild engine from per-target stored advanced rules
            try await rebuildAndReload(selectedFilters: merged.filter { $0.isSelected }, updatedCategories: updatedCategorySet)

            // Record successful update
            let successTime = Date().timeIntervalSince1970
            await MainActor.run {
                Task {
                    await ProtobufDataManager.shared.setAutoUpdateLastSuccessfulTime(Int64(successTime))
                }
            }
            invalidateStatusCache()

            appendSharedLog("Auto-update complete")
        } catch {
            os_log("Auto-update failed: %{public}@", log: log, type: .error, String(describing: error))
            appendSharedLog("Auto-update failed: \(error.localizedDescription)")
        }
        // Note: defer block above will clear running flag
    }

    // MARK: - Loading / Saving
    private func loadFilterListsFromDefaults(defaults: UserDefaults) throws -> ([FilterList], [FilterList]) {
        var lists: [FilterList] = []
        if let data = defaults.data(forKey: "filterLists"), let decoded = try? JSONDecoder().decode([FilterList].self, from: data) {
            lists.append(contentsOf: decoded)
        }
        if let customData = defaults.data(forKey: "customFilterLists"), let decodedCustom = try? JSONDecoder().decode([FilterList].self, from: customData) {
            lists.append(contentsOf: decodedCustom)
        }
        // Restore selection state
        for idx in lists.indices {
            let key = "filter_selected_\(lists[idx].id.uuidString)"
            if let sel = defaults.object(forKey: key) as? Bool {
                lists[idx].isSelected = sel
            }
        }
        let selected = lists.filter { $0.isSelected }
        return (lists, selected)
    }

    private func loadFilterListsFromProtobuf() async -> ([FilterList], [FilterList]) {
        // Wait for ProtobufDataManager to finish loading data
        let dataManager = await MainActor.run { ProtobufDataManager.shared }
        while await MainActor.run { dataManager.isLoading } {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let allFilters = await MainActor.run { dataManager.getFilterLists() }
        let selectedFilters = allFilters.filter { $0.isSelected }

        return (allFilters, selectedFilters)
    }

    private func saveFilterListsToProtobuf(_ lists: [FilterList]) async {
        let dataManager = await MainActor.run { ProtobufDataManager.shared }
        await dataManager.updateFilterLists(lists)
    }

    private func saveFilterListsToDefaults(_ lists: [FilterList], defaults: UserDefaults) {
        let defaultLists = lists.filter { $0.category != .custom }
        let customLists = lists.filter { $0.category == .custom }
        if let data = try? JSONEncoder().encode(defaultLists) { defaults.set(data, forKey: "filterLists") }
        if let cdata = try? JSONEncoder().encode(customLists) { defaults.set(cdata, forKey: "customFilterLists") }
        for fl in lists { defaults.set(fl.isSelected, forKey: "filter_selected_\(fl.id.uuidString)") }
    }

    // MARK: - Update Detection
    private func checkForUpdates(filters: [FilterList]) async throws -> [FilterList] {
        var result: [FilterList] = []
        await withTaskGroup(of: (FilterList, Bool).self) { group in
            for f in filters { group.addTask { (f, await self.hasUpdate(for: f)) } }
            for await (f, needs) in group where needs { result.append(f) }
        }
        return result
    }

    private func hasUpdate(for filter: FilterList) async -> Bool {
        // Compare remote signature (ETag/Last-Modified) – fall back to full body diff
        var request = URLRequest(url: filter.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)

        let uuid = filter.id.uuidString
        let etag = await getFilterEtag(uuid)
        let lastModified = await getFilterLastModified(uuid)

        if let etag = etag { request.addValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lm = lastModified { request.addValue(lm, forHTTPHeaderField: "If-Modified-Since") }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 304 { return false } // Not modified via conditional request

            // Update stored validators for later
            if let newEtag = http.value(forHTTPHeaderField: "ETag") {
                await MainActor.run {
                    Task {
                        await ProtobufDataManager.shared.setFilterEtag(uuid, etag: newEtag)
                    }
                }
            }
            if let newLM = http.value(forHTTPHeaderField: "Last-Modified") {
                await MainActor.run {
                    Task {
                        await ProtobufDataManager.shared.setFilterLastModified(uuid, lastModified: newLM)
                    }
                }
            }

            // Compare body with local file if exists
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
                let localURL = containerURL.appendingPathComponent("\(filter.name).txt")
                if FileManager.default.fileExists(atPath: localURL.path),
                   let localData = try? Data(contentsOf: localURL),
                   localData == data { return false }
            }
            // Content differs or no local file — treat as update
            return true
        } catch {
            os_log("Update check error for %{public}@ – %{public}@", log: log, type: .error, filter.name, error.localizedDescription)
            return false
        }
    }

    // MARK: - Fetch & Store
    private func fetchAndStoreFilters(_ filters: [FilterList]) async throws -> [FilterList] {
        var updated: [FilterList] = []
        await withTaskGroup(of: FilterList?.self) { group in
            for filter in filters {
                group.addTask { await self.fetchOne(filter) }
            }
            for await maybe in group { if let f = maybe { updated.append(f) } }
        }
        return updated
    }

    private func fetchOne(_ filter: FilterList) async -> FilterList? {
        do {
            let (data, response) = try await urlSession.data(from: filter.url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            
            // Write data directly to file to avoid keeping large content in memory
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
                let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
                try data.write(to: fileURL, options: .atomic)
            }
            
            // Only parse the beginning for metadata, not the entire content
            guard let content = String(data: data.prefix(8192), encoding: .utf8) else { return nil }
            let meta = parseMetadata(from: content)
            
            // Count rules efficiently without loading full content into memory
            let ruleCount = countRulesInData(data: data)
            
            var updated = filter
            if let version = meta.version, !version.isEmpty { updated.version = version }
            if let desc = meta.description, !desc.isEmpty { updated.description = desc }
            updated.sourceRuleCount = ruleCount
            return updated
        } catch {
            os_log("Fetch error for %{public}@ – %{public}@", log: log, type: .error, filter.name, error.localizedDescription)
            return nil
        }
    }

    // MARK: - Conversion & Reload
    private func rebuildAndReload(selectedFilters: [FilterList], updatedCategories: Set<FilterListCategory>) async throws {
        // Build rules per target using same mapping logic as main app
        #if os(iOS)
        let detectedPlatform: Platform = .iOS
        #else
        let detectedPlatform: Platform = .macOS
        #endif
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: detectedPlatform)
        var advancedRulesSnippets: [String] = []

        for target in targets {
            let targetCategories: [FilterListCategory] = {
                if let secondary = target.secondaryCategory { return [target.primaryCategory, secondary] }
                return [target.primaryCategory]
            }()

            let intersects = !updatedCategories.isDisjoint(with: targetCategories)
            let existingAdvanced = loadStoredAdvancedRules(for: target)

            // Decide if we must reconvert this target
            let mustReconvert: Bool = intersects || existingAdvanced == nil
            if mustReconvert {
                // Rebuild combined raw rules for this target from selected filters
                let filtersForTarget = selectedFilters.filter { targetCategories.contains($0.category) }
                var combined = ""
                if !filtersForTarget.isEmpty, let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
                    for f in filtersForTarget {
                        let fileURL = containerURL.appendingPathComponent("\(f.name).txt")
                        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                            combined += content + "\n"
                        }
                    }
                }
                let conversion = ContentBlockerService.convertFilter(rules: combined.isEmpty ? "" : combined, groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: target.rulesFilename)
                if let adv = conversion.advancedRulesText, !adv.isEmpty {
                    storeAdvancedRules(adv, for: target)
                    advancedRulesSnippets.append(adv)
                } else {
                    // Clear stored file if previously had advanced rules
                    removeStoredAdvancedRules(for: target)
                }
                _ = ContentBlockerService.reloadContentBlocker(withIdentifier: target.bundleIdentifier)
            } else if let existingAdvanced = existingAdvanced, !existingAdvanced.isEmpty {
                // Reuse stored advanced rules without reconversion
                advancedRulesSnippets.append(existingAdvanced)
            }
        }

        if !advancedRulesSnippets.isEmpty {
            ContentBlockerService.buildCombinedFilterEngine(combinedAdvancedRules: advancedRulesSnippets.joined(separator: "\n"), groupIdentifier: GroupIdentifier.shared.value)
        } else {
            ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
        }
    }

    // MARK: - Helpers
    private func countRulesInContent(content: String) -> Int {
        content.split(separator: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && !trimmed.hasPrefix("!") && !trimmed.hasPrefix("[") && !trimmed.hasPrefix("#")
        }.count
    }
    
    private func countRulesInData(data: Data) -> Int {
        var count = 0
        var position = 0
        let chunkSize = 8192
        var remainingLine = ""
        
        // Process data in chunks to avoid loading everything into memory
        while position < data.count {
            let endPosition = min(position + chunkSize, data.count)
            let chunk = data.subdata(in: position..<endPosition)
            
            if let string = String(data: chunk, encoding: .utf8) {
                let fullString = remainingLine + string
                let lines = fullString.components(separatedBy: .newlines)
                
                // Process all lines except the last (which may be incomplete)
                let linesToProcess = position + chunkSize >= data.count ? lines[...] : lines.dropLast()
                
                for line in linesToProcess {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !trimmed.hasPrefix("!") && !trimmed.hasPrefix("[") && !trimmed.hasPrefix("#") {
                        count += 1
                    }
                }
                
                // Keep the incomplete line for next chunk
                remainingLine = position + chunkSize >= data.count ? "" : lines.last ?? ""
            }
            
            position = endPosition
        }
        
        return count
    }

    private func parseMetadata(from content: String) -> (title: String?, description: String?, version: String?) {
        var title: String?; var description: String?; var version: String?
        let patterns: [String: String] = [
            "Title": "^!\\s*Title\\s*:?\\s*(.*)$",
            "Description": "^!\\s*Description\\s*:?\\s*(.*)$",
            "Version": "^!\\s*(?:version|last modified|updated)\\s*:?\\s*(.*)$"
        ]
        for line in content.split(separator: "\n").prefix(80) { // Scan only first 80 lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for (key, pattern) in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: trimmed) {
                    let raw = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
                    let clean = raw.replacingOccurrences(of: "/", with: " & ")
                    switch key {
                    case "Title": title = clean
                    case "Description": description = clean
                    case "Version":
                        // Filter out placeholder values like %timestamp% or similar build-time variables
                        if clean.contains("%") && (clean.lowercased().contains("timestamp") || clean.lowercased().contains("date")) {
                            version = nil
                        } else {
                            version = clean
                        }
                    default: break
                    }
                }
            }
            if title != nil, description != nil, version != nil { break }
        }
        return (title, description, version)
    }

    // MARK: - Advanced Rules Persistence
    private func advancedRulesURL(for target: ContentBlockerTargetInfo) -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else { return nil }
        return containerURL.appendingPathComponent("\(advancedRulesFilenamePrefix)\(target.bundleIdentifier).txt")
    }

    private func storeAdvancedRules(_ text: String, for target: ContentBlockerTargetInfo) {
        guard let url = advancedRulesURL(for: target) else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadStoredAdvancedRules(for target: ContentBlockerTargetInfo) -> String? {
        guard let url = advancedRulesURL(for: target), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func removeStoredAdvancedRules(for target: ContentBlockerTargetInfo) {
        guard let url = advancedRulesURL(for: target), FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Shared Log (File-Based for Extensions)
    private func appendSharedLog(_ line: String) {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else { return }
        let logURL = base.appendingPathComponent(sharedAutoUpdateLogFilename)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let full = "[\(timestamp)] \(line)\n"
        if let data = full.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                do {
                    let handle = try FileHandle(forWritingTo: logURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    // Fallback to direct write if handle fails
                    try? data.write(to: logURL, options: .atomic)
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    // Removed runtime heuristic; compile-time selection is sufficient.
}
