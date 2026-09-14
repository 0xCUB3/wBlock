import Foundation
import wBlockCoreService

/// Prepared independently of tab selection so layout never sorts the catalog.
struct FilterListPresentation: Sendable {
    struct Input: Equatable, Sendable {
        let filters: [FilterList]
        let order: Data
        let searchText: String
        let enabledOnly: Bool
        let localeIdentifier: String
    }

    struct Section: Sendable {
        let category: FilterListCategory
        let filters: [FilterList]
    }

    var sections: [Section] = []
    var foreignGroups: [ForeignFilterGroup] = []

    static func prepare(_ input: Input) async throws -> Self {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let query = input.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let visible = input.filters.filter { filter in
                (!input.enabledOnly || filter.isSelected) && (query.isEmpty
                    || filter.localizedDisplayName.localizedCaseInsensitiveContains(query)
                    || filter.localizedDisplayDescription.localizedCaseInsensitiveContains(query)
                    || filter.url.absoluteString.localizedCaseInsensitiveContains(query))
            }
            let ordered = ListDisplayOrder.sorted(visible.filter { $0.category != .foreign }, order: input.order)
                + ForeignFilterOrganizer.sortedFilters(visible.filter { $0.category == .foreign })
            let byCategory = Dictionary(grouping: ordered, by: \.category)
            let sections = FilterListCategory.allCases
                .filter { $0 != .all && !$0.isUserScriptOnly }
                .compactMap { category -> Section? in
                    guard let filters = byCategory[category] else { return nil }
                    return Section(category: category, filters: filters)
                }
            let foreignGroups = ForeignFilterOrganizer.groups(for: byCategory[.foreign] ?? [])
            try Task.checkCancellation()
            return Self(sections: sections, foreignGroups: foreignGroups)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            // A superseded search or model snapshot must never replace newer results.
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }
}
