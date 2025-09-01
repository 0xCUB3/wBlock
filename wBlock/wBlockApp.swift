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

    private var hasCompletedOnboarding: Bool {
        dataManager.hasCompletedOnboarding
    }

    var body: some Scene {
        WindowGroup {
            ContentView(filterManager: filterManager)
                    .onAppear {
                        appDelegate.filterManager = filterManager
                        handleLaunchArguments()
                    }
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Restart Onboarding…") {
                    Task { @MainActor in
                        await dataManager.updateAppSettings(hasCompletedOnboarding: false)
                    }
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

