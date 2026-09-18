// Behavioural check for #836: an `@@` exception that lives in a list compiled
// into another content blocker must be replicated next to the block it
// cancels, and exceptions that cancel nothing in a target stay out of it.
import Foundation
import wBlockCoreService

@main
struct Main {
    static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(1)
    }

    static func main() throws {
        let groupIdentifier = "group.wblock.test.issue836.\(UUID().uuidString.prefix(8))"
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-issue836-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .iOS)

        // Distribution is by size, so the big list and the small list land in
        // different blockers.
        var blocker = FilterList(name: "Blocker", url: URL(string: "https://example.com/blocker.txt")!, category: .privacy, isSelected: true)
        var excepter = FilterList(name: "Excepter", url: URL(string: "https://example.com/excepter.txt")!, category: .ads, isSelected: true)
        blocker.sourceRuleCount = 500
        excepter.sourceRuleCount = 5
        func write(_ filter: FilterList, _ text: String) throws {
            try text.write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter)), atomically: true, encoding: .utf8)
        }
        let filler = (1...500).map { "||site\($0).example^" }.joined(separator: "\n")
        try write(blocker, filler + "\n||bing.com/fd/ls/GLinkPing.aspx?\n||tracker.example^\n")
        try write(excepter, """
        ||ads.example^
        @@||bing.com/fd/ls/GLinkPing.aspx?
        @@||sub.tracker.example/path$script
        @@||unrelated.example^
        @@||ads.example^$domain=news.example
        """)

        let selection = [blocker, excepter]
        let ordered = ContentBlockerMappingService.orderedForCompilation(selection)
        let mapping = ContentBlockerMappingService.distribute(selectedFilters: selection, across: targets)
        let snapshot = SafariContentBlockerAffinityProcessor.snapshot(for: ordered, containerURL: container)
        guard let blockerSlot = mapping.first(where: { $0.value.contains(where: { $0.id == blocker.id }) })?.key,
              let excepterSlot = mapping.first(where: { $0.value.contains(where: { $0.id == excepter.id }) })?.key,
              blockerSlot != excepterSlot
        else { fail("the two lists must be assigned to different blockers") }

        func compile(_ slot: ContentBlockerTargetInfo) throws -> [[String: Any]] {
            _ = try ContentBlockerService.compileTargetRules(
                filters: mapping[slot] ?? [], orderedSelectedFilters: ordered,
                affinitySnapshot: snapshot, targetInfo: slot, allTargets: targets,
                disabledSites: [], extraRulesText: nil, groupIdentifier: groupIdentifier,
                containerURL: container
            )
            let data = try Data(contentsOf: container.appendingPathComponent(slot.rulesFilename))
            return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        }
        func actions(_ rules: [[String: Any]], containing fragment: String) -> [String] {
            rules.compactMap { rule in
                guard let trigger = rule["trigger"] as? [String: Any],
                      let filter = trigger["url-filter"] as? String, filter.contains(fragment),
                      let action = rule["action"] as? [String: Any]
                else { return nil }
                return action["type"] as? String
            }
        }

        let blockerRules = try compile(blockerSlot)
        if actions(blockerRules, containing: "GLinkPing") != ["block", "ignore-previous-rules"] {
            fail("exception for a block in another slot must be replicated after that block; got \(actions(blockerRules, containing: "GLinkPing"))")
        }
        if actions(blockerRules, containing: "tracker").last != "ignore-previous-rules" {
            fail("an exception narrower than a whole-host block must be replicated")
        }
        if !actions(blockerRules, containing: "unrelated").isEmpty {
            fail("an exception that cancels nothing in this slot must not be replicated")
        }
        if !actions(blockerRules, containing: "ads\\.example").isEmpty {
            fail("an exception whose block lives in its own slot must not be replicated")
        }

        let excepterRules = try compile(excepterSlot)
        if actions(excepterRules, containing: "ads\\.example") != ["block", "ignore-previous-rules"] {
            fail("same-slot exceptions must keep working")
        }
        if actions(excepterRules, containing: "GLinkPing").contains("block") {
            fail("the excepter's own slot must not gain the other slot's block")
        }

        // Cache identity must cover the other slot's exceptions.
        let cached = try ContentBlockerService.compileTargetRules(
            filters: mapping[blockerSlot] ?? [], orderedSelectedFilters: ordered,
            affinitySnapshot: snapshot, targetInfo: blockerSlot, allTargets: targets,
            disabledSites: [], extraRulesText: nil, groupIdentifier: groupIdentifier, containerURL: container
        )
        if !cached.reusedCachedBase { fail("unchanged inputs must hit the cache") }
        sleep(1)
        try write(excepter, "||ads.example^\n@@||unrelated.example^\n")
        let rebuilt = try ContentBlockerService.compileTargetRules(
            filters: mapping[blockerSlot] ?? [], orderedSelectedFilters: ordered,
            affinitySnapshot: snapshot, targetInfo: blockerSlot, allTargets: targets,
            disabledSites: [], extraRulesText: nil, groupIdentifier: groupIdentifier, containerURL: container
        )
        if rebuilt.reusedCachedBase { fail("changing another slot's exceptions must rebuild this slot") }
        let data = try Data(contentsOf: container.appendingPathComponent(blockerSlot.rulesFilename))
        let after = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        if actions(after, containing: "GLinkPing") != ["block"] {
            fail("a removed exception must disappear from the other slot")
        }

        print("PASS")
    }
}
