//
//  wBlockApp.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
import SwiftData

@main
struct wBlockApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var filterManager = AppFilterManager()

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

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some Scene {
        WindowGroup {
            ContentView(filterManager: filterManager)
                .onAppear {
                    appDelegate.filterManager = filterManager
                }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Restart Onboarding…") {
                    hasCompletedOnboarding = false
                }
            }
        }
        #endif
    }
}
