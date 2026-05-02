//
//  AppDelegate.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI
import Combine
import os.log
#if os(macOS)
import Cocoa
import wBlockCoreService
#elseif os(iOS)
import UIKit
import UserNotifications
import BackgroundTasks
import wBlockCoreService
#endif

// Define the notification name globally or in a shared place
extension Notification.Name {
    static let applyWBlockChangesNotification = Notification.Name("applyWBlockChangesNotification_unique_identifier")
}
#if os(iOS)
@MainActor
private final class BackgroundTaskHandle {
    private let application: UIApplication
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(application: UIApplication) {
        self.application = application
    }

    @discardableResult
    func start(name: String) -> Bool {
        identifier = application.beginBackgroundTask(withName: name) { [weak self] in
            os_log("Background task expired: %{public}@", type: .error, name)
            Task { @MainActor in
                self?.end()
            }
        }

        if identifier == .invalid {
            os_log("Failed to begin background task: %{public}@", type: .error, name)
            return false
        }

        return true
    }

    func end() {
        guard identifier != .invalid else { return }
        application.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif


class AppDelegate: NSObject {
    var filterManager: AppFilterManager?
    var hasPendingApplyNotification = false

    // MARK: - Background Update Constants

    /// Time threshold (in seconds) for considering an update "due soon"
    private let dueSoonThresholdSeconds: TimeInterval = 300 // 5 minutes

    #if os(macOS)
    /// Percentage of interval used for scheduler tolerance (0.0-1.0)
    private let schedulerTolerancePercentage: Double = 0.2 // 20%
    /// Maximum tolerance in hours regardless of interval
    private let maxSchedulerToleranceHours: Double = 1.0
    /// Interval for periodic timer checks (in seconds)
    private let periodicTimerInterval: TimeInterval = 30 * 60 // 30 minutes
    /// macOS-only scheduler holder
    private var backgroundScheduler: NSBackgroundActivityScheduler?
    /// Periodic timer for regular update checks
    private var periodicUpdateTimer: Timer?
    private var autoUpdateSaveObserver: AnyCancellable?
    private var lastObservedAutoUpdateEnabled: Bool?
    #endif

    #if os(iOS)
    private let backgroundTaskIdentifier = "com.alexanderskula.wblock.filter-update"
    private let backgroundProcessingIdentifier = "com.alexanderskula.wblock.filter-processing"

    /// Factor to multiply interval by for app refresh scheduling (accounts for iOS discretion)
    private let appRefreshScheduleDelayFactor: Double = 0.75
    /// Minimum schedule delay for app refresh (in hours)
    private let minAppRefreshDelayHours: Double = 1.0
    /// Maximum schedule delay for app refresh (in hours)
    private let maxAppRefreshDelayHours: Double = 12.0

    /// Minimum schedule delay for background processing (in hours)
    private let minProcessingDelayHours: Double = 1.0
    /// Maximum schedule delay for background processing (in hours)
    private let maxProcessingDelayHours: Double = 24.0
    #endif
}

private extension AppDelegate {
    @discardableResult
    func runForcedAutoUpdate(
        trigger: String,
        policy: SharedAutoUpdateManager.AutoUpdateExecutionPolicy? = nil
    ) async -> SharedAutoUpdateManager.AutoUpdateRunOutcome {
        await SharedAutoUpdateManager.shared.forceNextUpdate()
        let resolvedPolicy = policy ?? SharedAutoUpdateManager.AutoUpdateExecutionPolicy.foreground(trigger: trigger)
        return await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(
            trigger: trigger,
            force: true,
            policy: resolvedPolicy
        )
    }

    @MainActor
    func configuredAutoUpdateIntervalHours(defaultValue: Double = 6.0, minimum: Double = 1.0) -> Double {
        let storedInterval = ProtobufDataManager.shared.autoUpdateIntervalHours
        return max(storedInterval > 0 ? storedInterval : defaultValue, minimum)
    }
}

#if os(iOS)
private actor BGTaskCompletionState {
    private var didComplete = false

    func claimCompletion() -> Bool {
        guard !didComplete else { return false }
        didComplete = true
        return true
    }
}
#endif

// MARK: - Shared helper for schedule log formatting (platform-agnostic)
fileprivate func scheduleMessage(from status: SharedAutoUpdateManager.AutoUpdateStatus) -> String {
    let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var message = ""
    if let scheduledAt = status.scheduledAt, let remaining = status.remaining {
        if status.isRunning {
            message = "🔄 Auto-update: currently running"
        } else if status.isOverdue {
            message = "⚠️ Auto-update: overdue (will run on next trigger)"
        } else if remaining == 0 {
            message = "🕒 Auto-update: due now (will run on next trigger)"
        } else {
            let hrs = Int(remaining) / 3600
            let mins = (Int(remaining) % 3600) / 60
            let secs = Int(remaining) % 60
            message = "🕒 Auto-update: next in \(hrs)h \(mins)m \(secs)s"
        }
        message += " · Scheduled: \(formatter.string(from: scheduledAt))"
    } else {
        message = "🕒 Auto-update: no prior run yet (interval=\(status.intervalHours)h)"
    }

    if let lastSuccessful = status.lastSuccessful {
        message += " · Last success: \(formatter.string(from: lastSuccessful))"
    }

    return message
}

#if os(macOS)
extension AppDelegate: NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let filterManager = filterManager, filterManager.hasUnappliedChanges else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = LocalizedStrings.text(
            "Unapplied Filter Changes",
            comment: "Quit confirmation title"
        )
        alert.informativeText = LocalizedStrings.text(
            "You have unapplied filter changes. Do you want to apply them before quitting?",
            comment: "Quit confirmation message"
        )
        alert.addButton(
            withTitle: LocalizedStrings.text(
                "Apply Changes and Quit",
                comment: "Quit confirmation primary action"
            )
        )
        alert.addButton(
            withTitle: LocalizedStrings.text(
                "Quit Without Applying",
                comment: "Quit confirmation destructive action"
            )
        )
        alert.alertStyle = .warning

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn: // Apply Changes and Quit
            Task {
                await filterManager.applyChanges()
                // Ensure changes are applied before terminating
                DispatchQueue.main.async {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
            return .terminateLater
        case .alertSecondButtonReturn: // Quit Without Applying
            return .terminateNow
        default:
            return .terminateNow
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up periodic timer
        periodicUpdateTimer?.invalidate()
        periodicUpdateTimer = nil

        // Flush any pending coalesced filter list saves
        filterManager?.flushPendingSave()

        // Flush any pending protobuf saves
        ProtobufDataManager.shared.saveData()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup periodic auto-update system for macOS
        setupMacOSAutoUpdate()
        observeMacOSAutoUpdateSettingSaves()
        Task { @MainActor in
            await reconcileMacOSLaunchAgentRegistration(reason: "Launch")
        }

        // Opportunistic update on app launch
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()

            // Force update if significantly overdue (>1 hour past scheduled time)
            let oneHourInSeconds: TimeInterval = 3600
            let isSignificantlyOverdue = if let remaining = status.remaining {
                remaining == 0 && status.scheduledAt != nil && Date().timeIntervalSince(status.scheduledAt!) > oneHourInSeconds
            } else {
                false
            }

            if isSignificantlyOverdue && !status.isRunning {
                os_log("App launch: update significantly overdue (>1h) - forcing update", type: .info)
                await runForcedAutoUpdate(trigger: "AppLaunch")
            } else {
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "AppLaunch")
            }

            await ConcurrentLogManager.shared.info(.autoUpdate, scheduleMessage(from: status), metadata: [:])
        }
    }
    
