import Foundation
internal import WBEngine

extension RemoveParamDNRRuleGenerator {
    public static let pageRulesFilename = "removeparam_page_rules.json"

    /// Safari cannot redirect top-level loads on every supported release. Keep
    /// the original selectors for history.replaceState, including value regexes.
    struct PageRule: Codable {
        var rule: ParsedRule
        var excludedSites: [String] = []
        var includedSites: [String]? = nil
    }

    static func pageRule(_ line: String) -> PageRule? {
        guard let rule = parseRule(line), !rule.options.contains("badfilter"), !rule.options.contains(where: { optionNameAndValue($0).name == "method" }),
              !containsUnsupportedCriticalOptions(rule.options.map(optionNameAndValue)),
              urlPatternRegex(rule.pattern, caseSensitive: rule.options.contains("match-case")) != nil
        else { return nil }
        for option in rule.options.map(optionNameAndValue) where ["domain", "to", "denyallow"].contains(option.name) {
            guard let value = option.value, !value.isEmpty else { return nil }
            for part in value.split(separator: "|", omittingEmptySubsequences: false) {
                let domain = part.hasPrefix("~") ? String(part.dropFirst()) : String(part)
                let literal = domain.hasSuffix(".*") ? String(domain.dropLast(2)) : domain
                guard isSupportedDomain(literal), !(option.name == "denyallow" && part.hasPrefix("~")) else { return nil }
            }
        }
        var value = rule.removeParamValue ?? ""
        if value.hasPrefix("~") { value.removeFirst() }
        if isRegexRemoveValue(value) || value.hasPrefix("|") {
            guard selectorRegex(value) != nil else { return nil }
        } else if value.contains("|") || (value.isEmpty && rule.removeParamValue == "~") { return nil }
        return PageRule(rule: rule)
    }

    static func generatePageRules(from text: String) -> [PageRule] {
        activeRulesText(text).components(separatedBy: .newlines).compactMap(pageRule)
    }

    private static let expressionCache = NSCache<NSString, NSRegularExpression>()

    private static func selectorRegex(_ value: String) -> NSRegularExpression? {
        let key = "selector:" + value
        if let cached = expressionCache.object(forKey: key as NSString) { return cached }
        let regex = value.hasPrefix("|")
            ? try? NSRegularExpression(pattern: "^" + value.dropFirst(), options: [.caseInsensitive])
            : compiledRemoveParamRegex(value.replacingOccurrences(of: "\\,", with: ","))
        if let regex { expressionCache.setObject(regex, forKey: key as NSString) }
        return regex
    }

    private static func urlPatternRegex(_ pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
        let key = "url:\(caseSensitive):" + pattern
        if let cached = expressionCache.object(forKey: key as NSString) { return cached }
        var source: String
        if pattern.hasPrefix("/"), pattern.hasSuffix("/"), pattern.count > 1 {
            source = String(pattern.dropFirst().dropLast())
        } else {
            var text = pattern
            let hostAnchor = text.hasPrefix("||")
            if hostAnchor { text.removeFirst(2) }
            let start = !hostAnchor && text.hasPrefix("|")
            if start { text.removeFirst() }
            let end = text.hasSuffix("|")
            if end { text.removeLast() }
            source = hostAnchor ? "^https?://(?:[^/?#@]*\\.)?" : (start ? "^" : "")
            for char in text {
                switch char {
                case "*": source += ".*"
                case "^": source += "(?:[^A-Za-z0-9_.%-]|$)"
                default: source += NSRegularExpression.escapedPattern(for: String(char))
                }
            }
            if end { source += "$" }
        }
        let regex = try? NSRegularExpression(pattern: source.isEmpty ? ".*" : source, options: caseSensitive ? [] : [.caseInsensitive])
        if let regex { expressionCache.setObject(regex, forKey: key as NSString) }
        return regex
    }

    /// The host a page rule is matched against, with its entity form (the
    /// host without its public suffix) derived once.
    private struct PageHost {
        let name: String
        private(set) lazy var entity: String? = WBEngine.registrableDomain(of: name)
            .flatMap { root in root.firstIndex(of: ".").map { String(name.dropLast(root[$0...].count)) } }

