import Foundation
import wBlockCoreService

@main
struct FilterListSiteExclusionTests {
    static func main() {
        for only in [false, true] {
            for selected in [[], ["news.example.com"]] {
                let filter = FilterList(name: "Scoped", url: URL(string: "https://example.com/list")!, category: .ads,
                                        excludedSites: ["excluded.example.com"], selectedSites: selected, onlySelectedSites: only)
                let encoded = try! JSONEncoder().encode(filter)
                let restored = try! JSONDecoder().decode(FilterList.self, from: encoded)
                precondition(restored == filter)
                precondition(filter.appliedSelectedSites == (only ? selected : nil)
                             && filter.appliedExcludedSites == (only ? [] : filter.excludedSites))
                var stale = filter
                stale.selectedSites = []
                stale.onlySelectedSites = !only
                precondition(FilterSelectionRebaser.rebaseSelection(snapshot: [stale], latestPersisted: [filter])[0] == filter)
            }
        }
        var legacy = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(
            FilterList(name: "Old", url: URL(string: "https://example.com/list")!, category: .ads)
        )) as! [String: Any]
        legacy["onlySelectedSites"] = nil
        precondition(try! JSONDecoder().decode(FilterList.self, from: JSONSerialization.data(withJSONObject: legacy)).onlySelectedSites,
                     "a saved selection without the mode means selected-sites mode")
        precondition(FilterListSiteExclusion.normalizedDomains(from: [" Amazon.* ", "*.amazon.*", "*", ".*", "amazon.com"]) == ["amazon.*", "amazon.com"])
        print("PASS")
    }
}
