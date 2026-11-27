import Foundation
import wBlockCoreService

@main
struct CosmeticFilteringPreferenceTests {
    static func main() {
        func require(_ condition: Bool, _ message: String) {
            guard condition else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
        }

        require(CosmeticFilteringPreference.Sites(includesGeneric: false) != .all, "generic off must change cache identity")
        let decoded = try? JSONDecoder().decode(CosmeticFilteringPreference.Sites.self, from: Data(#"{"excludedSites":[]}"#.utf8))
        require(decoded == .all, "older saved scopes must decode with generic rules on")

        // The master switch and site mode are independent; both lists survive.
        let group = "test.cosmetic.\(UUID().uuidString)"
        CosmeticFilteringPreference.setSites(.init(selectedSites: ["a.com"], excludedSites: ["b.com"]), groupIdentifier: group)
        CosmeticFilteringPreference.setEnabled(true, groupIdentifier: group)
        require(CosmeticFilteringPreference.effectiveSites(groupIdentifier: group) == .init(selectedSites: ["a.com"]),
                "on must honor selected-sites mode")
        var saved = CosmeticFilteringPreference.sites(groupIdentifier: group)
        saved.onlySelectedSites = false
        CosmeticFilteringPreference.setSites(saved, groupIdentifier: group)
        require(CosmeticFilteringPreference.effectiveSites(groupIdentifier: group) == .init(excludedSites: ["b.com"]),
                "all-sites mode must ignore the saved selection")
        require(CosmeticFilteringPreference.sites(groupIdentifier: group).selectedSites == ["a.com"],
                "switching modes must retain selected sites")
        saved = CosmeticFilteringPreference.sites(groupIdentifier: group)
        require(!saved.onlySelectedSites, "all-sites mode must survive reloading")
        saved.onlySelectedSites = true
        CosmeticFilteringPreference.setSites(saved, groupIdentifier: group)
        require(CosmeticFilteringPreference.effectiveSites(groupIdentifier: group) == .init(selectedSites: ["a.com"]),
                "returning to selected mode must restore the saved selection")
        require(CosmeticFilteringPreference.sites(groupIdentifier: group).excludedSites == ["b.com"],
                "switching modes must retain excluded sites")
        CosmeticFilteringPreference.setEnabled(false, groupIdentifier: group)
        require(CosmeticFilteringPreference.effectiveSites(groupIdentifier: group) == .init(selectedSites: []),
                "off must disable cosmetic filtering even with selected sites")
        CosmeticFilteringPreference.setEnabled(true, groupIdentifier: group)
        require(CosmeticFilteringPreference.effectiveSites(groupIdentifier: group) == .init(selectedSites: ["a.com"]),
                "re-enabling must restore the selected scope")
        var empty = CosmeticFilteringPreference.Sites(selectedSites: [], excludedSites: ["b.com"], includesGeneric: false)
        empty.onlySelectedSites = true
        CosmeticFilteringPreference.setSites(empty, groupIdentifier: group)
        require(CosmeticFilteringPreference.effectiveSites(groupIdentifier: group) == .init(selectedSites: [], includesGeneric: false),
                "empty selected mode must apply nowhere and preserve generic preference")
        empty.onlySelectedSites = false
        CosmeticFilteringPreference.setSites(empty, groupIdentifier: group)
        require(CosmeticFilteringPreference.effectiveSites(groupIdentifier: group) == .init(excludedSites: ["b.com"], includesGeneric: false),
                "changing mode must preserve generic preference")
        CosmeticFilteringPreference.setEnabled(false, groupIdentifier: group)
        CosmeticFilteringPreference.setSites(.all, groupIdentifier: group)
        require(CosmeticFilteringPreference.effectiveSites(groupIdentifier: group) == .init(selectedSites: []),
                "off with no selected sites must apply nowhere")

        // Per-site matching (exact, subdomain, TLD wildcard) and toggle helpers.
        require(CosmeticFilteringPreference.matchesHost("sub.example.com", entries: ["example.com"]),
                "parent domain must match subdomain")
        require(CosmeticFilteringPreference.matchesHost("www.amazon.co.uk", entries: ["amazon.*"]),
                "name.* wildcard must match country TLDs")
        require(!CosmeticFilteringPreference.matchesHost("notamazon.com", entries: ["amazon.*"]),
                "name.* wildcard must not match unrelated prefix")

        var allMode = CosmeticFilteringPreference.Sites(selectedSites: ["keep.com"], excludedSites: ["example.com"], includesGeneric: false)
        allMode.onlySelectedSites = false
        let reEnabled = CosmeticFilteringPreference.updating(sites: allMode, enabled: true, onHost: "sub.example.com")
        require(reEnabled.excludedSites.isEmpty, "enabling subdomain must clear parent exclusion")
        require(reEnabled.selectedSites == ["keep.com"] && !reEnabled.includesGeneric && !reEnabled.onlySelectedSites,
                "toggling in all-sites mode must preserve selected list, generic setting, and mode")
        let disabledAgain = CosmeticFilteringPreference.updating(sites: reEnabled, enabled: false, onHost: "sub.example.com")
        require(disabledAgain.excludedSites == ["sub.example.com"], "disabling must record normalized host")

        let fastExcluded = CosmeticFilteringPreference.fastPathDisabledSites(
            isEnabled: true, sites: disabledAgain, compiledSites: .all
        )
        require(fastExcluded == ["sub.example.com"], "fast-path must emit newly excluded site")
        require(CosmeticFilteringPreference.fastPathDisabledSites(
            isEnabled: true, sites: disabledAgain, compiledSites: disabledAgain
        ).isEmpty, "fast-path must not duplicate already-compiled exclusions")
        require(!CosmeticFilteringPreference.requiresFullApply(enablingHost: "sub.example.com", compiledSites: .all),
                "re-enabling a site compiled as allowed must not require full apply")
        require(CosmeticFilteringPreference.requiresFullApply(enablingHost: "sub.example.com", compiledSites: disabledAgain),
                "enabling a site stripped at compile time must require full apply")

        // ContentBlockerService must inject cosmetic-only ignore rules right after leading css-display-none
        // rules and before any network rule, skipping blockers without cosmetic hides.
        let mixedBase = Data("""
        [{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".ad"}},{"trigger":{"url-filter":"ads\\\\.js"},"action":{"type":"block"}}]
        """.utf8)
        let mixedFinal = ContentBlockerService.finalizeContentBlockerJSON(
            baseJSON: mixedBase,
            disabledSites: ["full-off.com"],
            cosmeticDisabledSites: ["cosmetic-off.com", "full-off.com"]
        )
        require(mixedFinal.ruleCount == 4 && mixedFinal.truncatedRuleCount == 0,
                "expected 2 base + 1 cosmetic ignore + 1 full-site ignore (deduplicated)")
        let parsedMixed = (try? JSONSerialization.jsonObject(with: mixedFinal.json) as? [[String: Any]]) ?? []
        require(parsedMixed.count == 4, "finalized JSON must remain a valid 4-rule array")
        let actionTypes = parsedMixed.compactMap { ($0["action"] as? [String: Any])?["type"] as? String }
        require(actionTypes == ["css-display-none", "ignore-previous-rules", "block", "ignore-previous-rules"],
                "cosmetic ignore must sit after css-display-none and before network block; got \(actionTypes)")
        let cosmeticTrigger = parsedMixed[1]["trigger"] as? [String: Any]
        require((cosmeticTrigger?["resource-type"] as? [String]) == ["document"]
                && (cosmeticTrigger?["if-domain"] as? [String]) == ["*cosmetic-off.com"],
                "cosmetic ignore must scope to document loads on cosmetic-off.com")

        let networkOnlyBase = Data("""
        [{"trigger":{"url-filter":"ads\\\\.js"},"action":{"type":"block"}}]
        """.utf8)
        let networkOnlyFinal = ContentBlockerService.finalizeContentBlockerJSON(
            baseJSON: networkOnlyBase,
            disabledSites: [],
            cosmeticDisabledSites: ["cosmetic-off.com"]
        )
        require(networkOnlyFinal.ruleCount == 1 && networkOnlyFinal.json == networkOnlyBase,
                "blockers without leading css-display-none rules must stay untouched")

        UserDefaults().removePersistentDomain(forName: group)

        print("PASS: cosmetic filtering preference")
    }
}
