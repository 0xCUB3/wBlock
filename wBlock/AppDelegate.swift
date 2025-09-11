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
    
    #if os(iOS)
    private let backgroundTaskIdentifier = "com.alexanderskula.wblock.filter-update"
    private let backgroundProcessingIdentifier = "com.alexanderskula.wblock.filter-processing"
    #else
    // macOS-only scheduler holder
    private var backgroundScheduler: NSBackgroundActivityScheduler?
    #endif
}

// MARK: - Shared helper for schedule log formatting (platform-agnostic)
fileprivate func scheduleMessage(from status: (Date?, TimeInterval?, Double)) -> String {
    let (scheduledAt, remaining, interval) = status
    let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    if let scheduledAt, let remaining {
        if remaining == 0 {
            return "🕒 Auto-update: due now (interval=\(interval)h). Will run on next extension trigger. ScheduledAt=\(formatter.string(from: scheduledAt))"
        } else {
            let hrs = Int(remaining) / 3600
            let mins = (Int(remaining) % 3600) / 60
            let secs = Int(remaining) % 60
            return "🕒 Auto-update: next in \(hrs)h \(mins)m \(secs)s (scheduled \(formatter.string(from: scheduledAt))) interval=\(interval)h"
        }
    } else {
        return "🕒 Auto-update: no prior run yet. First window determined after initial extension trigger (interval=\(interval)h)."
    }
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
            await ConcurrentLogManager.shared.log(scheduleMessage(from: status))
        }
    }
    
    func applicationWillBecomeActive(_ notification: Notification) {
        // Opportunistic update when app becomes active
        Task {
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BecomeActive")
        }
    }
    
    // MARK: - macOS Auto-Update System
    
    private func setupMacOSAutoUpdate() {
        // Opportunistic periodic trigger while app is running
        Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { _ in
            Task { await self.runMacOSBackgroundUpdate(trigger: "PeriodicTimer") }
        }

        // System-optimized background scheduling (macOS 10.10+) — works when app is running
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.alexanderskula.wblock.filterupdate")
        scheduler.repeats = true
        scheduler.interval = 6 * 60 * 60 // Target ~6 hours
        scheduler.tolerance = 60 * 60    // Allow 1h flexibility for power/thermal conditions
        scheduler.schedule { completion in
            Task {
                await self.runMacOSBackgroundUpdate(trigger: "BackgroundActivity")
                completion(NSBackgroundActivityScheduler.Result.finished)
            }
        }
        self.backgroundScheduler = scheduler
    }

    private func runMacOSBackgroundUpdate(trigger: String) async {
        // If an XPC service exists in future builds, prefer it; else fallback in-process
        #if os(macOS)
        let usedXPC = await FilterUpdateClient.shared.updateFilters()
        if usedXPC { return }
        #endif
        await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: trigger)
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
            await ConcurrentLogManager.shared.log(scheduleMessage(from: status))
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
        // Opportunistic update when returning to foreground
        Task {
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "EnterForeground")
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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60) // 6 hours minimum
        
        do {
            try BGTaskScheduler.shared.submit(request)
            os_log("Background filter update task scheduled successfully", type: .info)
        } catch {
            os_log("Failed to schedule background filter update: %{public}@", type: .error, error.localizedDescription)
        }
    }

    private func scheduleBackgroundProcessingUpdate() {
        let request = BGProcessingTaskRequest(identifier: backgroundProcessingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true // prefer on charger for heavy conversions
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60) // be conservative
        do {
            try BGTaskScheduler.shared.submit(request)
            os_log("Background processing task scheduled successfully", type: .info)
        } catch {
            os_log("Failed to schedule background processing task: %{public}@", type: .error, error.localizedDescription)
        }
    }
    
    private func handleBackgroundFilterUpdate(task: BGAppRefreshTask) {
        os_log("Background filter update task started", type: .info)
        
        // Schedule next occurrence immediately
        scheduleBackgroundFilterUpdate()
        
        task.expirationHandler = {
            os_log("Background filter update task expired", type: .info)
            task.setTaskCompleted(success: false)
        }
        
        Task {
            do {
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BackgroundTask")
                os_log("Background filter update completed successfully", type: .info)
                task.setTaskCompleted(success: true)
            } catch {
                os_log("Background filter update failed: %{public}@", type: .error, error.localizedDescription)
                task.setTaskCompleted(success: false)
            }
        }
    }

    private func handleBackgroundProcessingUpdate(task: BGProcessingTask) {
        os_log("Background processing update task started", type: .info)

        // Reschedule next processing task
        scheduleBackgroundProcessingUpdate()

        task.expirationHandler = {
            os_log("Background processing update task expired", type: .info)
            task.setTaskCompleted(success: false)
        }

        Task {
            // Processing path can do the same work, but BGProcessing offers longer time
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BackgroundProcessing")
            os_log("Background processing update task finished", type: .info)
            task.setTaskCompleted(success: true)
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
            NotificationCenter.default.post(name: .applyWBlockChangesNotification, object: nil)
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
