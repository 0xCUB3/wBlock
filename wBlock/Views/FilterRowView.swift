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
    
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { filter.isSelected },
            set: { _ in filterListManager.toggleFilterListSelection(id: filter.id) }
        )
    }
    
    private var ruleCount: Int {
        guard filter.isSelected else { return 0 } // Only calculate if selected
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "DNP7DGUB7B.wBlock") else { return 0 }
        
        // Consider both standard and advanced rules
        let standardFileURL = containerURL.appendingPathComponent("\(filter.name).json")
        let advancedFileURL = containerURL.appendingPathComponent("\(filter.name)_advanced.json")
        
        var totalCount = 0
        
        // Function to count rules in a given file
        func countRules(at url: URL) -> Int {
            if let data = try? Data(contentsOf: url),
               let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return rules.count
            }
            return 0
        }
        
        totalCount += countRules(at: standardFileURL)
        totalCount += countRules(at: advancedFileURL)
        
        return totalCount
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
                    
                    // Show rule count *only* if the filter is enabled
                    if filter.isSelected {
                        Text("(\(ruleCount) rules)") // Added "rules" label
                            .font(.caption2) // Even smaller font
                            .foregroundColor(.gray) // Use gray color directly
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
    }
}
