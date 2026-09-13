import Foundation

enum ListDisplayOrder {
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
