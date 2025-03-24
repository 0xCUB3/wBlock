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
    
    private var enabledFiltersCount: Int {
        filterListManager.filterLists.filter { $0.isSelected }.count
    }
    
    private var totalRulesCount: Int {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "DNP7DGUB7B.wBlock"),
           let data = try? Data(contentsOf: containerURL.appendingPathComponent("blockerList.json")),
           let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return rules.count
        }
        return 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 48) {
                StatCard(
                    title: "Enabled Lists",
                    value: "\(enabledFiltersCount)",
                    icon: "list.bullet.rectangle"
                )
                
                StatCard(
                    title: "Active Rules",
                    value: "\(totalRulesCount)",
                    icon: "shield.lefthalf.filled"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}
