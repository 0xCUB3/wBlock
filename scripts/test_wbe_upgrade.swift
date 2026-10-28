import Foundation
@testable import wBlockCoreService

// wBlock 4 upgrade: a blocker cache AdGuard's converter left behind is never
// reused, every compiled output is one WebKit accepts, and a rule WebKit
// rejects costs only that rule.
@main
struct WbeUpgradeTests {
    static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() async throws {
        let groupIdentifier = "group.wblock.test.wbe-upgrade.\(UUID().uuidString.prefix(8))"
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-wbe-upgrade-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let target = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)[0]
        let list = FilterList(name: "upgrade", url: URL(string: "https://example.com/list.txt")!, category: .ads, isSelected: true)
        // Syntax that has tripped converters: regexes, entities, :has(),
        // procedural and scriptlet rules, denyallow, badfilter, hosts lines.
        try """
        ||ads.example^
        0.0.0.0 tracker.example
        /banner\\d{2,3}x/$image
        /x{0}/$script,domain=example.org
        google.*##.sponsored
        example.com##div:has(> .ad)
        example.com##.promo:has-text(Sponsored)
        example.com##+js(set-constant, ads, false)
        *$script,3p,denyallow=cdn.example|static.example,domain=site.example
        ||bad.example^$badfilter
        ||bad.example^
        @@||ads.example/ok^$document
        """.write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: list)), atomically: true, encoding: .utf8)

        // What 3.x left: a base cache and advanced rules with no compiler sidecar.
        let base = ContentBlockerIncrementalCache.baseRulesFilename(for: target.rulesFilename)
        let legacyJSON = #"[{"trigger":{"url-filter":"legacy"},"action":{"type":"block"}}]"#
        try legacyJSON.write(to: container.appendingPathComponent(base), atomically: true, encoding: .utf8)
        try "1".write(to: container.appendingPathComponent("\(base).count"), atomically: true, encoding: .utf8)
        try "example.com#%#//scriptlet('legacy')".write(
            to: container.appendingPathComponent(ContentBlockerIncrementalCache.baseAdvancedRulesFilename(for: target.rulesFilename)),
            atomically: true, encoding: .utf8
        )
        check(!ContentBlockerIncrementalCache.hasCoherentBaseRulesCache(
            targetRulesFilename: target.rulesFilename, groupIdentifier: groupIdentifier, containerURL: container
        ), "a cache without this engine's sidecar is not reused")

        let ordered = ContentBlockerMappingService.orderedForCompilation([list])
        let result = try ContentBlockerService.compileTargetRules(
            filters: [list], orderedSelectedFilters: ordered,
            affinitySnapshot: SafariContentBlockerAffinityProcessor.snapshot(for: ordered, containerURL: container),
            targetInfo: target, allTargets: [target], disabledSites: ["example.*"], extraRulesText: nil,
            groupIdentifier: groupIdentifier, containerURL: container
        )
        check(!result.reusedCachedBase, "the legacy base was recompiled")
        let output = try Data(contentsOf: container.appendingPathComponent(target.rulesFilename))
        check(!String(decoding: output, as: UTF8.self).contains("legacy"), "no legacy rule survives")
        check(ContentBlockerIncrementalCache.hasCoherentBaseRulesCache(
            targetRulesFilename: target.rulesFilename, groupIdentifier: groupIdentifier, containerURL: container
        ), "the new base is marked with this engine")
        check(!(result.advancedRulesText ?? "").contains("legacy"), "legacy advanced rules are not carried over")
        // Trust markers between lists never become rules themselves.
        let outputText = String(decoding: output, as: UTF8.self)
        check(!outputText.contains("wbe-trust") && !outputText.contains(#""url-filter":"on""#) && !outputText.contains(#""url-filter":"off""#),
              "trust markers stay out of the output")
        check((result.advancedRulesText ?? "").contains("+js(set-constant"), "scriptlets reach the runtime: \(result.advancedRulesText ?? "nil")")
        let accepted = await ContentBlockerRuleRepair.repaired(output)
        check(accepted == nil, "WebKit compiles the output as is")

        // A blocker with no native rules still gets a list Safari can load.
        let scriptsOnly = FilterList(name: "scripts only", url: URL(string: "https://example.com/s.txt")!, category: .ads, isSelected: true)
        try "example.com##+js(set-constant, a, 1)\n! nothing native\n".write(
            to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: scriptsOnly)), atomically: true, encoding: .utf8
        )
        let second = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)[1]
        let scriptsOrdered = ContentBlockerMappingService.orderedForCompilation([scriptsOnly])
        _ = try ContentBlockerService.compileTargetRules(
            filters: [scriptsOnly], orderedSelectedFilters: scriptsOrdered,
            affinitySnapshot: SafariContentBlockerAffinityProcessor.snapshot(for: scriptsOrdered, containerURL: container),
            targetInfo: second, allTargets: [second], disabledSites: [], extraRulesText: nil,
            groupIdentifier: groupIdentifier, containerURL: container
        )
        let emptyOutput = try Data(contentsOf: container.appendingPathComponent(second.rulesFilename))
        let emptyAccepted = await ContentBlockerRuleRepair.repaired(emptyOutput)
        check(emptyAccepted == nil && String(decoding: emptyOutput, as: UTF8.self) != "[]", "an empty blocker loads: \(String(decoding: emptyOutput, as: UTF8.self))")

        // One rule WebKit rejects (an empty url-filter) among good ones.
        let rules = #"[{"trigger":{"url-filter":"a"},"action":{"type":"block"}},{"trigger":{"url-filter":""},"action":{"type":"block"}},{"trigger":{"url-filter":"b"},"action":{"type":"block"}}]"#
        let repair = await ContentBlockerRuleRepair.repaired(Data(rules.utf8))
        check(repair?.dropped.count == 1, "exactly the rejected rule is dropped: \(repair?.dropped ?? [])")
        let kept = (try? JSONSerialization.jsonObject(with: repair?.data ?? Data())) as? [[String: Any]]
        check(kept?.count == 2, "the other rules stay")
        print("PASS: wbe upgrade outputs")
    }
}
