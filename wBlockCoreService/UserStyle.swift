//
//  UserStyle.swift
//  wBlockCoreService
//
//  Parsing, matching, and CSS assembly for UserCSS (.user.css) userstyles.
//
//  A userstyle carries a `/* ==UserStyle== ... ==/UserStyle== */` metadata block
//  and zero or more `@-moz-document` sections whose conditions decide which pages
//  receive the CSS. wBlock stores userstyles inside the regular userscript
//  pipeline (UserScript with isUserStyle == true); this enum is the single place
//  that understands the UserCSS format.
//
//  Supported preprocessors: none/"default" (variables become CSS custom
//  properties) and "uso" (textual /*[[name]]*/ substitution). Styles requiring
//  "less" or "stylus" need a full compiler and are rejected at import.
//

import Foundation

public enum UserStyleSupport {

    static let metadataStartMarker = "==UserStyle=="
    static let metadataEndMarker = "==/UserStyle=="

    /// Serialized-condition token meaning "CSS outside any @-moz-document block exists,
    /// so the style applies to every page".
    public static let globalConditionToken = "global"

    // MARK: - Detection

    /// True when the content carries a `==UserStyle== ... ==/UserStyle==` metadata block.
    public static func isUserStyleContent(_ content: String) -> Bool {
        guard let startRange = content.range(of: metadataStartMarker) else { return false }
        return content.range(of: metadataEndMarker, range: startRange.upperBound..<content.endIndex) != nil
    }

    /// True for URL paths / filenames that look like a userstyle source.
    public static func isUserStylePath(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.hasSuffix(".user.css") || lowercased.hasSuffix(".css")
    }

    /// Preprocessors wBlock can apply natively. "less"/"stylus" require a JS compiler.
    public static func isPreprocessorSupported(_ preprocessor: String) -> Bool {
        let normalized = preprocessor.trimmingCharacters(in: .whitespaces).lowercased()
        return normalized.isEmpty || normalized == "default" || normalized == "uso"
    }

    // MARK: - Model

    public struct Variable: Hashable, Sendable {
        public let name: String
        /// Default value with units already folded in (e.g. "16px", "#0021FF").
        public let value: String
    }

    public enum Condition: Hashable, Sendable {
        case url(String)
        case urlPrefix(String)
        case domain(String)
        case regexp(String)

        /// Compact `kind:value` form stored in `UserScript.matches` for persistence.
        public var serialized: String {
            switch self {
            case .url(let value): return "url:\(value)"
            case .urlPrefix(let value): return "url-prefix:\(value)"
            case .domain(let value): return "domain:\(value)"
            case .regexp(let value): return "regexp:\(value)"
            }
        }

        public init?(serialized: String) {
            if serialized.hasPrefix("url-prefix:") {
                self = .urlPrefix(String(serialized.dropFirst("url-prefix:".count)))
            } else if serialized.hasPrefix("url:") {
                self = .url(String(serialized.dropFirst("url:".count)))
            } else if serialized.hasPrefix("domain:") {
                self = .domain(String(serialized.dropFirst("domain:".count)))
            } else if serialized.hasPrefix("regexp:") {
                self = .regexp(String(serialized.dropFirst("regexp:".count)))
            } else {
                return nil
            }
        }

        public func matches(url: String) -> Bool {
            switch self {
            case .url(let value):
                return url == value
            case .urlPrefix(let value):
                return url.hasPrefix(value)
            case .domain(let value):
                guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
                let target = value.lowercased()
                return host == target || host.hasSuffix(".\(target)")
            case .regexp(let pattern):
                guard let regex = Self.cachedRegex(for: pattern) else { return false }
                let range = NSRange(location: 0, length: url.utf16.count)
                guard let match = regex.firstMatch(in: url, options: [.anchored], range: range) else {
                    return false
                }
                // @-moz-document regexp() must match the entire URL.
                return match.range == range
            }
        }

