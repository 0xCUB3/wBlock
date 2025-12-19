//
//  wBlockApp.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
import wBlockCoreService

@main
struct wBlockApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var filterManager = AppFilterManager()

    @StateObject private var dataManager = ProtobufDataManager.shared

    #if os(macOS)
    @State private var showingRestartConfirmation = false
    #endif

    private var hasCompletedOnboarding: Bool {
        dataManager.hasCompletedOnboarding
    }

    var body: some Scene {
        WindowGroup {
            ContentView(filterManager: filterManager)
                    .onAppear {
                        appDelegate.filterManager = filterManager
                        if appDelegate.hasPendingApplyNotification {
                            appDelegate.hasPendingApplyNotification = false
                            NotificationCenter.default.post(name: .applyWBlockChangesNotification, object: nil)
                        }
                        handleLaunchArguments()

                        // Run migrations (idempotent - only saves if needed)
                        Task {
                            await dataManager.migrateMultipurposeToAnnoyances()
                            await dataManager.migrateAnnoyancesFilterToSplitFilters()
                        }
                    }
                    #if os(macOS)
                    .confirmationDialog(
                        "Restart Onboarding?",
                        isPresented: $showingRestartConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Restart", role: .destructive) {
                            Task { @MainActor in
                                await dataManager.updateAppSettings(hasCompletedOnboarding: false)
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will reset all filters, userscripts, and preferences.")
                    }
                    #endif
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Restart Onboarding…") {
                    showingRestartConfirmation = true
                }
            }
        }
        #endif
    }
    
    private func handleLaunchArguments() {
        let arguments = CommandLine.arguments
        if arguments.contains("--background-filter-update") {
            Task {
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "LaunchAgent")
                // Exit after background update completes
                #if os(macOS)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSApp.terminate(nil)
                }
                #endif
            }
        }
    }
}
