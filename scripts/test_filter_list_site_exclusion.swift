import Foundation
import wBlockCoreService

@main
struct FilterListSiteExclusionTests {
    static func main() {
        let json = #"[{"action":{"type":"block"},"trigger":{"url-filter":".*"}}]"#
        let applied = FilterListSiteExclusion.applyingUnlessDomain(
            toJSON: json,
            domains: [" Example.com ", "www.example.com"]
        )
        guard applied.contains("unless-domain") else {
            fputs("FAIL: Safari JSON must gain unless-domain\n", stderr)
            exit(1)
        }
        guard applied.contains("*example.com") && applied.contains("*www.example.com") else {
            fputs("FAIL: unless-domain must include wildcard hosts\n\(applied)\n", stderr)
            exit(1)
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
        guard scoped.contains("domain=cnn.com|~nytimes.com") || scoped.contains("domain=~nytimes.com|cnn.com") else {
            fputs("FAIL: existing domain= options must append exclusions\n\(scoped)\n", stderr)
            exit(1)
        }

        let concat = FilterListSiteExclusion.concatenateContentBlockerJSON([
            #"[{"a":1}]"#,
            #"[{"b":2}]"#,
        ])
        guard concat == #"[{"a":1},{"b":2}]"# else {
            fputs("FAIL: JSON chunks must concatenate\n\(concat)\n", stderr)
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
            "FilterListSiteExclusion.restrictingAdvancedRules",
            "conversion must restrict lists with exclusions before Safari conversion"
        )
        requireContains(
            affinity,
            "FilterListSiteExclusion.restrictingAdvancedRules",
            "affinity contributions must honor per-list exclusions"
        )
        print("PASS")
    }
}
