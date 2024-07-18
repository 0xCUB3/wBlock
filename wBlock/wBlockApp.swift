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
        }
        .windowResizability(.contentSize)
    }
}
