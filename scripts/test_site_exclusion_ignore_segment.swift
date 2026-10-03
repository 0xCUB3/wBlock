import Foundation
import wBlockCoreService

// A large list with a site exclusion compiled ~99k domain-conditioned rules,
// which killed WebKit's compiler (#925). Its unscoped blocks now precede one
// ignore rule; other lists in the blocker must still block on that site.
@main
struct SiteExclusionIgnoreSegmentTests {
    static func main() throws {
        let groupIdentifier = "group.wblock.test.925.\(UUID().uuidString.prefix(8))"
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-925-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let target = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)[0]
        var excluded = FilterList(name: "excluded", url: URL(string: "https://example.com/a.txt")!, category: .privacy, isSelected: true)
        excluded.excludedSites = ["example.com"]
        let other = FilterList(name: "other", url: URL(string: "https://example.com/b.txt")!, category: .privacy, isSelected: true)
        let unscoped = (0..<2000).map { "||tracker\($0).net^" }.joined(separator: "\n")
        try (unscoped + "\n||scoped.net^$domain=news.org\n@@||allowed.net^\n")
            .write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: excluded)), atomically: true, encoding: .utf8)
        try "||other.net^\n".write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: other)), atomically: true, encoding: .utf8)

        let ordered = ContentBlockerMappingService.orderedForCompilation([excluded, other])
        _ = try ContentBlockerService.compileTargetRules(
            filters: [excluded, other], orderedSelectedFilters: ordered,
            affinitySnapshot: SafariContentBlockerAffinityProcessor.snapshot(for: ordered, containerURL: container),
            targetInfo: target, allTargets: [target], disabledSites: [], extraRulesText: nil,
            groupIdentifier: groupIdentifier, containerURL: container
        )
        let data = try Data(contentsOf: container.appendingPathComponent(target.rulesFilename))
        let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        func blocked(_ url: String, on host: String) -> Bool {
            var state = false
            for rule in rules {
                let trigger = rule["trigger"] as? [String: Any] ?? [:]
                guard let filter = trigger["url-filter"] as? String,
                      url.range(of: filter, options: .regularExpression) != nil else { continue }
                let matches: ([String]) -> Bool = { $0.contains { d in
                    let site = d.hasPrefix("*") ? String(d.dropFirst()) : d
                    return host == site || host.hasSuffix("." + site)
                } }
                if let only = trigger["if-domain"] as? [String], !matches(only) { continue }
                if let except = trigger["unless-domain"] as? [String], matches(except) { continue }
                switch (rule["action"] as? [String: Any])?["type"] as? String {
                case "block": state = true
                case "ignore-previous-rules": state = false
                default: break
                }
            }
            return state
        }

        let conditioned = rules.filter { (($0["trigger"] as? [String: Any])?["unless-domain"]) != nil }.count
        check(conditioned < 10, "unscoped rules carry no per-rule negation: \(conditioned)")
        check(blocked("https://tracker7.net/x.js", on: "news.org"), "excluded list still blocks elsewhere")
        check(!blocked("https://tracker7.net/x.js", on: "www.example.com"), "excluded list stops on the excluded site")
        check(!blocked("https://scoped.net/x.js", on: "example.com") && blocked("https://scoped.net/x.js", on: "news.org"), "scoped rules keep their scope")
        check(blocked("https://other.net/x.js", on: "example.com"), "other lists still block on the excluded site")
        print("PASS: site exclusions compile as one ignore rule")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
