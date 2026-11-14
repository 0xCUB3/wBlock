import Foundation
import wBlockCoreService

/// Finds custom lists that are copies of another list, such as a uBO list a
/// user added by hand in 3.x next to the built-in one, so both stop compiling
/// the same rules twice.
enum FilterListDuplicates {
    /// Share of their combined rules two lists must have in common.
    static let threshold = 0.9

    struct Pair: Equatable {
        /// The list to keep: the built-in one, or the earlier of two custom lists.
        let original: FilterList
        /// The custom list that copies it.
        let copy: FilterList
        var key: String { [original.url.absoluteString, copy.url.absoluteString].sorted().joined(separator: "\n") }
    }

    /// Pairs whose rules overlap by `threshold` or more of their union. Every
    /// pair has a custom side, and pairs in `dismissed` are skipped. `rules`
    /// returns a list's downloaded rules, or nil before its first download.
    static func pairs(
        in lists: [FilterList], dismissed: Set<String>, rules: (FilterList) -> Set<String>?
    ) -> [Pair] {
        var cache: [UUID: Set<String>?] = [:]
        func ruleSet(_ list: FilterList) -> Set<String>? {
            if let cached = cache[list.id] { return cached }
            let loaded = rules(list).flatMap { $0.isEmpty ? nil : $0 }
            cache[list.id] = loaded
            return loaded
        }
        var found: [Pair] = []
        var paired = Set<UUID>()
        for (index, later) in lists.enumerated() {
            for earlier in lists[..<index] where later.isCustom || earlier.isCustom {
                guard !paired.contains(earlier.id), !paired.contains(later.id) else { continue }
                let pair = later.isCustom
                    ? Pair(original: earlier, copy: later) : Pair(original: later, copy: earlier)
                guard !dismissed.contains(pair.key), countsCanMatch(earlier, later),
                      let a = ruleSet(earlier), let b = ruleSet(later) else { continue }
                let shared = a.intersection(b).count
                guard Double(shared) >= threshold * Double(a.count + b.count - shared) else { continue }
                found.append(pair)
                paired.formUnion([earlier.id, later.id])
            }
        }
        return found
    }

    /// Lists this far apart in size can't reach the threshold, so skip reading them.
    private static func countsCanMatch(_ a: FilterList, _ b: FilterList) -> Bool {
        guard let x = a.sourceRuleCount, let y = b.sourceRuleCount, x > 0, y > 0 else { return true }
        return Double(min(x, y)) >= threshold * Double(max(x, y))
    }

    /// A downloaded list's rules, without blank lines, comments and headers,
    /// which differ between minified and full copies of the same list.
    static func rules(in text: String) -> Set<String> {
        var rules = Set<String>()
        text.enumerateLines { line, _ in
            let rule = line.trimmingCharacters(in: .whitespaces)
            guard !rule.isEmpty, !rule.hasPrefix("!"), !rule.hasPrefix("[") else { return }
            rules.insert(rule)
        }
        return rules
    }
}
