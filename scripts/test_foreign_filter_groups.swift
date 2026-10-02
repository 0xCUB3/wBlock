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
        let groups = ForeignFilterOrganizer.groups(for: input, preferredLanguages: ["da", "is"])
        check(groups.count == 1, "shared Nordic languages form one group")
        check(Set(groups[0].filters.map(\.id)) == Set([nordic.id, icelandic.id, optional.id]), "optional and language-specific lists stay visible")
        check(groups[0].filters.count == 3, "shared list appears once")
        check(groups[0].filters.last?.id == optional.id, "recommendation ordering stays unchanged")
        check(groups[0].languageCode == "da+is", "group identity uses only selected language codes")

        let onlyIcelandic = ForeignFilterOrganizer.groups(for: input, preferredLanguages: ["is"])
        check(onlyIcelandic.count == 1 && onlyIcelandic[0].filters.count == 3, "Icelandic includes both Nordic and Icelandic lists")
        let serbian = list("SerboCroatian", ["sr", "hr", "bs", "cnr"])
        let balkan = ForeignFilterOrganizer.groups(for: [serbian], preferredLanguages: ["sr", "hr"])
        check(balkan.count == 1 && balkan[0].filters.count == 1, "Serbo-Croatian list has one toggle")
        let disjoint = ForeignFilterOrganizer.groups(for: [nordic, german], preferredLanguages: ["da", "de"])
        check(disjoint.count == 2, "unrelated languages remain separate")
        let repeated = ForeignFilterOrganizer.groups(for: [nordic, nordic], preferredLanguages: ["DA", "IS"])
        check(repeated.count == 1 && repeated[0].filters.count == 1, "case normalization and repeated identity do not duplicate rows")
        let permutations = ForeignFilterOrganizer.groups(for: input.reversed(), preferredLanguages: ["IS", "DA"])
        check(permutations.map(\.id) == groups.map(\.id), "group identities do not depend on input order")
        check(permutations.flatMap(\.filters).map(\.id) == groups.flatMap(\.filters).map(\.id), "row order is deterministic")
        check(ForeignFilterOrganizer.groups(for: input, preferredLanguages: []).isEmpty, "no selected languages yields no matches")
        let unknown = list("Unknown", [])
        let ungrouped = ForeignFilterOrganizer.groups(for: [german, unknown])
        check(ungrouped.count == 2 && ungrouped.last?.filters.first?.id == unknown.id, "lists without metadata stay in trailing regional group")
        let bridge = list("Bridge", ["da", "de"])
        let connected = ForeignFilterOrganizer.groups(for: [nordic, german, bridge], preferredLanguages: ["da", "is", "de"])
        check(connected.count == 1 && connected[0].filters.count == 3, "overlapping coverage merges transitively without duplicates")
        let buckets = ForeignFilterOrganizer.recommendationBuckets(from: input)
        check(Set(buckets.recommended.map(\.id)) == Set([nordic.id, icelandic.id, german.id]), "default recommendations preserved")
        check(buckets.optional.map(\.id) == [optional.id], "optional recommendation stays off by default")
        check(input.allSatisfy { !$0.isSelected }, "grouping never mutates selections")
        var selected = nordic
        selected.isSelected = true
        check(ForeignFilterOrganizer.groups(for: [selected], preferredLanguages: ["da"]).first?.filters == [selected], "selected record and metadata survive unchanged")
        print("PASS: foreign filter groups")
    }
}
