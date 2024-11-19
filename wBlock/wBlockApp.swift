//
//
//  wBlockApp.swift
//  wBlock
//
//  Created by Alexander Skula on 7/18/24.
//

import SwiftUI
import SwiftData

@main
struct wBlockApp: App {
    @StateObject private var filterListManager = FilterListManager()
    @StateObject private var updateController = UpdateController.shared
    
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
            ContentView(filterListManager: filterListManager)
                .frame(width: 700, height: 500)
                .fixedSize()
                .environmentObject(updateController)
                .task {
                    await updateController.checkForUpdates()
                }.alert(isPresented: $updateController.updateAvailable) {
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
            CommandGroup(replacing: .newItem) { }  // Disable New Window command
        }
    }
}
