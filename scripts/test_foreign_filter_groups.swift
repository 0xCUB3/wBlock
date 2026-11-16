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
        check(RegionalLanguageOption.fromForeignFilters(catalog).contains { $0.code == "gsw" },
              "Swiss German can select German regional recommendations")
        let covered = Set(catalog.flatMap(\.languages))
        let selections = catalog.map(\.isSelected)
        for (language, targets) in RegionalLanguageOption.regionalFallbacks {
            check(!covered.contains(language), "fallback \(language) stays separate from declared coverage")
            check(!targets.isEmpty && targets.isSubset(of: covered), "fallback targets exist in the catalog")
            check(targets.isDisjoint(with: ["tr", "th"]), "unsupported Turkish and Thai associations stay out")
            check(RegionalLanguageOption.expanding([language]) == targets.union([language]), "expansion preserves the selected language")
        }
        func matching(_ languages: Set<String>) -> Set<String> {
            let expanded = RegionalLanguageOption.expanding(languages)
            return Set(catalog.filter { !Set($0.languages).isDisjoint(with: expanded) }.map(\.name))
        }
        check(matching(["lb"]) == ["AdGuard German filter", "AdGuard French filter"], "Luxembourgish recommends both languages")
        check(matching(["gsw"]) == matching(["de"]), "Swiss German uses existing German recommendations")
        check(matching(["jv"]) == matching(["id"]), "Javanese preserves Indonesian list choices")
        check(matching(["yue"]) == matching(["zh"]), "Cantonese keeps its existing Chinese canonicalization")
        check(RegionalLanguageOption.expanding([]).isEmpty, "no selected language adds no recommendations")
        let expanded = RegionalLanguageOption.expanding(["GSW", "lb", "en"])
        check(RegionalLanguageOption.expanding(expanded) == expanded && expanded.contains("en"), "expansion is idempotent and keeps unrelated selections")
        check(RegionalLanguageOption.fromForeignFilters([german]).contains { $0.code == "gsw" }, "fallbacks work with custom lists")
        check(!RegionalLanguageOption.fromForeignFilters([icelandic]).contains { $0.code == "gsw" }, "fallbacks need an available target list")
        check(german.nativeLanguageNames(among: RegionalLanguageOption.expanding(["gsw"])) == german.nativeLanguageNames(), "card captions name actual coverage")
        check(catalog.map(\.isSelected) == selections, "recommendation lookup never enables lists")
        print("PASS: foreign filter groups and \(RegionalLanguageOption.regionalFallbacks.count) regional language fallbacks")
    }
}
