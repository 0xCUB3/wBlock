// Unsupported uBO syntax must not invalidate Safari's merged hiding selectors.
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
             "www.reddit.com#?#reddit-search-small[expanded-composer-enabled]:remove-attr(expanded-composer-enabled)"),
            ("example.com#@#div[data-x='y']:remove-class(a|b)",
             "example.com#@?#div[data-x='y']:remove-class(a|b)"),
            ("example.com##a:remove-attr(/^data-/)", "example.com#?#a:remove-attr(/^data-/)"),
            ("example.com###answers-nav-button", "example.com###answers-nav-button"),
            // Unknown pseudo-classes would poison the merged selector; they run as extended CSS.
            ("example.com##div:made-up(x)", "example.com#?#div:made-up(x)"),
            ("example.com#@#div:upward(2)", "example.com#@?#div:upward(2)"),
            // #949: unknown syntax anywhere in the selector poisons the merged selector too.
            ("example.com##:matches-path(/news) .a", "example.com#?#:matches-path(/news) .a"),
            ("example.com##.c:min-text-length(5) > span", "example.com#?#.c:min-text-length(5) > span"),
            ("example.com##.d >>> .e", "example.com#?#.d >>> .e"),
            ("example.com##div:has(> a):not(.b)", "example.com##div:has(> a):not(.b)"),
            ("example.com##a[title=':odd(x)']", "example.com##a[title=':odd(x)']"),
            ("example.com##li:nth-child(2n+1)", "example.com##li:nth-child(2n+1)"),
            // A style block makes a CSS injection rule, not a hiding selector.
            ("www.reddit.com##[slot=\"comment\"] p > a[href^=\"/a/\"] {pointer-events: none !important}",
             "www.reddit.com#$#[slot=\"comment\"] p > a[href^=\"/a/\"] {pointer-events: none !important}"),
            ("example.com#@#.a { color: red }", "example.com#@$#.a { color: red }"),
            ("example.com##.a:upward(2) { color: red }", "example.com#$?#.a:upward(2) { color: red }"),
            ("example.com##a[title='{x}']", "example.com##a[title='{x}']"),
            // #1029: a rule that already has its own marker passes through, even when
            // its selector starts with # or holds " #".
            ("example.com#$##mainheader, .search { top: 0 }", "example.com#$##mainheader, .search { top: 0 }"),
            ("#$##a { top: 0 }", "#$##a { top: 0 }"),
            ("example.com#@$##a { top: 0 }", "example.com#@$##a { top: 0 }"),
            ("example.com#?##a:upward(2)", "example.com#?##a:upward(2)"),
            ("example.com#$#.a, #b { top: 0 }", "example.com#$#.a, #b { top: 0 }"),
            // #975: Safari has no object type; drop it unless that would widen the rule.
            ("||media.net^$object,script,third-party", "||media.net^$script,third-party"),
            ("||quantserve.com^$~object,third-party", "||quantserve.com^$third-party"),
            ("||x.com^$~object", "||x.com^"),
            ("@@||x.com/imp;$object,domain=a.de", "@@||x.com/imp;$object,domain=a.de"),
            // #975: Safari can't exclude request domains; allowed domains become exceptions.
            ("$script,third-party,denyallow=a.net|b.com,domain=s.com",
             "$script,third-party,domain=s.com\n@@||a.net^$script,third-party,domain=s.com\n@@||b.com^$script,third-party,domain=s.com"),
            ("||x.com^$image,denyallow=a.net,domain=s.com", "||x.com^$image,denyallow=a.net,domain=s.com"),
            ("$script,denyallow=a.net", "$script,denyallow=a.net"),
            // #975: whitespace then # starts a uBO comment in network rules, but not in a regex.
            ("||ls.apple.com^$badfilter  # apple maps", "||ls.apple.com^$badfilter"),
            ("||x.com^$~object\t# note", "||x.com^"),
            ("/ads #x/$script", "/ads #x/$script"),
            ("||x.com/#anchor", "||x.com/#anchor"),
        ]
        for (input, expected) in cases {
            let output = FilterRuleAnalysis.adGuardEquivalent(input)
            require(output == expected, "\(input) -> \(output)")
        }

        let analysis = FilterRuleAnalysis.analyze(content: cases[0].0 + "\nwww.reddit.com###answers-nav-button")
        require(analysis.count(of: .advanced) == 1 && analysis.count(of: .elementHiding) == 1,
                "remove-attr must count as advanced and leave the hide rule supported")
        print("PASS: uBO conversion and ExtendedCss routing")
    }
}
