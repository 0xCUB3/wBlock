// Element Zapper rules belong to one blocker, so they must not split the
// selection's plan: every blocker plans alike, the zapper blocker alone
// compiles them, its saved output stays known to the plan's packing, and
// earlier blockers saving mid-apply must keep the shared plan intact.
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
        func planInputs(_ target: ContentBlockerTargetInfo, zapper: String? = zapperRules) throws -> ContentBlockerService.EnginePlanInputs {
            try ContentBlockerService.enginePlanInputs(
                filters: assigned(target), orderedSelectedFilters: selection, targetInfo: target, allTargets: targets,
                disabledSites: [], extraRulesText: ownRules(target, zapper: zapper), cosmeticSites: cosmeticSites, containerURL: container)
        }
        let inputs = try CompilationScope.$current.withValue(CompilationScope()) {
            try targets.map { try planInputs($0) }
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
        // others compile the plan's own extras and save one. Interleaving
        // enginePlanInputs with sequential compiles that write to disk must
        // keep a single memoized plan across the whole CompilationScope.
        func compile(_ target: ContentBlockerTargetInfo, zapper: String? = zapperRules) throws -> (output: String, outcome: ContentBlockerService.ContentBlockerTargetOutcome) {
            let outcome = try ContentBlockerService.compileTargetRules(
                filters: assigned(target), orderedSelectedFilters: selection, targetInfo: target, allTargets: targets,
                disabledSites: [], extraRulesText: ownRules(target, zapper: zapper),
                groupIdentifier: group, containerURL: container)
            // Hides can compile to Safari rules or to the runtime rules.
            let safariRules = try String(contentsOf: container.appendingPathComponent(target.rulesFilename), encoding: .utf8)
            return (safariRules + (outcome.advancedRulesText ?? ""), outcome)
        }
        let compileScope = CompilationScope()
        var interleavedPlanIDs: [ObjectIdentifier] = []
        var interleavedRequests: [String] = []
        var outputs: [String] = []
        try CompilationScope.$current.withValue(compileScope) {
            for target in targets {
                let planInput = try planInputs(target)
                interleavedPlanIDs.append(ObjectIdentifier(planInput.plan))
                interleavedRequests.append(planInput.requestJSON)
                outputs.append(try compile(target).output)
            }
        }
        if compileScope.entryCount != 1 {
            fail("interleaved sequential compiles must reuse one CompilationScope entry, got \(compileScope.entryCount)")
        }
        if Set(interleavedPlanIDs).count != 1 || Set(interleavedRequests).count != 1 {
            fail("mid-apply disk writes must not change the shared plan key")
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

        // Incremental rebuild after modifying one list on disk: all targets still
        // share a single WBEngine.Plan even as the dirty target writes new output.
        let adsFilter = selection.first(where: { $0.name == "ads" })!
        try "||ads.example^\n||ads-updated.example^\nexample.com##.ad\n".write(
            to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: adsFilter)),
            atomically: true, encoding: .utf8)
        let incrementalScan = try CompilationScope.$current.withValue(CompilationScope()) {
            try ContentBlockerService.targetRebuildScan(
                orderedSelectedFilters: selection, allTargets: targets, disabledSites: [],
                extraRulesText: { ownRules($0) }, groupIdentifier: group, containerURL: container)
        }
        let expectedDirty = Set(incrementalScan.dirtyIndices)
        if expectedDirty.isEmpty || expectedDirty.count >= targets.count {
            fail("expected a partial incremental rebuild, got dirtyIndices=\(incrementalScan.dirtyIndices)")
        }
        let incrementalScope = CompilationScope()
        var incrementalPlanIDs: [ObjectIdentifier] = []
        var incrementalOutcomes: [ContentBlockerService.ContentBlockerTargetOutcome] = []
        try CompilationScope.$current.withValue(incrementalScope) {
            for target in targets {
                incrementalPlanIDs.append(ObjectIdentifier(try planInputs(target).plan))
                incrementalOutcomes.append(try compile(target).outcome)
            }
        }
        if incrementalScope.entryCount != 1 || Set(incrementalPlanIDs).count != 1 {
            fail("incremental rebuild across targets must share one WBEngine.Plan")
        }
        for (index, (target, outcome)) in zip(targets, incrementalOutcomes).enumerated() {
            let expectedReused = !expectedDirty.contains(index)
            if outcome.reusedCachedBase != expectedReused {
                fail("\(target.displayName) expected reusedCachedBase=\(expectedReused) after modifying ads list")
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

        // Editing only zapper rules reuses non-zapper slots and recompiles only slot 5.
        let zapperEditOutcomes = try CompilationScope.$current.withValue(CompilationScope()) {
            try targets.map { try compile($0, zapper: updatedZapper).outcome }
        }
        for (target, outcome) in zip(targets, zapperEditOutcomes) {
            if outcome.reusedCachedBase != (target.slot != 5) {
                fail("\(target.displayName) expected reusedCachedBase=\(target.slot != 5) after zapper edit")
            }
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
            disabledSites: [], extraRulesText: updatedZapper, groupIdentifier: group, containerURL: container)
        if !reusedOutcome.reusedCachedBase { fail("unchanged zapper blocker must reuse cached base via plan fingerprint") }
        guard let backfilled = ContentBlockerService.savedTargetBase(rulesFilename: zapperTarget.rulesFilename, containerURL: container),
              backfilled.packFingerprint != backfilled.fingerprint else {
            fail("fingerprint reuse must backfill the pack fingerprint for zapper blockers")
        }

        // Clearing the zapper rules drops the separate pack fingerprint.
        if try compile(zapperTarget, zapper: nil).output.contains(".zapped-banner") { fail("cleared zapper rules still compiled") }
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
