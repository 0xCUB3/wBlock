import Foundation
internal import ContentBlockerConverter

/// Per-line classification of a filter list for the rules viewer (#675).
///
/// Every line gets one kind. Comments and headers are never rules. A rule is
/// a duplicate when the same rule identity appeared earlier, either in a list
/// that compiles before this one or earlier in the same list; the first copy
/// keeps its own kind. Remaining rules are parsed with the converter: a parse
/// failure is unsupported, an advanced rule needs wBlock Scripts, and the rest
/// compile into Safari's native content blocker format.
public enum FilterRuleKind: String, CaseIterable, Sendable {
    case comment
    case supported
    case advanced
    case unsupported
    case duplicate
}

public struct FilterRuleAnalysis: Sendable {
    public struct Line: Sendable {
        public let text: String
        public let kind: FilterRuleKind
    }

    public let lines: [Line]
    public let counts: [FilterRuleKind: Int]

    public init(lines: [Line]) {
        self.lines = lines
        var counts: [FilterRuleKind: Int] = [:]
        for line in lines { counts[line.kind, default: 0] += 1 }
        self.counts = counts
    }

    public func count(of kind: FilterRuleKind) -> Int { counts[kind] ?? 0 }

    /// Trimmed rule lines from `earlier`, matching the normalisation that
    /// `ContentBlockerMappingService.uniqueRuleCounts` uses.
    public static func ruleSet(from earlier: String) -> Set<String> {
        var seen = Set<String>()
        earlier.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isRuleLine(trimmed) { seen.insert(ruleIdentity(trimmed)) }
        }
        return seen
    }

    /// Fold only case-insensitive syntax. Selector bodies, option values,
    /// regular expressions and match-case URL patterns keep their spelling.
    public static func ruleIdentity(_ raw: String) -> String {
        let rule = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cosmeticMarkers = ["##", "#@#", "#?#", "#@?#", "#$#", "#@$#", "#%#", "#@%#", "#$?#", "#@$?#"]
        if let marker = rule.firstIndex(of: "#"),
           cosmeticMarkers.contains(where: { rule[marker...].hasPrefix($0) }) {
            return rule[..<marker].contains("/") ? rule : rule[..<marker].lowercased() + rule[marker...]
        }
        let exception = rule.hasPrefix("@@") ? "@@" : ""
        let body = exception.isEmpty ? rule : String(rule.dropFirst(2))
        let pieces = body.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        let pattern = String(pieces[0])
        let options = pieces.count > 1 ? String(pieces[1]) : nil
        // Regex escapes such as \\D and \\d have different meanings.
        guard !pattern.hasPrefix("/"),
              !(options?.split(separator: ",").contains("match-case") ?? false) else { return rule }
        return exception + pattern.lowercased() + (options.map { "$" + $0 } ?? "")
    }

    public static func isRuleLine(_ trimmed: String) -> Bool {
        if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") { return false }
        // "# comment" lines in hosts-style lists, but not "##selector" rules.
        if trimmed.hasPrefix("# ") || trimmed == "#" { return false }
        return true
    }

    /// Classifies `content`. `seen` carries rules from lists that compile
    /// earlier; it is extended with this list's rules as they are visited.
    public static func analyze(
        content: String,
        seenInEarlierLists: Set<String> = [],
        isCancelled: @escaping () -> Bool = { false }
    ) -> FilterRuleAnalysis {
        let safariVersion = SafariVersion.autodetect()
        var seen = Set(seenInEarlierLists.map(ruleIdentity))
        var lines: [Line] = []
        var stop = false
        content.enumerateLines { raw, shouldStop in
            if isCancelled() { stop = true; shouldStop = true; return }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRuleLine(trimmed) else {
                lines.append(Line(text: raw, kind: .comment))
                return
            }
            guard seen.insert(ruleIdentity(trimmed)).inserted else {
                lines.append(Line(text: raw, kind: .duplicate))
                return
            }
            lines.append(Line(text: raw, kind: classify(trimmed, safariVersion: safariVersion)))
        }
        if stop { return FilterRuleAnalysis(lines: []) }
        return FilterRuleAnalysis(lines: lines)
    }

    static func classify(_ rule: String, safariVersion: SafariVersion) -> FilterRuleKind {
        if let supported = RemoveParamDNRRuleGenerator.supportsRule(rule) {
            return supported ? .advanced : .unsupported
        }
        do {
            guard let parsed = try RuleFactory.createRule(ruleText: rule, for: safariVersion) else {
                return .comment
            }
            // Same split the converter applies: extended CSS, scripts,
            // scriptlets, and CSS injection need wBlock Scripts, as do
            // exceptions that only exist to modify those ($jsinject).
            if let cosmetic = parsed as? CosmeticRule {
                return cosmetic.isScript || cosmetic.isScriptlet || cosmetic.isExtendedCss || cosmetic.isInjectCss
                    ? .advanced : .supported
            }
            if let network = parsed as? NetworkRule, network.isWhiteList, network.isJsInject,
               !network.isDocumentWhiteList, !network.isCssExceptionRule {
                return .advanced
            }
            return .supported
        } catch {
            return .unsupported
        }
    }
}
