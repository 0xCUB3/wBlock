import Foundation
import wBlockCoreService

@main
struct CompilationProvenanceTests {
    static func main() throws {
        let groupIdentifier = "group.wblock.test.provenance.\(UUID().uuidString.prefix(8))"
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            fail("no scratch container")
        }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        CosmeticFilteringPreference.setEnabled(false, groupIdentifier: groupIdentifier)

        let target = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)[0]
        var newest = filter("newest", updated: 2_000)
        var older = filter("older", updated: 1_000)
        newest.sourceRuleCount = 3
        older.sourceRuleCount = 3

        try write(
            "||shared.example^\nnewest.example##.ad\n||newest.example^\n",
            for: newest,
            in: container
        )
        try write(
            "||shared.example^\nolder.example##.ad\n||older.example^\n",
            for: older,
            in: container
        )

        let first = try compile([older, newest], target: target, groupIdentifier: groupIdentifier)
        expect(!first.reusedCachedBase, "first conversion should build the target")
        expect(first.safariRulesCount > 0, "converter should report actual target output")
        expectEqual(
            first.admittedSourceRuleCountsByFilterID[newest.id],
            2,
            "newest list should own its two non-cosmetic source rules"
        )
        expectEqual(
            first.admittedSourceRuleCountsByFilterID[older.id],
            1,
            "older list should not be credited for a duplicate or stripped cosmetic rule"
        )
        expectEqual(
            savedRuleCount(target: target, in: container),
            first.safariRulesCount,
            "reported Safari count should match the saved target JSON"
        )

        let second = try compile([older, newest], target: target, groupIdentifier: groupIdentifier)
        expect(second.reusedCachedBase, "unchanged input should use the target cache")
        expectEqual(
            second.admittedSourceRuleCountsByFilterID,
            first.admittedSourceRuleCountsByFilterID,
            "cache reuse should return persisted compile-time provenance, not a fresh estimate"
        )

        let sidecar = container.appendingPathComponent(target.rulesFilename + ".source-rule-provenance.json")
        var stale = try JSONSerialization.jsonObject(with: Data(contentsOf: sidecar)) as! [String: Any]
        stale["inputSignature"] = "different-input"
        try JSONSerialization.data(withJSONObject: stale).write(to: sidecar)
        let third = try compile([older, newest], target: target, groupIdentifier: groupIdentifier)
        expect(third.reusedCachedBase, "the valid compiled target should remain reusable")
        expect(third.admittedSourceRuleCountsByFilterID.isEmpty, "stale sidecar counts must not be reported as current evidence")

        print("PASS test_compilation_provenance")
    }

    private static func filter(_ name: String, updated: TimeInterval) -> FilterList {
        FilterList(
            name: name,
            url: URL(string: "https://example.com/\(name).txt")!,
            category: .ads,
            isSelected: true,
            lastUpdated: Date(timeIntervalSince1970: updated)
        )
    }

    private static func write(_ content: String, for filter: FilterList, in container: URL) throws {
        let url = container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter))
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func compile(
        _ filters: [FilterList],
        target: ContentBlockerTargetInfo,
        groupIdentifier: String
    ) throws -> ContentBlockerService.ContentBlockerTargetOutcome {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            fail("no scratch container")
        }
        let ordered = ContentBlockerMappingService.orderedForCompilation(filters)
        let snapshot = SafariContentBlockerAffinityProcessor.snapshot(for: ordered, containerURL: container)
        return try ContentBlockerService.compileTargetRules(
            filters: filters,
            orderedSelectedFilters: ordered,
            affinitySnapshot: snapshot,
            targetInfo: target,
            allTargets: [target],
            disabledSites: [],
            extraRulesText: nil,
            groupIdentifier: groupIdentifier
        )
    }

    private static func savedRuleCount(target: ContentBlockerTargetInfo, in container: URL) -> Int {
        let url = container.appendingPathComponent(target.rulesFilename)
        guard let data = try? Data(contentsOf: url),
              let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            fail("could not read saved rules JSON")
        }
        return rules.count
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fail(message) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fail("\(message): actual=\(String(describing: actual)) expected=\(String(describing: expected))")
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
