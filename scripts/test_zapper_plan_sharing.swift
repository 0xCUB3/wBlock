// Element Zapper rules belong to one blocker, so they must not split the
// selection's plan: every blocker plans alike, the zapper blocker alone
// compiles them, and its saved output stays known to the plan's packing.
import Foundation
@testable import wBlockCoreService

@main
struct ZapperPlanSharingTests {
    static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(1)
    }

    static func main() throws {
        let group = "group.wblock.test.zapper-plan.\(UUID().uuidString.prefix(8))"
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-zapper-plan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .iOS)
        guard targets.contains(where: { $0.slot == 5 }) else { fail("expected a fifth blocker for zapper rules") }
        let zapperRules = ZapperContentBlockerRuleGenerator.generatedRules(forHost: "zapped.example", selectors: [".zapped-banner"])
            .joined(separator: "\n")
        func ownRules(_ target: ContentBlockerTargetInfo, zapper: String? = zapperRules) -> String? {
            target.slot == 5 ? zapper : nil
        }

        func list(_ name: String, _ text: String) throws -> FilterList {
            var filter = FilterList(name: name, url: URL(string: "https://example.com/\(name).txt")!, category: .ads, isSelected: true)
            filter.sourceRuleCount = FilterList.countRules(in: text)
            try text.write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter)),
                           atomically: true, encoding: .utf8)
            return filter
        }
        let selection = ContentBlockerMappingService.orderedForCompilation([
            try list("ads", "||ads.example^\nexample.com##.ad\n"),
            try list("privacy", "||tracker.example^\n@@||tracker.example/ok.js\n"),
        ])
        let distribution = ContentBlockerMappingService.plan(selectedFilters: selection, across: targets)
        func assigned(_ target: ContentBlockerTargetInfo) -> [FilterList] {
            ContentBlockerIncrementalCache.canonicalFilterOrder(distribution.filtersByTarget[target] ?? [])
        }

        // One plan for every blocker: inside a CompilationScope, every target
        // shares the exact same WBEngine.Plan instance, regardless of zapper rules.
        let cosmeticSites = CosmeticFilteringPreference.effectiveSites(groupIdentifier: group)
        let inputs = try CompilationScope.$current.withValue(CompilationScope()) {
            try targets.map { target in
                try ContentBlockerService.enginePlanInputs(
                    filters: assigned(target), orderedSelectedFilters: selection, targetInfo: target, allTargets: targets,
                    disabledSites: [], extraRulesText: ownRules(target), cosmeticSites: cosmeticSites, containerURL: container)
            }
        }
        if Set(inputs.map(\.requestJSON)).count != 1 { fail("zapper rules must not change the plan request") }
        if Set(inputs.map { ObjectIdentifier($0.plan) }).count != 1 {
            fail("zapper rules must share one memoized WBEngine.Plan across all targets")
        }
        if inputs.map(\.fingerprints).contains(where: { $0 != inputs[0].fingerprints }) { fail("blockers must read the same lists") }
        for (target, input) in zip(targets, inputs) {
            let compilesZapper = input.extrasJSON.contains(".zapped-banner")
            if compilesZapper != (target.slot == 5) { fail("\(target.displayName) must compile zapper rules only in the zapper blocker") }
            if (input.planExtrasJSON != nil) != compilesZapper { fail("\(target.displayName) reports the plan's extras wrongly") }
            if input.requestJSON.contains(".zapped-banner") { fail("the plan must pack without zapper rules") }
        }

        // The zapper blocker saves its output with both fingerprints; the
        // others compile the plan's own extras and save one.
        func compile(_ target: ContentBlockerTargetInfo, zapper: String? = zapperRules) throws -> String {
            let outcome = try ContentBlockerService.compileTargetRules(
                filters: assigned(target), orderedSelectedFilters: selection, targetInfo: target, allTargets: targets,
                disabledSites: [], extraRulesText: ownRules(target, zapper: zapper),
                groupIdentifier: group, containerURL: container)
            // Hides can compile to Safari rules or to the runtime rules.
            let safariRules = try String(contentsOf: container.appendingPathComponent(target.rulesFilename), encoding: .utf8)
            return safariRules + (outcome.advancedRulesText ?? "")
        }
        let outputs = try CompilationScope.$current.withValue(CompilationScope()) {
            try targets.map { try compile($0) }
        }
        for (target, output) in zip(targets, outputs) {
            if output.contains(".zapped-banner") != (target.slot == 5) {
                fail("\(target.displayName) output must hold zapper rules only in the zapper blocker")
            }
            guard let saved = ContentBlockerService.savedTargetBase(rulesFilename: target.rulesFilename, containerURL: container) else {
                fail("\(target.displayName) saved no fingerprint")
            }
            if (saved.packFingerprint != saved.fingerprint) != (target.slot == 5) {
                fail("\(target.displayName) pack fingerprint must differ only where the blocker compiles its own rules")
            }
        }

        // A rebuild scan with unchanged zapper rules marks nothing dirty;
        // editing zapper rules marks only the zapper blocker dirty.
        let zapperIndex = targets.firstIndex(where: { $0.slot == 5 })!
        let cleanScan = try CompilationScope.$current.withValue(CompilationScope()) {
            try ContentBlockerService.targetRebuildScan(
                orderedSelectedFilters: selection, allTargets: targets, disabledSites: [],
                extraRulesText: { ownRules($0) }, groupIdentifier: group, containerURL: container)
        }
        if !cleanScan.dirtyIndices.isEmpty || !cleanScan.fitsLimits {
            fail("clean scan with zapper rules must mark nothing dirty, got \(cleanScan.dirtyIndices)")
        }

        let updatedZapper = ZapperContentBlockerRuleGenerator.generatedRules(
            forHost: "zapped.example", selectors: [".zapped-banner", ".zapped-modal"]
        ).joined(separator: "\n")
        let editedScan = try CompilationScope.$current.withValue(CompilationScope()) {
            try ContentBlockerService.targetRebuildScan(
                orderedSelectedFilters: selection, allTargets: targets, disabledSites: [],
                extraRulesText: { ownRules($0, zapper: updatedZapper) }, groupIdentifier: group, containerURL: container)
        }
        if editedScan.dirtyIndices != [zapperIndex] {
            fail("editing zapper rules must dirty only slot 5, got \(editedScan.dirtyIndices)")
        }

        // Fingerprint reuse backfills a missing pack fingerprint (e.g. after upgrade).
        let zapperTarget = targets[zapperIndex]
        let packFPURL = container.appendingPathComponent(
            ContentBlockerService.packFingerprintFilename(for: zapperTarget.rulesFilename))
        try FileManager.default.removeItem(at: packFPURL)
        ContentBlockerIncrementalCache.saveInputSignature(
            "force-fingerprint-reuse", targetRulesFilename: zapperTarget.rulesFilename,
            groupIdentifier: group, containerURL: container)
        let reusedOutcome = try ContentBlockerService.compileTargetRules(
            filters: assigned(zapperTarget), orderedSelectedFilters: selection, targetInfo: zapperTarget, allTargets: targets,
            disabledSites: [], extraRulesText: zapperRules, groupIdentifier: group, containerURL: container)
        if !reusedOutcome.reusedCachedBase { fail("unchanged zapper blocker must reuse cached base via plan fingerprint") }
        guard let backfilled = ContentBlockerService.savedTargetBase(rulesFilename: zapperTarget.rulesFilename, containerURL: container),
              backfilled.packFingerprint != backfilled.fingerprint else {
            fail("fingerprint reuse must backfill the pack fingerprint for zapper blockers")
        }

        // Clearing the zapper rules drops the separate pack fingerprint.
        if try compile(zapperTarget, zapper: nil).contains(".zapped-banner") { fail("cleared zapper rules still compiled") }
        guard let cleared = ContentBlockerService.savedTargetBase(rulesFilename: zapperTarget.rulesFilename, containerURL: container),
              cleared.packFingerprint == cleared.fingerprint else {
            fail("a blocker without its own rules must pack by its plan fingerprint")
        }
        if FileManager.default.fileExists(atPath: container.appendingPathComponent(
            ContentBlockerService.packFingerprintFilename(for: zapperTarget.rulesFilename)).path) {
            fail("stale pack fingerprint left behind")
        }

        print("PASS zapper rules share the selection's plan")
    }
}
