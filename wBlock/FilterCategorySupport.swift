import Foundation
import wBlockCoreService

enum FilterCategorySupport {
    /// Only categories whose choices aren't obvious explain themselves: Regional
    /// picks languages, and Annoyances mixes lists from three projects, none
    /// on by default. Every other category has no info button (#1087).
    static func descriptionKey(for category: FilterListCategory) -> String? {
        switch category {
        case .annoyances: "Removes cookie notices, pop-ups, banners, and other distracting elements."
        case .foreign: "Adds rules tailored to websites and languages from specific regions."
        default: nil
        }
    }

    static func defaultFilterNames(
        for category: FilterListCategory,
        defaults: [FilterList]
    ) -> [String] {
        defaults
            .filter { $0.category == category && $0.isSelected }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func resetSelection(
        for filter: FilterList,
        category: FilterListCategory,
        defaultNames: Set<String>
    ) -> Bool? {
        guard filter.category == category else { return nil }
        return filter.isCustom ? false : defaultNames.contains(filter.name)
    }
}
