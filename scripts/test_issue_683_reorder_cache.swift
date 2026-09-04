import Foundation
import wBlockCoreService

@main
struct ReorderCacheTests {
    static func main() throws {
        let group = "group.wblock.test.issue683.\(UUID().uuidString)"
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            fatalError("scratch container unavailable")
        }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)
        let target = targets[0]
        let a = FilterList(name: "A", url: URL(string: "https://example.com/a.txt")!, category: .ads, isSelected: true)
        var b = FilterList(name: "B", url: URL(string: "https://example.com/b.txt")!, category: .ads, isSelected: true)
        let c = FilterList(name: "C", url: URL(string: "https://example.com/c.txt")!, category: .privacy, isSelected: true)
        let d = FilterList(name: "D", url: URL(string: "https://example.com/d.txt")!, category: .privacy, isSelected: true)
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
                targetInfo: target, allTargets: targets, disabledSites: [], extraRulesText: extra, groupIdentifier: group
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
        ContentBlockerIncrementalCache.invalidateInputSignature(targetRulesFilename: target.rulesFilename, groupIdentifier: group)
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
        let removed = try compile([a], [a, c, d], extra: "||extra.example^")
        precondition(!removed.reusedCachedBase, "removing a selected list still misses")
        print("PASS #683 reordering hits cache, fresh output is identical, semantic changes invalidate")
    }
}
