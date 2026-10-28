import Foundation
internal import WBEngine

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

    /// Non-overlapping byte-for-byte occurrences of `needle` in `data`.
    static func count(of needle: String, in data: Data) -> Int {
        var needle = needle
        return needle.withUTF8 { needle in
            data.withUnsafeBytes { haystack in
                guard let base = haystack.baseAddress, needle.count > 0 else { return 0 }
                var count = 0
                var offset = 0
                while let found = memmem(base + offset, haystack.count - offset, needle.baseAddress, needle.count) {
                    count += 1
                    offset = base.distance(to: UnsafeRawPointer(found)) + needle.count
                }
                return count
            }
        }
    }
}

/// Applied rules by kind, counted from the files Safari and wBlock Scripts
/// load (#978). Network rules are the Safari total less element hiding.
public struct AppliedRuleCounts: Sendable, Equatable {
    /// `css-display-none` rules across the content blockers.
    public var elementHiding: Int { elementHidingByTarget.values.reduce(0, +) }
    /// `css-display-none` rules per content blocker bundle identifier.
    public let elementHidingByTarget: [String: Int]
    /// Scriptlets, scripts, and extended CSS that wBlock Scripts applies.
    public let scripts: Int
    /// URL parameter and redirect rules, capped at `RemoveParamDNRRuleGenerator.maxGeneratedRules`.
    public let urlParameters: Int

    public static func load(targets: [ContentBlockerTargetInfo], groupIdentifier: String) -> AppliedRuleCounts {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        var elementHidingByTarget: [String: Int] = [:]
        var scripts = 0
        for target in targets {
            if let url = container?.appendingPathComponent(target.rulesFilename),
               let data = try? Data(contentsOf: url, options: .alwaysMapped) {
                // A quote inside a selector is escaped, so this only matches action types.
                elementHidingByTarget[target.bundleIdentifier] = RuleText.count(of: "\"css-display-none\"", in: data)
            }
            if let advanced = ContentBlockerIncrementalCache.loadCachedAdvancedRules(
                targetRulesFilename: target.rulesFilename, groupIdentifier: groupIdentifier, containerURL: container
            ) {
                // Only \n ends a rule here; scriptlet arguments may hold other line breaks.
                scripts += advanced.split(separator: "\n").filter { !RuleText.trimmed($0, newlines: true).isEmpty }.count
            }
        }
        let urlParameters = RemoveParamDNRRuleGenerator.loadRulesPayload(
            groupIdentifier: groupIdentifier, offset: 0, limit: 1
        )["count"] as? Int ?? 0
        return AppliedRuleCounts(elementHidingByTarget: elementHidingByTarget, scripts: scripts, urlParameters: urlParameters)
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
            lines.append(Line(text: raw, kind: classify(trimmed)))
        }
        if stop { return FilterRuleAnalysis(lines: []) }
        return FilterRuleAnalysis(lines: lines)
    }

    static func classify(_ rule: String) -> FilterRuleKind {
        if let supported = RemoveParamDNRRuleGenerator.supportsRule(rule) {
            return supported ? .removeParam : .unsupported
        }
        // The engine's own parse: procedural cosmetics and scriptlets need
        // wBlock Scripts; everything else Safari applies natively.
        guard let data = WBEngine.classify(line: rule),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .unsupported }
        switch parsed["status"] as? String {
        case "ignored": return .comment
        case "rule":
            switch parsed["kind"] as? String {
            case "network": return .network
            case "cosmetic":
                let body = parsed["body"] as? [String: Any]
                return body?["type"] as? String == "hide" ? .elementHiding : .advanced
            default: return .advanced
            }
        default: return .unsupported
        }
    }
}
