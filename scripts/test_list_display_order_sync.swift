import Foundation

private struct Item: Identifiable {
    let id = UUID()
    let key: String
}

@main
struct ListDisplayOrderSyncTests {
    static func main() {
        let key: (Item) -> String? = \.key
        let deviceB = ["a", "b", "c", "d", "e"].map { Item(key: $0) }
        let none = Data()

        // A reorder made while a sync was in flight is kept; an untouched order follows the remote.
        let remote = ["d", "b", "c", "a"]
        let midSync = ListDisplayOrder.saving([deviceB[2], deviceB[0]], in: deviceB)
        precondition(ListDisplayOrder.applying(remote, to: deviceB, current: midSync, baseline: none, key: key) == nil,
                     "a reorder during sync must not be overwritten")
        let followed = ListDisplayOrder.applying(remote, to: deviceB, current: none, baseline: none, key: key)!
        precondition(ListDisplayOrder.sorted(deviceB, order: followed).compactMap(key) == ["d", "b", "c", "a", "e"])
        precondition(ListDisplayOrder.applying(nil, to: deviceB, current: none, baseline: none, key: key) == nil)
    }
}
