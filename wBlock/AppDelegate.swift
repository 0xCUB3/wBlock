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
    private let minProcessingDelayHours: Double = 2.0
    /// Maximum schedule delay for background processing (in hours)
    private let maxProcessingDelayHours: Double = 24.0
    #endif
}

private extension AppDelegate {
    func runForcedAutoUpdate(trigger: String) async {
        await SharedAutoUpdateManager.shared.forceNextUpdate()
        await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: trigger, force: true)
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

#if os(iOS)
private enum ForcedBackgroundUpdateResult {
    case completed
    case timedOut
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
        alert.messageText = "Unapplied Filter Changes"
        alert.informativeText = "You have unapplied filter changes. Do you want to apply them before quitting?"
        alert.addButton(withTitle: "Apply Changes and Quit")
        alert.addButton(withTitle: "Quit Without Applying")
        alert.addButton(withTitle: "Cancel")
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
        default: // Cancel
            return .terminateCancel
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

    /// Register for remote notifications upon launch
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--background-filter-update") {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await SharedAutoUpdateManager.shared.recordProcessWake(
                    source: "LaunchAgent",
                    message: "Background app launch started"
                )
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "LaunchAgent")
                await SharedAutoUpdateManager.shared.recordProcessWake(
                    source: "LaunchAgent",
                    message: "Background app launch finished"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            }
            return
        }

        os_log("macOS app finished launching; registering for remote notifications", type: .info)
        NSApp.registerForRemoteNotifications()
        
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

    /// Handle silent push on macOS
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        os_log("Silent push received for filterList (macOS)", type: .info)
        guard let updateType = userInfo["update"] as? String, updateType == "filterList" else { return }
        Task {
            // Silent pushes may arrive when the UI hasn't been created; use the shared auto-update
            // path so this works even with no AppFilterManager instance.
            await runForcedAutoUpdate(trigger: "SilentPush(macOS)")
        }
    }
}

#endif

#if os(iOS)
extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Request silent push capability (no UI notifications) and register
        UNUserNotificationCenter.current().requestAuthorization(options: []) { _, _ in }
        application.registerForRemoteNotifications()
        
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

    /// Handle incoming silent pushes to update filter lists in background
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        os_log("Silent push received for filterList", type: .info)
        guard let updateType = userInfo["update"] as? String, updateType == "filterList" else {
            completionHandler(.noData)
            return
        }

        // Silent pushes may launch the app in the background without constructing SwiftUI scenes,
        // meaning `filterManager` may be nil. Use SharedAutoUpdateManager so pushes always work.
        Task {
            await ProtobufDataManager.shared.recordAutoUpdateSilentPushReceived()
            let updateResult = await runForcedAutoUpdateWithTimeout(trigger: "SilentPush(iOS)")
            switch updateResult {
            case .completed:
                await ProtobufDataManager.shared.recordAutoUpdateSilentPushCompletion(result: "completed")
                completionHandler(.newData)
            case .timedOut:
                os_log("Silent push auto-update timed out before completion handler deadline", type: .error)
                await ProtobufDataManager.shared.recordAutoUpdateSilentPushCompletion(result: "timed_out")
                completionHandler(.failed)
            }
        }
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Run opportunistic updates only when app is active (not during background launches).
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            let isDueSoon = if let remaining = status.remaining { remaining < dueSoonThresholdSeconds } else { false }

            // If overdue or due soon, force update
            if status.isOverdue || (isDueSoon && !status.isRunning) {
                let catchUpReason = status.isOverdue ? "overdue" : "due_soon"
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

        // Flush any pending protobuf saves when entering background
        ProtobufDataManager.shared.saveData()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Flush any pending coalesced filter list saves
        filterManager?.flushPendingSave()

        // Flush any pending protobuf saves before termination
        ProtobufDataManager.shared.saveData()
    }
    
    // MARK: - Background Task Management
    
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
        Task { @MainActor in
            await ProtobufDataManager.shared.recordAutoUpdateTaskRegistration(
                .appRefresh,
                success: refreshRegistered,
                error: refreshRegistered ? nil : "BGTaskScheduler.register returned false"
            )
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
        Task { @MainActor in
            await ProtobufDataManager.shared.recordAutoUpdateTaskRegistration(
                .processing,
                success: processingRegistered,
                error: processingRegistered ? nil : "BGTaskScheduler.register returned false"
            )
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
                    result: "submitted"
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
                    result: "submitted"
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
    
    private func taskScheduleFailureDetails(for error: NSError) -> (result: String, message: String) {
        guard error.domain == "BGTaskSchedulerErrorDomain" else {
            return ("submit_failed", error.localizedDescription)
        }

        switch error.code {
        case 1:
            return ("info_plist_missing", "Identifier not in Info.plist")
        case 2:
            return ("too_many_pending", "Too many pending tasks")
        case 3:
            return ("unavailable", "Background tasks unavailable")
        default:
            return ("scheduler_error", error.localizedDescription)
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
                // Schedule next attempt sooner due to failure.
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
        let completionState = BGTaskCompletionState()
        let updateTask = Task {
            await ProtobufDataManager.shared.recordAutoUpdateTaskStart(kind)
            await self.runForcedAutoUpdate(trigger: trigger)

            guard await completionState.claimCompletion() else { return }
            os_log("%{public}@ completed successfully", type: .info, taskLabel)
            await ProtobufDataManager.shared.recordAutoUpdateTaskCompletion(kind, result: "completed")
            task.setTaskCompleted(success: true)
            await MainActor.run {
                onSuccess(self)
            }
        }

        task.expirationHandler = {
            os_log("%{public}@ expired - clearing running flag", type: .default, taskLabel)
            updateTask.cancel()

            Task {
                await self.clearAutoUpdateRunningFlag()
            }

            Task { [weak self] in
                guard await completionState.claimCompletion() else { return }
                await ProtobufDataManager.shared.recordAutoUpdateTaskExpiration(kind)
                task.setTaskCompleted(success: false)
                guard let self else { return }
                await MainActor.run {
                    onExpiration(self)
                }
            }
        }
    }

    private func runForcedAutoUpdateWithTimeout(
        trigger: String,
        timeoutSeconds: UInt64 = 25
    ) async -> ForcedBackgroundUpdateResult {
        let result = await withTaskGroup(of: ForcedBackgroundUpdateResult.self) { group in
            group.addTask {
                await self.runForcedAutoUpdate(trigger: trigger)
                return .completed
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                return .timedOut
            }

            let result = await group.next() ?? .timedOut
            group.cancelAll()
            return result
        }

        switch result {
        case .completed:
            return .completed
        case .timedOut:
            os_log(
                "Forced auto-update timed out (%{public}@); clearing running flag and forcing retry",
                type: .error,
                trigger
            )
            await clearAutoUpdateRunningFlag()
            await SharedAutoUpdateManager.shared.forceNextUpdate()
            return .timedOut
        }
    }

    private func clearAutoUpdateRunningFlag() async {
        await ProtobufDataManager.shared.waitUntilLoaded()
        await ProtobufDataManager.shared.setAutoUpdateIsRunning(false)
        await ProtobufDataManager.shared.saveDataImmediately()
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
