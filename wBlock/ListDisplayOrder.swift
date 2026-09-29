import Foundation

enum ListDisplayOrder {
    static let filtersKey = "filterDisplayOrder"
    static let scriptsKey = "userScriptDisplayOrder"

    static func reset() {
        for key in [filtersKey, scriptsKey] { UserDefaults.standard.removeObject(forKey: key) }
    }

    static func saved(_ key: String) -> Data { UserDefaults.standard.data(forKey: key) ?? Data() }

    /// Device-independent keys in display order; nil while the user has never reordered.
    static func exportedKeys<Item: Identifiable>(_ items: [Item], order: Data, key: (Item) -> String?) -> [String]?
    where Item.ID == UUID {
        order.isEmpty ? nil : sorted(items, order: order).compactMap(key)
    }

    /// Follows a synced key order for the items both devices have; the rest keep their slots.
    static func merging<Item: Identifiable>(_ keys: [String], into items: [Item], key: (Item) -> String?) -> Data
    where Item.ID == UUID {
        let byKey = Dictionary(items.compactMap { item in key(item).map { ($0, item) } }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        return saving(keys.compactMap { byKey[$0] }.filter { seen.insert($0.id).inserted }, in: items)
    }

    static func sorted<Item: Identifiable>(_ filters: [Item], order: Data) -> [Item] where Item.ID == UUID {
        let ids = (try? JSONDecoder().decode([UUID].self, from: order)) ?? []
        let ranks = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        return filters.sorted {
            ranks[$0.id, default: ids.count] < ranks[$1.id, default: ids.count]
        }
    }

    // Replace only visible slots so search and enabled-only moves leave hidden rows in place.
    static func saving<Item: Identifiable>(_ moved: [Item], in filters: [Item]) -> Data where Item.ID == UUID {
        let liveIDs = Set(filters.map(\.id))
        let moved = moved.filter { liveIDs.contains($0.id) }
        let movedIDs = Set(moved.map(\.id))
        var iterator = moved.makeIterator()
        let ids = filters.map { movedIDs.contains($0.id) ? iterator.next()!.id : $0.id }
        return (try? JSONEncoder().encode(ids)) ?? Data()
    }
}