        private static let regexCache: NSCache<NSString, NSRegularExpression> = {
            let cache = NSCache<NSString, NSRegularExpression>()
            cache.countLimit = 256
            return cache
        }()

        private static func cachedRegex(for pattern: String) -> NSRegularExpression? {
            let key = pattern as NSString
            if let cached = regexCache.object(forKey: key) { return cached }
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            regexCache.setObject(regex, forKey: key)
            return regex
        }
    }

    public struct Section: Hashable, Sendable {
        public let conditions: [Condition]
        public let css: String

        public func matches(url: String) -> Bool {
            conditions.contains { $0.matches(url: url) }
        }
    }

    public struct ParsedStyle: Sendable {
        public let name: String?
        public let description: String?
        public let version: String?
        public let updateURL: String?
        public let preprocessor: String
        public let variables: [Variable]
        public let globalCSS: String
        public let sections: [Section]

        public var isPreprocessorSupported: Bool {
            UserStyleSupport.isPreprocessorSupported(preprocessor)
        }

        var hasGlobalCSS: Bool {
            UserStyleSupport.containsGlobalApplicableCSS(globalCSS)
        }

        /// Conditions persisted into `UserScript.matches` so per-URL filtering works
        /// without re-reading style content from disk.
        public var serializedConditions: [String] {
            var seen = Set<String>()
            var result: [String] = []
            if hasGlobalCSS {
                result.append(UserStyleSupport.globalConditionToken)
            }
            for section in sections {
                for condition in section.conditions {
                    let serialized = condition.serialized
                    if seen.insert(serialized).inserted {
                        result.append(serialized)
                    }
                }
            }
            return result
        }
    }

    // MARK: - Matching

    /// Matches a URL against conditions previously persisted via `serializedConditions`.
    public static func matches(serializedConditions: [String], url: String) -> Bool {
        for raw in serializedConditions {
            if raw == globalConditionToken { return true }
            if let condition = Condition(serialized: raw), condition.matches(url: url) {
                return true
            }
        }
        return false
    }

    // MARK: - Parsing (cached)

    private final class ParsedStyleBox {
        let value: ParsedStyle
        init(_ value: ParsedStyle) { self.value = value }
    }

    private static let parseCache: NSCache<NSString, ParsedStyleBox> = {
        let cache = NSCache<NSString, ParsedStyleBox>()
        cache.countLimit = 64
        return cache
    }()

    /// Parses userstyle content, returning nil when no UserStyle metadata block exists.
    /// Results are cached by content identity; repeated per-page-load calls are cheap.
    public static func parsed(from content: String) -> ParsedStyle? {
        guard isUserStyleContent(content) else { return nil }
        let key = content as NSString
        if let cached = parseCache.object(forKey: key) { return cached.value }
        let parsed = parse(content)
        parseCache.setObject(ParsedStyleBox(parsed), forKey: key)
        return parsed
    }

    // MARK: - Effective CSS

    /// Assembles the CSS a page at `url` should receive: global CSS plus every
    /// matching `@-moz-document` section, with variables applied per preprocessor.
    /// Returns nil when nothing applies.
    public static func effectiveCSS(forContent content: String, url: String) -> String? {
        guard let parsed = parsed(from: content) else { return nil }

        var sectionPieces: [String] = []
        for section in parsed.sections where section.matches(url: url) {
            let css = section.css.trimmingCharacters(in: .whitespacesAndNewlines)
            if !css.isEmpty {
                sectionPieces.append(css)
            }
        }

        var pieces: [String] = []
        let trimmedGlobal = parsed.globalCSS.trimmingCharacters(in: .whitespacesAndNewlines)
        // Global CSS rides along when the style is genuinely global, or when a
        // section matched and the preamble carries @namespace declarations the
        // section selectors may rely on.
        if containsGlobalApplicableCSS(trimmedGlobal)
            || (!sectionPieces.isEmpty && containsMeaningfulCSS(trimmedGlobal))
        {
            pieces.append(trimmedGlobal)
        }
        pieces.append(contentsOf: sectionPieces)
        guard !pieces.isEmpty else { return nil }

        let joined = pieces.joined(separator: "\n\n")
        return applyingVariables(parsed.variables, preprocessor: parsed.preprocessor, to: joined)
    }

