import Foundation
@testable import wBlockCoreService

/// The blocked-request count copies filter-list blocks into DNR. The copies
/// must stay a subset of what the content blockers block, and their allow
/// rules must never reach wBlock's other DNR rules.
@main
struct BlockedCountDNRRulesTests {
    typealias G = RemoveParamDNRRuleGenerator

    static func main() {
        let list = """
        ||tracker.example^
        ||third.example^$third-party
        ||scripted.example^$script
        ||sited.example^$domain=a.example
        ||path.example/pixel.gif
        ||parent.example^
        ||sub.parent.example^
        ||global-ex.example^
        @@||global-ex.example/allowed.js
        ||scoped-ex.example^
        @@||scoped-ex.example/x.js$domain=shop.example|store.example
        ||bad.example^
        ||bad.example^$badfilter
        ||cosmetic-ex.example^
        @@||cosmetic-ex.example^$elemhide
        @@||pagewide.example^$document
        @@*$script,third-party,domain=filemoon.*|good.example
        @@|http$script,domain=mylink.*
        ||popup-ex.example^
        @@||popup-ex.example^$popup
        ||transform-ex.example^
        @@||transform-ex.example^$doc,uritransform
        @@/^https:\\/\\/transform-ex\\.example\\/specific/$doc,uritransform=//https:\\/\\/kittygr.am\\/$1/
        @@/js/ads.js|$script,domain=~x.example
        """
        let rules = G.generateBlockedCountRules(
            from: G.extractBlockedCountLines(from: list),
            disabledSites: ["Disabled.example"]
        )
        let blocks = rules.filter { $0.action.type == "block" }
        let allows = rules.filter { $0.action.type == "allow" }
        let blockedHosts = Set(blocks.flatMap { $0.condition.requestDomains ?? [] })
        let blockedFilters = Set(blocks.compactMap(\.condition.urlFilter))
        func hasAllow(_ urlFilter: String?, on domains: [String]?) -> Bool {
            allows.contains { $0.condition.urlFilter == urlFilter && $0.condition.domains == domains }
        }

        expect(blockedHosts.isSuperset(of: ["tracker.example", "parent.example", "global-ex.example", "cosmetic-ex.example", "popup-ex.example", "transform-ex.example"]), "whole-host blocks copied")
        expect(!blockedHosts.contains("sub.parent.example"), "subdomain folded into its parent")
        expect(!blockedHosts.contains("sited.example") && !blockedFilters.contains { $0.contains("sited") }, "site-scoped block skipped")
        expect(!blockedHosts.contains("bad.example"), "badfilter respected")
        expect(blockedFilters.contains("||path.example/pixel.gif"), "path block copied")
        expect(blocks.contains { $0.condition.urlFilter == "||scripted.example^" && $0.condition.resourceTypes == ["script"] }, "typed block keeps its type")
        expect(blocks.contains { $0.condition.requestDomains?.contains("third.example") == true && $0.condition.domainType == "thirdParty" }, "third-party block keeps its scope")

        expect(hasAllow("||global-ex.example/allowed.js", on: nil), "global exception becomes a global allow")
        expect(hasAllow("||scoped-ex.example/x.js", on: ["shop.example", "store.example"]), "scoped exception stays scoped")
        expect(hasAllow("/js/ads.js|", on: nil), "inexpressible sites widen a narrow exception")
        expect(!allows.contains { $0.condition.urlFilter?.contains("cosmetic-ex") == true || $0.condition.urlFilter?.contains("popup-ex") == true || $0.condition.urlFilter?.contains("transform-ex") == true }, "non-blocking exceptions ignored")
        expect(!allows.contains { ["*", "|http"].contains($0.condition.urlFilter ?? "") && $0.condition.domains == nil }, "no catch-all allow")
        let pageWide = Set(allows.filter { $0.condition.urlFilter == nil && $0.condition.requestDomains == nil }.flatMap { $0.condition.domains ?? [] })
        expect(pageWide == ["disabled.example", "pagewide.example", "good.example"], "page-wide allows: \(pageWide.sorted())")

        expect(rules.allSatisfy { $0.priority == G.blockedCountPriority && $0.condition.excludedDomains == nil }, "counting rules share one priority")
        expect(rules.prefix(allows.count).allSatisfy { $0.action.type == "allow" }, "allows come first")
        expect(rules.enumerated().allSatisfy { $0.element.id == G.blockedCountRuleIDBase + $0.offset }, "ids start at the base")

        // Counting allows win ties with counting blocks; every other wBlock
        // rule must outrank them or the allows would switch it off.
        let removeParam = G.generateRules(
            from: "$removeparam=utm_source\n@@||a.example^$removeparam=utm_source\n||b.example^$removeparam=fbclid,important",
            disabledSites: ["off.example"]
        ).rules
        expect(!removeParam.isEmpty && removeParam.allSatisfy { $0.priority > G.blockedCountPriority }, "removeparam rules outrank counting rules")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-bc-dnr-test-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            try G.saveBlockedCountRules(rules, containerURL: tempDir)

            let fullPayload = G.loadBlockedCountRulesPayload(
                containerURL: tempDir,
                enabled: true,
                offset: 0,
                limit: 1_000,
                knownVersion: nil
            )
            let version = fullPayload["version"] as? String ?? ""
            expect(!version.isEmpty, "blocked-count payload produces non-empty version")
            expect((fullPayload["rules"] as? [[String: Any]])?.count == rules.count, "nil knownVersion returns blocked-count rules")
            expect(fullPayload["unchanged"] == nil, "nil knownVersion omits unchanged flag")

            let unchangedPayload = G.loadBlockedCountRulesPayload(
                containerURL: tempDir,
                enabled: true,
                offset: 0,
                limit: 1_000,
                knownVersion: "true:\(version)"
            )
            expect((unchangedPayload["unchanged"] as? Bool) == true, "matching enabled knownVersion returns unchanged=true")
            expect((unchangedPayload["rules"] as? [[String: Any]])?.isEmpty == true, "unchanged blocked-count payload omits rules")
            expect((unchangedPayload["count"] as? Int) == rules.count, "unchanged blocked-count payload reports count")

            let toggledOnPayload = G.loadBlockedCountRulesPayload(
                containerURL: tempDir,
                enabled: true,
                offset: 0,
                limit: 1_000,
                knownVersion: "false:"
            )
            expect((toggledOnPayload["rules"] as? [[String: Any]])?.count == rules.count, "enabling blocked-count ignores stale disabled knownVersion")
            expect(toggledOnPayload["unchanged"] == nil, "enabling blocked-count omits unchanged flag")

            let disabledUnchanged = G.loadBlockedCountRulesPayload(
                containerURL: tempDir,
                enabled: false,
                offset: 0,
                limit: 1_000,
                knownVersion: "false:"
            )
            expect((disabledUnchanged["unchanged"] as? Bool) == true, "disabled knownVersion 'false:' returns unchanged=true")
            expect((disabledUnchanged["count"] as? Int) == 0, "disabled payload has count=0")

            let disabledChanged = G.loadBlockedCountRulesPayload(
                containerURL: tempDir,
                enabled: false,
                offset: 0,
                limit: 1_000,
                knownVersion: "true:\(version)"
            )
            expect(disabledChanged["unchanged"] == nil, "disabling blocked-count from 'true:<ver>' does not set unchanged=true")
            expect(!G.hasCachedParsedBlockedCountRules, "single-page load clears parsed blocked-count rules from RAM")

            let coldDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("wblock-bc-dnr-cold-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: coldDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: coldDir) }
            try G.saveBlockedCountRules(rules, containerURL: coldDir)

            let coldHit = G.loadBlockedCountRulesPayload(
                containerURL: coldDir,
                enabled: true,
                offset: 0,
                limit: 1_000,
                knownVersion: "true:\(version)"
            )
            expect((coldHit["unchanged"] as? Bool) == true && (coldHit["count"] as? Int) == rules.count, "cold blocked-count knownVersion hit succeeds")
            expect(!G.hasCachedParsedBlockedCountRules, "cold blocked-count knownVersion hit skips JSON deserialization")

            expect(rules.count >= 2, "expected at least 2 blocked-count rules for multi-page test")
            let page0 = G.loadBlockedCountRulesPayload(containerURL: coldDir, enabled: true, offset: 0, limit: 1, knownVersion: nil)
            expect((page0["rules"] as? [[String: Any]])?.count == 1 && G.hasCachedParsedBlockedCountRules, "non-final blocked-count page retains cache")
            let page1 = G.loadBlockedCountRulesPayload(containerURL: coldDir, enabled: true, offset: 1, limit: rules.count, knownVersion: nil)
            expect((page1["rules"] as? [[String: Any]])?.count == rules.count - 1 && !G.hasCachedParsedBlockedCountRules, "final blocked-count page clears cache")
        } catch {
            failures += 1
            print("FAIL: blocked-count payload knownVersion test threw \(error)")
        }

        guard failures == 0 else {
            print("\(failures) blocked-count DNR check(s) failed")
            exit(1)
        }
        print("blocked-count DNR rule tests passed")
    }

    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}
