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

        // Device B synced A's reorder, so its order is agreed, not an opinion. After A resets, B (and a
        // never-reordered device) uploading unrelated settings must adopt [] instead of exporting the old
        // order or nil, so device C still receives the reset.
        let suite = UserDefaults(suiteName: "list-display-order-sync-test")!
        suite.removePersistentDomain(forName: "list-display-order-sync-test")
        ListDisplayOrder.adopt(sentReorder, to: deviceB, key: "order", baseline: ListDisplayOrder.synced("order", defaults: suite),
                               defaults: suite, itemKey: key)
        precondition(suite.data(forKey: "order") == onB && ListDisplayOrder.synced("order", defaults: suite) == onB)
        for start in [onB, none] {
            suite.set(start, forKey: "order"); suite.set(start, forKey: "orderSynced")
            ListDisplayOrder.adopt(sentReset, to: deviceB, key: "order", baseline: ListDisplayOrder.synced("order", defaults: suite),
                                   defaults: suite, itemKey: key)
            let uploaded = ListDisplayOrder.exportedKeys(deviceB, order: suite.data(forKey: "order") ?? none, key: key)
            precondition(uploaded == [], "an unrelated upload must keep the reset")
            precondition(ListDisplayOrder.applying(uploaded, to: deviceB, current: onB, baseline: onB, key: key) == ListDisplayOrder.cleared,
                         "device C must still receive the reset")
        }
        // A reorder B made since the last agreement is its own opinion and survives the adoption.
        suite.set(midSync, forKey: "order"); suite.set(onB, forKey: "orderSynced")
        ListDisplayOrder.adopt(sentReset, to: deviceB, key: "order", baseline: ListDisplayOrder.synced("order", defaults: suite),
                               defaults: suite, itemKey: key)
        precondition(suite.data(forKey: "order") == midSync, "an unsynced reorder must not be overwritten")
        ListDisplayOrder.markSynced(ListDisplayOrder.exportedKeys(deviceB, order: midSync, key: key), items: deviceB, key: "order",
                                    defaults: suite, itemKey: key)
        precondition(ListDisplayOrder.synced("order", defaults: suite) == midSync, "an uploaded order becomes the agreed one")

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

        // Two rows sharing an ID must not exhaust the moved order and trap.
        let shared = Item(key: "x")
        let duplicated = [shared, deviceB[0], shared]
        precondition(!ListDisplayOrder.merging(["x", "a"], into: duplicated, key: key).isEmpty)
    }
}
