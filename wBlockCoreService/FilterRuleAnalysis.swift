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

/// List text handled as UTF-8 bytes. Lists run to hundreds of thousands of
/// lines, and Character-based splitting, trimming and searching took most of
/// an update. Results match the Character-based calls they replace.
enum RuleText {
    enum EmptyLines {
        /// `split(whereSeparator: \.isNewline)`
        case omitted
        /// `split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)`
        case kept
        /// `components(separatedBy: .newlines)`, where CRLF holds an empty line.
        case keptPerScalar
    }

    /// The lines of `text`, split exactly as the call named by `emptyLines`, up to `limit`.
    static func forEachLine(
        _ text: String, emptyLines: EmptyLines = .omitted, limit: Int = .max, _ body: (Substring) throws -> Void
    ) rethrows {
        guard limit > 0 else { return }
        let keepingEmpty = emptyLines != .omitted
        var emitted = 0
        var text = text
        text.makeContiguousUTF8()
        let utf8 = text.utf8
        func line(_ from: Int, _ to: Int) -> Substring {
            text[utf8.index(utf8.startIndex, offsetBy: from)..<utf8.index(utf8.startIndex, offsetBy: to)]
        }
        let scanned: Void? = try utf8.withContiguousStorageIfAvailable { bytes in
            var start = 0
            var index = 0
            while index < bytes.count {
                let byte = bytes[index]
                let width: Int
                if byte == 0x0D, emptyLines == .kept, index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    width = 2
                } else if byte >= 0x0A && byte <= 0x0D {
                    width = 1
                } else if byte == 0xC2, index + 1 < bytes.count, bytes[index + 1] == 0x85 {
                    width = 2
                } else if byte == 0xE2, index + 2 < bytes.count, bytes[index + 1] == 0x80,
                          bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9 {
                    width = 3
                } else {
                    index += 1
                    continue
                }
                if keepingEmpty || index > start {
                    try body(line(start, index))
                    emitted += 1
                    if emitted == limit { return }
                }
                index += width
                start = index
            }
            if keepingEmpty || bytes.count > start { try body(line(start, bytes.count)) }
        }
        guard scanned == nil else { return }
        let pieces: [Substring]
        switch emptyLines {
        case .omitted: pieces = text.split(whereSeparator: \.isNewline)
        case .kept: pieces = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        case .keptPerScalar: pieces = text.components(separatedBy: .newlines).map { $0[...] }
        }
        for piece in pieces.prefix(limit) { try body(piece) }
    }

    static func lines(_ text: String, emptyLines: EmptyLines = .omitted, limit: Int = .max) -> [Substring] {
        var lines: [Substring] = []
        forEachLine(text, emptyLines: emptyLines, limit: limit) { lines.append($0) }
        return lines
    }

    /// `trimmingCharacters(in: .whitespaces)`, or `.whitespacesAndNewlines`.
    static func trimmed(_ text: String, newlines: Bool = false) -> Substring {
        trimmed(text[...], newlines: newlines)
    }

    static func trimmed(_ text: Substring, newlines: Bool = false) -> Substring {
        let utf8 = text.utf8
        func isSpace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || (newlines && byte >= 0x0A && byte <= 0x0D)
        }
        var start = utf8.startIndex
        var end = utf8.endIndex
        while start < end, isSpace(utf8[start]) { utf8.formIndex(after: &start) }
        while start < end, isSpace(utf8[utf8.index(before: end)]) { utf8.formIndex(before: &end) }
        // Other whitespace is never ASCII.
        if start < end, utf8[start] >= 0x80 || utf8[utf8.index(before: end)] >= 0x80 {
            return text[start..<end].trimmingCharacters(in: newlines ? .whitespacesAndNewlines : .whitespaces)[...]
        }
        return text[start..<end]
    }

    static func contains<S: StringProtocol>(_ text: S, _ needle: String) -> Bool where S.SubSequence == Substring {
        range(of: needle, in: text) != nil
    }

    /// The first byte-for-byte occurrence of `needle`.
    static func range<S: StringProtocol>(of needle: String, in text: S) -> Range<String.Index>? where S.SubSequence == Substring {
        let utf8 = text.utf8
        let offset: Int?? = utf8.withContiguousStorageIfAvailable { haystack in
            var needle = needle
            return needle.withUTF8 { needle -> Int? in
                guard needle.count > 0 else { return 0 }
                guard haystack.count >= needle.count, let base = haystack.baseAddress,
                      let found = memmem(base, haystack.count, needle.baseAddress, needle.count)
                else { return nil }
                return base.distance(to: found.assumingMemoryBound(to: UInt8.self))
            }
        }
        let start: String.Index
        if let offset {
            guard let offset else { return nil }
            start = utf8.index(utf8.startIndex, offsetBy: offset)
        } else {
            guard let found = utf8.indices.first(where: { utf8[$0...].starts(with: needle.utf8) }) else { return nil }
            start = found
        }
        return start..<utf8.index(start, offsetBy: needle.utf8.count)
    }

    /// Whether `text` holds `needle`, ignoring ASCII case. `needle` is lowercase ASCII.
    static func containsIgnoringASCIICase<S: StringProtocol>(_ text: S, _ needle: StaticString) -> Bool {
        let target = UnsafeBufferPointer(start: needle.utf8Start, count: needle.utf8CodeUnitCount)
        func search(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
            guard bytes.count >= target.count else { return target.isEmpty }
            var start = 0
            while start <= bytes.count - target.count {
                var matched = 0
                while matched < target.count {
                    let byte = bytes[start + matched]
                    guard (byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte) == target[matched] else { break }
                    matched += 1
                }
                if matched == target.count { return true }
                start += 1
            }
            return false
        }
        if let found = text.utf8.withContiguousStorageIfAvailable(search) { return found }
        return Array(text.utf8).withUnsafeBufferPointer(search)
    }

    /// `lowercased()`, without allocating when nothing changes case.
    static func lowercased(_ text: Substring) -> String {
        var hasUpper = false
        for byte in text.utf8 {
            if byte >= 0x80 { return text.lowercased() }
            if byte >= 0x41 && byte <= 0x5A { hasUpper = true }
        }
        guard hasUpper else { return String(text) }
        return String(decoding: text.utf8.map { $0 >= 0x41 && $0 <= 0x5A ? $0 | 0x20 : $0 }, as: UTF8.self)
    }

    static func needsLowercasing(_ text: Substring) -> Bool {
        text.utf8.contains { $0 >= 0x80 || ($0 >= 0x41 && $0 <= 0x5A) }
    }
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
        ruleIdentity(raw[...])
    }

    private static let cosmeticMarkers = ["##", "#@#", "#?#", "#@?#", "#$#", "#@$#", "#%#", "#@%#", "#$?#", "#@$?#"]

    static func ruleIdentity(_ raw: Substring) -> String {
        let rule = RuleText.trimmed(raw, newlines: true)
        let bytes = rule.utf8
        if let marker = bytes.firstIndex(of: UInt8(ascii: "#")),
           cosmeticMarkers.contains(where: { rule.utf8[marker...].starts(with: $0.utf8) }) {
            let domains = rule[..<marker]
            return domains.utf8.contains(UInt8(ascii: "/")) ? String(rule) : RuleText.lowercased(domains) + rule[marker...]
        }
        let isException = bytes.starts(with: "@@".utf8)
        let body = isException ? rule[bytes.index(bytes.startIndex, offsetBy: 2)...] : rule
        let dollar = body.utf8.firstIndex(of: UInt8(ascii: "$")) ?? body.endIndex
        let pattern = body[..<dollar]
        // Regex escapes such as \\D and \\d have different meanings.
        guard RuleText.needsLowercasing(pattern), pattern.utf8.first != UInt8(ascii: "/"),
              !body[dollar...].utf8.dropFirst().split(separator: UInt8(ascii: ",")).contains(where: {
                  $0.elementsEqual("match-case".utf8)
              })
        else { return String(rule) }
        return (isException ? "@@" : "") + RuleText.lowercased(pattern) + body[dollar...]
    }

    /// uBO's `##selector:remove-attr(name)` and `:remove-class(name)` read
    /// as plain CSS to the converter, which merges them into the site's hiding
    /// selector and invalidates every sibling rule there (#918). Rewrite them
    /// as the equivalent AdGuard scriptlets.
    public static func adGuardEquivalent(_ rule: String) -> String {
        let trimmed = String(RuleText.trimmed(rule))
        guard let marker = RuleText.range(of: "#@#", in: trimmed) ?? RuleText.range(of: "##", in: trimmed) else {
            // Only these options are rewritten outside cosmetic rules.
            guard !trimmed.utf8.allSatisfy({ $0 < 0x80 }) || RuleText.containsIgnoringASCIICase(trimmed, "denyallow")
                || RuleText.containsIgnoringASCIICase(trimmed, "object") else { return rule }
            return expandingDenyAllow(trimmed) ?? droppingObjectType(trimmed) ?? rule
        }
        let exception = trimmed[marker] == "#@#"
        let body = trimmed[marker.upperBound...]
        // Both rewrites below need a parenthesis or a shadow-DOM combinator.
        guard body.utf8.contains(UInt8(ascii: "(")) || RuleText.contains(body, ">>>") else { return rule }
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

    public static func isRuleLine<S: StringProtocol>(_ trimmed: S) -> Bool {
        let utf8 = trimmed.utf8
        guard let first = utf8.first, first != UInt8(ascii: "!"), first != UInt8(ascii: "[") else { return false }
        // "# comment" lines in hosts-style lists, but not "##selector" rules.
        if first == UInt8(ascii: "#") {
            let second = utf8.dropFirst().first
            if second == nil || second == UInt8(ascii: " ") { return false }
        }
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
