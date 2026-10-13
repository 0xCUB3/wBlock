import Foundation
internal import ContentBlockerConverter

/// Per-line classification of a filter list for the rules viewer (#675).
///
/// Every line gets one kind. Comments and headers are never rules. A rule is
/// a duplicate when the same rule identity appeared earlier, either in a list
/// that compiles before this one or earlier in the same list; the first copy
/// keeps its own kind. Remaining rules are parsed with the converter: a parse
/// failure is unsupported, an advanced rule needs wBlock Scripts, a
/// `$removeparam` rule the DNR generator can express is counted on its own
/// because Safari caps those separately, and the rest compile into Safari's
/// native content blocker format.
public enum FilterRuleKind: String, CaseIterable, Sendable {
    case comment
    /// Blocks and exceptions Safari applies to requests.
    case network
    /// Plain CSS hiding rules Safari applies.
    case elementHiding
    case advanced
    case removeParam
    case unsupported
    case duplicate
}

/// 128 bits standing for a rule identity in sets that span whole lists, which
/// would otherwise keep a string per rule. Seeded per process; never persist it.
struct RuleFingerprint: Hashable {
    private let first: Int
    private let second: Int

    init(_ identity: String) {
        var hasher = Hasher()
        hasher.combine(identity)
        first = hasher.finalize()
        hasher = Hasher()
        hasher.combine(identity.utf8.count)
        hasher.combine(identity)
        second = hasher.finalize()
    }
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

