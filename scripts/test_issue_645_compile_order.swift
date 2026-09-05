import Foundation
import wBlockCoreService

@main
struct Test {
    static func main() {
        func require(_ c: Bool, _ m: String) { guard c else { fputs("FAIL: \(m)\n", stderr); exit(1) } }
        func list(_ name: String, rules: Int, updated: TimeInterval?, url: URL? = nil) -> FilterList {
            FilterList(
                id: UUID(), name: name, url: url ?? URL(string: "https://example.com/\(name).txt")!,
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

        let pasted = list("pasted", rules: 2, updated: 6_000, url: URL(string: "wblock://userlist/local")!)
        let fileImported = list("file", rules: 2, updated: 4_000, url: URL(fileURLWithPath: "/Users/example/list.txt"))
        let localCompile = ContentBlockerMappingService.orderedForCompilation([big, pasted, fileImported]).map(\.name)
        require(localCompile == ["pasted", "file", "big-old"], "file/paste imports use their stored update dates in overflow order: \(localCompile)")

        let tieA = list("tie-a", rules: 10, updated: 7_000)
        let tieB = list("tie-b", rules: 20, updated: 7_000)
        let ties = ContentBlockerMappingService.orderedForCompilation([tieA, tieB]).map(\.name)
        require(ties == ["tie-b", "tie-a"], "equal dates fall back to distribution order: \(ties)")

        let pipeline = try! String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)
        let shared = try! String(contentsOfFile: "wBlockCoreService/SharedAutoUpdateManager.swift", encoding: .utf8)
        require(pipeline.contains("ContentBlockerMappingService.orderedForCompilation(allSelectedFilters)"), "app apply uses compile order")
        require(shared.contains("ContentBlockerMappingService.orderedForCompilation(selectedFilters)"), "background apply uses compile order")
        print("PASS test_issue_645_compile_order")
    }
}
