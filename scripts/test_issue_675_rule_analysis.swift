import Foundation
import wBlockCoreService

@main
struct Test {
    static func main() {
        func require(_ c: Bool, _ m: String) { guard c else { fputs("FAIL: \(m)\n", stderr); exit(1) } }

        // #675: the rules viewer classifies every line so it can highlight and
        // filter unsupported, duplicate, and Scripts-only rules.
        let content = """
        ! Title: Sample
        [Adblock Plus 2.0]
        ||ads.example.com^
        example.com##.banner
        example.com#?#.card:has(> .ad)
        example.com#%#//scriptlet('set-constant', 'adsEnabled', 'false')
        ||ads.example.com^
        ||
        # hosts-style comment
        example.com#$#body { overflow: auto !important; }
        @@||example.com^$jsinject
        """
        let analysis = FilterRuleAnalysis.analyze(content: content, seenInEarlierLists: ["example.com##.banner"])
        let kinds = analysis.lines.map(\.kind)
        let expected: [FilterRuleKind] = [
            .comment, .comment, .supported, .duplicate, .advanced, .advanced,
            .duplicate, .unsupported, .comment, .advanced, .advanced
        ]
        require(kinds == expected, "line kinds: \(kinds.map(\.rawValue))")
        require(analysis.count(of: .duplicate) == 2, "duplicate count \(analysis.count(of: .duplicate))")
        require(analysis.count(of: .unsupported) == 1, "unsupported count")
        require(analysis.lines.map(\.text) == content.components(separatedBy: "\n"), "original text is preserved line for line")

        let earlier = FilterRuleAnalysis.ruleSet(from: "! c\n  ||a.com^  \n\n||b.com^")
        require(earlier == ["||a.com^", "||b.com^"], "ruleSet trims and drops comments: \(earlier)")

        let cleaning = FilterRuleAnalysis.analyze(content: """
        $removeparam=gclid
        $removeparam=utm_source
        @@||example.com^$removeparam
        $removeparam=/^utm_/
        $removeparam=~keep
        $removeparam=x,unsupported-option
        """)
        require(cleaning.lines.map(\.kind) == [.advanced, .advanced, .advanced, .unsupported, .unsupported, .unsupported], "removeparam uses actual DNR support")

        let identities = FilterRuleAnalysis.analyze(content: """
        ||EXAMPLE.com^
        ||example.com^
        EXAMPLE.com##.Ad
        example.com##.Ad
        example.com##.ad
        ||example.com/Ad$match-case
        ||example.com/ad$match-case
        /\\D/
        /\\d/
        $removeparam=Name
        $removeparam=name
        """)
        require(identities.count(of: .duplicate) == 2, "fold domains, not CSS, regex escapes, match-case paths or parameter names")
        let mixedEarlier = FilterRuleAnalysis.analyze(content: "||example.com^", seenInEarlierLists: ["||EXAMPLE.COM^"])
        require(mixedEarlier.count(of: .duplicate) == 1, "normalize earlier-list identities")

        let cancelled = FilterRuleAnalysis.analyze(content: content, isCancelled: { true })
        require(cancelled.lines.isEmpty, "cancellation yields an empty analysis")

        let view = try! String(contentsOfFile: "wBlock/FilterInfoView.swift", encoding: .utf8)
        require(view.contains("FilterRuleAnalysis.analyze(") && view.contains("shownKinds") && view.contains("orderedForCompilation"),
                "rules viewer analyses against earlier lists and filters by kind")
        print("PASS test_issue_675_rule_analysis")
    }
}
