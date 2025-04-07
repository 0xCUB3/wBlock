//
//  FilterStatsBanner.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import SwiftUI
import SwiftData

struct FilterStatsBanner: View {
    @ObservedObject var filterListManager: FilterListManager
    @State private var totalRulesCount: Int = 0

    private var enabledFiltersCount: Int {
        filterListManager.filterLists.filter { $0.isSelected }.count
    }

    // Async function to calculate rule count off the main thread
    private func calculateTotalRulesCount() async -> Int {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "DNP7DGUB7B.wBlock") else { return 0 }
        let fileURL = containerURL.appendingPathComponent("blockerList.json")

        // Perform file reading in a background task
        return await Task.detached { // Use detached task for potential I/O blocking
            do {
                let data = try Data(contentsOf: fileURL)
                if let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    return rules.count
                }
            } catch {
                // Log error appropriately if needed, maybe using filterListManager's logger
                print("Error loading blockerList.json for stats: \(error)")
            }
            return 0
        }.value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 48) {
                StatCard(
                    title: "Enabled Lists",
                    value: "\(enabledFiltersCount)", // This is usually fast
                    icon: "list.bullet.rectangle"
                )

                StatCard(
                    title: "Active Rules",
                    value: "\(totalRulesCount)", // Display the state variable
                    icon: "shield.lefthalf.filled"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .task(id: filterListManager.filterLists.filter { $0.isSelected }.map { $0.id }) { // Re-run if selected filters change
            self.totalRulesCount = await calculateTotalRulesCount()
        }
        .onChange(of: filterListManager.hasUnappliedChanges) { hasChanges in
             // Re-calculate when changes are potentially applied (i.e., hasUnappliedChanges becomes false)
            if !hasChanges {
                 Task {
                      self.totalRulesCount = await calculateTotalRulesCount()
                 }
            }
        }
    }
}
