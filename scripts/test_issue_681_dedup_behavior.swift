// Behavioural check for #681: a list and an identical copy of it must not
// double the compiled Safari rule count, while preprocessor directives and
// comments survive the dedupe untouched.
import Foundation
import wBlockCoreService

@main
struct Main {
    static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(1)
    }

    static func main() throws {
        let groupIdentifier = "group.wblock.test.issue681.\(UUID().uuidString.prefix(8))"
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            fail("no scratch container")
        }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)
        let target = targets[0]

        let content = (1...200).map { "||site\($0).example^" }.joined(separator: "\n") + "\n"
        let original = FilterList(name: "Original", url: URL(string: "https://example.com/a.txt")!, category: .ads, isCustom: true, isSelected: true)
        let fork = FilterList(name: "Fork", url: URL(string: "https://example.com/b.txt")!, category: .ads, isCustom: true, isSelected: true)
        for filter in [original, fork] {
            let url = container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter))
            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        func compile(_ filters: [FilterList]) throws -> Int {
            try ContentBlockerService.compileTargetRules(
                filters: filters,
                orderedSelectedFilters: filters,
                affinitySnapshot: SafariContentBlockerAffinityProcessor.snapshot(for: filters, containerURL: container),
                targetInfo: target,
                allTargets: targets,
                disabledSites: [],
                extraRulesText: nil,
                groupIdentifier: groupIdentifier
            ).safariRulesCount
        }

        let single = try compile([original])
        let both = try compile([original, fork])
        print("count single=\(single) both=\(both)")
        if single == 0 { fail("single list must compile to rules") }
        if both != single { fail("an identical second list must not change the Safari rule count") }

        // Direct unit check on the line filter.
        let lines = ["! comment", "||a.example^", "!#if (adguard)", "||a.example^", "!#endif", "# host comment", "# host comment", "##.ad", " ##.ad "]
        let kept = ContentBlockerService.deduplicatedRuleLines(lines)
        let expected = ["! comment", "||a.example^", "!#if (adguard)", "!#endif", "# host comment", "# host comment", "##.ad"]
        if kept != expected { fail("dedupe must keep comments and directives and drop repeated rules; got \(kept)") }

        print("PASS")
    }
}