    /// Trimmed rule lines from `earlier`, matching the rule-identity
    /// normalisation used by conversion-time deduplication.
    public static func ruleSet(
        from earlier: String,
        isCancelled: @escaping () -> Bool = { false }
    ) -> Set<String> {
        var seen = Set<String>()
        var cancelled = false
        earlier.enumerateLines { line, shouldStop in
            if isCancelled() { cancelled = true; shouldStop = true; return }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isRuleLine(trimmed) { seen.insert(ruleIdentity(trimmed)) }
        }
        return cancelled ? [] : seen
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

    /// uBO's `##selector:remove-attr(name)` and `:remove-class(name)` read
    /// as plain CSS to the converter, which merges them into the site's hiding
    /// selector and invalidates every sibling rule there (#918). Rewrite them
    /// as the equivalent AdGuard scriptlets.
    public static func adGuardEquivalent(_ rule: String) -> String {
        let trimmed = rule.trimmingCharacters(in: .whitespaces)
        guard let marker = ["#@#", "##"].lazy.compactMap({ trimmed.range(of: $0) }).first else {
            return expandingDenyAllow(trimmed) ?? droppingObjectType(trimmed) ?? rule
        }
        let exception = trimmed[marker] == "#@#"
        let body = trimmed[marker.upperBound...]
        for name in ["remove-attr", "remove-class"] where body.hasSuffix(")") {
            guard let pseudo = body.range(of: ":\(name)(", options: .backwards) else { continue }
            let selector = body[..<pseudo.lowerBound].trimmingCharacters(in: .whitespaces)
            let argument = body[pseudo.upperBound...].dropLast().trimmingCharacters(in: .whitespaces)
            // Regex arguments have no scriptlet form; they run as extended CSS below.
            guard !selector.isEmpty, !argument.isEmpty, !argument.hasPrefix("/"),
                  !argument.contains("("), !argument.contains(")") else { break }
            let quoted = { (value: String) in
                "'" + value.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'") + "'"
            }
            return trimmed[..<marker.lowerBound] + (exception ? "#@%#" : "#%#")
                + "//scriptlet(\(quoted(name)), \(quoted(argument)), \(quoted(selector)))"
        }
        // Syntax Safari's CSS engine does not know, anywhere in the selector
        // (#949), would be merged into the site's shared hiding selector, and
        // Safari rejects the merged selector whole. Run it as extended CSS instead.
        if body.contains(">>>") || hasUnknownFunctionalPseudo(body) {
            return trimmed[..<marker.lowerBound] + (exception ? "#@?#" : "#?#") + body
        }
        return rule
    }

    /// Safari has no plugin resource type, so the converter rejects any rule that
    /// names `object` (#975). Plugin requests never happen, so `~object` excludes
    /// nothing and `object` can go from a type list. A rule left with no other
    /// type would match everything instead of nothing, so it stays rejected.
    private static func droppingObjectType(_ rule: String) -> String? {
        guard let dollar = rule.lastIndex(of: "$") else { return nil }
        let options = rule[rule.index(after: dollar)...].split(separator: ",", omittingEmptySubsequences: false)
        let kept = options.filter { !["object", "~object"].contains($0.lowercased()) }
        guard kept.count < options.count else { return nil }
        if options.contains(where: { $0.lowercased() == "object" }),
           !kept.contains(where: { resourceTypes.contains($0.lowercased()) }) { return nil }
        return String(rule[..<dollar]) + (kept.isEmpty ? "" : "$" + kept.joined(separator: ","))
    }

    /// Content blockers can't exclude request domains from a block rule, so the
    /// converter rejects `denyallow` (#975). A pattern-less, site-scoped block
    /// with `denyallow=a.com|b.com` becomes the block plus one exception per
    /// allowed domain under the same options, one rule per line. An exception
    /// also lifts other lists' blocks of those domains on those sites, so only
    /// pattern-less rules are expanded; a pattern would widen it further.
    private static func expandingDenyAllow(_ rule: String) -> String? {
        guard !rule.hasPrefix("@@"), let dollar = rule.lastIndex(of: "$"),
              ["", "*"].contains(rule[..<dollar]) else { return nil }
        let options = rule[rule.index(after: dollar)...].split(separator: ",").map(String.init)
        guard let deny = options.first(where: { $0.lowercased().hasPrefix("denyallow=") }),
              options.contains(where: { $0.lowercased().hasPrefix("domain=") }),
              !options.contains(where: { $0.lowercased().hasPrefix("removeparam") }) else { return nil }
        let domains = deny.dropFirst("denyallow=".count).split(separator: "|")
        guard !domains.isEmpty, domains.allSatisfy({
            RemoveParamDNRRuleGenerator.isSupportedDomain($0.lowercased())
        }) else { return nil }
        let suffix = "$" + options.filter { $0 != deny }.joined(separator: ",")
        return ([suffix] + domains.map { "@@||\($0)^" + suffix }).joined(separator: "\n")
    }

    private static let resourceTypes: Set<String> = [
        "script", "image", "stylesheet", "css", "xmlhttprequest", "xhr", "subdocument", "frame",
        "media", "font", "websocket", "ping", "other", "document", "doc", "popup",
    ]

    /// Functional pseudo-classes WebKit compiles in content blocker selectors.
    private static let nativeFunctionalPseudos: Set<String> = [
        "has", "is", "not", "where", "matches", "lang", "dir",
        "nth-child", "nth-last-child", "nth-of-type", "nth-last-of-type",
    ]

    private static func hasUnknownFunctionalPseudo<S: StringProtocol>(_ selector: S) -> Bool {
        var quote: Character?
        var name: String?
        for character in selector {
            if let open = quote { if character == open { quote = nil }; continue }
            switch character {
            case "\"", "'": quote = character; name = nil
            case ":": name = ""
            case "(":
                if let pseudo = name?.lowercased(), !pseudo.isEmpty, !nativeFunctionalPseudos.contains(pseudo) { return true }
                name = nil
            default:
                if name != nil {
                    if character.isLetter || character.isNumber || character == "-" { name?.append(character) } else { name = nil }
                }
            }
        }
        return false
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
            let rewritten = adGuardEquivalent(trimmed).split(separator: "\n").map(String.init)
            let kinds = rewritten.map { classify($0, safariVersion: safariVersion) }
            lines.append(Line(text: raw, kind: kinds.first { $0 == .unsupported } ?? kinds[0]))
        }
        if stop { return FilterRuleAnalysis(lines: []) }
        return FilterRuleAnalysis(lines: lines)
    }

    static func classify(_ rule: String, safariVersion: SafariVersion) -> FilterRuleKind {
        if let supported = RemoveParamDNRRuleGenerator.supportsRule(rule) {
            return supported ? .removeParam : .unsupported
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
                    ? .advanced : .elementHiding
            }
            if let network = parsed as? NetworkRule, network.isWhiteList, network.isJsInject,
               !network.isDocumentWhiteList, !network.isCssExceptionRule {
                return .advanced
            }
            return .network
        } catch {
            return .unsupported
        }
    }
}
