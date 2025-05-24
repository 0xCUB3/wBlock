//
//  AppDelegate.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI
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
}
#endif

#if os(iOS)
extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // This method is called when a notification is delivered to a foreground app or when a user taps on a notification.
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

    // Optional: Handle notification when app is in foreground (if needed)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Decide how to present the notification if the app is in the foreground
        // For this specific "you forgot" notification, it's typically for when the app is backgrounded.
        // If it could also trigger while app is foreground (e.g. scene phase changes rapidly),
        // you might want to handle it differently or not show it.
        // For now, let's assume it won't be shown/needed if app is foreground.
        completionHandler([]) // Don't show alert if app is open, or choose .banner, .list, .sound
    }
}
#endif

