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

        expect(blockedHosts.isSuperset(of: ["tracker.example", "parent.example", "global-ex.example", "cosmetic-ex.example", "popup-ex.example"]), "whole-host blocks copied")
        expect(!blockedHosts.contains("sub.parent.example"), "subdomain folded into its parent")
        expect(!blockedHosts.contains("sited.example") && !blockedFilters.contains { $0.contains("sited") }, "site-scoped block skipped")
        expect(!blockedHosts.contains("bad.example"), "badfilter respected")
        expect(blockedFilters.contains("||path.example/pixel.gif"), "path block copied")
        expect(blocks.contains { $0.condition.urlFilter == "||scripted.example^" && $0.condition.resourceTypes == ["script"] }, "typed block keeps its type")
        expect(blocks.contains { $0.condition.requestDomains?.contains("third.example") == true && $0.condition.domainType == "thirdParty" }, "third-party block keeps its scope")

        expect(hasAllow("||global-ex.example/allowed.js", on: nil), "global exception becomes a global allow")
        expect(hasAllow("||scoped-ex.example/x.js", on: ["shop.example", "store.example"]), "scoped exception stays scoped")
        expect(hasAllow("/js/ads.js|", on: nil), "inexpressible sites widen a narrow exception")
        expect(!allows.contains { $0.condition.urlFilter?.contains("cosmetic-ex") == true || $0.condition.urlFilter?.contains("popup-ex") == true }, "non-blocking exceptions ignored")
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
