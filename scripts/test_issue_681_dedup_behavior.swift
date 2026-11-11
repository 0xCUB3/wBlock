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
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-issue681-\(UUID().uuidString)", isDirectory: true)
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
                targetInfo: target,
                allTargets: targets,
                disabledSites: [],
                extraRulesText: nil,
                groupIdentifier: groupIdentifier,
                containerURL: container
            ).safariRulesCount
        }

        let single = try compile([original])
        let both = try compile([original, fork])
        print("count single=\(single) both=\(both)")
        if single == 0 { fail("single list must compile to rules") }
        if both != single { fail("an identical second list must not change the Safari rule count") }

        var left = FilterList(name: "Left", url: URL(string: "https://example.com/left")!, category: .ads, isSelected: true)
        var right = FilterList(name: "Right", url: URL(string: "https://example.com/right")!, category: .privacy, isSelected: true)
        left.sourceRuleCount = 200
        right.sourceRuleCount = 200
        func write(_ filter: FilterList, _ text: String) throws {
            try text.write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter)), atomically: true, encoding: .utf8)
        }
        try write(left, content)
        try write(right, content.uppercased())
        func compileSlots(_ selection: [FilterList], in folder: URL = container) throws -> [ContentBlockerService.ContentBlockerTargetOutcome] {
            let ordered = ContentBlockerMappingService.orderedForCompilation(selection)
            let mapping = ContentBlockerMappingService.distribute(selectedFilters: selection, across: targets)
            return try targets.map { slot in
                try ContentBlockerService.compileTargetRules(
                    filters: mapping[slot] ?? [], orderedSelectedFilters: ordered,
                    targetInfo: slot, allTargets: targets,
                    disabledSites: [], extraRulesText: nil, groupIdentifier: groupIdentifier,
                    containerURL: folder
                )
            }
        }
        // Every blocker must hold what a build without any cache makes of the
        // same lists: a blocker whose output depends on a changed list, by its
        // own lists, the blocks it holds for others or their exceptions, is
        // never left stale.
        func expectCurrent(_ selection: [FilterList], _ message: String) throws {
            let fresh = container.appendingPathComponent("fresh-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
            for filter in selection {
                let name = ContentBlockerIncrementalCache.localFilename(for: filter)
                try FileManager.default.copyItem(at: container.appendingPathComponent(name), to: fresh.appendingPathComponent(name))
            }
            _ = try compileSlots(selection, in: fresh)
            for slot in targets {
                let output = { (folder: URL) in try Data(contentsOf: folder.appendingPathComponent(slot.rulesFilename)) }
                if try output(container) != output(fresh) { fail("\(message): \(slot.displayName) is stale") }
            }
        }
        let baseline = try compileSlots([left]).reduce(0) { $0 + $1.safariRulesCount }
        let split = try compileSlots([left, right])
        if split.reduce(0, { $0 + $1.safariRulesCount }) != baseline { fail("case variants in different slots must compile once") }
        if !(try compileSlots([left, right])).allSatisfy(\.reusedCachedBase) { fail("cross-slot cache must be reusable") }
        let ordered = ContentBlockerIncrementalCache.canonicalFilterOrder([left, right])
        try write(ordered[0], "! emptied owner\n")
        let moved = try compileSlots([left, right])
        try expectCurrent([left, right], "changing an owner must invalidate dependent slots")
        if moved.reduce(0, { $0 + $1.safariRulesCount }) != baseline { fail("later copy must take ownership when first copy disappears") }
        // A list's blocks may sit in a blocker another list is assigned to.
        try write(ordered[1], content.uppercased() + "||added.example^\n")
        _ = try compileSlots([left, right])
        try expectCurrent([left, right], "a new block must reach the blocker that holds it")

        try write(left, content + "@@||site1.example^\n")
        try write(right, content)
        let exceptions = try compileSlots([left, right])
        try expectCurrent([left, right], "an exception must reach the blocker that holds its block")
        if exceptions.reduce(0, { $0 + $1.safariRulesCount }) <= baseline { fail("different slot-local exceptions require separate blocking copies") }

        print("PASS")
    }
}
