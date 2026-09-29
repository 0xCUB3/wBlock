import Foundation
import wBlockCoreService

struct ApplyFilterConfiguration: Equatable {
    let id: UUID
    let name: String
    let url: URL
    let category: FilterListCategory
    let isCustom: Bool
    let hasUserProvidedName: Bool
    let excludedSites: [String]
    let selectedSites: [String]?

    init(_ filter: FilterList) {
        id = filter.id
        name = filter.name
        url = filter.url
        category = filter.category
        isCustom = filter.isCustom
        hasUserProvidedName = filter.hasUserProvidedName
        excludedSites = filter.excludedSites
        selectedSites = filter.selectedSites
    }
}

extension ApplyFilterConfiguration {
    /// Adds one configuration to the applied baseline at its current list position,
    /// so acknowledgements arriving in any order match `current` and leave other pending edits pending.
    static func acknowledging(_ id: UUID, in current: [Self], baseline: [Self]) -> [Self] {
        guard let index = current.firstIndex(where: { $0.id == id }) else { return baseline }
        var result = baseline.filter { $0.id != id }
        let anchor = current[..<index].reversed().lazy.compactMap { previous in result.firstIndex { $0.id == previous.id } }.first
        result.insert(current[index], at: anchor.map { $0 + 1 } ?? 0)
        return result
    }
}
