import Foundation
import wBlockCoreService

// WebKit rejects a whole rule list when any if-domain/unless-domain entry has uppercase
// letters, and SafariConverterLib keeps domains as written (#898).
@main
struct ContentBlockerDomainCaseTests {
    static func main() throws {
        let groupIdentifier = "group.wblock.test.domain-case.\(UUID().uuidString.prefix(8))"
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-domain-case-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        CosmeticFilteringPreference.setEnabled(true, groupIdentifier: groupIdentifier)

        let target = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)[0]
        let list = FilterList(name: "mixed case", url: URL(string: "https://example.com/list.txt")!, category: .foreign, isSelected: true)
        try "Foo.COM##.ad\nbar.com,~Baz.Com##.ad\nKaro.Studio##a[href*=\"Karo.Studio\"]>img\n"
            .write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: list)), atomically: true, encoding: .utf8)

        let ordered = ContentBlockerMappingService.orderedForCompilation([list])
        _ = try ContentBlockerService.compileTargetRules(
            filters: [list],
            orderedSelectedFilters: ordered,
            affinitySnapshot: SafariContentBlockerAffinityProcessor.snapshot(for: ordered, containerURL: container),
            targetInfo: target,
            allTargets: [target],
            disabledSites: [],
            extraRulesText: nil,
            groupIdentifier: groupIdentifier,
            containerURL: container
        )

        let data = try Data(contentsOf: container.appendingPathComponent(target.rulesFilename))
        let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        let domains = rules.flatMap { rule -> [String] in
            let trigger = rule["trigger"] as? [String: Any] ?? [:]
            return (trigger["if-domain"] as? [String] ?? []) + (trigger["unless-domain"] as? [String] ?? [])
        }
        let selectors = rules.compactMap { ($0["action"] as? [String: Any])?["selector"] as? String }
        check(Set(["*foo.com", "*baz.com"]).isSubset(of: domains), "mixed-case domains are lowercased: \(domains)")
        check(domains.allSatisfy { $0 == $0.lowercased() }, "no uppercase domain reaches Safari: \(domains)")
        check(selectors.contains { $0.contains("Karo.Studio") }, "selectors keep their case: \(selectors)")
        print("PASS: content blocker domains are lowercase")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
