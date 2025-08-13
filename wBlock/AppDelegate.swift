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
#elseif os(iOS)
import UIKit
import UserNotifications
#endif

// Define the notification name globally or in a shared place
extension Notification.Name {
    static let applyWBlockChangesNotification = Notification.Name("applyWBlockChangesNotification_unique_identifier")
}

class AppDelegate: NSObject {
    var filterManager: AppFilterManager?
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

