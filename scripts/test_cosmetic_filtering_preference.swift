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

        let stripped = CosmeticFilteringPreference.strippingCosmeticRules(
            from: (cosmetic + kept).joined(separator: "\n")
        )
        let lines = stripped.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        require(lines == kept, "stripping must keep non-cosmetic lines in order, got \(lines)")

        print("PASS: cosmetic filtering preference")
    }
}
