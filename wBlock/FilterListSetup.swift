import Foundation
import wBlockCoreService

enum FilterListSetup {
    static func hydrate(_ filters: [FilterList], defaults: [FilterList]) -> [FilterList] {
        let defaultsByURL = Dictionary(defaults.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [FilterList] = []
        for var filter in filters {
            // A custom subscription can share a catalog URL after cloud sync or
            // backup restore. Its ID and user-owned metadata are independent.
            if !filter.isCustom {
                if let index = result.firstIndex(where: { !$0.isCustom && $0.url == filter.url }) {
                    result[index].isSelected = result[index].isSelected || filter.isSelected
                    continue
                }
                if let catalog = defaultsByURL[filter.url] {
                    filter.name = catalog.name
                    filter.description = catalog.description
                    filter.languages = catalog.languages
                    filter.trustLevel = catalog.trustLevel
                }
            }
            result.append(filter)
        }
        // Stored arrays append newly introduced lists. Saved user ordering is
        // applied separately, so the base order must come from the current catalog.
        let ranks = Dictionary(defaults.enumerated().map { ($0.element.url, $0.offset) }, uniquingKeysWith: min)
        return result.sorted {
            let lhs = $0.isCustom ? defaults.count : ranks[$0.url, default: defaults.count]
            let rhs = $1.isCustom ? defaults.count : ranks[$1.url, default: defaults.count]
            return lhs < rhs
        }
    }
}
