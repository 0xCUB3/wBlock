//
//  wBlockApp.swift
//  wBlock
//
//  Created by Alexander Skula on7/18/24.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct wBlockApp: App {
    @StateObject private var filterListManager = FilterListManager()

    // Only create and use the update controller on macOS.
    #if os(macOS)
    @StateObject private var updateController = UpdateController.shared
    #endif

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(filterListManager: filterListManager)
                // Remove fixed frame and size.  Let SwiftUI handle the layout.
                #if os(macOS)
                .frame(width: 700, height: 500)
                .fixedSize()
                .environmentObject(updateController)
                #endif
                .environmentObject(filterListManager)
                .task {
                    // Request notification permissions on all platforms.
                    try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])

                    #if os(macOS)
                    await updateController.checkForUpdates()
                    await updateController.scheduleBackgroundUpdates(filterListManager: filterListManager)
                    #endif
                }
                // Present an “update available” alert only macOS.
                #if os(macOS)
                .alert(isPresented: $updateController.updateAvailable) {
                    Alert(
                        title: Text("Update Available"),
                        message: Text("A new version (\(updateController.latestVersion ?? "")) of wBlock is available. Would you like to update?"),
                        primaryButton: .default(Text("Update")) {
                            updateController.openReleasesPage()
                        },
                        secondaryButton: .cancel(Text("Later"))
                    )
                }
                #endif
        }
        // Only add macOS‑specific window modifiers and commands.
        #if os(macOS)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { } // Disable New Window command
        }
        #endif
    }
}
