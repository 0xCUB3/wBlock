import Foundation

enum FilterCategorySupport {
    static func descriptionKey(for category: FilterListCategory) -> String {
        switch category {
        case .ads:
            "Blocks advertisements and other promotional page elements."
        case .privacy:
            "Blocks trackers, analytics, and other privacy-invasive requests."
        case .security:
            "Blocks malicious URLs, phishing pages, and unwanted software."
        case .multipurpose:
            "Combines broad ad-blocking and tracking protection in one list."
        case .annoyances:
            "Removes cookie notices, pop-ups, banners, and other distracting elements."
        case .experimental:
            "Provides newer rules and fixes that are still being tested."
        case .allowlists:
            "Allows trusted sites and resources that should not be blocked."
        case .custom:
            "Contains filter lists that you added or imported yourself."
        case .foreign:
            "Adds rules tailored to websites and languages from specific regions."
        case .scripts:
            "Organizes userscripts and userstyles added to wBlock."
        case .all:
            "Shows all filter lists across every category."
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
