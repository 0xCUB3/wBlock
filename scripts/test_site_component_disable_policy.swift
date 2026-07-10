import Foundation

public struct FilterList {
    public let id = UUID()
    public let isCustom = false
    public let name = ""
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
@main
struct SiteComponentDisablePolicyTest {
    static func main() {
        let master = ["example.com"]
        let filterOnly = ["filter-only.test"]
        let effective = DisabledSitesNormalizer.effectiveFilterDisabledDomains(master: master, filterOnly: filterOnly)

        check(HostMatcher.isHostDisabled(host: "www.example.com", disabledSites: master), "master subdomain should be disabled")
        check(HostMatcher.isHostDisabled(host: "example.com", disabledSites: effective), "master domain should bypass filtering")
        check(effective.contains("filter-only.test"), "filter-only domain should be effective for filtering")
        check(!HostMatcher.isHostDisabled(host: "filter-only.test", disabledSites: master), "filter-only domain must not be globally disabled")
        check(HostMatcher.isHostDisabled(host: "sub.filter-only.test", disabledSites: effective), "filter-only subdomain should bypass filtering")

        print("site component disable policy passed")
    }
}
