//
//  FilterRowView.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import SwiftUI
import SwiftData

struct FilterRowView: View {
    let filter: FilterList
    @ObservedObject var filterListManager: FilterListManager
    @State private var ruleCount: Int = 0 // Use @State

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { filter.isSelected },
            set: { _ in filterListManager.toggleFilterListSelection(id: filter.id) }
        )
    }

    // Async function to load rule count
    private func loadRuleCount() async -> Int {
        // No need to calculate if not selected
        guard filter.isSelected else { return 0 }
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "DNP7DGUB7B.wBlock") else { return 0 }

        let standardFileURL = containerURL.appendingPathComponent("\(filter.name).json")
        let advancedFileURL = containerURL.appendingPathComponent("\(filter.name)_advanced.json")

        // Perform file reading and counting in detached tasks to avoid blocking
        let standardCount = await Task.detached { await countRules(at: standardFileURL) }.value
        let advancedCount = await Task.detached { await countRules(at: advancedFileURL) }.value

        return standardCount + advancedCount
    }

    // Helper function for counting (remains synchronous but called from detached task)
    private func countRules(at url: URL) -> Int {
         guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
         do {
             let data = try Data(contentsOf: url)
             if let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                 return rules.count
             }
         } catch {
             // Log appropriately
             print("Error counting rules for \(url.lastPathComponent): \(error)")
         }
         return 0
     }


    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(filter.name)

                    if filter.category != .custom {
                        Link(destination: filter.url) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.gray)
                        }
                        .help("View Source")
                    }

                    // Show rule count *only* if the filter is enabled and count > 0
                    if filter.isSelected && ruleCount > 0 {
                        Text("(\(ruleCount) rules)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }

                if !filter.description.isEmpty {
                    Text(filter.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if !filter.version.isEmpty {
                    Text("Version: \(filter.version)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: toggleBinding)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .labelsHidden()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            filterListManager.toggleFilterListSelection(id: filter.id)
        }
        .contextMenu {
            if filter.category == .custom {
                Button("Remove Filter") {
                    filterListManager.removeCustomFilterList(filter)
                }
            }
        }
        // Load the count when the view appears or when the filter selection state changes
        .task(id: filter.isSelected) {
             self.ruleCount = await loadRuleCount()
        }
        // Also reload count if the underlying filter files might have changed (e.g., after an update)
        .onChange(of: filterListManager.isUpdating) { isUpdating in
            if !isUpdating { // When an update finishes
                 Task {
                     self.ruleCount = await loadRuleCount()
                 }
            }
        }
    }
}
