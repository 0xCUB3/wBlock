//
//  SharedAutoUpdateManager.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 8/22/25.
//
//  This manager coordinates auto-update checks and rebuilds using the shared
//  App Group state. Heavy conversion/reload work is intentionally run from the
//  app / background task contexts (not extension processes) to avoid
//  RunningBoard termination while extensions are being suspended.
//  It is heavily throttled (default every 6 hours) and designed to minimize
//  data & energy usage:
//    * Conditional requests via If-None-Match / If-Modified-Since when possible
//    * Parallel network checks with TaskGroup
//    * Only performs full conversion if at least one filter actually changed
//
//  NOTE: This intentionally duplicates a subset of logic from AppFilterManager /
//  FilterListUpdater to avoid pulling SwiftUI / app-layer dependencies into the
//  shared service layer. Keep this file pure Foundation + wBlockCoreService.

import Foundation
import CryptoKit
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

    private let sharedAutoUpdateLogFilename = "auto_update.log"

    // Staleness threshold: if running flag is set for longer than this, it's considered stuck
    private let runningFlagStalenessThreshold: TimeInterval = 180 // 3 minutes (reduced from 10)

    // Default interval (6 hours) — conservative to limit energy usage
    private let defaultIntervalHours: Double = 6

    private let log = OSLog(subsystem: "wBlockCoreService", category: "SharedAutoUpdate")
    private static let isAppExtensionProcess: Bool = {
        let mainBundle = Bundle.main
        if mainBundle.bundleURL.pathExtension == "appex" {
            return true
        }
        return mainBundle.object(forInfoDictionaryKey: "NSExtension") != nil
    }()
    private var hasLoggedExtensionSafeModeNotice = false

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

    @inline(__always)
    private func throwIfCancelled() throws {
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    private enum AutoUpdateError: Error {
        case sharedContainerUnavailable
        case contentBlockerReloadFailed(identifier: String)
    }

    private struct ReloadAttemptResult {
        let success: Bool
        let attempts: Int
        let durationMs: Int
    }

    private struct RebuildTargetMetrics {
        let targetName: String
        let cacheHit: Bool
        let inputWriteMs: Int
        let inputBytes: Int64
        let conversionMs: Int
        let reloadMs: Int
        let reloadAttempts: Int
        let safariRules: Int
    }

    private struct RebuildAndReloadSummary {
        let targetCount: Int
        let cacheHits: Int
        let cacheMisses: Int
        let safariRulesTotal: Int
        let inputWriteDurationMs: Int
        let inputBytesTotal: Int64
        let conversionDurationMs: Int
        let reloadDurationMs: Int
        let totalReloadAttempts: Int
        let slowestWriteTarget: String
        let slowestTarget: String
    }

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
        let interval = await MainActor.run { manager.autoUpdateIntervalHours }
        guard interval.isFinite else { return defaultIntervalHours }
        guard interval > 0 else { return defaultIntervalHours }
        return min(max(interval, 1.0), 24.0 * 7.0)
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

    private func getDisabledSites() async -> [String] {
        let manager = await getDataManager()
        return await MainActor.run { manager.disabledSites }
    }

    private func autoUpdateUserScriptsIfNeeded() async -> (updated: Int, failed: Int) {
        let manager = await MainActor.run { UserScriptManager.shared }
        let result = await manager.autoUpdateEnabledUserScripts()
        return (result.updated, result.failed)
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

        await ProtobufDataManager.shared.waitUntilLoaded()

        // Check cache validity
        if let lastCheck = lastStatusCheck,
           now.timeIntervalSince(lastCheck) < statusCacheTTL,
           let cached = cachedStatus {
            return cached
        }

        // Cache miss - recompute from protobuf
        // Check for and clear stale running flags
        _ = await checkAndClearStaleRunningFlag()

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
        await ProtobufDataManager.shared.setAutoUpdateForceNext(true)
        invalidateStatusCache()
    }

    /// Clears the cached auto-update window so future runs re-evaluate scheduling.
    public func resetScheduleAfterConfigurationChange() async {
        await ProtobufDataManager.shared.setAutoUpdateNextEligibleTime(0)
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
            await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
            appendSharedLog("Cleared stuck running flag (no timestamp)")
            return true
        }

        let now = Date().timeIntervalSince1970
        let age = now - TimeInterval(timestamp)

        if age > runningFlagStalenessThreshold {
            // Flag has been set for too long - clear it
            os_log("Running flag stale (%.1f seconds old, threshold %.1f) - clearing stuck state", log: log, type: .info, age, runningFlagStalenessThreshold)
            await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
            appendSharedLog("Cleared stale running flag (age: \(Int(age))s, threshold: \(Int(runningFlagStalenessThreshold))s)")
            return true
        }

        return false
    }

    // MARK: - Core Logic
    private func runIfNeeded(trigger: String, force: Bool = false) async {
        await ProtobufDataManager.shared.waitUntilLoaded()

        if Self.isAppExtensionProcess {
            if !hasLoggedExtensionSafeModeNotice {
                os_log(
                    "Skipping auto-update run in app extension process (trigger: %{public}@)",
                    log: log,
                    type: .info,
                    trigger
                )
                appendSharedLog(
                    "Auto-update safe mode: skipped work inside extension. Updates run when the app is active or via background tasks."
                )
                hasLoggedExtensionSafeModeNotice = true
            }
            appendSkipTelemetry(trigger: trigger, reason: "extension_safe_mode")
            return
        }

        if Task.isCancelled {
            appendSkipTelemetry(trigger: trigger, reason: "task_cancelled_preflight")
            return
        }

        let now = Date().timeIntervalSince1970

        // Respect enable flag
        let enabled = await getAutoUpdateEnabled()
        if !enabled {
            appendSkipTelemetry(trigger: trigger, reason: "auto_update_disabled")
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
            appendSkipTelemetry(trigger: trigger, reason: "already_running")
            return
        }

        let interval = await getAutoUpdateIntervalHours()

        // Check if force flag was set externally
        let forceFlag = await getAutoUpdateForceNext()
        let shouldForce = force || forceFlag

        // Skip throttling if the current trigger is forced or forceNext flag is set
        if !shouldForce {
            // New jitter-aware scheduling: prefer nextEligibleTime if present
            let nextEligibleInt64 = await getAutoUpdateNextEligibleTime()
            if nextEligibleInt64 > 0 {
                let nextEligible = TimeInterval(nextEligibleInt64)
                if now < nextEligible {
                    let remainingSeconds = Int(max(0, nextEligible - now))
                    appendSkipTelemetry(
                        trigger: trigger,
                        reason: "throttled_not_eligible",
                        extra: ["remaining_seconds": "\(remainingSeconds)"]
                    )
                    return // Still inside jittered window
                }
            } else {
                // Backward compatibility: if nextEligible not set, fall back to lastCheck logic once
                let lastCheckInt64 = await getAutoUpdateLastCheckTime()
                if lastCheckInt64 > 0 {
                    let lastCheck = TimeInterval(lastCheckInt64)
                    if now - lastCheck < interval * 3600 {
                        let remainingSeconds = Int(max(0, interval * 3600 - (now - lastCheck)))
                        appendSkipTelemetry(
                            trigger: trigger,
                            reason: "throttled_legacy_interval",
                            extra: ["remaining_seconds": "\(remainingSeconds)"]
                        )
                        return
                    }
                }
            }
        }

        // Clear force flag if it was set
        if forceFlag {
            await ProtobufDataManager.shared.setAutoUpdateForceNext(false)
        }

        // Mark as running with timestamp and invalidate cache
        let startTimestamp = Date().timeIntervalSince1970
        await ProtobufDataManager.shared.setAutoUpdateIsRunning(true)
        let heartbeatTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)  // 60s
                if Task.isCancelled { break }
                // Refresh the running timestamp so long conversions aren't considered "stuck".
                await ProtobufDataManager.shared.refreshAutoUpdateRunningTimestamp()
            }
        }
        defer { heartbeatTask.cancel() }
        invalidateStatusCache()
        os_log("Auto-update started at %.0f (trigger: %{public}@, forced: %d)", log: log, type: .info, startTimestamp, trigger, shouldForce)

        await ProtobufDataManager.shared.setAutoUpdateLastCheckTime(Int64(now))
        // Persist the running flag + check timestamp immediately so other processes don't start overlapping runs.
        await ProtobufDataManager.shared.saveDataImmediately()
        appendSharedLog(
            "Auto-update started: trigger=\(trigger), forced=\(shouldForce), intervalHours=\(String(format: "%.1f", interval))"
        )
        appendTelemetry(
            "run_start",
            fields: [
                "trigger": trigger,
                "forced": shouldForce ? "true" : "false",
                "interval_hours": String(format: "%.1f", interval)
            ]
        )

        // Use do-catch to ensure cleanup always runs
        do {
            try throwIfCancelled()
            let (allFilters, selectedFilters) = await loadFilterListsFromProtobuf()
            try throwIfCancelled()
            guard !selectedFilters.isEmpty else {
                // Still auto-update enabled userscripts even if no filters are selected.
                let scriptsResult = await autoUpdateUserScriptsIfNeeded()
                if scriptsResult.updated > 0 {
                    await ProtobufDataManager.shared.setAutoUpdateLastSuccessfulTime(Int64(Date().timeIntervalSince1970))
                }

                let completionTime = Date().timeIntervalSince1970
                let nextEligibleTime = completionTime + interval * 3600
                await ProtobufDataManager.shared.setAutoUpdateNextEligibleTime(Int64(nextEligibleTime))
                invalidateStatusCache()

                appendSharedLog(
                    "Auto-update skipped: no selected filters, userscripts +\(scriptsResult.updated)/-\(scriptsResult.failed), nextCheckIn=\(formatDurationSeconds(Int(interval * 3600)))"
                )
                let durationMs = Int((completionTime - startTimestamp) * 1000)
                appendTelemetry(
                    "run_result",
                    fields: [
                        "trigger": trigger,
                        "result": "no_selected_filters",
                        "forced": shouldForce ? "true" : "false",
                        "checked_filters": "0",
                        "updated_filters": "0",
                        "error_count": "0",
                        "scripts_updated": "\(scriptsResult.updated)",
                        "scripts_failed": "\(scriptsResult.failed)",
                        "next_check_seconds": "\(Int(interval * 3600))",
                        "duration_ms": "\(durationMs)"
                    ]
                )

                // Still record check time even though no filters selected
                // Clear running flag before return
                await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
                await ProtobufDataManager.shared.saveDataImmediately()
                invalidateStatusCache()
                let endTimestamp = Date().timeIntervalSince1970
                let duration = endTimestamp - startTimestamp
                os_log("Auto-update completed at %.0f (duration: %.1fs)", log: log, type: .info, endTimestamp, duration)
                return
            }

            try throwIfCancelled()
            let updateResult = try await checkAndFetchUpdates(filters: selectedFilters)
            try throwIfCancelled()
            let updatedFilterSet = updateResult.updatedFilters
            let hadErrors = updateResult.hadErrors

            guard !updatedFilterSet.isEmpty else {
                // If this run was forced (BG task / silent push) or outputs are missing, do a
                // lightweight reload to keep Safari in sync even when no filter bodies changed.
                var reloadStatus = "skipped"
                if shouldForce || contentBlockerOutputsNeedRepair() {
                    try throwIfCancelled()
                    let reloaded = await reloadExistingContentBlockers()
                    reloadStatus = reloaded ? "ok" : "failed"
                }

                let completionTime = Date().timeIntervalSince1970
                let nextCheckInSeconds: Int
                if hadErrors {
                    // Don't treat network errors as "up to date" – retry sooner.
                    let retryDelaySeconds = min(3600.0, max(900.0, interval * 3600 * 0.25))
                    let nextEligibleTime = completionTime + retryDelaySeconds
                    await ProtobufDataManager.shared.setAutoUpdateNextEligibleTime(Int64(nextEligibleTime))
                    invalidateStatusCache()
                    nextCheckInSeconds = Int(retryDelaySeconds)
                } else {
                    // No updates found - still update schedule since check was successful
                    let scheduledSeconds = Int(interval * 3600)
                    let nextEligibleTime = completionTime + Double(scheduledSeconds)
                    await ProtobufDataManager.shared.setAutoUpdateNextEligibleTime(Int64(nextEligibleTime))
                    invalidateStatusCache()
                    nextCheckInSeconds = scheduledSeconds
                }

                // Auto-update enabled userscripts during the same schedule window.
                let scriptsResult = await autoUpdateUserScriptsIfNeeded()
                if scriptsResult.updated > 0 {
                    await ProtobufDataManager.shared.setAutoUpdateLastSuccessfulTime(Int64(Date().timeIntervalSince1970))
                }
                appendSharedLog(
                    "No filter updates: checkErrors=\(hadErrors), reload=\(reloadStatus), userscripts +\(scriptsResult.updated)/-\(scriptsResult.failed), nextCheckIn=\(formatDurationSeconds(nextCheckInSeconds))"
                )
                let durationMs = Int((completionTime - startTimestamp) * 1000)
                appendTelemetry(
                    "run_result",
                    fields: [
                        "trigger": trigger,
                        "result": "no_filter_updates",
                        "forced": shouldForce ? "true" : "false",
                        "checked_filters": "\(updateResult.checkedCount)",
                        "updated_filters": "0",
                        "error_count": "\(updateResult.errorCount)",
                        "reload_status": reloadStatus,
                        "scripts_updated": "\(scriptsResult.updated)",
                        "scripts_failed": "\(scriptsResult.failed)",
                        "next_check_seconds": "\(nextCheckInSeconds)",
                        "duration_ms": "\(durationMs)"
                    ]
                )

                // Clear running flag before return
                await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
                await ProtobufDataManager.shared.saveDataImmediately()
                invalidateStatusCache()
                let endTimestamp = Date().timeIntervalSince1970
                let duration = endTimestamp - startTimestamp
                os_log("Auto-update completed at %.0f (duration: %.1fs)", log: log, type: .info, endTimestamp, duration)
                return
            }

            os_log("Found %d filter updates — applying", log: log, type: .info, updatedFilterSet.count)
            let updatedPreview = updatedFilterSet.prefix(3).map(\.name).joined(separator: ", ")

            // Merge updated filters back into full list model
            var merged = allFilters
            for updated in updatedFilterSet {
                if let idx = merged.firstIndex(where: { $0.id == updated.id }) {
                    merged[idx] = updated
                }
            }

            // Persist metadata (versions, counts)
            await saveFilterListsToProtobuf(merged)

            // Re-convert & reload content blockers. (Rule distribution is slot-based, so updates can affect any target.)
            try throwIfCancelled()
            let rebuildSummary = try await rebuildAndReload(selectedFilters: merged.filter { $0.isSelected })
            try throwIfCancelled()

            // Auto-update enabled userscripts during the same schedule window.
            let scriptsResult = await autoUpdateUserScriptsIfNeeded()

            // Record successful update and schedule next
            let successTime = Date().timeIntervalSince1970
            await ProtobufDataManager.shared.setAutoUpdateLastSuccessfulTime(Int64(successTime))
            var nextEligibleTime = successTime + interval * 3600
            let nextCheckInSeconds: Int
            if hadErrors {
                // Some filters failed to check; retry sooner than the normal interval.
                let retryDelaySeconds = min(3600.0, max(900.0, interval * 3600 * 0.25))
                nextEligibleTime = min(nextEligibleTime, successTime + retryDelaySeconds)
                nextCheckInSeconds = Int(retryDelaySeconds)
            } else {
                nextCheckInSeconds = Int(interval * 3600)
            }
            await ProtobufDataManager.shared.setAutoUpdateNextEligibleTime(Int64(nextEligibleTime))
            invalidateStatusCache()

            appendSharedLog(
                "Applied \(updatedFilterSet.count) filter update(s): \(updatedPreview)\(updatedFilterSet.count > 3 ? ", ..." : "")."
            )
            appendSharedLog(
                "Rebuild summary: targets \(rebuildSummary.targetCount), cache \(rebuildSummary.cacheHits)/\(rebuildSummary.cacheMisses), rules \(rebuildSummary.safariRulesTotal), input \(formatBytes(rebuildSummary.inputBytesTotal)) written in \(formatDurationMs(rebuildSummary.inputWriteDurationMs)), conversion \(formatDurationMs(rebuildSummary.conversionDurationMs)), reload \(formatDurationMs(rebuildSummary.reloadDurationMs)), slowest write \(rebuildSummary.slowestWriteTarget), slowest rebuild \(rebuildSummary.slowestTarget), userscripts +\(scriptsResult.updated)/-\(scriptsResult.failed), next check in \(formatDurationSeconds(nextCheckInSeconds))."
            )
            if hadErrors {
                appendSharedLog("Some filter checks failed; using a shorter retry interval.")
            }
            appendTelemetry(
                "run_result",
                fields: [
                    "trigger": trigger,
                    "result": "applied_updates",
                    "forced": shouldForce ? "true" : "false",
                    "checked_filters": "\(updateResult.checkedCount)",
                    "updated_filters": "\(updatedFilterSet.count)",
                    "error_count": "\(updateResult.errorCount)",
                    "scripts_updated": "\(scriptsResult.updated)",
                    "scripts_failed": "\(scriptsResult.failed)",
                    "next_check_seconds": "\(nextCheckInSeconds)",
                    "duration_ms": "\(Int((Date().timeIntervalSince1970 - startTimestamp) * 1000))"
                ]
            )
        } catch is CancellationError {
            os_log("Auto-update cancelled (trigger: %{public}@)", log: log, type: .info, trigger)
            appendSharedLog("Auto-update cancelled: trigger=\(trigger)")
            appendTelemetry(
                "run_result",
                fields: [
                    "trigger": trigger,
                    "result": "cancelled",
                    "forced": shouldForce ? "true" : "false",
                    "duration_ms": "\(Int((Date().timeIntervalSince1970 - startTimestamp) * 1000))"
                ]
            )
        } catch {
            os_log("Auto-update failed: %{public}@", log: log, type: .error, String(describing: error))
            appendSharedLog("Auto-update failed: \(error.localizedDescription)")
            appendTelemetry(
                "run_result",
                fields: [
                    "trigger": trigger,
                    "result": "failed",
                    "forced": shouldForce ? "true" : "false",
                    "error": String(describing: error),
                    "duration_ms": "\(Int((Date().timeIntervalSince1970 - startTimestamp) * 1000))"
                ]
            )
        }

        // ALWAYS clear running flag after completion (success or failure)
        await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
        await ProtobufDataManager.shared.saveDataImmediately()
        invalidateStatusCache()
        let endTimestamp = Date().timeIntervalSince1970
        let duration = endTimestamp - startTimestamp
        os_log("Auto-update completed at %.0f (duration: %.1fs)", log: log, type: .info, endTimestamp, duration)
    }

    // MARK: - Loading / Saving
    private func loadFilterListsFromProtobuf() async -> ([FilterList], [FilterList]) {
        await ProtobufDataManager.shared.waitUntilLoaded()
        let allFilters = await ProtobufDataManager.shared.getFilterLists()
        let selectedFilters = allFilters.filter { $0.isSelected }

        return (allFilters, selectedFilters)
    }

    private func saveFilterListsToProtobuf(_ lists: [FilterList]) async {
        await ProtobufDataManager.shared.updateFilterLists(lists)
    }

    // MARK: - Update Detection & Fetch
    private struct UpdateFetchResult {
        var updatedFilters: [FilterList]
        var hadErrors: Bool
        var errorCount: Int
        var checkedCount: Int
    }

    private enum FilterFetchOutcome {
        case noChange
        case noChangeWithValidators(uuid: String, etag: String?, lastModified: String?)
        case updated(filter: FilterList, validators: (etag: String?, lastModified: String?))
        case error(filterName: String, error: Error)
    }

    private func checkAndFetchUpdates(filters: [FilterList]) async throws -> UpdateFetchResult {
        try Task.checkCancellation()

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            throw AutoUpdateError.sharedContainerUnavailable
        }

        var updatedFilters: [FilterList] = []
        var hadErrors = false
        var errorCount = 0
        var validatorUpdates: [String: (etag: String?, lastModified: String?)] = [:]

        await withTaskGroup(of: FilterFetchOutcome.self) { group in
            for filter in filters {
                group.addTask { await self.fetchIfUpdated(filter, containerURL: containerURL) }
            }

            for await outcome in group {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                switch outcome {
                case .noChange:
                    break
                case .noChangeWithValidators(let uuid, let etag, let lastModified):
                    validatorUpdates[uuid] = (etag: etag, lastModified: lastModified)
                case .updated(let filter, let validators):
                    updatedFilters.append(filter)
                    if validators.etag != nil || validators.lastModified != nil {
                        validatorUpdates[filter.id.uuidString] = validators
                    }
                case .error(let filterName, let error):
                    hadErrors = true
                    errorCount += 1
                    os_log(
                        "Update fetch error for %{public}@ – %{public}@",
                        log: log,
                        type: .error,
                        filterName,
                        error.localizedDescription
                    )
                }
            }
        }

        try Task.checkCancellation()

        if !validatorUpdates.isEmpty {
            await ProtobufDataManager.shared.setFilterValidators(validatorUpdates)
        }

        return UpdateFetchResult(
            updatedFilters: updatedFilters,
            hadErrors: hadErrors,
            errorCount: errorCount,
            checkedCount: filters.count
        )
    }

    private func fetchIfUpdated(_ filter: FilterList, containerURL: URL) async -> FilterFetchOutcome {
        let uuid = filter.id.uuidString
        let etag = await getFilterEtag(uuid)
        let lastModified = await getFilterLastModified(uuid)

        let request = makeConditionalRequest(for: filter, etag: etag, lastModified: lastModified)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error(filterName: filter.name, error: URLError(.badServerResponse))
            }

            let responseEtag = http.value(forHTTPHeaderField: "ETag")
            let responseLastModified = http.value(forHTTPHeaderField: "Last-Modified")
            let hasValidatorUpdates = responseEtag != nil || responseLastModified != nil

            let localURL = containerURL.appendingPathComponent(
                ContentBlockerIncrementalCache.localFilename(for: filter)
            )
            let localData = localDataForComparison(filter: filter, containerURL: containerURL)
            let responseStatus = FilterUpdateResponseClassifier.classify(
                statusCode: http.statusCode,
                responseData: data,
                localData: localData
            )

            switch responseStatus {
            case .notModified:
                return .noChange
            case .unchangedContent:
                return hasValidatorUpdates
                    ? .noChangeWithValidators(
                        uuid: uuid,
                        etag: responseEtag,
                        lastModified: responseLastModified
                    )
                    : .noChange
            case .invalidContent:
                // Don't overwrite the on-disk list with HTML challenge pages or other garbage.
                return .error(filterName: filter.name, error: URLError(.cannotParseResponse))
            case .unexpectedStatus:
                return .error(filterName: filter.name, error: URLError(.badServerResponse))
            case .updatedContent:
                break
            }

            do {
                try data.write(to: localURL, options: .atomic)
            } catch {
                return .error(filterName: filter.name, error: error)
            }

            // Only parse the beginning for metadata, not the entire content.
            guard let content = String(data: data.prefix(8192), encoding: .utf8) else {
                return .error(filterName: filter.name, error: URLError(.cannotDecodeContentData))
            }
            let meta = parseMetadata(from: content)

            // Count rules efficiently without loading full content into memory.
            let ruleCount = countRulesInData(data: data)

            var updated = filter
            if let version = meta.version, !version.isEmpty { updated.version = version }
            if let desc = meta.description, !desc.isEmpty { updated.description = desc }
            updated.sourceRuleCount = ruleCount
            return .updated(
                filter: updated,
                validators: (etag: responseEtag, lastModified: responseLastModified)
            )
        } catch {
            return .error(filterName: filter.name, error: error)
        }
    }

    private func makeConditionalRequest(for filter: FilterList, etag: String?, lastModified: String?) -> URLRequest {
        if filter.url.host?.contains("gitflic.ru") == true {
            return NetworkRequestFactory.makeGitflicRequest(
                url: filter.url,
                etag: etag,
                lastModified: lastModified,
                timeout: 30
            )
        }

        return NetworkRequestFactory.makeConditionalRequest(
            url: filter.url,
            etag: etag,
            lastModified: lastModified,
            timeout: 20
        )
    }

    private func localDataForComparison(filter: FilterList, containerURL: URL) -> Data? {
        let localURL = containerURL.appendingPathComponent(
            ContentBlockerIncrementalCache.localFilename(for: filter)
        )
        if let localData = try? Data(contentsOf: localURL) {
            return localData
        }

        guard filter.isCustom else { return nil }
        let legacyURL = containerURL.appendingPathComponent("\(filter.name).txt")
        return try? Data(contentsOf: legacyURL)
    }

    @discardableResult
    private func streamFilterDataForConversion(
        _ filter: FilterList,
        containerURL: URL,
        destinationHandle: FileHandle,
        hasher: inout SHA256,
        newlineData: Data
    ) -> Bool {
        let primaryURL = containerURL.appendingPathComponent(
            ContentBlockerIncrementalCache.localFilename(for: filter)
        )
        if appendFileContentsToCombinedStream(
            sourceURL: primaryURL,
            destinationHandle: destinationHandle,
            hasher: &hasher,
            newlineData: newlineData
        ) {
            return true
        }

        // Backward compatibility: legacy custom filters were stored as "<name>.txt".
        guard filter.isCustom else { return false }
        let legacyURL = containerURL.appendingPathComponent("\(filter.name).txt")
        guard appendFileContentsToCombinedStream(
            sourceURL: legacyURL,
            destinationHandle: destinationHandle,
            hasher: &hasher,
            newlineData: newlineData
        ) else {
            return false
        }

        // Best-effort migration to the stable ID-based filename.
        if !FileManager.default.fileExists(atPath: primaryURL.path),
           FileManager.default.fileExists(atPath: legacyURL.path) {
            try? FileManager.default.moveItem(at: legacyURL, to: primaryURL)
        }
        return true
    }

    @discardableResult
    private func appendFileContentsToCombinedStream(
        sourceURL: URL,
        destinationHandle: FileHandle,
        hasher: inout SHA256,
        newlineData: Data,
        chunkSize: Int = 64 * 1024
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return false }

        do {
            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            defer { try? sourceHandle.close() }

            while true {
                let chunk = try sourceHandle.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
                try destinationHandle.write(contentsOf: chunk)
            }

            hasher.update(data: newlineData)
            try destinationHandle.write(contentsOf: newlineData)
            return true
        } catch {
            os_log(
                "Failed to stream filter data from %{public}@ – %{public}@",
                log: log,
                type: .error,
                sourceURL.lastPathComponent,
                error.localizedDescription
            )
            return false
        }
    }

    private func reloadContentBlockerWithRetryWithMetrics(
        identifier: String,
        maxRetries: Int = 6
    ) async -> ReloadAttemptResult {
        let start = Date()
        for attempt in 1...maxRetries {
            if Task.isCancelled {
                return ReloadAttemptResult(
                    success: false,
                    attempts: max(0, attempt - 1),
                    durationMs: Int(Date().timeIntervalSince(start) * 1000)
                )
            }

            let result = await ContentBlockerService.reloadContentBlocker(withIdentifier: identifier)
            if case .success = result {
                return ReloadAttemptResult(
                    success: true,
                    attempts: attempt,
                    durationMs: Int(Date().timeIntervalSince(start) * 1000)
                )
            }

            if attempt < maxRetries {
                // Back off quickly; WKErrorDomain error 6 is often transient right after writes.
                let delayMs = min(200 * attempt, 1500)
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
        }

        return ReloadAttemptResult(
            success: false,
            attempts: maxRetries,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    private func contentBlockerOutputsNeedRepair() -> Bool {
        #if os(iOS)
        let platform: Platform = .iOS
        #else
        let platform: Platform = .macOS
        #endif

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            return false
        }

        for target in ContentBlockerTargetManager.shared.allTargets(forPlatform: platform) {
            let rulesURL = containerURL.appendingPathComponent(target.rulesFilename)
            if !FileManager.default.fileExists(atPath: rulesURL.path) {
                return true
            }
        }

        return false
    }

    private func reloadExistingContentBlockers() async -> Bool {
        #if os(iOS)
        let platform: Platform = .iOS
        #else
        let platform: Platform = .macOS
        #endif

        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: platform)
        var allReloaded = true
        var failedTargets: [String] = []
        var advancedRulesSnippets: [String] = []

        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value)

        for target in targets {
            if Task.isCancelled {
                return false
            }

            let reloadResult = await reloadContentBlockerWithRetryWithMetrics(identifier: target.bundleIdentifier)
            let reloaded = reloadResult.success
            allReloaded = allReloaded && reloaded
            if !reloaded {
                failedTargets.append(target.displayName)
            }
            if let containerURL,
               let adv = loadCachedAdvancedRules(for: target, containerURL: containerURL),
               !adv.isEmpty {
                advancedRulesSnippets.append(adv)
            }
        }

        if !advancedRulesSnippets.isEmpty {
            ContentBlockerService.buildCombinedFilterEngine(
                combinedAdvancedRules: advancedRulesSnippets.joined(separator: "\n"),
                groupIdentifier: GroupIdentifier.shared.value
            )
        } else {
            ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
        }

        if !failedTargets.isEmpty {
            appendSharedLog(
                "Reload failures while reusing existing outputs: \(failedTargets.prefix(3).joined(separator: ", "))"
            )
        }

        return allReloaded
    }

    // MARK: - Conversion & Reload
    private func rebuildAndReload(selectedFilters: [FilterList]) async throws -> RebuildAndReloadSummary {
        try Task.checkCancellation()

        // Build rules per target using same slot-based mapping logic as the main app.
        #if os(iOS)
        let detectedPlatform: Platform = .iOS
        #else
        let detectedPlatform: Platform = .macOS
        #endif

        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: detectedPlatform)
        var advancedRulesSnippets: [String] = []

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            throw AutoUpdateError.sharedContainerUnavailable
        }

        // Get disabled sites for injection
        let disabledSites = await getDisabledSites()

        let filtersByTarget = ContentBlockerMappingService.distribute(
            selectedFilters: selectedFilters,
            across: targets
        )
        var targetMetrics: [RebuildTargetMetrics] = []

        for target in targets {
            try Task.checkCancellation()

            let filtersForTarget = filtersByTarget[target] ?? []
            let rulesFilename = target.rulesFilename
            let conversionStart = Date()
            var inputWriteDurationMs = 0
            var inputBytes: Int64 = 0
            let currentSignature = ContentBlockerIncrementalCache.computeInputSignature(
                filters: filtersForTarget,
                groupIdentifier: GroupIdentifier.shared.value
            )
            let storedSignature = ContentBlockerIncrementalCache.loadInputSignature(
                targetRulesFilename: rulesFilename,
                groupIdentifier: GroupIdentifier.shared.value
            )

            let canReuseCachedConversion =
                currentSignature != nil
                && currentSignature == storedSignature
                && ContentBlockerIncrementalCache.hasBaseRulesCache(
                    targetRulesFilename: rulesFilename,
                    groupIdentifier: GroupIdentifier.shared.value
                )

            let conversion: (safariRulesCount: Int, advancedRulesText: String?)
            let usedCache: Bool
            if canReuseCachedConversion {
                usedCache = true
                conversion = ContentBlockerService.fastUpdateDisabledSites(
                    groupIdentifier: GroupIdentifier.shared.value,
                    targetRulesFilename: rulesFilename,
                    disabledSites: disabledSites
                )
            } else {
                usedCache = false
                // Rebuild combined raw rules for this target from assigned filters (streaming + hashed).
                let tempURL = containerURL.appendingPathComponent("temp_autoupdate_\(target.bundleIdentifier).txt")
                defer { try? FileManager.default.removeItem(at: tempURL) }

                FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
                let newlineData = Data("\n".utf8)
                var hasher = SHA256()
                let fileHandle = try FileHandle(forWritingTo: tempURL)
                defer { try? fileHandle.close() }
                let inputWriteStart = Date()

                for f in filtersForTarget {
                    try Task.checkCancellation()
                    _ = streamFilterDataForConversion(
                        f,
                        containerURL: containerURL,
                        destinationHandle: fileHandle,
                        hasher: &hasher,
                        newlineData: newlineData
                    )
                }
                inputWriteDurationMs = Int(Date().timeIntervalSince(inputWriteStart) * 1000)
                inputBytes = fileSizeBytes(at: tempURL)

                let digest = hasher.finalize()
                let rulesSHA256Hex = digest.map { String(format: "%02x", $0) }.joined()

                conversion = ContentBlockerService.convertFilterFromFile(
                    rulesFileURL: tempURL,
                    rulesSHA256Hex: rulesSHA256Hex,
                    groupIdentifier: GroupIdentifier.shared.value,
                    targetRulesFilename: rulesFilename,
                    disabledSites: disabledSites
                )

                if let currentSignature {
                    ContentBlockerIncrementalCache.saveInputSignature(
                        currentSignature,
                        targetRulesFilename: rulesFilename,
                        groupIdentifier: GroupIdentifier.shared.value
                    )
                }
            }
            let conversionDurationMs = Int(Date().timeIntervalSince(conversionStart) * 1000)

            let cachedAdvancedRules = ContentBlockerIncrementalCache.loadCachedAdvancedRules(
                targetRulesFilename: rulesFilename,
                groupIdentifier: GroupIdentifier.shared.value
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            let advancedRulesText = conversion.advancedRulesText?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if let adv = (advancedRulesText?.isEmpty == false ? advancedRulesText : cachedAdvancedRules),
                !adv.isEmpty
            {
                advancedRulesSnippets.append(adv)
            }

            let reloadResult = await reloadContentBlockerWithRetryWithMetrics(identifier: target.bundleIdentifier)
            let targetMetric = RebuildTargetMetrics(
                targetName: target.displayName,
                cacheHit: usedCache,
                inputWriteMs: inputWriteDurationMs,
                inputBytes: inputBytes,
                conversionMs: conversionDurationMs,
                reloadMs: reloadResult.durationMs,
                reloadAttempts: reloadResult.attempts,
                safariRules: conversion.safariRulesCount
            )
            targetMetrics.append(targetMetric)

            if !reloadResult.success {
                appendSharedLog(
                    "Rebuild failed reloading \(target.displayName) after \(reloadResult.attempts) attempt(s)"
                )
                throw AutoUpdateError.contentBlockerReloadFailed(identifier: target.bundleIdentifier)
            }
        }

        try Task.checkCancellation()

        if !advancedRulesSnippets.isEmpty {
            ContentBlockerService.buildCombinedFilterEngine(
                combinedAdvancedRules: advancedRulesSnippets.joined(separator: "\n"),
                groupIdentifier: GroupIdentifier.shared.value
            )
        } else {
            ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
        }

        let cacheHits = targetMetrics.filter { $0.cacheHit }.count
        let inputWriteDurationMs = targetMetrics.reduce(0) { $0 + $1.inputWriteMs }
        let inputBytesTotal = targetMetrics.reduce(Int64(0)) { $0 + $1.inputBytes }
        let conversionDurationMs = targetMetrics.reduce(0) { $0 + $1.conversionMs }
        let reloadDurationMs = targetMetrics.reduce(0) { $0 + $1.reloadMs }
        let totalReloadAttempts = targetMetrics.reduce(0) { $0 + $1.reloadAttempts }
        let safariRulesTotal = targetMetrics.reduce(0) { $0 + $1.safariRules }
        let slowestWriteTarget = targetMetrics
            .filter { $0.inputWriteMs > 0 }
            .max(by: { $0.inputWriteMs < $1.inputWriteMs })
            .map { "\($0.targetName)@\(formatDurationMs($0.inputWriteMs))" } ?? "n/a"
        let slowestTarget = targetMetrics.max(by: {
            ($0.conversionMs + $0.reloadMs) < ($1.conversionMs + $1.reloadMs)
        }).map {
            let totalMs = $0.conversionMs + $0.reloadMs
            return "\($0.targetName)@\(formatDurationMs(totalMs))"
        } ?? "n/a"

        return RebuildAndReloadSummary(
            targetCount: targetMetrics.count,
            cacheHits: cacheHits,
            cacheMisses: max(0, targetMetrics.count - cacheHits),
            safariRulesTotal: safariRulesTotal,
            inputWriteDurationMs: inputWriteDurationMs,
            inputBytesTotal: inputBytesTotal,
            conversionDurationMs: conversionDurationMs,
            reloadDurationMs: reloadDurationMs,
            totalReloadAttempts: totalReloadAttempts,
            slowestWriteTarget: slowestWriteTarget,
            slowestTarget: slowestTarget
        )
    }

    // MARK: - Helpers
    private func countRulesInData(data: Data) -> Int {
        guard !data.isEmpty else { return 0 }

        return data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var count = 0
            var firstNonWhitespace: UInt8?
            var skipLF = false

            @inline(__always)
            func finishLine() {
                guard let first = firstNonWhitespace else { return }
                if first != UInt8(ascii: "!") && first != UInt8(ascii: "[") && first != UInt8(ascii: "#") {
                    count += 1
                }
                firstNonWhitespace = nil
            }

            for byte in bytes {
                if skipLF {
                    skipLF = false
                    if byte == UInt8(ascii: "\n") {
                        continue
                    }
                }

                if byte == UInt8(ascii: "\n") {
                    finishLine()
                    continue
                }

                if byte == UInt8(ascii: "\r") {
                    finishLine()
                    skipLF = true
                    continue
                }

                if firstNonWhitespace == nil {
                    // Trim leading ASCII whitespace (space/tab + vertical tab/form feed).
                    if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == 0x0B || byte == 0x0C {
                        continue
                    }
                    firstNonWhitespace = byte
                }
            }

            // Account for the last line when the file doesn't end with a newline.
            finishLine()
            return count
        }
    }

    private func parseMetadata(from content: String) -> (title: String?, description: String?, version: String?) {
        let rawMetadata = FilterListMetadataParser.parse(from: content, maxLines: 80)
        let title = rawMetadata.title?.replacingOccurrences(of: "/", with: " & ")
        let description = rawMetadata.description?.replacingOccurrences(of: "/", with: " & ")

        let normalizedVersion = rawMetadata.version?.replacingOccurrences(of: "/", with: " & ")
        let version: String?
        if let normalizedVersion,
           normalizedVersion.contains("%"),
           (normalizedVersion.lowercased().contains("timestamp")
                || normalizedVersion.lowercased().contains("date")) {
            version = nil
        } else {
            version = normalizedVersion
        }

        return (title: title, description: description, version: version)
    }

    private func loadCachedAdvancedRules(for target: ContentBlockerTargetInfo, containerURL: URL) -> String? {
        let url = containerURL.appendingPathComponent(
            ContentBlockerIncrementalCache.baseAdvancedRulesFilename(for: target.rulesFilename)
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func formatDurationMs(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        }
        return String(format: "%.2fs", Double(ms) / 1000.0)
    }

    private func formatDurationSeconds(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            return String(format: "%.1fm", Double(seconds) / 60.0)
        }
        return String(format: "%.1fh", Double(seconds) / 3600.0)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        }
        if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }

    private func fileSizeBytes(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
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

    private func appendTelemetry(_ event: String, fields: [String: String]) {
        let merged = fields.merging(["event": event]) { current, _ in current }
        let payload = merged
            .map { key, value in
                let normalized = value.replacingOccurrences(of: " ", with: "_")
                return "\(key)=\(normalized)"
            }
            .sorted()
            .joined(separator: " ")
        appendSharedLog("telemetry \(payload)")
    }

    private func appendSkipTelemetry(trigger: String, reason: String, extra: [String: String] = [:]) {
        var fields = extra
        fields["trigger"] = trigger
        fields["reason"] = reason
        appendTelemetry("run_skip", fields: fields)
    }

    // Removed runtime heuristic; compile-time selection is sufficient.
}
