import Foundation
import wBlockCoreService

@main struct ForeignFilterGroupsTest {
    static func main() {
        func check(_ value: Bool, _ message: String) {
            if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        func list(_ name: String, _ languages: [String], trust: String = "high") -> FilterList {
            FilterList(name: name, url: URL(string: "https://example.com/\(name).txt")!, category: .foreign,
                       languages: languages, trustLevel: trust)
        }
        let nordic = list("Nordic", ["nb", "nn", "da", "is", "fo", "kl"])
        let icelandic = list("Icelandic", ["is"])
        let optional = list("Optional", ["is"], trust: "low")
        let german = list("German", ["de"], trust: "full")
        let input = [nordic, icelandic, optional, german]
        let buckets = ForeignFilterOrganizer.recommendationBuckets(from: input)
        check(Set(buckets.recommended.map(\.id)) == Set([nordic.id, icelandic.id, german.id]), "default recommendations preserved")
        check(buckets.optional.map(\.id) == [optional.id], "optional recommendation stays off by default")
        let catalog = FilterListLoader().getDefaultFilterLists().filter { $0.category == .foreign }
        check(ForeignFilterOrganizer.sortedFilters(catalog.reversed()).map(\.url) == catalog.map(\.url),
              "regional display follows catalog order regardless of stored order or trust")
        let subset = Array(catalog.enumerated().filter { $0.offset.isMultiple(of: 3) }.map(\.element))
        check(ForeignFilterOrganizer.sortedFilters(subset.reversed()).map(\.url) == subset.map(\.url),
              "filtered regional display preserves catalog order")
        print("PASS: foreign filter groups")
    }
}
