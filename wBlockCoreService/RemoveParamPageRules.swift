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

    private static func domainMatches(_ host: String, _ domain: String) -> Bool {
        let domain = domain.lowercased()
        if domain.hasSuffix(".*") {
            // Entity boundaries use the same PSL as the network engine. In
            // particular, transfernow.co.uk matches but transfernow.evil.com does not.
            guard let root = WBEngine.registrableDomain(of: host), let dot = root.firstIndex(of: ".") else { return false }
            let suffix = root[dot...]
            let entityHost = String(host.dropLast(suffix.count))
            let entity = String(domain.dropLast(2))
            return entityHost == entity || entityHost.hasSuffix("." + entity)
        }
        return host == domain || host.hasSuffix("." + domain)
    }

    private static func scopeMatches(_ value: String, host: String) -> Bool {
        let domains = value.split(separator: "|").map(String.init)
        if domains.contains(where: { $0.hasPrefix("~") && domainMatches(host, String($0.dropFirst())) }) { return false }
        let included = domains.filter { !$0.hasPrefix("~") }
        return included.isEmpty || included.contains { domainMatches(host, $0) }
    }

    /// A page has itself as its document origin, as in uBO's main_frame context.
    /// This never guesses the initiator of an XHR or rewrites subresources after load.
    static func cleanPageURL(_ original: String, rules: [PageRule]) -> String {
        guard let url = URL(string: original), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), let queryStart = original.firstIndex(of: "?") else { return original }
        let fragmentStart = original.firstIndex(of: "#") ?? original.endIndex
        guard queryStart < fragmentStart else { return original }
        let requestURL = String(original[..<fragmentStart])
        let range = NSRange(requestURL.startIndex..., in: requestURL)
        let matching = rules.filter { page in
            let rule = page.rule, pairs = rule.options.map(optionNameAndValue)
            if !page.excludedSites.allSatisfy({ !domainMatches(host, $0) }) { return false }
            if let sites = page.includedSites, !sites.contains(where: { domainMatches(host, $0) }) { return false }
            if let types = resourceTypes(from: pairs), !types.contains("main_frame") { return false }
            if pairs.contains(where: { $0.name == "third-party" }) { return false }
            for pair in pairs {
                if ["domain", "to"].contains(pair.name), !scopeMatches(pair.value ?? "", host: host) { return false }
                if pair.name == "denyallow", (pair.value ?? "").split(separator: "|").contains(where: { domainMatches(host, String($0)) }) { return false }
            }
            return urlPatternRegex(rule.pattern, caseSensitive: rule.options.contains("match-case"))?
                .firstMatch(in: requestURL, range: range) != nil
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
    nonisolated(unsafe) private static var pageCache: (data: Data, rules: [PageRule])?

    static func cleanSavedPageURL(_ original: String, containerURL: URL) -> String {
        guard let data = try? Data(contentsOf: containerURL.appendingPathComponent(pageRulesFilename)) else { return original }
        pageCacheLock.lock()
        defer { pageCacheLock.unlock() }
        if pageCache?.data != data {
            guard let rules = try? JSONDecoder().decode([PageRule].self, from: data) else { return original }
            pageCache = (data, rules)
        }
        return cleanPageURL(original, rules: pageCache?.rules ?? [])
    }
}
