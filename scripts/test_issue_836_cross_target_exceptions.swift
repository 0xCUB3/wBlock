// Behavioural check for #836: an `@@` exception that lives in a list compiled
// into another content blocker must still lift the blocks it can cancel,
// wherever the engine places them, including generic blocks that name no host.
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
        let slotOf = { (list: FilterList) in mapping.first(where: { $0.value.contains(where: { $0.id == list.id }) })?.key }
        guard let blockerSlot = slotOf(blocker), blockerSlot != slotOf(excepter)
        else { fail("the two lists must be assigned to different blockers") }

        // Every blocker, compiled as the app applies them; true where the
        // blocker reused its cached output.
        func compileAll() throws -> (blockers: [[[String: Any]]], reused: [Bool]) {
            var blockers: [[[String: Any]]] = []
            var reused: [Bool] = []
            for slot in targets {
                let outcome = try ContentBlockerService.compileTargetRules(
                    filters: mapping[slot] ?? [], orderedSelectedFilters: ordered,
                    targetInfo: slot, allTargets: targets,
                    disabledSites: [], extraRulesText: nil, groupIdentifier: groupIdentifier,
                    containerURL: container
                )
                let data = try Data(contentsOf: container.appendingPathComponent(slot.rulesFilename))
                blockers.append(try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? [])
                reused.append(outcome.reusedCachedBase)
            }
            return (blockers, reused)
        }

        let glinkPing = "https://www.bing.com/fd/ls/GLinkPing.aspx?IG=1"
        let first = try compileAll()
        func blocks(_ url: String, on host: String = "page.example", type: String = "script") -> Bool {
            safariBlocks(url, on: host, type: type, in: first.blockers)
        }
        if !blocks("https://site1.example/x.js") || !blocks("https://tracker.example/x.js") {
            fail("the blocker list's blocks must apply")
        }
        if blocks(glinkPing) { fail("an exception in another list must lift a block it matches") }
        if blocks("https://sub.tracker.example/path/x.js") || !blocks("https://sub.tracker.example/path/x.js", type: "image") {
            fail("an exception narrower than a whole-host block must lift only the loads it names")
        }
        // The compatibility rules' path blocks match URLs on any host, so a
        // host exception lifts them there too.
        if !blocks("https://cdn.example/js/widget/ads.js") || blocks("https://unrelated.example/js/widget/ads.js") {
            fail("an exception must reach generic blocks that match its URLs")
        }
        if !blocks("https://ads.example/a.js") || blocks("https://ads.example/a.js", on: "news.example") {
            fail("an exception in the block's own list must keep working")
        }

        // Cache identity must cover the other list's exceptions, wherever
        // they were compiled.
        if !(try compileAll()).reused.allSatisfy({ $0 }) { fail("unchanged inputs must hit the cache") }
        sleep(1)
        try write(excepter, "||ads.example^\n@@||unrelated.example^\n")
        let rebuilt = try compileAll()
        if !safariBlocks(glinkPing, on: "page.example", in: rebuilt.blockers) {
            fail("a removed exception must stop lifting the block in every blocker")
        }
        if safariBlocks("https://unrelated.example/js/widget/ads.js", on: "page.example", in: rebuilt.blockers) {
            fail("the remaining exception must keep working")
        }

        print("PASS")
    }
}
