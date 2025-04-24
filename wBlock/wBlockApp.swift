//
//  wBlockApp.swift
//  wBlock
//
//  Created by Alexander Skula on 7/18/24.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct wBlockApp: App {
    @StateObject private var filterListManager = FilterListManager()
    @StateObject private var updateController = UpdateController.shared

    @State private var commandState = ContentViewCommandState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(
                filterListManager: filterListManager,
                commandState: $commandState
            )
                .frame(width: 700, height: 500)
                .fixedSize()
                .environmentObject(updateController)
                .environmentObject(filterListManager)
                .task {
                    // Request notification permissions
                    try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    await updateController.scheduleBackgroundUpdates(filterListManager: filterListManager)
                }
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
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { } // Disable New Window command

            CommandMenu("wBlock Actions") {
                Button("Check for Updates", action: { commandState.refresh() })
                    .keyboardShortcut("r", modifiers: [.command])

                Button("Apply Changes", action: { commandState.applyChanges() })
                    .keyboardShortcut("s", modifiers: [.command])
                    // Could be: .disabled(!filterListManager.hasUnappliedChanges)

                Divider()

                Button("Add Custom Filter", action: { commandState.addCustomFilter() })
                    .keyboardShortcut("n", modifiers: [.command])

                Button("Show Logs", action: { commandState.showLogs() })
                    .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Show Settings", action: { commandState.showSettings() })
                    .keyboardShortcut(",", modifiers: [.command])

                Button("Reset to Default", action: { commandState.resetToDefault() })
                    .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Toggle Only Enabled Filters", action: { commandState.toggleOnlyEnabled() })
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                
                Button("Cheat Sheet (Keyboard Shortcuts)", action: { commandState.showCheatSheet() })
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
