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

        let cosmetic = [
            "##.ad-banner",
            "example.com##.promoted",
            "example.com#@#.promoted",
            "example.com#?#div:has(> .ad)",
            "example.com#$#body { overflow: auto !important; }",
            "example.com#$?#.x:has(.y) { display: none; }",
        ]
        let kept = [
            "||ads.example.com^",
            "@@||example.com/allowed.js$script",
            "/js/pagead.js$script",
            "example.com#%#//scriptlet('set-constant', 'adBlock', 'false')",
            "example.com$$script[tag-content=\"ads\"]",
            "! comment with ## inside",
            "||example.com/path#anchor^",
            "",
        ]
        for rule in cosmetic {
            require(CosmeticFilteringPreference.isCosmeticRule(rule), "\(rule) must be cosmetic")
        }
        for rule in kept {
            require(!CosmeticFilteringPreference.isCosmeticRule(rule), "\(rule) must be kept")
        }

        func lines(_ text: String) -> [String] {
            text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        }
        let all = (cosmetic + kept).joined(separator: "\n")
        let off = CosmeticFilteringPreference.Sites(selectedSites: [])
        let stripped = lines(off.restricting(all)).filter { !$0.isEmpty }
        require(stripped == kept.filter { !$0.isEmpty }, "off must keep only non-cosmetic lines in order, got \(stripped)")
        require(CosmeticFilteringPreference.Sites.all.restricting(all) == all, "all sites must leave rules untouched")

        // #899: only on reddit.com, or everywhere but gazzetta.it.
        let only = lines(CosmeticFilteringPreference.Sites(selectedSites: ["reddit.com"]).restricting(all))
        require(only.contains("reddit.com##.ad-banner"), "generic rule must be tied to the selected site, got \(only)")
        require(!only.contains { $0.hasPrefix("example.com##") }, "rules for other sites must be dropped, got \(only)")
        require(only.contains("||ads.example.com^"), "network rules must stay unscoped, got \(only)")
        let except = lines(CosmeticFilteringPreference.Sites(excludedSites: ["gazzetta.it"]).restricting(all))
        require(except.contains("~gazzetta.it##.ad-banner"), "generic rule must exclude the site, got \(except)")
        require(except.contains("example.com##.promoted"), "rules for other sites stay, got \(except)")
        require(except.contains("example.com#%#//scriptlet('set-constant', 'adBlock', 'false')"), "scriptlets untouched")

        // Generic rules off: only hiding rules that name a site remain.
        let generic = [
            "##.ad-banner", "~gazzetta.it##.wide", "#?#div:has(> .sponsor)", "#$#.overlay { display: none; }",
        ]
        let specific = lines(CosmeticFilteringPreference.Sites(includesGeneric: false).restricting((generic + cosmetic + kept).joined(separator: "\n")))
        require(!specific.contains { generic.contains($0) }, "generic rules must be dropped, got \(specific)")
        let disguised = CosmeticFilteringPreference.Sites(includesGeneric: false)
            .restricting(##"##[data-ad="#@#"]"## + "\n" + ##"##[data-ad="#$#"]"##)
        require(lines(disguised).allSatisfy(\.isEmpty), "marker text inside a selector must not hide a generic rule, got \(disguised)")
        let excludedDisguise = lines(CosmeticFilteringPreference.Sites(excludedSites: ["a.com"]).restricting(#"b.com##[title="x##y"]"#))
        require(excludedDisguise == [#"b.com##[title="x##y"]"#], "selector text must stay intact, got \(excludedDisguise)")
        require(specific.contains("example.com##.promoted") && specific.contains("example.com#@#.promoted"),
                "site rules and exceptions must stay, got \(specific)")
        require(kept.filter { !$0.isEmpty }.allSatisfy(specific.contains), "non-cosmetic rules must stay, got \(specific)")
        require(CosmeticFilteringPreference.Sites(includesGeneric: false) != .all, "generic off must change cache identity")
        let decoded = try? JSONDecoder().decode(CosmeticFilteringPreference.Sites.self, from: Data(#"{"excludedSites":[]}"#.utf8))
        require(decoded == .all, "older saved scopes must decode with generic rules on")

        print("PASS: cosmetic filtering preference")
    }
}
