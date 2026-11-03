// A list larger than one content blocker must be split across blockers instead
// of overflowing one, and an overflow the converter cuts must be reported.
import Foundation
import wBlockCoreService

@main
struct Main {
    static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(1)
    }

    static func main() throws {
        let groupIdentifier = "group.wblock.test.overflow.\(UUID().uuidString.prefix(8))"
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-overflow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .iOS)

        // A large custom list alongside the upgrade defaults fits in five
        // blockers, but coarse shards used to strand space and overflow two.
        let counts = [400_000, 108_487, 86_027, 56_426, 28_178, 23_540, 4_862, 3_564, 3_108, 2_547, 2_408, 1_831, 403, 38, 1]
        let upgrade = counts.enumerated().map { index, count -> FilterList in
            var filter = FilterList(name: "upgrade-\(index)", url: URL(string: "https://example.com/\(index)")!, category: .ads, isSelected: true)
            filter.sourceRuleCount = count
            return filter
        }
        let packed = ContentBlockerMappingService.plan(selectedFilters: upgrade, across: targets)
        for target in targets {
            let estimated = (packed.filtersByTarget[target] ?? []).reduce(0) { total, filter in
                let parts = packed.shardsByTarget[target]?[filter.id]?.count ?? 1
                return total + ((filter.sourceRuleCount ?? 0) + parts - 1) / parts
            }
            if estimated >= ContentBlockerService.safariContentBlockerRuleLimit { fail("upgrade strands capacity: \(estimated)") }
        }

        func list(_ name: String, _ count: Int, _ extra: String = "") throws -> FilterList {
            var filter = FilterList(name: name, url: URL(string: "https://example.com/\(name).txt")!, category: .ads, isSelected: true)
            let text = (0..<count).map { "||\(name)-\($0).example^" }.joined(separator: "\n") + "\n" + extra
            filter.sourceRuleCount = FilterList.countRules(in: text)
            try text.write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter)), atomically: true, encoding: .utf8)
            return filter
        }
        func compile(_ filters: [FilterList], _ selection: [FilterList], _ slot: ContentBlockerTargetInfo) throws -> ContentBlockerService.ContentBlockerTargetOutcome {
            let ordered = ContentBlockerMappingService.orderedForCompilation(selection)
            return try ContentBlockerService.compileTargetRules(
                filters: filters, orderedSelectedFilters: ordered,
                targetInfo: slot, allTargets: targets, disabledSites: [], extraRulesText: nil,
                groupIdentifier: groupIdentifier, containerURL: container
            )
        }

        let big = try list("big", 170_000, "@@||big-7.example^")
        let selection = [big, try list("small", 1_000)]
        let mapping = ContentBlockerMappingService.distribute(selectedFilters: selection, across: targets)
        let bigSlots = targets.filter { mapping[$0]?.contains { $0.id == big.id } == true }
        if bigSlots.count != 2 { fail("a 170k list must be split across two blockers, got \(bigSlots.count)") }
        var compiled = 0
        for slot in bigSlots {
            let outcome = try compile(mapping[slot] ?? [], selection, slot)
            if outcome.truncatedRuleCount > 0 { fail("\(slot.displayName) still overflows") }
            let json = try String(contentsOf: container.appendingPathComponent(slot.rulesFilename), encoding: .utf8)
            if !json.contains("ignore-previous-rules") { fail("every part of a split list keeps its exceptions") }
            compiled += outcome.safariRulesCount
        }
        if compiled < 170_000 { fail("split parts must keep every rule, got \(compiled)") }

        // Underestimated, so not split: the converter's own cut must surface.
        var hidden = try list("hidden", 170_000)
        hidden.sourceRuleCount = 50_000
        let lone = [hidden]
        let loneMapping = ContentBlockerMappingService.distribute(selectedFilters: lone, across: targets)
        guard let slot = targets.first(where: { loneMapping[$0]?.isEmpty == false }) else { fail("no blocker for the list") }
        for attempt in 1...2 {
            let outcome = try compile(loneMapping[slot] ?? [], lone, slot)
            if outcome.truncatedRuleCount == 0 { fail("converter overflow went unreported on attempt \(attempt)") }
        }

        print("PASS")
    }
}
