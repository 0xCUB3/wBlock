import Foundation
import wBlockCoreService

@main
struct ReorderCacheTests {
    static func main() throws {
        let group = "group.wblock.test.issue683.\(UUID().uuidString)"
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-issue683-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)
        let target = targets[0]
        let a = FilterList(name: "A", url: URL(string: "https://example.com/a.txt")!, category: .ads, isSelected: true)
        var b = FilterList(name: "B", url: URL(string: "https://example.com/b.txt")!, category: .ads, isSelected: true)
        let c = FilterList(name: "C", url: URL(string: "https://example.com/c.txt")!, category: .privacy, isSelected: true)
        let d = FilterList(name: "D", url: URL(string: "https://example.com/d.txt")!, category: .privacy, isSelected: true)
        let displayItems = [a, b, c, d]
        let displayOrder = ListDisplayOrder.saving([d, a], in: displayItems)
        precondition(ListDisplayOrder.sorted(displayItems, order: displayOrder).map(\.id) == [d.id, b.id, c.id, a.id],
                     "moving visible rows must leave hidden slots in place")
        precondition(ListDisplayOrder.sorted(displayItems, order: Data()).map(\.id) == displayItems.map(\.id))
        let duplicateOrder = try JSONEncoder().encode([c.id, c.id, a.id])
        precondition(ListDisplayOrder.sorted(displayItems, order: duplicateOrder).map(\.id) == [c.id, a.id, b.id, d.id])
        let stale = FilterList(name: "Deleted", url: URL(string: "https://example.com/deleted")!, category: .ads)
        precondition(ListDisplayOrder.sorted(displayItems, order: ListDisplayOrder.saving([stale, d, a], in: displayItems)).map(\.id)
                     == [d.id, b.id, c.id, a.id], "deleted rows must not corrupt saved ordering")
        func write(_ filter: FilterList, _ text: String) throws {
            try text.write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter)), atomically: true, encoding: .utf8)
        }
        try write(a, "||ads-a.example^\nexample.com##.ad-a\n")
        try write(b, "||ads-b.example^\nexample.com##.ad-b\n")
        try write(c, "!#safari_cb_affinity(all)\n@@||allow-c.example^\n!#safari_cb_affinity\n")
        try write(d, "!#safari_cb_affinity(all)\n@@||allow-d.example^\n!#safari_cb_affinity\n")
        func compile(_ assigned: [FilterList], _ ordered: [FilterList], extra: String? = nil) throws -> ContentBlockerService.ContentBlockerTargetOutcome {
            try ContentBlockerService.compileTargetRules(
                filters: assigned, orderedSelectedFilters: ordered,
                affinitySnapshot: SafariContentBlockerAffinityProcessor.snapshot(for: ordered, containerURL: container),
                targetInfo: target, allTargets: targets, disabledSites: [], extraRulesText: extra,
                groupIdentifier: group, containerURL: container
            )
        }
        func output() throws -> Data {
            try Data(contentsOf: container.appendingPathComponent(ContentBlockerIncrementalCache.baseRulesFilename(for: target.rulesFilename)))
        }
        let first = try compile([a, b], [a, c, b, d])
        precondition(!first.reusedCachedBase)
        let original = try output()
        let reordered = try compile([b, a], [d, b, c, a])
        precondition(reordered.reusedCachedBase, "reordering assigned and affinity lists must hit cache")
        precondition(first.safariRulesCount == reordered.safariRulesCount)
        ContentBlockerIncrementalCache.invalidateInputSignature(
            targetRulesFilename: target.rulesFilename,
            groupIdentifier: group,
            containerURL: container
        )
        let rebuilt = try compile([b, a], [d, b, c, a])
        let fresh = try output()
        precondition(!rebuilt.reusedCachedBase && original == fresh, "fresh output must match cached output after reorder")
        precondition(first.advancedRulesText == rebuilt.advancedRulesText)
        b.excludedSites = ["excluded.example"]
        let excluded = try compile([a, b], [a, b, c, d])
        precondition(!excluded.reusedCachedBase, "site exclusions remain part of cache identity")
        let extra = try compile([a, b], [a, b, c, d], extra: "||extra.example^")
        precondition(!extra.reusedCachedBase, "extra rules remain part of cache identity")
        try write(c, "!#safari_cb_affinity(all)\n@@||changed-c.example^\n@@||another.example^\n!#safari_cb_affinity\n")
        let changed = try compile([a, b], [a, b, c, d], extra: "||extra.example^")
        precondition(!changed.reusedCachedBase, "affinity content changes still miss")
        b.selectedSites = ["only.test"]
        let selectedOnly = try compile([a, b], [a, b, c, d], extra: "||extra.example^")
        precondition(!selectedOnly.reusedCachedBase, "selected-site changes must invalidate cached output")
        b.selectedSites = []
        let nowhere = try compile([a, b], [a, b, c, d], extra: "||extra.example^")
        let nowhereText = String(decoding: try output(), as: UTF8.self)
        precondition(!nowhere.reusedCachedBase && !nowhereText.contains("ads-b") && nowhereText.contains("ads-a"),
                     "an empty selection must disable only that list, not other lists")
        let removed = try compile([a], [a, c, d], extra: "||extra.example^")
        precondition(!removed.reusedCachedBase, "removing a selected list still misses")
        print("PASS #683 reordering hits cache, fresh output is identical, semantic changes invalidate")
    }
}
