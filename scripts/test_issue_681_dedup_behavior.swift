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

        var left = FilterList(name: "Left", url: URL(string: "https://example.com/left")!, category: .ads, isSelected: true)
        var right = FilterList(name: "Right", url: URL(string: "https://example.com/right")!, category: .privacy, isSelected: true)
        left.sourceRuleCount = 200
        right.sourceRuleCount = 200
        func write(_ filter: FilterList, _ text: String) throws {
            try text.write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter)), atomically: true, encoding: .utf8)
        }
        try write(left, content)
        try write(right, content.uppercased())
        func compileSlots(_ selection: [FilterList]) throws -> [ContentBlockerService.ContentBlockerTargetOutcome] {
            let ordered = ContentBlockerMappingService.orderedForCompilation(selection)
            let mapping = ContentBlockerMappingService.distribute(selectedFilters: selection, across: targets)
            let snapshot = SafariContentBlockerAffinityProcessor.snapshot(for: ordered, containerURL: container)
            return try targets.map { slot in
                try ContentBlockerService.compileTargetRules(
                    filters: mapping[slot] ?? [], orderedSelectedFilters: ordered,
                    affinitySnapshot: snapshot, targetInfo: slot, allTargets: targets,
                    disabledSites: [], extraRulesText: nil, groupIdentifier: groupIdentifier
                )
            }
        }
        let baseline = try compileSlots([left]).reduce(0) { $0 + $1.safariRulesCount }
        let split = try compileSlots([left, right])
        if split.reduce(0, { $0 + $1.safariRulesCount }) != baseline { fail("case variants in different slots must compile once") }
        if !(try compileSlots([left, right])).allSatisfy(\.reusedCachedBase) { fail("cross-slot cache must be reusable") }
        let ordered = ContentBlockerIncrementalCache.canonicalFilterOrder([left, right])
        try write(ordered[0], "! emptied owner\n")
        let moved = try compileSlots([left, right])
        if moved.contains(where: \.reusedCachedBase) { fail("changing an owner must invalidate dependent slots") }
        if moved.reduce(0, { $0 + $1.safariRulesCount }) != baseline { fail("later copy must take ownership when first copy disappears") }

        try write(left, content + "@@||site1.example^\n")
        try write(right, content)
        let exceptions = try compileSlots([left, right])
        if exceptions.reduce(0, { $0 + $1.safariRulesCount }) <= baseline { fail("different slot-local exceptions require separate blocking copies") }

        print("PASS")
    }
}
