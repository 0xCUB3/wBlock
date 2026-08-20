import Foundation

/// Pure catalog operations used while hydrating the built-in filter lists.
public enum FilterCatalogMerge {
    public static func mergeDefaults(
        into filters: [FilterList],
        defaults: [FilterList],
        nameMigrations: [String: [String]] = [:]
    ) -> [FilterList] {
        var result = filters
        for defaultFilter in defaults {
            let alreadyPresent = result.contains { filter in
                !filter.isCustom && (filter.url == defaultFilter.url
                    || filter.name == defaultFilter.name
                    || nameMigrations[defaultFilter.name, default: []].contains(filter.name))
            }
            guard !alreadyPresent else { continue }
            var added = defaultFilter
            added.isSelected = false
            result.append(added)
        }
        return collapseDuplicateBuiltIns(result)
    }

    /// Keeps the first built-in entry (and therefore its ID), while retaining selection.
    public static func collapseDuplicateBuiltIns(_ filters: [FilterList]) -> [FilterList] {
        var result: [FilterList] = []
        for filter in filters {
            guard !filter.isCustom else {
                result.append(filter)
                continue
            }
            if let index = result.firstIndex(where: { !$0.isCustom && $0.url == filter.url }) {
                result[index].isSelected = result[index].isSelected || filter.isSelected
            } else {
                result.append(filter)
            }
        }
        return result
    }
}
