import Foundation
import wBlockCoreService

// Compile with wBlock/FilterListDuplicates.swift and link wBlockCoreService.framework.
@main
struct FilterListDuplicatesTests {
    static func main() {
        func list(_ name: String, _ url: String, custom: Bool = false, count: Int? = nil) -> FilterList {
            var list = FilterList(name: name, url: URL(string: url)!, category: custom ? .custom : .security, isCustom: custom)
            list.sourceRuleCount = count
            return list
        }
        let rules = (0..<1000).map { "||badware\($0).example^" }
        let minified = rules.joined(separator: "\n")
        // A hand-added copy from another address, with comments, headers and a few local edits.
        let full = (["[Adblock Plus 2.0]", "! Title: uBlock filters – Badware risks", "! Expires: 1 day", ""]
            + rules.dropLast(20) + ["||mine.example^"]).joined(separator: "\n")
        let builtIn = list("uBlock filters – Badware risks", "https://ublockorigin.github.io/uAssetsCDN/filters/badware.min.txt")
        let copy = list("uBlock filters – Badware risks", "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt", custom: true)
        let other = list("Other", "https://example.org/other.txt", custom: true)
        let builtInTwin = list("Twin", "https://example.org/twin.txt")
        let texts: [UUID: String] = [
            builtIn.id: minified, copy.id: full, other.id: (0..<1000).map { "||other\($0).example^" }.joined(separator: "\n"),
            builtInTwin.id: minified,
        ]
        let read = { (list: FilterList) in texts[list.id].map(FilterListDuplicates.rules(in:)) }

        let found = FilterListDuplicates.pairs(in: [builtIn, other, copy], dismissed: [], rules: read)
        precondition(found == [.init(original: builtIn, copy: copy)], "a custom copy from another address is found")
        precondition(FilterListDuplicates.pairs(in: [copy, builtIn], dismissed: [], rules: read)
            == [.init(original: builtIn, copy: copy)], "the built-in list is kept even when listed after its copy")
        precondition(FilterListDuplicates.pairs(in: [builtIn, copy], dismissed: [found[0].key], rules: read).isEmpty,
                     "an answered pair is not asked about again")
        precondition(FilterListDuplicates.pairs(in: [builtIn, builtInTwin], dismissed: [], rules: read).isEmpty,
                     "built-in lists are never offered for removal")
        precondition(FilterListDuplicates.pairs(in: [builtIn, copy], dismissed: [], rules: { _ in nil }).isEmpty,
                     "lists without downloads are skipped")

        // A small custom list inside a big one is a subset, not a copy.
        let subset = list("Subset", "https://example.org/subset.txt", custom: true)
        let subsetText = rules.prefix(500).joined(separator: "\n")
        precondition(FilterListDuplicates.pairs(in: [builtIn, subset], dismissed: [], rules: {
            $0.id == subset.id ? FilterListDuplicates.rules(in: subsetText) : read($0)
        }).isEmpty, "a subset is not a duplicate")
        var readCount = 0
        precondition(FilterListDuplicates.pairs(
            in: [list("Big", "https://example.org/big", count: 100_000), list("Small", "https://example.org/small", custom: true, count: 1_000)],
            dismissed: [], rules: { _ in readCount += 1; return nil }).isEmpty && readCount == 0,
                     "lists of very different sizes are not read")
        print("filter list duplicates: all checks passed")
    }
}