        init(_ name: String) { self.name = name }

        /// `domain` is lowercased.
        mutating func matches(_ domain: String) -> Bool {
            if domain.hasSuffix(".*") {
                // Entity boundaries use the same PSL as the network engine. In
                // particular, transfernow.co.uk matches but transfernow.evil.com does not.
                guard let entityHost = entity else { return false }
                let entity = String(domain.dropLast(2))
                return entityHost == entity || entityHost.hasSuffix("." + entity)
            }
            return name == domain || name.hasSuffix("." + domain)
        }

        mutating func inScope(_ domains: [String]) -> Bool {
            if domains.contains(where: { $0.hasPrefix("~") && matches(String($0.dropFirst())) }) { return false }
            let included = domains.filter { !$0.hasPrefix("~") }
            return included.isEmpty || included.contains { matches($0) }
        }
    }

    /// A page rule that can apply to a top-level page, with its options
    /// parsed and its domains lowercased once rather than on every page.
    struct PreparedPageRule {
        let rule: ParsedRule
        let excludedSites: [String]
        let includedSites: [String]?
        /// Each `domain` and `to` list.
        let scopes: [[String]]
        /// Each `denyallow` list.
        let denyallow: [[String]]
        let caseSensitive: Bool
        /// Bytes every URL the pattern matches contains, lowercased unless
        /// `caseSensitive`; empty when there are none to test.
        let literal: [UInt8]
    }

    static func prepare(_ rules: [PageRule]) -> [PreparedPageRule] {
        rules.compactMap { page in
            let pairs = page.rule.options.map(optionNameAndValue)
            if let types = resourceTypes(from: pairs), !types.contains("main_frame") { return nil }
            if pairs.contains(where: { $0.name == "third-party" }) { return nil }
            let caseSensitive = page.rule.options.contains("match-case")
            let lists = { (names: [String]) in
                pairs.filter { names.contains($0.name) }.map { ($0.value ?? "").split(separator: "|").map { $0.lowercased() } }
            }
            return PreparedPageRule(
                rule: page.rule,
                excludedSites: page.excludedSites.map { $0.lowercased() },
                includedSites: page.includedSites?.map { $0.lowercased() },
                scopes: lists(["domain", "to"]),
                denyallow: lists(["denyallow"]),
                caseSensitive: caseSensitive,
                literal: requiredLiteral(page.rule.pattern, caseSensitive: caseSensitive)
            )
        }
    }

    /// The longest run of a pattern that `urlPatternRegex` escapes as literal
    /// text, lowercased unless `caseSensitive`; empty for a regex pattern or a
    /// run that is not ASCII.
    private static func requiredLiteral(_ pattern: String, caseSensitive: Bool) -> [UInt8] {
        if pattern.hasPrefix("/"), pattern.hasSuffix("/"), pattern.count > 1 { return [] }
        var text = Substring(pattern)
        if text.hasPrefix("||") { text.removeFirst(2) } else if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        let longest = text.utf8.split { $0 == UInt8(ascii: "*") || $0 == UInt8(ascii: "^") }.max { $0.count < $1.count } ?? []
        guard longest.allSatisfy({ $0 < 0x80 }) else { return [] }
        return longest.map { !caseSensitive && (65...90).contains($0) ? $0 + 32 : $0 }
    }

    static func cleanPageURL(_ original: String, rules: [PageRule]) -> String {
        cleanPageURL(original, prepared: prepare(rules))
    }

