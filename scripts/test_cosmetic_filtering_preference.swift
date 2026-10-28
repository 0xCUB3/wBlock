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
        UserDefaults().removePersistentDomain(forName: group)

        print("PASS: cosmetic filtering preference")
    }
}