    func applicationWillBecomeActive(_ notification: Notification) {
        // Check if update is overdue when app becomes active
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            let isDueSoon = if let remaining = status.remaining { remaining < dueSoonThresholdSeconds } else { false }

            // If overdue or due soon, force update
            if status.isOverdue || (isDueSoon && !status.isRunning) {
                await runForcedAutoUpdate(trigger: "BecomeActive")
            } else {
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BecomeActive")
            }
        }
    }
    
    // MARK: - macOS Auto-Update System
    
    @MainActor private func setupMacOSAutoUpdate() {
        // More aggressive periodic trigger while app is running
        periodicUpdateTimer = Timer.scheduledTimer(withTimeInterval: periodicTimerInterval, repeats: true) { [weak self] _ in
            Task { await self?.runMacOSBackgroundUpdate(trigger: "PeriodicTimer") }
        }

        let intervalHours = configuredAutoUpdateIntervalHours()
        
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.alexanderskula.wblock.filterupdate")
        scheduler.repeats = true
        scheduler.interval = intervalHours * 60 * 60 // Use configured interval
        scheduler.tolerance = min(intervalHours * schedulerTolerancePercentage, maxSchedulerToleranceHours) * 60 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task {
                await self?.runMacOSBackgroundUpdate(trigger: "BackgroundActivityScheduler")
                completion(NSBackgroundActivityScheduler.Result.finished)
            }
        }
        self.backgroundScheduler = scheduler
    }

    @MainActor private func observeMacOSAutoUpdateSettingSaves() {
        autoUpdateSaveObserver = ProtobufDataManager.shared.didSaveData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor in
                    await self?.reconcileMacOSLaunchAgentRegistration(reason: "SavedSettings")
                }
            }
    }

    @MainActor private func reconcileMacOSLaunchAgentRegistration(reason: String) async {
        await ProtobufDataManager.shared.waitUntilLoaded()
        let enabled = ProtobufDataManager.shared.autoUpdateEnabled
        guard lastObservedAutoUpdateEnabled != enabled || reason == "Launch" else { return }
        lastObservedAutoUpdateEnabled = enabled

        let status = AutoUpdateLaunchAgentManager.shared.reconcileWithAutoUpdateSetting(enabled)
        os_log(
            "Launch agent reconciliation (%{public}@): %{public}@",
            type: .info,
            reason,
            status.detail
        )
    }


    private func runMacOSBackgroundUpdate(trigger: String) async {
        // Check if update is overdue
        let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()

        // If an XPC service exists in future builds, prefer it; else fallback in-process
        #if os(macOS)
        let usedXPC = await FilterUpdateClient.shared.updateFilters()
        if usedXPC { return }
        #endif

        // Force update if overdue
        if status.isOverdue && !status.isRunning {
            await runForcedAutoUpdate(trigger: trigger)
        } else {
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: trigger)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "wblockapp" }) else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

}

