//
//  FilterStatsBanner.swift
//  wBlock
//
//  Created by Alexander Skula on3/11/25.
//

import SwiftUI

struct FilterStatsBanner: View {
    @ObservedObject var filterListManager: FilterListManager

    private var enabledFiltersCount: Int {
        filterListManager.filterLists.filter { $0.isSelected }.count
    }
    private var totalRulesCount: Int {
        let enabledIDs = filterListManager.filterLists.filter { $0.isSelected }.map(\.id)
        return enabledIDs.reduce(0) { sum, id in
            sum + (filterListManager.ruleCounts[id] ?? 0)
        }
    }

    private var pillInfo: (color: Color, textColor: Color) {
        switch totalRulesCount {
        case 0..<140_000: return (Color(NSColor.controlBackgroundColor), .blue)
        case 140_000..<150_000: return (.yellow.opacity(0.50), .orange)
        default: return (.red.opacity(0.38), .red)
        }
    }

    var body: some View {
        HStack(spacing: 28) {
            StatCard(
                title: "Enabled Lists",
                value: "\(enabledFiltersCount)",
                icon: "list.bullet.rectangle",
                pillColor: Color(NSColor.controlBackgroundColor),
                valueColor: .blue
            )
            StatCard(
                title: "Rule Count",
                value: "\(totalRulesCount)",
                icon: "shield.lefthalf.filled",
                pillColor: pillInfo.color,
                valueColor: pillInfo.textColor
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .center)
        .help("Projected rule count if you Apply Changes now")
    }
}
