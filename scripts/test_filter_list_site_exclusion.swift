import Foundation
import wBlockCoreService

@main
struct FilterListSiteExclusionTests {
    static func main() {
        let selectedCases: [(String, [String], [String], String)] = [
            ("##.ad", [], ["example.com"], "example.com##.ad"),
            ("||ads.test^", [], ["example.com"], "||ads.test^$domain=example.com"),
            ("example.com##.ad", [], ["news.example.com"], "news.example.com##.ad"),
            ("news.example.com##.ad", [], ["example.com"], "news.example.com##.ad"),
            ("other.test##.ad", [], ["example.com"], ""),
            ("||ads.test^$domain=other.test", [], ["example.com"], ""),
            ("||ads.test^$from=other.test", [], ["example.com"], ""),
            ("||ads.test^$from=example.com", [], ["news.example.com"], "||ads.test^$domain=news.example.com"),
            (#"/ads\/end$/$replace=/a$/b/"#, [], ["example.com"], #"/ads\/end$/$replace=/a$/b/,domain=example.com"#),
            ("##.ad", ["example.com"], ["news.example.com"], ""),
            ("~example.com##.ad", [], ["example.com"], ""),
            ("~other.test##.ad", [], ["example.com"], "example.com##.ad"),
            ("||ads.test^$domain=~other.test", [], ["example.com"], "||ads.test^$domain=example.com"),
            ("##.ad", ["news.example.com"], ["example.com"], "example.com,~news.example.com##.ad"),
            ("||ads.test^", ["news.example.com"], ["example.com"], "||ads.test^$domain=example.com\n@@||ads.test^$domain=news.example.com"),
            ("@@||ads.test^$document", [], ["example.com"], "@@||ads.test^$document,domain=example.com"),
            ("/ads[0-9]+$/", [], ["example.com"], "/ads[0-9]+$/$domain=example.com"),
            ("##.ad", [], [], ""),
            ("example.com#%#//scriptlet('abort-on-property-read', 'adblock')", [], ["news.example.com"],
             "news.example.com#%#//scriptlet('abort-on-property-read', 'adblock')")
        ]
        for (rule, excluded, selected, expected) in selectedCases {
            precondition(FilterListSiteExclusion.restrictingAdvancedRules(rule, excluding: excluded, including: selected) == expected,
                         "selected-site restriction failed for \(rule)")
        }
        let cosmetic = FilterListSiteExclusion.restrictingAdvancedRules(
            "##.ad",
            excluding: ["nytimes.com"]
        )
        guard cosmetic == "~nytimes.com##.ad" else {
            fputs("FAIL: unscoped cosmetic rules must negate excluded hosts\n\(cosmetic)\n", stderr)
            exit(1)
        }

        let network = FilterListSiteExclusion.restrictingAdvancedRules(
            "||ads.example^",
            excluding: ["nytimes.com"]
        )
        guard network == "||ads.example^$domain=~nytimes.com" else {
            fputs("FAIL: unscoped network rules must add domain negation\n\(network)\n", stderr)
            exit(1)
        }

        let scoped = FilterListSiteExclusion.restrictingAdvancedRules(
            "||ads.example^$domain=cnn.com",
            excluding: ["nytimes.com"]
        )
        guard scoped == "||ads.example^$domain=cnn.com" else {
            fputs("FAIL: rules scoped to other sites must stay unmixed (Safari rejects mixed domains)\n\(scoped)\n", stderr)
            exit(1)
        }

        let scopedToExcluded = FilterListSiteExclusion.restrictingAdvancedRules(
            "||ads.example^$third-party,domain=www.nytimes.com|nytimes.com",
            excluding: ["nytimes.com"]
        )
        guard scopedToExcluded == "" else {
            fputs("FAIL: rules scoped only to excluded sites must be dropped\n\(scopedToExcluded)\n", stderr)
            exit(1)
        }

        let partiallyScoped = FilterListSiteExclusion.restrictingAdvancedRules(
            "||ads.example^$third-party,domain=nytimes.com|cnn.com,important",
            excluding: ["nytimes.com"]
        )
        guard partiallyScoped == "||ads.example^$third-party,domain=cnn.com,important" else {
            fputs("FAIL: excluded sites must be removed from positive domain lists\n\(partiallyScoped)\n", stderr)
            exit(1)
        }

        let negatedOnly = FilterListSiteExclusion.restrictingAdvancedRules(
            "~foo.com##.ad",
            excluding: ["nytimes.com"]
        )
        guard negatedOnly == "~foo.com,~nytimes.com##.ad" else {
            fputs("FAIL: negation-only cosmetic rules must gain the exclusion\n\(negatedOnly)\n", stderr)
            exit(1)
        }

        let cosmeticScoped = FilterListSiteExclusion.restrictingAdvancedRules(
            "nytimes.com,cnn.com##.ad",
            excluding: ["nytimes.com"]
        )
        guard cosmeticScoped == "cnn.com##.ad" else {
            fputs("FAIL: excluded sites must be removed from cosmetic domain lists\n\(cosmeticScoped)\n", stderr)
            exit(1)
        }

        let untouched = FilterListSiteExclusion.restrictingAdvancedRules(
            "! comment",
            excluding: ["nytimes.com"]
        )
        guard untouched == "! comment" else {
            fputs("FAIL: comments must pass through\n\(untouched)\n", stderr)
            exit(1)
        }

        let exception = FilterListSiteExclusion.restrictingAdvancedRules(
            "@@||ads.example^",
            excluding: ["nytimes.com"]
        )
        guard exception == "@@||ads.example^$domain=~nytimes.com" else {
            fputs("FAIL: unscoped exceptions must not apply on excluded sites\n\(exception)\n", stderr)
            exit(1)
        }

        let documentException = FilterListSiteExclusion.restrictingAdvancedRules(
            "@@||nytimes.com^$document",
            excluding: ["nytimes.com"]
        )
        guard documentException == "@@||nytimes.com^$document,domain=~nytimes.com" else {
            fputs("FAIL: document exceptions must stop applying on excluded sites without dropping the URL pattern\n\(documentException)\n", stderr)
            exit(1)
        }

        let subdomainNetwork = FilterListSiteExclusion.restrictingAdvancedRules(
            "||ads.example^$third-party,domain=smth.com",
            excluding: ["m.smth.com"]
        )
        guard subdomainNetwork == "||ads.example^$third-party,domain=smth.com\n@@||ads.example^$third-party,domain=m.smth.com" else {
            fputs("FAIL: excluded subdomains of a scoped network rule need a companion exception (#767)\n\(subdomainNetwork)\n", stderr)
            exit(1)
        }

        let subdomainCosmetic = FilterListSiteExclusion.restrictingAdvancedRules(
            "smth.com##.ad",
            excluding: ["m.smth.com"]
        )
        guard subdomainCosmetic == "smth.com,~m.smth.com##.ad" else {
            fputs("FAIL: excluded subdomains of a scoped cosmetic rule need a negation (#767)\n\(subdomainCosmetic)\n", stderr)
            exit(1)
        }

        let subdomainException = FilterListSiteExclusion.restrictingAdvancedRules(
            "@@||ads.example^$domain=smth.com",
            excluding: ["m.smth.com"]
        )
        guard subdomainException == "@@||ads.example^$domain=smth.com" else {
            fputs("FAIL: exceptions scoped to a parent domain have no inverse and must pass through\n\(subdomainException)\n", stderr)
            exit(1)
        }

        let alreadyNegated = FilterListSiteExclusion.restrictingAdvancedRules(
            "smth.com,~m.smth.com##.ad",
            excluding: ["m.smth.com"]
        )
        guard alreadyNegated == "smth.com,~m.smth.com##.ad" else {
            fputs("FAIL: existing negations must not be duplicated\n\(alreadyNegated)\n", stderr)
            exit(1)
        }

        for selected: [String]? in [nil, [], ["news.example.com"]] {
            let filter = FilterList(name: "Scoped", url: URL(string: "https://example.com/list")!, category: .ads,
                                    excludedSites: ["excluded.example.com"], selectedSites: selected)
            let encoded = try! JSONEncoder().encode(filter)
            let restored = try! JSONDecoder().decode(FilterList.self, from: encoded)
            precondition(restored.selectedSites == selected && restored.excludedSites == filter.excludedSites)
            var stale = filter
            stale.selectedSites = nil
            precondition(FilterSelectionRebaser.rebaseSelection(snapshot: [stale], latestPersisted: [filter])[0].selectedSites == selected)
        }
        print("PASS")
    }
}
