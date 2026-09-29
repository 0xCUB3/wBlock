import Foundation

enum ListDisplayOrder {
    static let filtersKey = "filterDisplayOrder"
    static let scriptsKey = "userScriptDisplayOrder"

    /// An explicit reset to the default order. Unlike an absent blob ("never reordered"), it syncs.
    static let cleared = Data("[]".utf8)

    static func reset() {
        for key in [filtersKey, scriptsKey] { UserDefaults.standard.set(cleared, forKey: key) }
    }

    static func saved(_ key: String) -> Data { UserDefaults.standard.data(forKey: key) ?? Data() }

    /// Device-independent keys in display order; nil while the user has never reordered, empty after a reset.
    static func exportedKeys<Item: Identifiable>(_ items: [Item], order: Data, key: (Item) -> String?) -> [String]?
    where Item.ID == UUID {
        order.isEmpty ? nil : order == cleared ? [] : sorted(items, order: order).compactMap(key)
    }

    /// The order to store after a synced payload, or nil to keep the local one (no remote opinion,
    /// or the user reordered since `baseline`).
    static func applying<Item: Identifiable>(
        _ keys: [String]?, to items: [Item], current: Data, baseline: Data, key: (Item) -> String?
    ) -> Data? where Item.ID == UUID {
        guard let keys, current == baseline else { return nil }
        return keys.isEmpty ? cleared : merging(keys, into: sorted(items, order: current), key: key)
    }

    /// The order last agreed with the server. A device whose order still equals it has no opinion of its own.
    static func synced(_ key: String, defaults: UserDefaults = .standard) -> Data {
        defaults.data(forKey: key + "Synced") ?? Data()
    }

    /// Stores the remote order unless `applying` says to keep the local one, and records it as agreed.
    static func adopt<Item: Identifiable>(
        _ keys: [String]?, to items: [Item], key: String, baseline: Data,
        defaults: UserDefaults = .standard, itemKey: (Item) -> String?
    ) where Item.ID == UUID {
        let current = defaults.data(forKey: key) ?? Data()
        guard let order = applying(keys, to: items, current: current, baseline: baseline, key: itemKey) else { return }
        defaults.set(order, forKey: key)
        defaults.set(order, forKey: key + "Synced")
    }

    /// Records the current order as agreed once the server holds exactly it.
    static func markSynced<Item: Identifiable>(
        _ keys: [String]?, items: [Item], key: String, defaults: UserDefaults = .standard, itemKey: (Item) -> String?
    ) where Item.ID == UUID {
        let current = defaults.data(forKey: key) ?? Data()
        if exportedKeys(items, order: current, key: itemKey) == keys { defaults.set(current, forKey: key + "Synced") }
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
