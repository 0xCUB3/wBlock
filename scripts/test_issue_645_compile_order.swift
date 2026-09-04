import Foundation
import wBlockCoreService

@main
struct Test {
    static func main() {
        func require(_ c: Bool, _ m: String) { guard c else { fputs("FAIL: \(m)\n", stderr); exit(1) } }
        func list(_ name: String, rules: Int, updated: TimeInterval?) -> FilterList {
            FilterList(
                id: UUID(), name: name, url: URL(string: "https://example.com/\(name).txt")!,
                category: .ads, isSelected: true, description: "", sourceRuleCount: rules,
                lastUpdated: updated.map { Date(timeIntervalSince1970: $0) }
            )
        }
        // #645: newest lists compile first so overflow drops the oldest content.
        let big = list("big-old", rules: 100_000, updated: 1_000)
        let small = list("small-new", rules: 1_000, updated: 5_000)
        let never = list("never-checked", rules: 50_000, updated: nil)
        let mid = list("mid", rules: 20_000, updated: 3_000)

        let distribution = ContentBlockerMappingService.orderedForDistribution([small, never, mid, big]).map(\.name)
        require(distribution == ["big-old", "never-checked", "mid", "small-new"], "distribution still packs largest first: \(distribution)")

        let compile = ContentBlockerMappingService.orderedForCompilation([small, never, mid, big]).map(\.name)
        require(compile == ["small-new", "mid", "big-old", "never-checked"], "compile order is newest first, never-updated last: \(compile)")

        let tieA = list("tie-a", rules: 10, updated: 7_000)
        let tieB = list("tie-b", rules: 20, updated: 7_000)
        let ties = ContentBlockerMappingService.orderedForCompilation([tieA, tieB]).map(\.name)
        require(ties == ["tie-b", "tie-a"], "equal dates fall back to distribution order: \(ties)")

        let pipeline = try! String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)
        let shared = try! String(contentsOfFile: "wBlockCoreService/SharedAutoUpdateManager.swift", encoding: .utf8)
        require(pipeline.contains("ContentBlockerMappingService.orderedForCompilation(allSelectedFilters)"), "app apply uses compile order")
        require(shared.contains("ContentBlockerMappingService.orderedForCompilation(selectedFilters)"), "background apply uses compile order")
        // #644: unique counts credit a rule to the first list in compile order.
        let newer = list("newer", rules: 3, updated: 9_000)
        let older = list("older", rules: 3, updated: 1_000)
        let unselected = list("off", rules: 1, updated: 8_000)
        let texts: [String: String] = [
            "newer": "! header\n||a.com^\n||b.com^\n##.ad\n",
            "older": "[Adblock Plus 2.0]\n||b.com^\n||c.com^\n##.ad\n",
        ]
        let unique = ContentBlockerMappingService.uniqueRuleCounts(for: [older, newer]) { texts[$0.name] }
        require(unique[newer.id] == 3, "newest list keeps all of its rules: \(unique[newer.id] ?? -1)")
        require(unique[older.id] == 1, "older list only counts rules the newer one lacks: \(unique[older.id] ?? -1)")
        require(unique[unselected.id] == nil, "lists without content are skipped")
        print("PASS test_issue_645_compile_order")
    }
}