#endif

#if os(iOS)
extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        // Register background tasks for filter updates (refresh + processing)
        registerBackgroundTasks()

        // Schedule initial background refresh + processing tasks (also re-schedules after protobuf loads)
        scheduleBackgroundFilterUpdate()
        scheduleBackgroundProcessingUpdate()
        Task { @MainActor in
            await rescheduleBackgroundTasks(reason: "Launch")
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Run opportunistic updates only when app is active (not during background launches).
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            let isDueSoon = if let remaining = status.remaining { remaining < dueSoonThresholdSeconds } else { false }

            // If overdue or due soon, force update
            if status.isOverdue || (isDueSoon && !status.isRunning) {
                let catchUpReason: AutoUpdateDiagnosticResult = status.isOverdue ? .overdue : .dueSoon
                os_log("App became active with overdue/due update - forcing update", type: .info)
                await ProtobufDataManager.shared.recordAutoUpdateForegroundCatchUp(reason: catchUpReason)
                await runForcedAutoUpdate(trigger: "BecomeActive")
            } else {
                // Normal opportunistic update
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BecomeActive")
            }

            await ConcurrentLogManager.shared.info(.autoUpdate, scheduleMessage(from: status), metadata: [:])
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Schedule next background tasks when entering background
        scheduleBackgroundFilterUpdate()
        scheduleBackgroundProcessingUpdate()
        Task { @MainActor in
            await rescheduleBackgroundTasks(reason: "EnterBackground")
        }

        // Flush any pending coalesced filter list saves
        filterManager?.flushPendingSave()

        // Flush pending protobuf saves with background time instead of leaving a
        // debounced disk write to race app suspension.
        flushProtobufDataForBackgroundTransition(reason: "EnterBackground")
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Flush any pending coalesced filter list saves
        filterManager?.flushPendingSave()

        flushProtobufDataForBackgroundTransition(reason: "Terminate")
    }
    
    // MARK: - Background Task Management
    
    @MainActor
    private func flushProtobufDataForBackgroundTransition(reason: String) {
        let application = UIApplication.shared

        let backgroundTask = BackgroundTaskHandle(application: application)
        let didStartBackgroundTask = backgroundTask.start(name: "wBlock protobuf save: \(reason)")

        Task { @MainActor in
            defer {
                if didStartBackgroundTask {
                    backgroundTask.end()
                }
            }

            let didSave = await ProtobufDataManager.shared.saveDataImmediately()
            if !didSave {
                os_log("Failed to flush protobuf data during %{public}@", type: .error, reason)
            }
        }
    }

    private func registerBackgroundTasks() {
        let refreshRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                os_log(
                    "Unexpected BGTask type for %{public}@ (%{public}@)",
                    type: .error,
                    self.backgroundTaskIdentifier,
                    String(describing: type(of: task))
                )
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundFilterUpdate(task: refreshTask)
        }
        if !refreshRegistered {
            os_log("Failed to register BG task identifier %{public}@", type: .error, backgroundTaskIdentifier)
        }

        let processingRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundProcessingIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                os_log(
                    "Unexpected BGTask type for %{public}@ (%{public}@)",
                    type: .error,
                    self.backgroundProcessingIdentifier,
                    String(describing: type(of: task))
                )
                task.setTaskCompleted(success: false)
                return
            }
            self.handleBackgroundProcessingUpdate(task: processingTask)
        }
        if !processingRegistered {
            os_log("Failed to register BG task identifier %{public}@", type: .error, backgroundProcessingIdentifier)
        }
    }

    @MainActor
    private func scheduleBackgroundFilterUpdate() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // Use protobuf-backed interval (legacy UserDefaults may be stale). Fall back to 6h if unset.
        let intervalHours = configuredAutoUpdateIntervalHours()
        // Schedule for 75% of interval to account for iOS's discretionary nature
        let delaySeconds = min(max(intervalHours * appRefreshScheduleDelayFactor, minAppRefreshDelayHours), maxAppRefreshDelayHours) * 60 * 60
        request.earliestBeginDate = Date(timeIntervalSinceNow: delaySeconds)

        do {
            // Cancel and resubmit atomically
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
            try BGTaskScheduler.shared.submit(request)
            os_log("Background filter update task scheduled successfully (delay: %.1f hrs)", type: .info, delaySeconds / 3600)
            Task { @MainActor in
                await ProtobufDataManager.shared.recordAutoUpdateTaskScheduleAttempt(
                    .appRefresh,
                    result: .submitted
                )
            }
        } catch let error as NSError {
            let details = taskScheduleFailureDetails(for: error)
            if error.domain == "BGTaskSchedulerErrorDomain" {
                switch error.code {
                case 1: os_log("BGTaskScheduler: Identifier not in Info.plist", type: .error)
                case 2: os_log("BGTaskScheduler: Too many pending tasks", type: .error)
                case 3: os_log("BGTaskScheduler: Background tasks unavailable", type: .error)
                default: os_log("BGTaskScheduler error: %{public}@", type: .error, error.localizedDescription)
                }
            } else {
                os_log("Failed to schedule background filter update: %{public}@", type: .error, error.localizedDescription)
            }
            Task { @MainActor in
                await ProtobufDataManager.shared.recordAutoUpdateTaskScheduleAttempt(
                    .appRefresh,
                    result: details.result,
                    error: details.message
                )
            }
        }
    }

    @MainActor
    private func scheduleBackgroundProcessingUpdate() {
        let request = BGProcessingTaskRequest(identifier: backgroundProcessingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false // Don't require power - be more aggressive
        // Schedule processing task for full interval (less critical than app refresh)
        let intervalHours = configuredAutoUpdateIntervalHours()
        let delaySeconds = min(max(intervalHours, minProcessingDelayHours), maxProcessingDelayHours) * 60 * 60
        request.earliestBeginDate = Date(timeIntervalSinceNow: delaySeconds)
        do {
            // Cancel and resubmit atomically
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundProcessingIdentifier)
            try BGTaskScheduler.shared.submit(request)
            os_log("Background processing task scheduled successfully (delay: %.1f hrs)", type: .info, delaySeconds / 3600)
            Task { @MainActor in
                await ProtobufDataManager.shared.recordAutoUpdateTaskScheduleAttempt(
                    .processing,
                    result: .submitted
                )
            }
        } catch let error as NSError {
            let details = taskScheduleFailureDetails(for: error)
            if error.domain == "BGTaskSchedulerErrorDomain" {
                switch error.code {
                case 1: os_log("BGTaskScheduler: Processing identifier not in Info.plist", type: .error)
                case 2: os_log("BGTaskScheduler: Too many pending processing tasks", type: .error)
                case 3: os_log("BGTaskScheduler: Background processing unavailable", type: .error)
                default: os_log("BGTaskScheduler processing error: %{public}@", type: .error, error.localizedDescription)
                }
            } else {
                os_log("Failed to schedule background processing task: %{public}@", type: .error, error.localizedDescription)
            }
            Task { @MainActor in
                await ProtobufDataManager.shared.recordAutoUpdateTaskScheduleAttempt(
                    .processing,
                    result: details.result,
                    error: details.message
                )
            }
        }
    }
    
    private func taskScheduleFailureDetails(for error: NSError) -> (result: AutoUpdateDiagnosticResult, message: String) {
        guard error.domain == "BGTaskSchedulerErrorDomain" else {
            return (.submitFailed, error.localizedDescription)
        }

        switch error.code {
        case 1:
            return (.infoPlistMissing, "Identifier not in Info.plist")
        case 2:
            return (.tooManyPending, "Too many pending tasks")
        case 3:
            return (.unavailable, "Background tasks unavailable")
        default:
            return (.schedulerError, error.localizedDescription)
        }
    }

    @MainActor
    private func backgroundAutoUpdateDeadline(safetyMargin: TimeInterval = 10) -> Date? {
        let remaining = UIApplication.shared.backgroundTimeRemaining
        guard remaining.isFinite, remaining > 0, remaining < .greatestFiniteMagnitude else {
            return nil
        }
        return Date().addingTimeInterval(max(0, remaining - safetyMargin))
    }

    @MainActor
    private func backgroundAutoUpdatePolicy(
        kind: AutoUpdateDiagnosticTaskKind,
        trigger: String
    ) -> SharedAutoUpdateManager.AutoUpdateExecutionPolicy {
        return .background(
            trigger: trigger,
            deadline: backgroundAutoUpdateDeadline(),
            allowsFullRebuild: kind == .processing
        )
    }

    private func diagnosticResult(
        for outcome: SharedAutoUpdateManager.AutoUpdateRunOutcome
    ) -> AutoUpdateDiagnosticResult {
        switch outcome {
        case .completed, .skipped(_):
            return .completed
        case .cancelled:
            return .timedOut
        case .deferred(_):
            return .deferred
        case .failed(_):
            return .failed
        @unknown default:
            return .failed
        }
    }

    private func handleBackgroundFilterUpdate(task: BGAppRefreshTask) {
        handleForcedBackgroundTask(
            task: task,
            taskLabel: "Background filter update task",
            kind: .appRefresh,
            trigger: "BGAppRefreshTask",
            onSuccess: { delegate in
                delegate.scheduleBackgroundFilterUpdate()
                delegate.scheduleBackgroundProcessingUpdate()
            },
            onExpiration: { delegate in
                delegate.scheduleBackgroundFilterUpdate()
            }
        )
    }

    private func handleBackgroundProcessingUpdate(task: BGProcessingTask) {
        handleForcedBackgroundTask(
            task: task,
            taskLabel: "Background processing update task",
            kind: .processing,
            trigger: "BGProcessingTask",
            onSuccess: { delegate in
                delegate.scheduleBackgroundFilterUpdate()
                delegate.scheduleBackgroundProcessingUpdate()
            },
            onExpiration: { delegate in
                delegate.scheduleBackgroundProcessingUpdate()
            }
        )
    }

    private func handleForcedBackgroundTask(
        task: BGTask,
        taskLabel: String,
        kind: AutoUpdateDiagnosticTaskKind,
        trigger: String,
        onSuccess: @escaping @MainActor (AppDelegate) -> Void,
        onExpiration: @escaping @MainActor (AppDelegate) -> Void
    ) {
        os_log("%{public}@ started", type: .info, taskLabel)
        Task { @MainActor in
            self.scheduleBackgroundFilterUpdate()
            self.scheduleBackgroundProcessingUpdate()
        }
        let completionState = BGTaskCompletionState()
        let updateTask = Task {
            await ProtobufDataManager.shared.recordAutoUpdateTaskStart(kind)
            let policy = await self.backgroundAutoUpdatePolicy(kind: kind, trigger: trigger)
            let outcome = await self.runForcedAutoUpdate(trigger: trigger, policy: policy)
            let success = outcome.isSuccessfulForBackgroundTask
            let result = diagnosticResult(for: outcome)

            switch outcome {
            case .completed, .skipped(_):
                os_log("%{public}@ completed successfully", type: .info, taskLabel)
            case let .deferred(phase):
                os_log("%{public}@ deferred at %{public}@", type: .info, taskLabel, phase)
            case let .failed(message):
                os_log("%{public}@ failed: %{public}@", type: .error, taskLabel, message)
            case .cancelled:
                os_log("%{public}@ cancelled", type: .default, taskLabel)
            @unknown default:
                os_log("%{public}@ failed with an unknown outcome", type: .error, taskLabel)
            }

            guard await completionState.claimCompletion() else { return }
            await ProtobufDataManager.shared.recordAutoUpdateTaskCompletion(kind, result: result)
            task.setTaskCompleted(success: success)
            await MainActor.run {
                if success {
                    onSuccess(self)
                } else {
                    onExpiration(self)
                }
            }
        }

        task.expirationHandler = {
            os_log("%{public}@ expired - clearing running flag", type: .default, taskLabel)
            updateTask.cancel()

            Task { [weak self] in
                guard await completionState.claimCompletion() else { return }
                guard let self else { return }
                await self.clearAutoUpdateRunningFlag(context: taskLabel)
                await ProtobufDataManager.shared.recordAutoUpdateTaskExpiration(kind)
                await ProtobufDataManager.shared.recordAutoUpdateTaskCompletion(kind, result: .timedOut)
                task.setTaskCompleted(success: false)
                await MainActor.run {
                    onExpiration(self)
                }
            }
        }
    }

    private func clearAutoUpdateRunningFlag(context: String) async {
        await ProtobufDataManager.shared.waitUntilLoaded()
        await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
        let didSave = await ProtobufDataManager.shared.saveDataImmediately()
        if !didSave {
            os_log("Failed to clear auto-update running flag during %{public}@", type: .error, context)
        }
    }

    /// Re-schedules BGTaskScheduler requests using the protobuf-backed settings once loaded.
    @MainActor
    private func rescheduleBackgroundTasks(reason: String) async {
        await ProtobufDataManager.shared.waitUntilLoaded()

        let enabled = ProtobufDataManager.shared.autoUpdateEnabled
        if !enabled {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundProcessingIdentifier)
            os_log("Auto-update disabled; canceled background tasks (%{public}@)", type: .info, reason)
            return
        }

        scheduleBackgroundFilterUpdate()
        scheduleBackgroundProcessingUpdate()
        os_log("Rescheduled background tasks (%{public}@)", type: .info, reason)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        if let actionType = userInfo["action_type"] as? String, actionType == "apply_wblock_changes" {
            if filterManager != nil {
                NotificationCenter.default.post(name: .applyWBlockChangesNotification, object: nil)
            } else {
                hasPendingApplyNotification = true
            }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([]) // Don't show alert if app is open, or choose .banner, .list, .sound
    }
}
#endif
