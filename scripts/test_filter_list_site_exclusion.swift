import Foundation
import wBlockCoreService

@main
struct FilterListSiteExclusionTests {
    static func main() {
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

        let manager = try! String(contentsOfFile: "wBlock/AppFilterManager.swift", encoding: .utf8)
        let info = try! String(contentsOfFile: "wBlock/FilterInfoView.swift", encoding: .utf8)
        let protoExt = try! String(contentsOfFile: "wBlockCoreService/ProtobufDataManager+Extensions.swift", encoding: .utf8)
        let conversion = try! String(contentsOfFile: "wBlockCoreService/wBlockCoreService.swift", encoding: .utf8)
        let affinity = try! String(contentsOfFile: "wBlockCoreService/SafariContentBlockerAffinityProcessor.swift", encoding: .utf8)

        func requireContains(_ haystack: String, _ needle: String, _ message: String) {
            guard haystack.contains(needle) else {
                fputs("FAIL: \(message)\nMissing: \(needle)\n", stderr)
                exit(1)
            }
        }

        requireContains(manager, "excludedSites = filter.excludedSites", "apply snapshots must treat exclusions as configuration")
        requireContains(manager, "func setExcludedSites(", "the filter manager must persist per-list exclusions")
        requireContains(info, "excludedSitesSection", "filter info must expose per-list exclusions")
        requireContains(info, "filterManager.setExcludedSites", "filter info must write exclusions through the manager")
        requireContains(protoExt, "protoFilterList.excludedSites = filter.excludedSites", "protobuf saves must persist excluded sites")
        requireContains(protoExt, "excludedSites: Array(protoData.excludedSites)", "protobuf loads must restore excluded sites")
        requireContains(
            conversion,
            "FilterListSiteExclusion.applyingSiteRestrictions",
            "conversion must restrict lists with exclusions before Safari conversion"
        )
        requireContains(
            affinity,
            "FilterListSiteExclusion.applyingSiteRestrictions",
            "affinity contributions must honor per-list exclusions"
        )
        print("PASS")
    }
}
