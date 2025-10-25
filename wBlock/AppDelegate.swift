//
//  AppDelegate.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI
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
    
    #if os(iOS)
    private let backgroundTaskIdentifier = "com.alexanderskula.wblock.filter-update"
    private let backgroundProcessingIdentifier = "com.alexanderskula.wblock.filter-processing"
    #else
    // macOS-only scheduler holder
    private var backgroundScheduler: NSBackgroundActivityScheduler?
    #endif
}

// MARK: - Shared helper for schedule log formatting (platform-agnostic)
fileprivate func scheduleMessage(from status: (Date?, TimeInterval?, Double, Date?, Bool, Bool)) -> String {
    let (scheduledAt, remaining, interval, lastSuccessful, isRunning, isOverdue) = status
    let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var message = ""
    if let scheduledAt, let remaining {
        if isRunning {
            message = "🔄 Auto-update: currently running"
        } else if isOverdue {
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
        message = "🕒 Auto-update: no prior run yet (interval=\(interval)h)"
    }

    if let lastSuccessful {
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

    /// Register for remote notifications upon launch
    func applicationDidFinishLaunching(_ notification: Notification) {
        os_log("macOS app finished launching; registering for remote notifications", type: .info)
        NSApp.registerForRemoteNotifications()
        
        // Setup periodic auto-update system for macOS
        setupMacOSAutoUpdate()
        
        // Opportunistic update on app launch
        Task {
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "AppLaunch")
        }

        // Log next auto-update schedule status
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            await ConcurrentLogManager.shared.info(.autoUpdate, scheduleMessage(from: status), metadata: [:])
        }
    }
    
    func applicationWillBecomeActive(_ notification: Notification) {
        // Check if update is overdue when app becomes active
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            let (_, remaining, _, _, isRunning, isOverdue) = status

            // If overdue or due within 5 minutes, force update
            if isOverdue || ( ( ( (if let remaining = remaining { remaining < 300 } else { false } ) ) && !isRunning ) ) {
            if isOverdue || isDueSoon {
                await SharedAutoUpdateManager.shared.forceNextUpdate()
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BecomeActive", force: true)
            } else {
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BecomeActive")
            }
        }
    }
    
    // MARK: - macOS Auto-Update System
    
    private func setupMacOSAutoUpdate() {
        // More aggressive periodic trigger while app is running (check every 30 minutes)
        Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { await self?.runMacOSBackgroundUpdate(trigger: "PeriodicTimer") }
        }

        // System-optimized background scheduling (macOS 10.10+) — works when app is running
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
        let intervalHours = defaults?.double(forKey: "autoUpdateIntervalHours") ?? 6.0
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.alexanderskula.wblock.filterupdate")
        scheduler.repeats = true
        scheduler.interval = intervalHours * 60 * 60 // Use configured interval
        scheduler.tolerance = min(intervalHours * 0.2, 1.0) * 60 * 60 // 20% tolerance, max 1 hour
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task {
                await self?.runMacOSBackgroundUpdate(trigger: "BackgroundActivityScheduler")
                completion(NSBackgroundActivityScheduler.Result.finished)
            }
        }
        self.backgroundScheduler = scheduler
    }

    private func runMacOSBackgroundUpdate(trigger: String) async {
        // Check if update is overdue
        let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
        let (_, _, _, _, isRunning, isOverdue) = status

        // If an XPC service exists in future builds, prefer it; else fallback in-process
        #if os(macOS)
        let usedXPC = await FilterUpdateClient.shared.updateFilters()
        if usedXPC { return }
        #endif

        // Force update if overdue
        if isOverdue && !isRunning {
            await SharedAutoUpdateManager.shared.forceNextUpdate()
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: trigger, force: true)
        } else {
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: trigger)
        }
    }

    /// Handle silent push on macOS
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        os_log("Silent push received for filterList (macOS)", type: .info)
        guard let updateType = userInfo["update"] as? String, updateType == "filterList",
              let manager = filterManager else { return }
        Task {
            os_log("Checking for pending filter-list updates...", type: .info)
            let pending = await manager.filterUpdater.checkForUpdates(filterLists: manager.filterLists)
            if pending.isEmpty {
                os_log("No pending filter-list updates found", type: .info)
            } else {
                let names = pending.map { $0.name }.joined(separator: ", ")
                os_log("Pending filter-list updates for: %{public}@", type: .info, names)
            }
            for filter in pending {
                os_log("Fetching and processing filter list: %{public}@", type: .info, filter.name)
                _ = await manager.filterUpdater.fetchAndProcessFilter(filter)
            }
            os_log("Applying filter changes...", type: .info)
            await manager.applyChanges()
            os_log("Background filter update process completed (macOS)", type: .info)
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
        
        // Schedule initial background refresh + processing tasks
        scheduleBackgroundFilterUpdate()
        scheduleBackgroundProcessingUpdate()
        
        // Opportunistic update on app launch
        Task {
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "AppLaunch")
        }

        // Log next auto-update schedule status
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            await ConcurrentLogManager.shared.info(.autoUpdate, scheduleMessage(from: status), metadata: [:])
        }
        return true
    }

    /// Handle incoming silent pushes to update filter lists in background
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        os_log("Silent push received for filterList", type: .info)
        // Only handle filter list updates
        if let updateType = userInfo["update"] as? String, updateType == "filterList",
           let manager = filterManager {
            Task {
                os_log("Checking for pending filter-list updates...", type: .info)
                let pending = await manager.filterUpdater.checkForUpdates(filterLists: manager.filterLists)
                if pending.isEmpty {
                    os_log("No pending filter-list updates found", type: .info)
                } else {
                    let names = pending.map { $0.name }.joined(separator: ", ")
                    os_log("Pending filter-list updates for: %{public}@", type: .info, names)
                }
                // For each pending filter, fetch and save new list
                for filter in pending {
                    os_log("Fetching and processing filter list: %{public}@", type: .info, filter.name)
                    _ = await manager.filterUpdater.fetchAndProcessFilter(filter)
                }
                // Apply all changes to content blockers
                os_log("Applying filter changes...", type: .info)
                await manager.applyChanges()
                os_log("Background filter update process completed", type: .info)
                completionHandler(.newData)
            }
        } else {
            completionHandler(.noData)
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Check if update is overdue when returning to foreground
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            let (_, remaining, _, _, isRunning, isOverdue) = status

            // If overdue or due within 5 minutes, force update
            if isOverdue || (remaining != nil && remaining! < 300 && !isRunning) {
                os_log("App entering foreground with overdue/due update - forcing update", type: .info)
                await SharedAutoUpdateManager.shared.forceNextUpdate()
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "EnterForeground", force: true)
            } else {
                // Normal opportunistic update
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "EnterForeground")
            }
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Schedule next background task when entering background
        scheduleBackgroundFilterUpdate()
    }
    
    // MARK: - Background Task Management
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            self.handleBackgroundFilterUpdate(task: task as! BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundProcessingIdentifier, using: nil) { task in
            self.handleBackgroundProcessingUpdate(task: task as! BGProcessingTask)
        }
    }

    private func scheduleBackgroundFilterUpdate() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // Use configured interval, but cap at reasonable limits
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
        let intervalHours = defaults?.double(forKey: "autoUpdateIntervalHours") ?? 6.0
        // Schedule for 75% of interval to account for iOS's discretionary nature
        let delaySeconds = min(max(intervalHours * 0.75, 1.0), 12.0) * 60 * 60 // Between 1-12 hours
        request.earliestBeginDate = Date(timeIntervalSinceNow: delaySeconds)

        do {
            // Cancel and resubmit atomically
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
            try BGTaskScheduler.shared.submit(request)
            os_log("Background filter update task scheduled successfully (delay: %.1f hrs)", type: .info, delaySeconds / 3600)
        } catch let error as NSError {
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
        }
    }

    private func scheduleBackgroundProcessingUpdate() {
        let request = BGProcessingTaskRequest(identifier: backgroundProcessingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false // Don't require power - be more aggressive
        // Schedule processing task for full interval (less critical than app refresh)
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
        let intervalHours = defaults?.double(forKey: "autoUpdateIntervalHours") ?? 6.0
        let delaySeconds = min(max(intervalHours, 2.0), 24.0) * 60 * 60 // Between 2-24 hours
        request.earliestBeginDate = Date(timeIntervalSinceNow: delaySeconds)
        do {
            // Cancel and resubmit atomically
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundProcessingIdentifier)
            try BGTaskScheduler.shared.submit(request)
            os_log("Background processing task scheduled successfully (delay: %.1f hrs)", type: .info, delaySeconds / 3600)
        } catch let error as NSError {
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
        }
    }
    
    private func handleBackgroundFilterUpdate(task: BGAppRefreshTask) {
        os_log("Background filter update task started", type: .info)

        var taskCompleted = false

        task.expirationHandler = {
            os_log("Background filter update task expired", type: .warning)
            if !taskCompleted {
                taskCompleted = true
                task.setTaskCompleted(success: false)
                // Schedule next attempt sooner due to failure
                self.scheduleBackgroundFilterUpdate()
            }
        }

        Task {
            // Always force update since background tasks are precious and rare
            await SharedAutoUpdateManager.shared.forceNextUpdate()
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BGAppRefreshTask", force: true)

            if !taskCompleted {
                taskCompleted = true
                os_log("Background filter update completed successfully", type: .info)
                task.setTaskCompleted(success: true)

                // Schedule next occurrence after success
                self.scheduleBackgroundFilterUpdate()
                self.scheduleBackgroundProcessingUpdate()
            }
        }
    }

    private func handleBackgroundProcessingUpdate(task: BGProcessingTask) {
        os_log("Background processing update task started", type: .info)

        var taskCompleted = false

        task.expirationHandler = {
            os_log("Background processing update task expired", type: .warning)
            if !taskCompleted {
                taskCompleted = true
                task.setTaskCompleted(success: false)
                // Schedule next attempt
                self.scheduleBackgroundProcessingUpdate()
            }
        }

        Task {
            // Force update for processing tasks as well
            await SharedAutoUpdateManager.shared.forceNextUpdate()
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BGProcessingTask", force: true)

            if !taskCompleted {
                taskCompleted = true
                os_log("Background processing update task finished successfully", type: .info)
                task.setTaskCompleted(success: true)

                // Schedule next occurrence after success
                self.scheduleBackgroundFilterUpdate()
                self.scheduleBackgroundProcessingUpdate()
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        if let actionType = userInfo["action_type"] as? String, actionType == "apply_wblock_changes" {
            print("Apply changes notification tapped. Posting internal notification.")
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
