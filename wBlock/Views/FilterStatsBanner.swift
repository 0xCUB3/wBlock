//
//  FilterStatsBanner.swift
//  wBlock
//
//  Created by Alexander Skula on3/11/25.
//

import SwiftUI

struct FilterStatsBanner: View {
    @ObservedObject var filterListManager: FilterListManager
    @State private var totalRulesCount: Int = 0

    private var enabledFiltersCount: Int {
        filterListManager.filterLists.filter { $0.isSelected }.count
    }

    private func calculateProspectiveTotalRulesCount() async -> Int {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "DNP7DGUB7B.wBlock") else { return 0 }

        let enabledFilters = filterListManager.filterLists.filter { $0.isSelected }

        func countRulesForFilter(_ filter: FilterList) -> Int {
            let fileURL = containerURL.appendingPathComponent("\(filter.name).json")
            let advURL = containerURL.appendingPathComponent("\(filter.name)_advanced.json")
            func count(_ url: URL) -> Int {
                guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
                do {
                    let data = try Data(contentsOf: url)
                    if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] { return arr.count }
                } catch {}
                return 0
            }
            return count(fileURL) + count(advURL)
        }

        return await Task.detached {
            enabledFilters.reduce(0) { $0 + countRulesForFilter($1) }
        }.value
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
                    title: "Rule Count",
                    value: "\(totalRulesCount)",
                    icon: "shield.lefthalf.filled"
                )
            }
            .help("Projected rule count if you Apply Changes now")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .task(id: filterListManager.filterLists.map(\.isSelected)) {
            self.totalRulesCount = await calculateProspectiveTotalRulesCount()
        }
        .onChange(of: filterListManager.filterLists.map(\.isSelected)) { _ in
            Task { self.totalRulesCount = await calculateProspectiveTotalRulesCount() }
        }
    }
}
