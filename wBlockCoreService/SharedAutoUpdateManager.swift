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

    public struct AutoUpdateExecutionPolicy: Sendable {
        public let trigger: String
        public let isBackground: Bool
        public let deadline: Date?
        public let minimumTimeForNetwork: TimeInterval
        public let minimumTimeForConversionTarget: TimeInterval
        public let minimumTimeForReloadRetry: TimeInterval
        public let minimumTimeForAdvancedEngine: TimeInterval
        public let minimumTimeForUserScripts: TimeInterval
        public let minimumTimeForFinalSave: TimeInterval
        public let allowsFullRebuild: Bool

        public init(
            trigger: String,
            isBackground: Bool = false,
            deadline: Date? = nil,
            minimumTimeForNetwork: TimeInterval = 0,
            minimumTimeForConversionTarget: TimeInterval = 0,
            minimumTimeForReloadRetry: TimeInterval = 0,
            minimumTimeForAdvancedEngine: TimeInterval = 0,
            minimumTimeForUserScripts: TimeInterval = 0,
            minimumTimeForFinalSave: TimeInterval = 0,
            allowsFullRebuild: Bool = true
        ) {
            self.trigger = trigger
            self.isBackground = isBackground
            self.deadline = deadline
            self.minimumTimeForNetwork = minimumTimeForNetwork
            self.minimumTimeForConversionTarget = minimumTimeForConversionTarget
            self.minimumTimeForReloadRetry = minimumTimeForReloadRetry
            self.minimumTimeForAdvancedEngine = minimumTimeForAdvancedEngine
            self.minimumTimeForUserScripts = minimumTimeForUserScripts
            self.minimumTimeForFinalSave = minimumTimeForFinalSave
            self.allowsFullRebuild = allowsFullRebuild
        }

        public static func foreground(trigger: String) -> Self {
            Self(trigger: trigger)
        }

        public static func background(
            trigger: String,
            deadline: Date?,
            allowsFullRebuild: Bool
        ) -> Self {
            Self(
                trigger: trigger,
                isBackground: true,
                deadline: deadline,
                minimumTimeForNetwork: 15,
                minimumTimeForConversionTarget: 12,
                minimumTimeForReloadRetry: 8,
                minimumTimeForAdvancedEngine: 10,
                minimumTimeForUserScripts: 8,
                minimumTimeForFinalSave: 3,
                allowsFullRebuild: allowsFullRebuild
            )
        }
    }

    public enum AutoUpdateCompletionResult: Sendable, Equatable {
        case appliedUpdates
        case noFilterUpdates
        case noSelectedFilters
    }

    public struct AutoUpdateCompletion: Sendable, Equatable {
        public let result: AutoUpdateCompletionResult
        public let checkedFilters: Int
        public let updatedFilters: Int
        public let updatedScripts: Int
        public let failedScripts: Int

        public init(
            result: AutoUpdateCompletionResult,
            checkedFilters: Int,
            updatedFilters: Int,
            updatedScripts: Int,
            failedScripts: Int
        ) {
            self.result = result
            self.checkedFilters = checkedFilters
            self.updatedFilters = updatedFilters
            self.updatedScripts = updatedScripts
            self.failedScripts = failedScripts
        }
    }

    public enum AutoUpdateRunOutcome: Sendable, Equatable {
        case completed(AutoUpdateCompletion)
        case skipped(reason: String)
        case cancelled
        case deferred(phase: String)
        case failed(message: String)

        public var isSuccessfulForBackgroundTask: Bool {
            switch self {
            case .completed(_), .skipped(_):
                return true
            case .cancelled, .deferred(_), .failed(_):
                return false
            }
        }
    }

    private var cachedStatus: AutoUpdateStatus?
    private var lastStatusCheck: Date?
    private let statusCacheTTL: TimeInterval = 5.0 // 5 seconds cache
    private var runInProgress = false

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

    private enum AutoUpdateError: LocalizedError {
        case sharedContainerUnavailable
        case contentBlockerReloadFailed(identifiers: [String], names: [String])
        case advancedEngineOperationFailed(phase: String, underlying: Error)
        case backgroundBudgetExpired(phase: String, remainingSeconds: Int)
        case backgroundFullRebuildDeferred(phase: String)
        case selectedFilterStateUnavailable
        case statePersistenceFailed(context: String)

        var failurePhase: String? {
            switch self {
            case .sharedContainerUnavailable:
                return "shared_container"
            case .contentBlockerReloadFailed:
                return "content_blocker_reload"
            case let .advancedEngineOperationFailed(phase, _):
                return phase
            case let .backgroundBudgetExpired(phase, _):
                return phase
            case let .backgroundFullRebuildDeferred(phase):
                return phase
            case .selectedFilterStateUnavailable:
                return "selected_filter_state"
            case let .statePersistenceFailed(context):
                return context
            }
        }

        var isDeferred: Bool {
            switch self {
            case .backgroundBudgetExpired, .backgroundFullRebuildDeferred:
                return true
            default:
                return false
            }
        }

        var errorDescription: String? {
            switch self {
            case .sharedContainerUnavailable:
                return "Shared app group container unavailable."
            case let .contentBlockerReloadFailed(_, names):
                return "Failed to reload \(names.joined(separator: ", "))."
            case let .advancedEngineOperationFailed(_, underlying):
                return underlying.localizedDescription
            case let .backgroundBudgetExpired(phase, remainingSeconds):
                return "Background budget expired before \(phase) with \(remainingSeconds)s remaining."
            case let .backgroundFullRebuildDeferred(phase):
                return "Background policy deferred \(phase)."
            case .selectedFilterStateUnavailable:
                return "Selected filter state is unavailable while existing blocker output is present."
            case let .statePersistenceFailed(context):
                return "Failed to persist auto-update state during \(context)."
            }
        }
    }

    private enum AutoUpdateBudgetPhase {
        static let existingOutputReload = "existing_output_reload"
        static let networkFetch = "network_fetch"
        static let fullRebuild = "full_rebuild"
        static let conversionTarget = "conversion_target"
        static let reloadRetry = "reload_retry"
        static let advancedEngineBuild = "advanced_engine_build"
        static let advancedEngineClear = "advanced_engine_clear"
        static let userScripts = "userscripts"
        static let finalStateSave = "final_state_save"
        static let runStartSave = "run_start_save"
        static let runCleanupSave = "run_cleanup_save"
    }

    private func checkBudget(
        _ policy: AutoUpdateExecutionPolicy,
        phase: String,
        requiredTime: TimeInterval
    ) throws {
        guard policy.isBackground, let deadline = policy.deadline else { return }

        let remaining = deadline.timeIntervalSinceNow
        guard remaining >= requiredTime else {
            throw AutoUpdateError.backgroundBudgetExpired(
                phase: phase,
                remainingSeconds: max(0, Int(remaining.rounded(.down)))
            )
        }
    }

    private func requireFullRebuildAllowed(
        _ policy: AutoUpdateExecutionPolicy,
        phase: String
    ) throws {
        guard policy.isBackground, !policy.allowsFullRebuild else { return }
        throw AutoUpdateError.backgroundFullRebuildDeferred(phase: phase)
    }

    private func saveAutoUpdateStateImmediately(context: String) async throws {
        guard await ProtobufDataManager.shared.saveDataImmediately() else {
            throw AutoUpdateError.statePersistenceFailed(context: context)
        }
    }

    private func publishAdvancedEngine(
        advancedRulesSnippets: [String],
        policy: AutoUpdateExecutionPolicy,
        failureLogPrefix: String
    ) throws {
        let phase = advancedRulesSnippets.isEmpty
            ? AutoUpdateBudgetPhase.advancedEngineClear
            : AutoUpdateBudgetPhase.advancedEngineBuild
        try checkBudget(
            policy,
            phase: phase,
            requiredTime: policy.minimumTimeForAdvancedEngine
        )

        do {
            if advancedRulesSnippets.isEmpty {
                try ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
            } else {
                try ContentBlockerService.buildCombinedFilterEngine(
                    combinedAdvancedRules: advancedRulesSnippets.joined(separator: "\n"),
                    groupIdentifier: GroupIdentifier.shared.value
                )
            }
        } catch {
            appendSharedLog("\(failureLogPrefix): \(error.localizedDescription)")
            throw AutoUpdateError.advancedEngineOperationFailed(
                phase: phase,
                underlying: error
            )
        }
    }

    private func clearPersistedRunningFlag(
        clearedMessage: String,
        persistFailureMessage: String
    ) async {
        await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
        let didPersist = await ProtobufDataManager.shared.saveDataImmediately()
        appendSharedLog(clearedMessage)
        if !didPersist {
            appendSharedLog(persistFailureMessage)
        }
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
    @discardableResult
    public func maybeRunAutoUpdate(trigger: String, force: Bool = false) async -> AutoUpdateRunOutcome {
        await maybeRunAutoUpdate(
            trigger: trigger,
            force: force,
            policy: AutoUpdateExecutionPolicy.foreground(trigger: trigger)
        )
    }

    @discardableResult
    public func maybeRunAutoUpdate(
        trigger: String,
        force: Bool = false,
        policy: AutoUpdateExecutionPolicy
    ) async -> AutoUpdateRunOutcome {
        await runIfNeeded(trigger: trigger, force: force, policy: policy)
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
            os_log("Running flag set without timestamp - clearing potentially stuck state", log: log, type: .info)
            await clearPersistedRunningFlag(
                clearedMessage: "Cleared stuck running flag (no timestamp)",
                persistFailureMessage: "Failed to persist cleared running flag (no timestamp)"
            )
            return true
        }

        let now = Date().timeIntervalSince1970
        let age = now - TimeInterval(timestamp)

        if age > runningFlagStalenessThreshold {
            os_log("Running flag stale (%.1f seconds old, threshold %.1f) - clearing stuck state", log: log, type: .info, age, runningFlagStalenessThreshold)
            await clearPersistedRunningFlag(
                clearedMessage: "Cleared stale running flag (age: \(Int(age))s, threshold: \(Int(runningFlagStalenessThreshold))s)",
                persistFailureMessage: "Failed to persist cleared stale running flag"
            )
            return true
        }

        return false
    }

    // MARK: - Core Logic
    private func runIfNeeded(
        trigger: String,
        force: Bool = false,
        policy: AutoUpdateExecutionPolicy
    ) async -> AutoUpdateRunOutcome {
        guard !runInProgress else {
            os_log("Auto-update already running, skipping trigger: %{public}@", log: log, type: .info, trigger)
            appendSkipTelemetry(trigger: trigger, reason: "already_running")
            return .skipped(reason: "already_running")
        }
        runInProgress = true
        defer { runInProgress = false }

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
                appendSkipTelemetry(trigger: trigger, reason: "extension_safe_mode")
            }
            return .skipped(reason: "extension_safe_mode")
        }

        if Task.isCancelled {
            appendSkipTelemetry(trigger: trigger, reason: "task_cancelled_preflight")
            return .cancelled
        }

        let now = Date().timeIntervalSince1970

        let enabled = await getAutoUpdateEnabled()
        if !enabled {
            appendSkipTelemetry(trigger: trigger, reason: "auto_update_disabled")
            return .skipped(reason: "auto_update_disabled")
        }

        let wasStale = await checkAndClearStaleRunningFlag()
        if wasStale {
            invalidateStatusCache()
        }

        let isRunning = await getAutoUpdateIsRunning()
        if isRunning {
            os_log("Auto-update already running, skipping trigger: %{public}@", log: log, type: .info, trigger)
            appendSkipTelemetry(trigger: trigger, reason: "already_running")
            return .skipped(reason: "already_running")
        }

        if BlockingPauseStore.isPaused() {
            let persistedOutputsContainRules = contentBlockerOutputsContainRules()
            let repairedOutputs = persistedOutputsContainRules
                ? await clearPersistedBlockingOutputsForPause()
                : false
            appendSharedLog(
                repairedOutputs
                    ? "Auto-update skipped: blocking is paused; cleared persisted blocker outputs"
                    : "Auto-update skipped: blocking is paused"
            )
            appendSkipTelemetry(
                trigger: trigger,
                reason: "blocking_paused",
                extra: ["repaired_outputs": repairedOutputs ? "true" : "false"]
            )
            return .skipped(reason: "blocking_paused")
        }

        let interval = await getAutoUpdateIntervalHours()
        let forceFlag = await getAutoUpdateForceNext()
        let shouldForce = force || forceFlag

        if !shouldForce {
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
                    return .skipped(reason: "throttled_not_eligible")
                }
            } else {
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
                        return .skipped(reason: "throttled_legacy_interval")
                    }
                }
            }
        }

        if forceFlag {
            await ProtobufDataManager.shared.setAutoUpdateForceNext(false)
        }

        let startTimestamp = Date().timeIntervalSince1970
        await ProtobufDataManager.shared.setAutoUpdateIsRunning(true)
        let heartbeatTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                await ProtobufDataManager.shared.refreshAutoUpdateRunningTimestamp()
            }
        }
        invalidateStatusCache()
        os_log("Auto-update started at %.0f (trigger: %{public}@, forced: %d)", log: log, type: .info, startTimestamp, trigger, shouldForce)

        func finishStartedRun(_ outcome: AutoUpdateRunOutcome) async -> AutoUpdateRunOutcome {
            heartbeatTask.cancel()
            await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
            let didPersistCleanup = await ProtobufDataManager.shared.saveDataImmediately()
            invalidateStatusCache()
            let endTimestamp = Date().timeIntervalSince1970
            let duration = endTimestamp - startTimestamp
            os_log("Auto-update completed at %.0f (duration: %.1fs)", log: log, type: .info, endTimestamp, duration)

            guard didPersistCleanup else {
                appendSharedLog("Auto-update cleanup save failed: context=\(AutoUpdateBudgetPhase.runCleanupSave)")
                return .failed(
                    message: AutoUpdateError.statePersistenceFailed(
                        context: AutoUpdateBudgetPhase.runCleanupSave
                    ).localizedDescription
                )
            }

            return outcome
        }

        func currentDurationMs() -> String {
            "\(Int((Date().timeIntervalSince1970 - startTimestamp) * 1000))"
        }

        func requireBudget(_ phase: String, _ requiredTime: TimeInterval) throws {
            try checkBudget(policy, phase: phase, requiredTime: requiredTime)
        }

        func requireFinalSaveBudget() throws {
            try requireBudget(
                AutoUpdateBudgetPhase.finalStateSave,
                policy.minimumTimeForFinalSave
            )
        }

        func requireRunStartSaveBudget() throws {
            try requireBudget(
                AutoUpdateBudgetPhase.runStartSave,
                policy.minimumTimeForFinalSave
            )
        }

        func requireUserScriptsBudget() throws {
            try requireBudget(
                AutoUpdateBudgetPhase.userScripts,
                policy.minimumTimeForUserScripts
            )
        }

        do {
            await ProtobufDataManager.shared.setAutoUpdateLastCheckTime(Int64(now))
            try requireRunStartSaveBudget()
            try await saveAutoUpdateStateImmediately(context: AutoUpdateBudgetPhase.runStartSave)
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

            try throwIfCancelled()
            let (allFilters, selectedFilters) = await loadFilterListsFromProtobuf()
            try throwIfCancelled()

            guard !selectedFilters.isEmpty else {
                if isExternalHelperTrigger(trigger), contentBlockerOutputsContainRules() {
                    appendSharedLog(
                        "Auto-update aborted: selected filter state was empty while existing blocker output is present (trigger=\(trigger))."
                    )
                    throw AutoUpdateError.selectedFilterStateUnavailable
                }

                try requireUserScriptsBudget()
                let scriptsResult = await autoUpdateUserScriptsIfNeeded()
                if scriptsResult.updated > 0 {
                    await ProtobufDataManager.shared.setAutoUpdateLastSuccessfulTime(Int64(Date().timeIntervalSince1970))
                }

                let completionTime = Date().timeIntervalSince1970
                let nextEligibleTime = completionTime + interval * 3600
                try requireFinalSaveBudget()
                await ProtobufDataManager.shared.setAutoUpdateNextEligibleTime(Int64(nextEligibleTime))
                invalidateStatusCache()

                appendSharedLog(
                    "Auto-update skipped: no selected filters, userscripts +\(scriptsResult.updated)/-\(scriptsResult.failed), nextCheckIn=\(formatDurationSeconds(Int(interval * 3600)))"
                )
                let durationMs = currentDurationMs()
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
                        "duration_ms": durationMs
                    ]
                )

                return await finishStartedRun(.completed(
                    AutoUpdateCompletion(
                        result: .noSelectedFilters,
                        checkedFilters: 0,
                        updatedFilters: 0,
                        updatedScripts: scriptsResult.updated,
                        failedScripts: scriptsResult.failed
                    )
                ))
            }

            try checkBudget(
                policy,
                phase: AutoUpdateBudgetPhase.networkFetch,
                requiredTime: policy.minimumTimeForNetwork
            )
            try throwIfCancelled()
            let updateResult = try await checkAndFetchUpdates(filters: selectedFilters)
            try throwIfCancelled()
            let updatedFilterSet = updateResult.updatedFilters
            let hadErrors = updateResult.hadErrors

            guard !updatedFilterSet.isEmpty else {
                var reloadStatus = "skipped"
                if shouldForce || contentBlockerOutputsNeedRepair() {
                    try checkBudget(
                        policy,
                        phase: AutoUpdateBudgetPhase.existingOutputReload,
                        requiredTime: max(policy.minimumTimeForReloadRetry, policy.minimumTimeForAdvancedEngine)
                    )
                    try throwIfCancelled()
                    try await reloadExistingContentBlockers(policy: policy)
                    reloadStatus = "ok"
                }

                let completionTime = Date().timeIntervalSince1970
                let nextCheckInSeconds: Int
                try requireFinalSaveBudget()
                if hadErrors {
                    let retryDelaySeconds = min(3600.0, max(900.0, interval * 3600 * 0.25))
                    let nextEligibleTime = completionTime + retryDelaySeconds
                    await ProtobufDataManager.shared.setAutoUpdateNextEligibleTime(Int64(nextEligibleTime))
                    invalidateStatusCache()
                    nextCheckInSeconds = Int(retryDelaySeconds)
                } else {
                    let scheduledSeconds = Int(interval * 3600)
                    let nextEligibleTime = completionTime + Double(scheduledSeconds)
                    await ProtobufDataManager.shared.setAutoUpdateNextEligibleTime(Int64(nextEligibleTime))
                    invalidateStatusCache()
                    nextCheckInSeconds = scheduledSeconds
                }

                try requireUserScriptsBudget()
                let scriptsResult = await autoUpdateUserScriptsIfNeeded()
                if scriptsResult.updated > 0 {
                    await ProtobufDataManager.shared.setAutoUpdateLastSuccessfulTime(Int64(Date().timeIntervalSince1970))
                }
                appendSharedLog(
                    "No filter updates: checkErrors=\(hadErrors), reload=\(reloadStatus), userscripts +\(scriptsResult.updated)/-\(scriptsResult.failed), nextCheckIn=\(formatDurationSeconds(nextCheckInSeconds))"
                )
                let durationMs = currentDurationMs()
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
                        "duration_ms": durationMs
                    ]
                )

                return await finishStartedRun(.completed(
                    AutoUpdateCompletion(
                        result: .noFilterUpdates,
                        checkedFilters: updateResult.checkedCount,
                        updatedFilters: 0,
                        updatedScripts: scriptsResult.updated,
                        failedScripts: scriptsResult.failed
                    )
                ))
            }

            try requireFullRebuildAllowed(policy, phase: AutoUpdateBudgetPhase.fullRebuild)
            try checkBudget(
                policy,
                phase: AutoUpdateBudgetPhase.fullRebuild,
                requiredTime: policy.minimumTimeForConversionTarget
                    + policy.minimumTimeForReloadRetry
                    + policy.minimumTimeForAdvancedEngine
            )
            os_log("Found %d filter updates — applying", log: log, type: .info, updatedFilterSet.count)
            let updatedPreview = updatedFilterSet.prefix(3).map(\.name).joined(separator: ", ")

            var merged = allFilters
            for updated in updatedFilterSet {
                if let idx = merged.firstIndex(where: { $0.id == updated.id }) {
                    merged[idx] = updated
                }
            }

            try requireFinalSaveBudget()
            await saveFilterListsToProtobuf(merged)
            try await saveAutoUpdateStateImmediately(context: AutoUpdateBudgetPhase.finalStateSave)
            try throwIfCancelled()
            let rebuildSummary = try await rebuildAndReload(
                selectedFilters: merged.filter { $0.isSelected },
                policy: policy
            )
            try throwIfCancelled()

            try requireUserScriptsBudget()
            let scriptsResult = await autoUpdateUserScriptsIfNeeded()

            let successTime = Date().timeIntervalSince1970
            try requireFinalSaveBudget()
            await ProtobufDataManager.shared.setAutoUpdateLastSuccessfulTime(Int64(successTime))
            var nextEligibleTime = successTime + interval * 3600
            let nextCheckInSeconds: Int
            if hadErrors {
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
            let durationMs = currentDurationMs()
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
                    "duration_ms": durationMs
                ]
            )

            return await finishStartedRun(.completed(
                AutoUpdateCompletion(
                    result: .appliedUpdates,
                    checkedFilters: updateResult.checkedCount,
                    updatedFilters: updatedFilterSet.count,
                    updatedScripts: scriptsResult.updated,
                    failedScripts: scriptsResult.failed
                )
            ))
        } catch is CancellationError {
            os_log("Auto-update cancelled (trigger: %{public}@)", log: log, type: .info, trigger)
            appendSharedLog("Auto-update cancelled: trigger=\(trigger)")
            let durationMs = currentDurationMs()
            appendTelemetry(
                "run_result",
                fields: [
                    "trigger": trigger,
                    "result": "cancelled",
                    "forced": shouldForce ? "true" : "false",
                    "duration_ms": durationMs
                ]
            )
            return await finishStartedRun(.cancelled)
        } catch let autoUpdateError as AutoUpdateError {
            let isDeferred = autoUpdateError.isDeferred
            let phase = autoUpdateError.failurePhase ?? "unknown"
            if isDeferred {
                await ProtobufDataManager.shared.setAutoUpdateForceNext(true)
                invalidateStatusCache()
            }
            let result = isDeferred ? "deferred" : "failed"

            if isDeferred {
                os_log("Auto-update deferred: %{public}@", log: log, type: .info, autoUpdateError.localizedDescription)
            } else {
                os_log("Auto-update failed: %{public}@", log: log, type: .error, autoUpdateError.localizedDescription)
            }

            appendSharedLog(
                "Auto-update \(result): trigger=\(trigger), phase=\(phase), reason=\(autoUpdateError.localizedDescription)"
            )
            let durationMs = currentDurationMs()
            appendTelemetry(
                "run_result",
                fields: [
                    "trigger": trigger,
                    "result": result,
                    "forced": shouldForce ? "true" : "false",
                    "phase": phase,
                    "error": autoUpdateError.localizedDescription,
                    "duration_ms": durationMs
                ]
            )
            let outcome: AutoUpdateRunOutcome = isDeferred
                ? .deferred(phase: phase)
                : .failed(message: autoUpdateError.localizedDescription)
            return await finishStartedRun(outcome)
        } catch {
            os_log("Auto-update failed: %{public}@", log: log, type: .error, String(describing: error))
            appendSharedLog("Auto-update failed: trigger=\(trigger), phase=unknown, reason=\(error.localizedDescription)")
            let durationMs = currentDurationMs()
            appendTelemetry(
                "run_result",
                fields: [
                    "trigger": trigger,
                    "result": "failed",
                    "forced": shouldForce ? "true" : "false",
                    "phase": "unknown",
                    "error": String(describing: error),
                    "duration_ms": durationMs
                ]
            )
            return await finishStartedRun(.failed(message: error.localizedDescription))
        }
    }

    // MARK: - Loading / Saving
    private func loadFilterListsFromProtobuf() async -> ([FilterList], [FilterList]) {
        await ProtobufDataManager.shared.waitUntilLoaded()
        let allFilters = await hydrateMissingSourceRuleCountsIfNeeded(
            await ProtobufDataManager.shared.getFilterLists()
        )
        let selectedFilters = allFilters.filter { $0.isSelected }

        return (allFilters, selectedFilters)
    }

    private func saveFilterListsToProtobuf(_ lists: [FilterList]) async {
        await ProtobufDataManager.shared.updateFilterLists(lists)
    }

    private func hydrateMissingSourceRuleCountsIfNeeded(_ filters: [FilterList]) async -> [FilterList] {
        guard filters.contains(where: { $0.sourceRuleCount == nil }) else {
            return filters
        }

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
        ) else {
            return filters
        }

        var hydratedFilters = filters
        var didHydrate = false

        for index in hydratedFilters.indices where hydratedFilters[index].sourceRuleCount == nil {
            guard let localData = localDataForComparison(
                filter: hydratedFilters[index],
                containerURL: containerURL
            ) else {
                continue
            }

            hydratedFilters[index].sourceRuleCount = countRulesInData(data: localData)
            didHydrate = true
        }

        if didHydrate {
            await saveFilterListsToProtobuf(hydratedFilters)
        }

        return hydratedFilters
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
        let remoteFilters = filters.filter {
            guard let scheme = $0.url.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }


        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            throw AutoUpdateError.sharedContainerUnavailable
        }

        var updatedFilters: [FilterList] = []
        var hadErrors = false
        var errorCount = 0
        var validatorUpdates: [String: (etag: String?, lastModified: String?)] = [:]

        await boundedConcurrentForEach(remoteFilters, operation: { filter in
            await self.fetchIfUpdated(filter, containerURL: containerURL)
        }, onResult: { outcome in
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
        })

        try Task.checkCancellation()

        if !validatorUpdates.isEmpty {
            await ProtobufDataManager.shared.setFilterValidators(validatorUpdates)
        }

        return UpdateFetchResult(
            updatedFilters: updatedFilters,
            hadErrors: hadErrors,
            errorCount: errorCount,
            checkedCount: remoteFilters.count
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

            // Decode raw data for preprocessing
            guard let rawContent = String(data: data, encoding: .utf8) else {
                return .error(filterName: filter.name, error: URLError(.cannotDecodeContentData))
            }

            // PREP-07: Strip unknown !# directives before preprocessing.
            let processedContent = stripUnknownDirectives(from: rawContent)

            // OBSV-02: Measure pre-expansion rule count.
            let rawCount = countRulesInData(data: Data(processedContent.utf8))

            // Preprocess: expand !#include directives and evaluate !#if conditionals.
            // Skip for built-in optimized lists — already pre-expanded.
            let finalContent: String
            if filter.isOptimizedBuiltin {
                finalContent = processedContent
            } else {
                let filterName = filter.name
                let preprocessor = FilterPreprocessor(
                    onFetchError: { subURL, statusCode in
                        let statusStr = statusCode.map { "\($0)" } ?? "network error"
                        await self.appendSharedLog(
                            "!#include fetch failed: filter=\(filterName), subURL=\(subURL.absoluteString), status=\(statusStr)"
                        )
                    }
                )
                finalContent = await preprocessor.preprocess(
                    content: processedContent,
                    listURL: filter.url
                )
            }

            guard let finalData = finalContent.data(using: .utf8) else {
                return .error(filterName: filter.name, error: URLError(.cannotDecodeContentData))
            }

            do {
                try finalData.write(to: localURL, options: .atomic)
            } catch {
                return .error(filterName: filter.name, error: error)
            }

            let meta = parseMetadata(from: String(finalContent.prefix(8192)))

            let ruleCount = countRulesInData(data: finalData)

            var updated = filter
            if let version = meta.version, !version.isEmpty { updated.version = version }
            if let desc = meta.description, !desc.isEmpty { updated.description = desc }
            updated.sourceRuleCount = ruleCount
            updated.rawSourceRuleCount = rawCount
            return .updated(
                filter: updated,
                validators: (etag: responseEtag, lastModified: responseLastModified)
            )
        } catch {
            return .error(filterName: filter.name, error: error)
        }
    }

    private func makeConditionalRequest(for filter: FilterList, etag: String?, lastModified: String?) -> URLRequest {
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

    private func isExternalHelperTrigger(_ trigger: String) -> Bool {
        switch trigger {
        case "XPCService", "LaunchAgent", "LegacyLoginItem":
            return true
        default:
            return false
        }
    }

    private func contentBlockerOutputsContainRules() -> Bool {
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
            guard let data = try? Data(contentsOf: rulesURL), !data.isEmpty else {
                continue
            }

            if data.contains(UInt8(ascii: "{")) {
                return true
            }
        }

        return false
    }

    private func clearPersistedBlockingOutputsForPause() async -> Bool {
        #if os(iOS)
        let platform: Platform = .iOS
        #else
        let platform: Platform = .macOS
        #endif

        var failedTargets: [String] = []
        let groupIdentifier = GroupIdentifier.shared.value

        do {
            try ContentBlockerService.clearFilterEngine(groupIdentifier: groupIdentifier)
        } catch {
            appendSharedLog("Failed to clear paused advanced engine during auto-update: \(error.localizedDescription)")
        }

        do {
            _ = try RemoveParamDNRRuleGenerator.clearSavedRules(groupIdentifier: groupIdentifier)
        } catch {
            appendSharedLog("Failed to clear paused removeparam rules during auto-update: \(error.localizedDescription)")
        }

        for target in ContentBlockerTargetManager.shared.allTargets(forPlatform: platform) {
            let savedRuleCount = try? ContentBlockerService.saveContentBlocker(
                jsonRules: ContentBlockerService.inertContentBlockerRulesJSON,
                groupIdentifier: groupIdentifier,
                targetRulesFilename: target.rulesFilename
            )
            if savedRuleCount != ContentBlockerService.inertContentBlockerRuleCount {
                failedTargets.append(target.displayName)
                continue
            }

            let reloadResult = await ContentBlockerService.reloadWithRetry(
                identifier: target.bundleIdentifier
            )
            if !reloadResult.success {
                failedTargets.append(target.displayName)
            }
        }

        if failedTargets.isEmpty {
            return true
        }

        appendSharedLog(
            "Failed to clear paused blocker outputs for: \(failedTargets.prefix(3).joined(separator: ", "))"
        )
        return false
    }

    private func reloadExistingContentBlockers(
        policy: AutoUpdateExecutionPolicy
    ) async throws {
        #if os(iOS)
        let platform: Platform = .iOS
        #else
        let platform: Platform = .macOS
        #endif

        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: platform)
        var failedTargets: [String] = []
        var advancedRulesSnippets: [String] = []

        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value)

        for target in targets {
            try Task.checkCancellation()
            try checkBudget(
                policy,
                phase: AutoUpdateBudgetPhase.reloadRetry,
                requiredTime: policy.minimumTimeForReloadRetry
            )

            let reloadResult = await ContentBlockerService.reloadWithRetry(identifier: target.bundleIdentifier, maxRetries: 6)
            if !reloadResult.success {
                failedTargets.append(target.displayName)
            }
            if let containerURL,
               let adv = loadCachedAdvancedRules(for: target, containerURL: containerURL),
               !adv.isEmpty {
                advancedRulesSnippets.append(adv)
            }
        }

        try publishAdvancedEngine(
            advancedRulesSnippets: advancedRulesSnippets,
            policy: policy,
            failureLogPrefix: "Advanced engine publish failed while reusing existing outputs"
        )

        if !failedTargets.isEmpty {
            appendSharedLog(
                "Reload failures while reusing existing outputs: \(failedTargets.prefix(3).joined(separator: ", "))"
            )
            throw AutoUpdateError.contentBlockerReloadFailed(
                identifiers: [],
                names: failedTargets
            )
        }
    }

    // MARK: - Conversion & Reload
    private struct ConversionTargetWork: Sendable {
        let target: ContentBlockerTargetInfo
        let filters: [FilterList]
        let allTargets: [ContentBlockerTargetInfo]
        let containerURL: URL
        let disabledSites: [String]
        let affinityFilterIDs: Set<UUID>
        let orderedFilters: [FilterList]
        let extraRulesText: String?
        let isBackground: Bool
        let deadline: Date?
        let minimumTimeForConversionTarget: TimeInterval
    }

    private enum ConversionTargetFailure: Sendable {
        case cancelled
        case budgetExpired(remainingSeconds: Int)
        case failed(description: String)
    }

    private struct ConversionTargetResult: Sendable {
        let target: ContentBlockerTargetInfo
        let conversion: (safariRulesCount: Int, advancedRulesText: String?)?
        let usedCache: Bool
        let inputWriteMs: Int
        let inputBytes: Int64
        let conversionMs: Int
        let failure: ConversionTargetFailure?
    }

    private nonisolated static func convertTarget(_ work: ConversionTargetWork) -> ConversionTargetResult {
        let target = work.target
        let filters = work.filters
        let assigned = Set(filters.map(\.id))
        let hasAffinity = !assigned.isDisjoint(with: work.affinityFilterIDs)
        let rulesFilename = target.rulesFilename
        let start = Date()
        var writeMs = 0
        if work.isBackground, let deadline = work.deadline,
           deadline.timeIntervalSinceNow < work.minimumTimeForConversionTarget {
            return ConversionTargetResult(
                target: target,
                conversion: nil,
                usedCache: false,
                inputWriteMs: 0,
                inputBytes: 0,
                conversionMs: 0,
                failure: .budgetExpired(
                    remainingSeconds: max(0, Int(deadline.timeIntervalSinceNow.rounded(.down)))
                )
            )
        }
        var bytes: Int64 = 0
        do {
            let currentSignature = hasAffinity ? nil : ContentBlockerIncrementalCache.computeInputSignature(
                filters: filters, groupIdentifier: GroupIdentifier.shared.value, extraRulesText: work.extraRulesText
            )
            let storedSignature = ContentBlockerIncrementalCache.loadInputSignature(
                targetRulesFilename: rulesFilename, groupIdentifier: GroupIdentifier.shared.value
            )
            let canReuse = currentSignature != nil && currentSignature == storedSignature &&
                ContentBlockerIncrementalCache.hasBaseRulesCache(
                    targetRulesFilename: rulesFilename, groupIdentifier: GroupIdentifier.shared.value
                )
            let conversion: (safariRulesCount: Int, advancedRulesText: String?)
            let usedCache: Bool
            if canReuse {
                usedCache = true
                conversion = try ContentBlockerService.fastUpdateDisabledSites(
                    groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: rulesFilename,
                    disabledSites: work.disabledSites
                )
            } else {
                if hasAffinity {
                    ContentBlockerIncrementalCache.invalidateInputSignature(
                        targetRulesFilename: rulesFilename, groupIdentifier: GroupIdentifier.shared.value
                    )
                }
                usedCache = false
                let tempURL = work.containerURL.appendingPathComponent("temp_autoupdate_\(target.bundleIdentifier).txt")
                defer { try? FileManager.default.removeItem(at: tempURL) }
                FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
                let newline = Data("\n".utf8)
                var hasher = SHA256()
                let handle = try FileHandle(forWritingTo: tempURL)
                defer { try? handle.close() }
                let writeStart = Date()
                for filter in work.orderedFilters {
                    try Task.checkCancellation()
                    let includeBaseRules = assigned.contains(filter.id)
                    let hasAffinity = work.affinityFilterIDs.contains(filter.id)
                    guard includeBaseRules || hasAffinity else { continue }
                    if hasAffinity {
                        do {
                            _ = try SafariContentBlockerAffinityProcessor.appendAffinityFilteredContribution(
                                for: filter, includeBaseRules: includeBaseRules, target: target,
                                allTargets: work.allTargets, containerURL: work.containerURL,
                                destinationHandle: handle, hasher: &hasher, newlineData: newline
                            )
                        } catch {
                            let workerLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "wBlock", category: "AutoUpdate")
                            os_log("Failed to stream affinity-filtered data from %{public}@ – %{public}@",
                                   log: workerLog, type: .error, filter.name, error.localizedDescription)
                        }
                    } else if let sourceURL = SafariContentBlockerAffinityProcessor.sourceURL(
                        for: filter, containerURL: work.containerURL
                    ) {
                        _ = try ContentBlockerInputWriter.appendFile(
                            from: sourceURL, to: handle, hasher: &hasher, newlineData: newline,
                            policy: .permissive { error in
                                let workerLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "wBlock", category: "AutoUpdate")
                                os_log("Failed to stream filter data from %{public}@ – %{public}@",
                                       log: workerLog, type: .error, sourceURL.lastPathComponent, error.localizedDescription)
                            }
                        )
                    }
                }
                if let extra = work.extraRulesText, !extra.isEmpty {
                    try ContentBlockerInputWriter.appendInline(
                        extra, to: handle, hasher: &hasher, newlineData: newline
                    )
                }
                writeMs = Int(Date().timeIntervalSince(writeStart) * 1000)
                bytes = Self.fileSizeBytes(at: tempURL)
                let digest = hasher.finalize()
                let hex = digest.map { String(format: "%02x", $0) }.joined()
                conversion = try ContentBlockerService.convertFilterFromFile(
                    rulesFileURL: tempURL, rulesSHA256Hex: hex, groupIdentifier: GroupIdentifier.shared.value,
                    targetRulesFilename: rulesFilename, disabledSites: work.disabledSites
                )
                if let currentSignature {
                    ContentBlockerIncrementalCache.saveInputSignature(
                        currentSignature, targetRulesFilename: rulesFilename, groupIdentifier: GroupIdentifier.shared.value
                    )
                }
            }
            return ConversionTargetResult(
                target: target,
                conversion: conversion,
                usedCache: usedCache,
                inputWriteMs: writeMs,
                inputBytes: bytes,
                conversionMs: Int(Date().timeIntervalSince(start) * 1000),
                failure: nil
            )
        } catch is CancellationError {
            return ConversionTargetResult(
                target: target,
                conversion: nil,
                usedCache: false,
                inputWriteMs: writeMs,
                inputBytes: bytes,
                conversionMs: Int(Date().timeIntervalSince(start) * 1000),
                failure: .cancelled
            )
        } catch {
            return ConversionTargetResult(
                target: target,
                conversion: nil,
                usedCache: false,
                inputWriteMs: writeMs,
                inputBytes: bytes,
                conversionMs: Int(Date().timeIntervalSince(start) * 1000),
                failure: .failed(description: error.localizedDescription)
            )
        }
    }

    private func rebuildAndReload(
        selectedFilters: [FilterList],
        policy: AutoUpdateExecutionPolicy
    ) async throws -> RebuildAndReloadSummary {
        try Task.checkCancellation()
        #if os(iOS)
        let detectedPlatform: Platform = .iOS
        #else
        let detectedPlatform: Platform = .macOS
        #endif
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: detectedPlatform)
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            throw AutoUpdateError.sharedContainerUnavailable
        }
        let disabledSites = await getDisabledSites()
        do {
            let summary = try RemoveParamDNRRuleGenerator.saveRules(for: selectedFilters, disabledSites: disabledSites, groupIdentifier: GroupIdentifier.shared.value)
            appendSharedLog("Prepared removeparam DNR rules: generated=\(summary.generatedRules) source=\(summary.removeParamRules) exceptions=\(summary.exceptionRules) skipped=\(summary.skippedRules)")
        } catch { appendSharedLog("Failed to prepare removeparam DNR rules: \(error.localizedDescription)") }
        let ordered = ContentBlockerMappingService.orderedForDistribution(selectedFilters)
        let byTarget = ContentBlockerMappingService.distribute(selectedFilters: selectedFilters, across: targets)
        let affinity = SafariContentBlockerAffinityProcessor.detectFiltersWithAffinity(ordered, containerURL: containerURL)
        let zapper = await MainActor.run { ZapperContentBlockerRuleGenerator.generatedRulesText(from: ProtobufDataManager.shared.getActiveZapperRulesByHost()) }
        var results: [String: ConversionTargetResult] = [:]
        let works = targets.map { target in
            ConversionTargetWork(
                target: target,
                filters: byTarget[target] ?? [],
                allTargets: targets,
                containerURL: containerURL,
                disabledSites: disabledSites,
                affinityFilterIDs: affinity,
                orderedFilters: ordered,
                extraRulesText: target.slot == 5 ? zapper : nil,
                isBackground: policy.isBackground,
                deadline: policy.deadline,
                minimumTimeForConversionTarget: policy.minimumTimeForConversionTarget
            )
        }
        await boundedConcurrentForEach(
            works,
            operation: { Self.convertTarget($0) },
            onResult: { result in
                results[result.target.bundleIdentifier] = result
            }
        )

        for target in targets {
            guard let result = results[target.bundleIdentifier] else {
                throw CancellationError()
            }
            switch result.failure {
            case .cancelled:
                throw CancellationError()
            case let .budgetExpired(remainingSeconds):
                throw AutoUpdateError.backgroundBudgetExpired(
                    phase: AutoUpdateBudgetPhase.conversionTarget,
                    remainingSeconds: remainingSeconds
                )
            case let .failed(description):
                throw NSError(
                    domain: "SharedAutoUpdateManager.Conversion",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: description]
                )
            case nil:
                guard result.conversion != nil else { throw CancellationError() }
            }
        }

        var metrics: [RebuildTargetMetrics] = []
        var advanced: [String] = []
        var failedIDs: [String] = []
        var failedNames: [String] = []
        for target in targets {
            try Task.checkCancellation()
            try checkBudget(
                policy,
                phase: AutoUpdateBudgetPhase.reloadRetry,
                requiredTime: policy.minimumTimeForReloadRetry
            )
            guard let result = results[target.bundleIdentifier],
                  let conversion = result.conversion else {
                throw CancellationError()
            }
            let cached = ContentBlockerIncrementalCache.loadCachedAdvancedRules(
                targetRulesFilename: target.rulesFilename,
                groupIdentifier: GroupIdentifier.shared.value
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fresh = conversion.advancedRulesText?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let snippet = fresh?.isEmpty == false ? fresh : cached, !snippet.isEmpty {
                advanced.append(snippet)
            }

            let reload = await ContentBlockerService.reloadWithRetry(
                identifier: target.bundleIdentifier,
                maxRetries: 6
            )
            metrics.append(
                RebuildTargetMetrics(
                    targetName: target.displayName,
                    cacheHit: result.usedCache,
                    inputWriteMs: result.inputWriteMs,
                    inputBytes: result.inputBytes,
                    conversionMs: result.conversionMs,
                    reloadMs: reload.durationMs,
                    reloadAttempts: reload.attempts,
                    safariRules: conversion.safariRulesCount
                )
            )
            if !reload.success {
                failedIDs.append(target.bundleIdentifier)
                failedNames.append(target.displayName)
            }
        }
        if !failedIDs.isEmpty {
            appendSharedLog("Rebuild reload failures: \(failedNames.joined(separator: ", "))")
            throw AutoUpdateError.contentBlockerReloadFailed(identifiers: failedIDs, names: failedNames)
        }
        try publishAdvancedEngine(advancedRulesSnippets: advanced, policy: policy, failureLogPrefix: "Advanced engine publish failed after rebuilding content blockers")
        let hits = metrics.filter(\.cacheHit).count
        let writes = metrics.reduce(0) { $0 + $1.inputWriteMs }
        let bytes = metrics.reduce(Int64(0)) { $0 + $1.inputBytes }
        let conversions = metrics.reduce(0) { $0 + $1.conversionMs }
        let reloads = metrics.reduce(0) { $0 + $1.reloadMs }
        let attempts = metrics.reduce(0) { $0 + $1.reloadAttempts }
        let safari = metrics.reduce(0) { $0 + $1.safariRules }
        let slowWrite = metrics.filter { $0.inputWriteMs > 0 }.max(by: { $0.inputWriteMs < $1.inputWriteMs }).map { "\($0.targetName)@\(formatDurationMs($0.inputWriteMs))" } ?? "n/a"
        let slow = metrics.max(by: { ($0.conversionMs + $0.reloadMs) < ($1.conversionMs + $1.reloadMs) }).map { "\($0.targetName)@\(formatDurationMs($0.conversionMs + $0.reloadMs))" } ?? "n/a"
        return RebuildAndReloadSummary(targetCount: metrics.count, cacheHits: hits, cacheMisses: max(0, metrics.count - hits), safariRulesTotal: safari, inputWriteDurationMs: writes, inputBytesTotal: bytes, conversionDurationMs: conversions, reloadDurationMs: reloads, totalReloadAttempts: attempts, slowestWriteTarget: slowWrite, slowestTarget: slow)
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

        let normalizedVersion = rawMetadata.version
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

    // MARK: - Directive Stripping (PREP-07)

    private func stripUnknownDirectives(from content: String) -> String {
        var result: [String] = []
        for line in content.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let originalLine = String(line)
            guard FilterDirectivePolicy.shouldStripUnsupportedDirective(trimmed) else {
                result.append(originalLine)
                continue
            }
            // Unknown directive: silently omitted (PREP-07)
        }
        return result.joined(separator: "\n")
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

    private nonisolated static func fileSizeBytes(at url: URL) -> Int64 {
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