    /// A page has itself as its document origin, as in uBO's main_frame context.
    /// This never guesses the initiator of an XHR or rewrites subresources after load.
    static func cleanPageURL(_ original: String, prepared rules: [PreparedPageRule]) -> String {
        guard let url = URL(string: original), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let hostName = url.host?.lowercased(), let queryStart = original.firstIndex(of: "?") else { return original }
        let fragmentStart = original.firstIndex(of: "#") ?? original.endIndex
        guard queryStart < fragmentStart else { return original }
        let requestURL = String(original[..<fragmentStart])
        let range = NSRange(requestURL.startIndex..., in: requestURL)
        var host = PageHost(hostName)
        // A pattern's literal text is in every URL it matches. On ASCII text,
        // case-insensitive matching is ASCII lowercasing; other text skips the test.
        let ascii = requestURL.utf8.allSatisfy { $0 < 0x80 }
        let (exact, lowered) = (Array(requestURL.utf8), Array(requestURL.lowercased().utf8))
        func contains(_ text: [UInt8], _ literal: [UInt8]) -> Bool {
            text.withUnsafeBytes { t in literal.withUnsafeBytes { memmem(t.baseAddress, t.count, $0.baseAddress, $0.count) != nil } }
        }
        let matching = rules.filter { page in
            if page.excludedSites.contains(where: { host.matches($0) }) { return false }
            if let sites = page.includedSites, !sites.contains(where: { host.matches($0) }) { return false }
            if page.scopes.contains(where: { !host.inScope($0) }) { return false }
            if page.denyallow.contains(where: { $0.contains { host.matches($0) } }) { return false }
            if page.rule.pattern.isEmpty { return true }
            if ascii, !page.literal.isEmpty, !contains(page.caseSensitive ? exact : lowered, page.literal) { return false }
            return urlPatternRegex(page.rule.pattern, caseSensitive: page.caseSensitive)?.firstMatch(in: requestURL, range: range) != nil
        }.map(\.rule)
        let exceptions = Set(matching.filter(\.isException).map { $0.removeParamValue ?? "" })
        let directives = matching.filter { rule in
            !rule.isException && (rule.options.contains("important") ||
                (!exceptions.contains("") && !exceptions.contains(rule.removeParamValue ?? "")))
        }
        guard !directives.isEmpty else { return original }
        // Keep untouched query bytes, duplicate names, bare keys and fragments.
        // URLComponents/URLSearchParams would normalize signatures and '+' here.
        let query = original[original.index(after: queryStart)..<fragmentStart]
        let parts = query.split(separator: "&", omittingEmptySubsequences: false)
        let selectors = directives.map { rule -> (String, Bool, NSRegularExpression?) in
            var value = rule.removeParamValue ?? ""
            let inverted = value.hasPrefix("~")
            if inverted { value.removeFirst() }
            return (value, inverted, (isRegexRemoveValue(value) || value.hasPrefix("|")) ? selectorRegex(value) : nil)
        }
        let kept = parts.filter { part in
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(pair.first ?? ""), raw = pair.count > 1 ? String(pair[1]) : ""
            let input = key + "=" + (raw.removingPercentEncoding ?? raw)
            return !selectors.contains { value, inverted, regex in
                let matches = regex.map { $0.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil }
                    ?? (value.isEmpty || key == value)
                return matches != inverted
            }
        }
        guard kept.count != parts.count else { return original }
        return String(original[..<queryStart]) + (kept.isEmpty ? "" : "?" + kept.joined(separator: "&")) + original[fragmentStart...]
    }

    private static let pageCacheLock = NSLock()
    nonisolated(unsafe) private static var pageCache: (identity: [UInt64], rules: [PreparedPageRule])?

    static func cleanSavedPageURL(_ original: String, containerURL: URL) -> String {
        // Writes replace the file by rename, so its file number and time
        // identify its contents; it is read and decoded only when they change.
        let file = containerURL.appendingPathComponent(pageRulesFilename)
        var info = stat()
        guard stat(file.path, &info) == 0 else { return original }
        let identity = [UInt64(info.st_ino), UInt64(bitPattern: Int64(info.st_mtimespec.tv_sec)),
                        UInt64(bitPattern: Int64(info.st_mtimespec.tv_nsec)), UInt64(bitPattern: Int64(info.st_size))]
        pageCacheLock.lock()
        defer { pageCacheLock.unlock() }
        if pageCache?.identity != identity {
            guard let data = try? Data(contentsOf: file),
                  let rules = try? JSONDecoder().decode([PageRule].self, from: data) else { return original }
            pageCache = (identity, prepare(rules))
        }
        return cleanPageURL(original, prepared: pageCache?.rules ?? [])
    }
}
