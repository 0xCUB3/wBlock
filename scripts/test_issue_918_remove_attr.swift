// #918: a uBO :remove-attr()/:remove-class() rule must not break other
// hiding rules for the same site.
import Foundation
import wBlockCoreService

@main
struct Main {
    static func require(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL: \(message)"); exit(1) }
    }

    static func main() {
        let cases: [(String, String)] = [
            ("www.reddit.com##reddit-search-small[expanded-composer-enabled]:remove-attr(expanded-composer-enabled)",
             "www.reddit.com#%#//scriptlet('remove-attr', 'expanded-composer-enabled', 'reddit-search-small[expanded-composer-enabled]')"),
            ("example.com#@#div[data-x='y']:remove-class(a|b)",
             "example.com#@%#//scriptlet('remove-class', 'a|b', 'div[data-x=\\'y\\']')"),
            ("example.com##a:remove-attr(/^data-/)", "example.com##a:remove-attr(/^data-/)"),
            ("example.com###answers-nav-button", "example.com###answers-nav-button"),
        ]
        for (input, expected) in cases {
            let output = FilterRuleAnalysis.adGuardEquivalent(input)
            require(output == expected, "\(input) -> \(output)")
        }

        let analysis = FilterRuleAnalysis.analyze(content: cases[0].0 + "\nwww.reddit.com###answers-nav-button")
        require(analysis.count(of: .advanced) == 1 && analysis.count(of: .supported) == 1,
                "remove-attr must count as advanced and leave the hide rule supported")
        print("PASS: uBO remove-attr/remove-class rewritten to scriptlets")
    }
}
