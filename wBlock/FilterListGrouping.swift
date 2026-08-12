import Foundation
import wBlockCoreService

struct FilterListGroup: Identifiable {
    enum Kind: Hashable {
        case filter(UUID)
        case adGuardAnnoyances
    }

    let kind: Kind
    let filters: [FilterList]

    var id: Kind { kind }
    var isAdGuardAnnoyances: Bool { kind == .adGuardAnnoyances }
    var title: String? { isAdGuardAnnoyances ? "AdGuard Annoyances" : nil }
}

enum FilterListGrouping {
    /// AdGuard Filters Registry IDs 18–22 are the five granular Annoyances lists.
    static let adGuardAnnoyanceRegistryIDs: Set<String> = ["18", "19", "20", "21", "22"]

    static func isAdGuardAnnoyance(_ filter: FilterList) -> Bool {
        guard !filter.isCustom, filter.category == .annoyances else { return false }
        let filename = filter.url.path.split(separator: "/").last.map(String.init) ?? ""
        let registryID = filename.split(separator: "_").first.map(String.init) ?? ""
        return adGuardAnnoyanceRegistryIDs.contains(registryID)
    }

    static func groups(for filters: [FilterList]) -> [FilterListGroup] {
        var groups: [FilterListGroup] = []
        let adGuardFilters = filters.filter(isAdGuardAnnoyance)
        if !adGuardFilters.isEmpty {
            groups.append(FilterListGroup(kind: .adGuardAnnoyances, filters: adGuardFilters))
        }

        for filter in filters where !isAdGuardAnnoyance(filter) {
            groups.append(FilterListGroup(kind: .filter(filter.id), filters: [filter]))
        }
        return groups
    }
}
