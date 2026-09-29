import Foundation

private struct Item: Identifiable {
    let id = UUID()
    let key: String
}

@main
struct ListDisplayOrderSyncTests {
    @MainActor static func main() async {
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

        // Two devices: reorder -> sync -> reset -> sync. The reset must reach the other device.
        let deviceA = Array(deviceB.dropLast())
        let reorderedA = ListDisplayOrder.saving([deviceA[3], deviceA[0]], in: deviceA)
        let sentReorder = ListDisplayOrder.exportedKeys(deviceA, order: reorderedA, key: key)
        let onB = ListDisplayOrder.applying(sentReorder, to: deviceB, current: none, baseline: none, key: key)!
        precondition(ListDisplayOrder.sorted(deviceB, order: onB).first?.key == "d")

        let sentReset = ListDisplayOrder.exportedKeys(deviceA, order: ListDisplayOrder.cleared, key: key)
        precondition(sentReset == [], "a reset must be exported, not look like never reordered")
        let resetOnB = ListDisplayOrder.applying(sentReset, to: deviceB, current: onB, baseline: onB, key: key)
        precondition(resetOnB == ListDisplayOrder.cleared, "the other device must adopt the reset")
        precondition(ListDisplayOrder.exportedKeys(deviceB, order: resetOnB!, key: key) == sentReset, "devices converge")
        precondition(ListDisplayOrder.sorted(deviceB, order: resetOnB!).compactMap(key) == ["a", "b", "c", "d", "e"])

        // A drag made after the order was read, while final payload construction awaits, is rebuilt in
        // and so differs from the remote payload, which schedules the follow-up upload.
        var order = ["a", "b"]
        var dragged = false
        let final = await StableSnapshot.build(state: { order }) {
            let captured = order
            await Task.yield()
            if !dragged { dragged = true; order = ["b", "a"] }
            return captured
        }
        precondition(final.value == ["b", "a"], "the final payload must include the mid-build reorder")
        precondition(final.value != ["a", "b"], "the reorder must differ from the remote payload")
    }
}
