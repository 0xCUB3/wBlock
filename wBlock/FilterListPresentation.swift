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
        var downloadedIDs: Set<UUID> = []
        /// Server Last-Modified headers keyed by filter UUID string.
        var lastModified: [String: String] = [:]
    }

    /// Row strings built once per snapshot; building them in each row body
    /// made every row that scrolled in redo lookups, formatting, and parsing.
    struct RowText: Equatable, Sendable {
        let name: String
        let languages: String
        let description: String
        let metadata: String

        init(_ filter: FilterList, isDownloaded: Bool, lastModified: String?) {
            name = filter.localizedDisplayName
            languages = filter.category == .foreign ? filter.nativeLanguageNames().joined(separator: ", ") : ""
            description = filter.localizedDisplayDescription
            let updated = HTTPModifiedDate.date(from: lastModified) ?? filter.lastUpdated
            metadata = filter.isRemoteURL && !isDownloaded ? "" : ContentRowMetadata.summary([
                Self.ruleCountSummary(filter),
                Self.appliedSummary(filter),
                ContentRowMetadata.versionLabel(filter.version),
                ContentRowMetadata.updatedLabel(updated),
            ])
        }

        /// Source rules the last apply handed to the converter (#742), shown
        /// when rules another list already supplied were left out.
        private static func appliedSummary(_ filter: FilterList) -> String? {
            guard filter.isSelected, let applied = filter.uniqueRuleCount,
                  applied < filter.sourceRuleCount ?? 0 else { return nil }
            return String.localizedStringWithFormat(
                NSLocalizedString("%@ applied", comment: "Source rules this list added to the last apply after duplicates in other lists were removed"),
                applied.formatted()
            )
        }

        private static func ruleCountSummary(_ filter: FilterList) -> String? {
            if filter.isCustom && !filter.isInlineUserList && filter.isSelected && filter.sourceRuleCount == nil {
                return NSLocalizedString("Not Downloaded", comment: "Filter has no local content")
            }
            if let rawCount = filter.rawSourceRuleCount, let expandedCount = filter.sourceRuleCount, rawCount != expandedCount {
                return String.localizedStringWithFormat(
                    NSLocalizedString("%@ source → %@ expanded rules", comment: "Filter rule expansion summary"),
                    rawCount.formatted(), expandedCount.formatted()
                )
            }
            if let count = filter.sourceRuleCount, count > 0 {
                return String.localizedStringWithFormat(
                    NSLocalizedString("%@ rules", comment: "Filter rule count summary"), count.formatted()
                )
            }
            return nil
        }
    }

    struct Section: Sendable {
        let category: FilterListCategory
        let filters: [FilterList]
    }

    var sections: [Section] = []
    var rowText: [UUID: RowText] = [:]

    static func ordered(_ filters: [FilterList], order: Data) -> [FilterList] {
        ListDisplayOrder.sorted(
            filters.filter { $0.category != .foreign }
                + ForeignFilterOrganizer.sortedFilters(filters.filter { $0.category == .foreign }),
            order: order)
    }

    static func prepare(_ input: Input) async throws -> Self {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let query = input.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let locale = Locale(identifier: input.localeIdentifier)
            let visible = input.filters.filter { filter in
                (!input.enabledOnly || filter.isSelected) && filter.matchesSearch(query, locale: locale)
            }
            let ordered = Self.ordered(visible, order: input.order)
            let byCategory = Dictionary(grouping: ordered, by: \.category)
            let sections = FilterListCategory.allCases
                .filter { $0 != .all && !$0.isUserScriptOnly }
                .compactMap { category -> Section? in
                    guard let filters = byCategory[category] else { return nil }
                    return Section(category: category, filters: filters)
                }
            try Task.checkCancellation()
            let rowText = Dictionary(uniqueKeysWithValues: ordered.map { filter in
                (filter.id, RowText(filter, isDownloaded: input.downloadedIDs.contains(filter.id),
                                    lastModified: input.lastModified[filter.id.uuidString]))
            })
            return Self(sections: sections, rowText: rowText)
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