    /// True when the text contains anything besides whitespace and block comments.
    /// USO styles routinely carry decorative comment headers outside their
    /// @-moz-document sections; those must not make a style apply globally.
    static func containsMeaningfulCSS(_ text: String) -> Bool {
        containsCSSContent(text, ignoringNamespaceRules: false)
    }

    /// Like `containsMeaningfulCSS`, but additionally ignores `@namespace …;`
    /// declarations. A namespace-only preamble (typical of USO conversions) must
    /// not make a style apply to every page, yet still ships with matching
    /// sections because their selectors may rely on it.
    static func containsGlobalApplicableCSS(_ text: String) -> Bool {
        containsCSSContent(text, ignoringNamespaceRules: true)
    }

    private static let namespaceKeyword = Array("@namespace".utf8)

    private static func containsCSSContent(_ text: String, ignoringNamespaceRules: Bool) -> Bool {
        let bytes = Array(text.utf8)
        let count = bytes.count
        var index = 0
        while index < count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "/"), index + 1 < count, bytes[index + 1] == UInt8(ascii: "*") {
                var closed = false
                index += 2
                while index + 1 < count {
                    if bytes[index] == UInt8(ascii: "*"), bytes[index + 1] == UInt8(ascii: "/") {
                        index += 2
                        closed = true
                        break
                    }
                    index += 1
                }
                if !closed { return false }  // Unterminated comment swallows the rest.
                continue
            }
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n")
                || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t")
            {
                index += 1
                continue
            }
            if ignoringNamespaceRules,
               byte == UInt8(ascii: "@"),
               index + namespaceKeyword.count <= count,
               Array(bytes[index..<(index + namespaceKeyword.count)]) == namespaceKeyword
            {
                // Skip to the terminating semicolon, honoring quoted strings.
                index += namespaceKeyword.count
                scanDeclaration: while index < count {
                    let current = bytes[index]
                    if current == UInt8(ascii: "\"") || current == UInt8(ascii: "'") {
                        let quote = current
                        index += 1
                        while index < count {
                            if bytes[index] == UInt8(ascii: "\\") {
                                index += 2
                                continue
                            }
                            if bytes[index] == quote {
                                index += 1
                                continue scanDeclaration
                            }
                            index += 1
                        }
                        continue
                    }
                    if current == UInt8(ascii: ";") {
                        index += 1
                        break
                    }
                    index += 1
                }
                continue
            }
            return true
        }
        return false
    }

    private static func applyingVariables(
        _ variables: [Variable],
        preprocessor: String,
        to css: String
    ) -> String {
        guard !variables.isEmpty else { return css }

        let normalized = preprocessor.trimmingCharacters(in: .whitespaces).lowercased()
        if normalized == "uso" {
            // USO styles reference variables via /*[[name]]*/ placeholders. Unresolved
            // placeholders stay behind as harmless CSS comments.
            var substituted = css
            for variable in variables {
                substituted = substituted.replacingOccurrences(
                    of: "/*[[\(variable.name)]]*/",
                    with: variable.value
                )
            }
            return substituted
        }

        // Default preprocessor: expose variables as CSS custom properties.
        var prelude = ":root {\n"
        for variable in variables {
            prelude += "  --\(variable.name): \(variable.value);\n"
        }
        prelude += "}\n\n"
        return prelude + css
    }

    // MARK: - Parser internals

    private static func parse(_ content: String) -> ParsedStyle {
        var metadata = MetadataAccumulator()
        var body = content

        if let metaStart = content.range(of: metadataStartMarker),
           let metaEnd = content.range(of: metadataEndMarker, range: metaStart.upperBound..<content.endIndex)
        {
            metadata = parseMetadataDirectives(String(content[metaStart.upperBound..<metaEnd.lowerBound]))

            // Drop the comment hosting the metadata block from the CSS body.
            let commentStart = content.range(
                of: "/*",
                options: .backwards,
                range: content.startIndex..<metaStart.lowerBound
            )?.lowerBound ?? metaStart.lowerBound
            let commentEnd = content.range(
                of: "*/",
                range: metaEnd.upperBound..<content.endIndex
            )?.upperBound ?? metaEnd.upperBound

            var stripped = String()
            stripped.reserveCapacity(content.count)
            stripped.append(contentsOf: content[..<commentStart])
            stripped.append(contentsOf: content[commentEnd...])
            body = stripped
        }

        let (globalCSS, sections) = parseSections(body)

        return ParsedStyle(
            name: metadata.name,
            description: metadata.description,
            version: metadata.version,
            updateURL: metadata.updateURL,
            preprocessor: metadata.preprocessor ?? "default",
            variables: metadata.variables,
            globalCSS: globalCSS,
            sections: sections
        )
    }

    // MARK: Metadata directives

    private struct MetadataAccumulator {
        var name: String?
        var description: String?
        var version: String?
        var updateURL: String?
        var preprocessor: String?
        var variables: [Variable] = []
    }

    private static func parseMetadataDirectives(_ text: String) -> MetadataAccumulator {
        var accumulator = MetadataAccumulator()
        let lines = text.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            var line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1

            // Tolerate decorative comment continuation prefixes ("* @name ...").
            if line.hasPrefix("*") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard line.hasPrefix("@") else { continue }

            let split = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard let keyPart = split.first else { continue }
            let key = String(keyPart)
            let value = split.count > 1 ? String(split[1]).trimmingCharacters(in: .whitespaces) : ""

            switch key {
            case "@name":
                if !value.isEmpty { accumulator.name = value }
            case "@description":
                if !value.isEmpty { accumulator.description = value }
            case "@version":
                if !value.isEmpty { accumulator.version = value }
            case "@updateURL":
                if !value.isEmpty { accumulator.updateURL = value }
            case "@preprocessor":
                if !value.isEmpty { accumulator.preprocessor = value.lowercased() }
            case "@var":
                if let variable = parseVarDirective(value, lines: lines, index: &index) {
                    accumulator.variables.append(variable)
                }
            case "@advanced":
                if let variable = parseAdvancedDirective(value, lines: lines, index: &index) {
                    accumulator.variables.append(variable)
                }
            default:
                break
            }
        }

        return accumulator
    }

    /// `@var <type> <name> <label> <default>` — label is a quoted string or bare token.
    private static func parseVarDirective(_ value: String, lines: [String], index: inout Int) -> Variable? {
        var scanner = TokenScanner(value)
        guard let type = scanner.scanBareToken()?.lowercased(),
              let name = scanner.scanBareToken(),
              scanner.scanLabel() != nil
        else { return nil }

        var remainder = scanner.remainder()
        if needsBlockContinuation(remainder) {
            remainder = consumeBalancedBlock(startingWith: remainder, lines: lines, index: &index)
        }
        guard !remainder.isEmpty else { return nil }

        switch type {
        case "color":
            return Variable(name: name, value: remainder)
        case "checkbox":
            return Variable(name: name, value: remainder.hasPrefix("1") ? "1" : "0")
        case "text":
            return Variable(name: name, value: unquoted(remainder))
        case "number", "range":
            return resolvedNumericVariable(name: name, from: remainder)
        case "select", "dropdown", "image":
            return resolvedOptionVariable(name: name, type: type, from: remainder)
        default:
            // Unknown variable type: keep the raw default so placeholders still resolve.
            return Variable(name: name, value: unquoted(remainder))
        }
    }

    /// `@advanced <type> <name> <label> <default-or-block>` (USO archive convention).
    private static func parseAdvancedDirective(_ value: String, lines: [String], index: inout Int) -> Variable? {
        var scanner = TokenScanner(value)
        guard let type = scanner.scanBareToken()?.lowercased(),
              let name = scanner.scanBareToken(),
              scanner.scanLabel() != nil
        else { return nil }

        var remainder = scanner.remainder()
        if needsBlockContinuation(remainder) {
            remainder = consumeBalancedBlock(startingWith: remainder, lines: lines, index: &index)
        }
        guard !remainder.isEmpty else { return nil }

        switch type {
        case "color":
            return Variable(name: name, value: remainder)
        case "text":
            return Variable(name: name, value: unquoted(remainder))
        case "dropdown", "image":
            return resolvedOptionVariable(name: name, type: type, from: remainder)
        default:
            return Variable(name: name, value: unquoted(remainder))
        }
    }

    /// A `{`/`[` default that does not balance on its own line spans multiple lines.
    private static func needsBlockContinuation(_ remainder: String) -> Bool {
        guard remainder.hasPrefix("{") || remainder.hasPrefix("[") else { return false }
        return !isBalancedBlock(remainder)
    }

    private static func isBalancedBlock(_ text: String) -> Bool {
        var depth = 0
        var inString: Character? = nil
        var inEOT = false
        var rest = Substring(text)

        while let char = rest.first {
            if inEOT {
                if rest.hasPrefix("EOT;") {
                    inEOT = false
                    rest = rest.dropFirst(4)
                    continue
                }
                rest = rest.dropFirst()
                continue
            }
            if let quote = inString {
                if char == "\\" {
                    rest = rest.dropFirst(2)
                    continue
                }
                if char == quote { inString = nil }
                rest = rest.dropFirst()
                continue
            }
            if rest.hasPrefix("<<<EOT") {
                inEOT = true
                rest = rest.dropFirst(6)
                continue
            }
            switch char {
            case "\"", "'": inString = char
            case "{", "[": depth += 1
            case "}", "]": depth -= 1
            default: break
            }
            rest = rest.dropFirst()
            if depth == 0 { return true }
        }
        return depth <= 0
    }

    private static func consumeBalancedBlock(startingWith first: String, lines: [String], index: inout Int) -> String {
        var block = first
        while !isBalancedBlock(block), index < lines.count {
            block += "\n" + lines[index]
            index += 1
        }
        return block
    }

    /// number/range defaults: bare `16` or array `[16, 0, 50, 1, "px"]`.
    private static func resolvedNumericVariable(name: String, from remainder: String) -> Variable? {
        let trimmed = remainder.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") else {
            return Variable(name: name, value: trimmed)
        }
        guard let data = trimmed.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return Variable(name: name, value: trimmed) }

        var defaultNumber: String?
        var unit = ""
        for element in array {
            if defaultNumber == nil, let number = element as? NSNumber, !(element is NSNull) {
                defaultNumber = Self.compactNumberString(number)
            }
            if let text = element as? String {
                unit = text
            }
        }
        guard let resolved = defaultNumber else { return Variable(name: name, value: trimmed) }
        return Variable(name: name, value: resolved + unit)
    }

    private static func compactNumberString(_ number: NSNumber) -> String {
        let doubleValue = number.doubleValue
        if doubleValue.rounded() == doubleValue, abs(doubleValue) < 1e15 {
            return String(Int64(doubleValue))
        }
        return String(doubleValue)
    }

    /// select/dropdown/image defaults: ordered option lists where a label suffixed
    /// with `*` marks the default; otherwise the first option wins.
    private static func resolvedOptionVariable(name: String, type: String, from remainder: String) -> Variable? {
        var options: [(label: String, value: String)] = []

        if type == "dropdown" || remainder.contains("<<<EOT") {
            options = scanEOTOptions(remainder)
        }
        if options.isEmpty {
            options = scanPairOptions(remainder)
        }
        if options.isEmpty {
            options = scanArrayOptions(remainder)
        }
        guard !options.isEmpty else { return nil }

        let chosen = options.first(where: { $0.label.hasSuffix("*") }) ?? options[0]
        return Variable(name: name, value: chosen.value)
    }

    /// `optName "Label" <<<EOT ... EOT;` blocks (USO @advanced dropdown).
    private static func scanEOTOptions(_ block: String) -> [(label: String, value: String)] {
        var options: [(String, String)] = []
        var rest = Substring(block)

        while let labelStart = rest.firstIndex(of: "\"") {
            let afterLabelStart = rest.index(after: labelStart)
            guard let labelEnd = rest[afterLabelStart...].firstIndex(of: "\"") else { break }
            let label = String(rest[afterLabelStart..<labelEnd])
            rest = rest[rest.index(after: labelEnd)...]

            guard let eotStart = rest.range(of: "<<<EOT") else { continue }
            guard let eotEnd = rest.range(of: "EOT;", range: eotStart.upperBound..<rest.endIndex) else { break }
            let value = String(rest[eotStart.upperBound..<eotEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            options.append((label, value))
            rest = rest[eotEnd.upperBound...]
        }
        return options
    }

    /// `"Label": "value"` pairs (JSON-style select map) or `optName "Label" "value"`
    /// lines (USO @advanced image), scanned in source order.
    private static func scanPairOptions(_ block: String) -> [(label: String, value: String)] {
        var options: [(String, String)] = []
        var strings: [String] = []
        var separators: [Character] = []

        var rest = Substring(block)
        while let quoteStart = rest.firstIndex(of: "\"") {
            var cursor = rest.index(after: quoteStart)
            var value = ""
            var closed = false
            while cursor < rest.endIndex {
                let char = rest[cursor]
                if char == "\\" {
                    let next = rest.index(after: cursor)
                    if next < rest.endIndex {
                        value.append(rest[next])
                        cursor = rest.index(after: next)
                        continue
                    }
                }
                if char == "\"" {
                    closed = true
                    cursor = rest.index(after: cursor)
                    break
                }
                value.append(char)
                cursor = rest.index(after: cursor)
            }
            guard closed else { break }

            strings.append(value)
            // Record whether this string is followed by ':' (a JSON map key).
            let tail = rest[cursor...]
            let nextMeaningful = tail.first(where: { !$0.isWhitespace })
            separators.append(nextMeaningful ?? " ")
            rest = tail
        }

        var index = 0
        while index < strings.count {
            if separators[index] == ":", index + 1 < strings.count {
                options.append((strings[index], strings[index + 1]))
                index += 2
            } else if index + 1 < strings.count, separators[index] != ":", separators[index + 1] != ":" {
                // `optName "Label" "value"` image form: pair consecutive plain strings.
                options.append((strings[index], strings[index + 1]))
                index += 2
            } else {
                index += 1
            }
        }
        return options
    }

    /// Plain JSON array form: `["a", "b*"]` — values double as labels.
    private static func scanArrayOptions(_ block: String) -> [(label: String, value: String)] {
        let trimmed = block.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [] }

        return array.compactMap { element in
            guard let text = element as? String else { return nil }
            let value = text.hasSuffix("*") ? String(text.dropLast()) : text
            return (label: text, value: value)
        }
    }

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'"))
        {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    /// Minimal token scanner for `@var`/`@advanced` directive lines.
    private struct TokenScanner {
        private var rest: Substring

        init(_ text: String) {
            rest = Substring(text)
        }

        mutating func skipWhitespace() {
            rest = rest.drop(while: { $0.isWhitespace })
        }

        mutating func scanBareToken() -> String? {
            skipWhitespace()
            let token = rest.prefix(while: { !$0.isWhitespace })
            guard !token.isEmpty else { return nil }
            rest = rest.dropFirst(token.count)
            return String(token)
        }

        /// Scans a quoted label (single or double quotes) or a bare token.
        mutating func scanLabel() -> String? {
            skipWhitespace()
            guard let first = rest.first else { return nil }
            guard first == "\"" || first == "'" else { return scanBareToken() }

            var cursor = rest.index(after: rest.startIndex)
            var label = ""
            while cursor < rest.endIndex {
                let char = rest[cursor]
                if char == "\\" {
                    let next = rest.index(after: cursor)
                    if next < rest.endIndex {
                        label.append(rest[next])
                        cursor = rest.index(after: next)
                        continue
                    }
                }
                if char == first {
                    rest = rest[rest.index(after: cursor)...]
                    return label
                }
                label.append(char)
                cursor = rest.index(after: cursor)
            }
            return nil
        }

        func remainder() -> String {
            rest.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: Section parsing

    private static let mozDocumentKeyword = Array("@-moz-document".utf8)

    private static func parseSections(_ body: String) -> (globalCSS: String, sections: [Section]) {
        let bytes = Array(body.utf8)
        let count = bytes.count
        var sections: [Section] = []
        var globalRanges: [Range<Int>] = []
        var globalStart = 0
        var index = 0

        func skipString(from start: Int) -> Int {
            let quote = bytes[start]
            var cursor = start + 1
            while cursor < count {
                if bytes[cursor] == UInt8(ascii: "\\") {
                    cursor += 2
                    continue
                }
                if bytes[cursor] == quote { return cursor + 1 }
                cursor += 1
            }
            return count
        }

        func skipComment(from start: Int) -> Int {
            var cursor = start + 2
            while cursor + 1 < count {
                if bytes[cursor] == UInt8(ascii: "*"), bytes[cursor + 1] == UInt8(ascii: "/") {
                    return cursor + 2
                }
                cursor += 1
            }
            return count
        }

        while index < count {
            let byte = bytes[index]

            if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                index = skipString(from: index)
                continue
            }
            if byte == UInt8(ascii: "/"), index + 1 < count, bytes[index + 1] == UInt8(ascii: "*") {
                index = skipComment(from: index)
                continue
            }
            if byte == UInt8(ascii: "@"),
               index + mozDocumentKeyword.count <= count,
               Array(bytes[index..<(index + mozDocumentKeyword.count)]) == mozDocumentKeyword
            {
                let sectionStart = index
                var cursor = index + mozDocumentKeyword.count
                var conditions: [Condition] = []

                // Parse the comma-separated condition list up to the opening brace.
                parseConditions: while cursor < count {
                    let current = bytes[cursor]
                    if current == UInt8(ascii: "{") { break }
                    if current == UInt8(ascii: "/"), cursor + 1 < count, bytes[cursor + 1] == UInt8(ascii: "*") {
                        cursor = skipComment(from: cursor)
                        continue
                    }
                    if current == UInt8(ascii: ",") || current == UInt8(ascii: " ")
                        || current == UInt8(ascii: "\n") || current == UInt8(ascii: "\r")
                        || current == UInt8(ascii: "\t")
                    {
                        cursor += 1
                        continue
                    }
                    // Read a function identifier.
                    var identifierEnd = cursor
                    while identifierEnd < count {
                        let c = bytes[identifierEnd]
                        let isIdentifierByte = (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
                            || (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
                            || c == UInt8(ascii: "-")
                        if !isIdentifierByte { break }
                        identifierEnd += 1
                    }
                    guard identifierEnd > cursor, identifierEnd < count,
                          bytes[identifierEnd] == UInt8(ascii: "(")
                    else {
                        // Malformed condition list; abandon this @-moz-document.
                        break parseConditions
                    }

                    let identifier = String(decoding: bytes[cursor..<identifierEnd], as: UTF8.self).lowercased()

                    // Read the argument up to the matching close paren, respecting quotes.
                    var argumentCursor = identifierEnd + 1
                    var argumentBytes: [UInt8] = []
                    var argumentClosed = false
                    while argumentCursor < count {
                        let argByte = bytes[argumentCursor]
                        if argByte == UInt8(ascii: "\"") || argByte == UInt8(ascii: "'") {
                            let stringEnd = skipString(from: argumentCursor)
                            argumentBytes.append(contentsOf: bytes[argumentCursor..<stringEnd])
                            argumentCursor = stringEnd
                            continue
                        }
                        if argByte == UInt8(ascii: ")") {
                            argumentClosed = true
                            argumentCursor += 1
                            break
                        }
                        argumentBytes.append(argByte)
                        argumentCursor += 1
                    }
                    guard argumentClosed else { break parseConditions }

                    let rawArgument = String(decoding: argumentBytes, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let argument = unescapedConditionArgument(rawArgument)

                    switch identifier {
                    case "url": conditions.append(.url(argument))
                    case "url-prefix": conditions.append(.urlPrefix(argument))
                    case "domain": conditions.append(.domain(argument))
                    case "regexp": conditions.append(.regexp(argument))
                    default: break  // Unknown condition functions are ignored.
                    }
                    cursor = argumentCursor
                }

                guard cursor < count, bytes[cursor] == UInt8(ascii: "{") else {
                    // No block found; treat the @-moz-document text as global CSS.
                    index = sectionStart + mozDocumentKeyword.count
                    continue
                }

                // Capture the block body with brace matching.
                let cssStart = cursor + 1
                var depth = 1
                var blockCursor = cssStart
                while blockCursor < count, depth > 0 {
                    let blockByte = bytes[blockCursor]
                    if blockByte == UInt8(ascii: "\"") || blockByte == UInt8(ascii: "'") {
                        blockCursor = skipString(from: blockCursor)
                        continue
                    }
                    if blockByte == UInt8(ascii: "/"), blockCursor + 1 < count,
                       bytes[blockCursor + 1] == UInt8(ascii: "*")
                    {
                        blockCursor = skipComment(from: blockCursor)
                        continue
                    }
                    if blockByte == UInt8(ascii: "{") { depth += 1 }
                    if blockByte == UInt8(ascii: "}") { depth -= 1 }
                    blockCursor += 1
                }

                let cssEnd = depth == 0 ? blockCursor - 1 : blockCursor
                let css = String(decoding: bytes[cssStart..<cssEnd], as: UTF8.self)
                if !conditions.isEmpty {
                    sections.append(Section(conditions: conditions, css: css))
                }

                globalRanges.append(globalStart..<sectionStart)
                index = blockCursor
                globalStart = index
                continue
            }

            index += 1
        }

        globalRanges.append(globalStart..<count)

        var globalCSS = String()
        for range in globalRanges where !range.isEmpty {
            globalCSS += String(decoding: bytes[range], as: UTF8.self)
        }
        return (globalCSS, sections)
    }

    /// Unwraps a possibly-quoted condition argument and resolves backslash escapes
    /// (CSS strings escape quotes and backslashes; regexp patterns arrive doubled).
    private static func unescapedConditionArgument(_ raw: String) -> String {
        guard raw.count >= 2, let first = raw.first, first == "\"" || first == "'",
              raw.hasSuffix(String(first))
        else { return raw }

        let inner = raw.dropFirst().dropLast()
        var result = ""
        result.reserveCapacity(inner.count)
        var pendingEscape = false
        for char in inner {
            if pendingEscape {
                result.append(char)
                pendingEscape = false
                continue
            }
            if char == "\\" {
                pendingEscape = true
                continue
            }
            result.append(char)
        }
        if pendingEscape { result.append("\\") }
        return result
    }
}
