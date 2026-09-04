// Behavioural check for #679: with an affinity list in the selection, a
// second compile of the same inputs must be a cache hit, and changing the
// affinity list must be a miss.
import Foundation
import wBlockCoreService

@main
struct Main {
    static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(1)
    }

    static func main() throws {
        let groupIdentifier = "group.wblock.test.issue679.\(UUID().uuidString.prefix(8))"
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            fail("no scratch container")
        }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)
        guard targets.count >= 2 else { fail("need at least two targets") }
        let target = targets[0]
        let other = targets[1]

        let plain = FilterList(name: "Plain List", url: URL(string: "https://example.com/plain.txt")!, category: .ads, isSelected: true)
        let affinity = FilterList(name: "Affinity List", url: URL(string: "https://example.com/affinity.txt")!, category: .privacy, isSelected: true)

        func write(_ filter: FilterList, _ content: String) throws {
            let url = container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter))
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(plain, "||ads.example^\n||tracker.example^\n")
        try write(affinity, "||privacy.example^\n!#safari_cb_affinity(all)\n@@||allowed.example^\n!#safari_cb_affinity\n")

        func compile() throws -> ContentBlockerService.ContentBlockerTargetOutcome {
            let snapshot = SafariContentBlockerAffinityProcessor.snapshot(for: [plain, affinity], containerURL: container)
            guard !snapshot.isEmpty else { fail("affinity snapshot should contain the affinity list") }
            return try ContentBlockerService.compileTargetRules(
                filters: [plain],
                orderedSelectedFilters: [plain, affinity],
                affinitySnapshot: snapshot,
                targetInfo: target,
                allTargets: [target, other],
                disabledSites: [],
                extraRulesText: nil,
                groupIdentifier: groupIdentifier
            )
        }

        let first = try compile()
        if first.reusedCachedBase { fail("first compile must be a miss") }
        let second = try compile()
        if !second.reusedCachedBase { fail("second compile with identical inputs must reuse the cache even with an affinity list present") }
        if second.safariRulesCount != first.safariRulesCount { fail("cached compile must report the same rule count") }

        // Touch the affinity contributor: it feeds this target, so the cache must miss.
        sleep(1)
        try write(affinity, "||privacy.example^\n!#safari_cb_affinity(all)\n@@||allowed.example^\n@@||another.example^\n!#safari_cb_affinity\n")
        let third = try compile()
        if third.reusedCachedBase { fail("changing an affinity contributor must invalidate the cache") }
        let fourth = try compile()
        if !fourth.reusedCachedBase { fail("unchanged inputs after the contributor change must hit again") }

        print("PASS")
    }
}
