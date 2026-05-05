import Foundation

public struct AdvancedRuleBundle: Sendable, Equatable, Codable {
    public var formatVersion: String
    public var engineTimestamp: Double
    public var css: [AdvancedStyleRule]
    public var extendedCss: [AdvancedStyleRule]
    public var js: [AdvancedStyleRule]
    public var scriptlets: [AdvancedScriptletRule]

    public var ruleCount: Int { css.count + extendedCss.count + js.count + scriptlets.count }

    public init(
        formatVersion: String = "wblock-advanced-rules-v1",
        engineTimestamp: Double = Date().timeIntervalSince1970,
        css: [AdvancedStyleRule] = [],
        extendedCss: [AdvancedStyleRule] = [],
        js: [AdvancedStyleRule] = [],
        scriptlets: [AdvancedScriptletRule] = []
    ) {
        self.formatVersion = formatVersion
        self.engineTimestamp = engineTimestamp
        self.css = css
        self.extendedCss = extendedCss
        self.js = js
        self.scriptlets = scriptlets
    }

    public func jsonString(prettyPrinted: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func decode(jsonString: String) throws -> AdvancedRuleBundle {
        try JSONDecoder().decode(AdvancedRuleBundle.self, from: Data(jsonString.utf8))
    }

    public static func combine(_ bundles: [AdvancedRuleBundle]) -> AdvancedRuleBundle {
        var css: [AdvancedStyleRule] = []
        var extendedCss: [AdvancedStyleRule] = []
        var js: [AdvancedStyleRule] = []
        var scriptlets: [AdvancedScriptletRule] = []
        for bundle in bundles {
            css.append(contentsOf: bundle.css)
            extendedCss.append(contentsOf: bundle.extendedCss)
            js.append(contentsOf: bundle.js)
            scriptlets.append(contentsOf: bundle.scriptlets)
        }
        return AdvancedRuleBundle(css: css, extendedCss: extendedCss, js: js, scriptlets: scriptlets)
    }
}

public struct AdvancedDomainScope: Sendable, Equatable, Codable, Hashable {
    public var ifDomains: [String]
    public var unlessDomains: [String]

    public init(ifDomains: [String] = [], unlessDomains: [String] = []) {
        self.ifDomains = Array(Set(ifDomains.map(Self.normalizeDomain).filter { !$0.isEmpty })).sorted()
        self.unlessDomains = Array(Set(unlessDomains.map(Self.normalizeDomain).filter { !$0.isEmpty })).sorted()
    }

    public func matches(host: String) -> Bool {
        let normalizedHost = Self.normalizeDomain(host)
        guard !normalizedHost.isEmpty else { return ifDomains.isEmpty }
        if unlessDomains.contains(where: { Self.domain($0, matchesHost: normalizedHost) }) {
            return false
        }
        return ifDomains.isEmpty || ifDomains.contains(where: { Self.domain($0, matchesHost: normalizedHost) })
    }

    static func normalizeDomain(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    static func domain(_ domain: String, matchesHost host: String) -> Bool {
        let normalizedDomain = normalizeDomain(domain)
        guard !normalizedDomain.isEmpty else { return false }
        if normalizedDomain == "*" { return true }
        let withoutWildcard = normalizedDomain.hasPrefix("*.") ? String(normalizedDomain.dropFirst(2)) : normalizedDomain
        return host == withoutWildcard || host.hasSuffix("." + withoutWildcard)
    }
}

public struct AdvancedStyleRule: Sendable, Equatable, Codable, Hashable {
    public var scope: AdvancedDomainScope
    public var content: String

    public init(scope: AdvancedDomainScope = AdvancedDomainScope(), content: String) {
        self.scope = scope
        self.content = content
    }
}

public struct AdvancedScriptletRule: Sendable, Equatable, Codable, Hashable {
    public var scope: AdvancedDomainScope
    public var name: String
    public var args: [String]

    public init(scope: AdvancedDomainScope = AdvancedDomainScope(), name: String, args: [String] = []) {
        self.scope = scope
        self.name = name
        self.args = args
    }
}

public struct AdvancedScriptlet: Sendable, Equatable, Codable, Hashable {
    public var name: String
    public var args: [String]

    public init(name: String, args: [String] = []) {
        self.name = name
        self.args = args
    }
}

public struct AdvancedWebExtensionConfiguration: Sendable, Equatable, Codable {
    public var css: [String]
    public var extendedCss: [String]
    public var js: [String]
    public var scriptlets: [AdvancedScriptlet]
    public var engineTimestamp: Double

    public init(
        css: [String] = [],
        extendedCss: [String] = [],
        js: [String] = [],
        scriptlets: [AdvancedScriptlet] = [],
        engineTimestamp: Double = 0
    ) {
        self.css = css
        self.extendedCss = extendedCss
        self.js = js
        self.scriptlets = scriptlets
        self.engineTimestamp = engineTimestamp
    }
}

public struct AdvancedRuleRuntime: Sendable, Equatable {
    public var bundle: AdvancedRuleBundle

    public init(bundle: AdvancedRuleBundle) {
        self.bundle = bundle
    }

    public func lookup(pageURL: URL, topURL: URL? = nil) -> AdvancedWebExtensionConfiguration {
        let host = pageURL.host ?? ""
        return lookup(host: host)
    }

    public func lookup(host: String) -> AdvancedWebExtensionConfiguration {
        var css: [String] = []
        var extendedCss: [String] = []
        var js: [String] = []
        var scriptlets: [AdvancedScriptlet] = []
        var seen = Set<String>()

        for rule in bundle.css where rule.scope.matches(host: host) {
            if seen.insert("css\u{1f}\(rule.content)").inserted {
                css.append(rule.content)
            }
        }
        for rule in bundle.extendedCss where rule.scope.matches(host: host) {
            if seen.insert("extendedCss\u{1f}\(rule.content)").inserted {
                extendedCss.append(rule.content)
            }
        }
        for rule in bundle.js where rule.scope.matches(host: host) {
            if seen.insert("js\u{1f}\(rule.content)").inserted {
                js.append(rule.content)
            }
        }
        for rule in bundle.scriptlets where rule.scope.matches(host: host) {
            let key = "scriptlet\u{1f}\(rule.name)\u{1f}\(rule.args.joined(separator: "\u{1e}"))"
            if seen.insert(key).inserted {
                scriptlets.append(AdvancedScriptlet(name: rule.name, args: rule.args))
            }
        }

        return AdvancedWebExtensionConfiguration(
            css: css,
            extendedCss: extendedCss,
            js: js,
            scriptlets: scriptlets,
            engineTimestamp: bundle.engineTimestamp
        )
    }
}

enum AdvancedRuleParser {
    static func parse(_ line: SourceLine) -> AdvancedParsedRule? {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("!"), !text.hasPrefix("[") else { return nil }

        if let parsed = parseScriptlet(text, delimiter: "#@%#//scriptlet(", uboSyntax: false, exception: true) {
            return parsed
        }
        if let parsed = parseScriptlet(text, delimiter: "#@#+js(", uboSyntax: true, exception: true) {
            return parsed
        }
        if let parsed = parseScriptlet(text, delimiter: "#%#//scriptlet(", uboSyntax: false, exception: false) {
            return parsed
        }
        if let parsed = parseScriptlet(text, delimiter: "##+js(", uboSyntax: true, exception: false) {
            return parsed
        }
        if let parsed = parseCSSInjection(text) {
            return parsed
        }
        if let parsed = parseExtendedCSS(text) {
            return parsed
        }
        return nil
    }

    private static func parseScriptlet(_ text: String, delimiter: String, uboSyntax: Bool, exception: Bool) -> AdvancedParsedRule? {
        guard let range = text.range(of: delimiter), text.hasSuffix(")") else { return nil }
        let domainPart = String(text[..<range.lowerBound])
        let contentStart = range.upperBound
        let contentEnd = text.index(before: text.endIndex)
        let argumentsText = String(text[contentStart..<contentEnd])
        var args = parseArguments(argumentsText)
        guard let rawName = args.first?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else { return nil }
        args.removeFirst()
        let name = uboSyntax ? normalizeUBlockScriptletName(rawName) : rawName
        let rule = AdvancedScriptletRule(scope: parseScope(domainPart), name: name, args: args)
        return exception ? .scriptletException(rule) : .scriptlet(rule)
    }

    private static func parseCSSInjection(_ text: String) -> AdvancedParsedRule? {
        guard let range = text.range(of: "#$#") else { return nil }
        let domainPart = String(text[..<range.lowerBound])
        let content = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        return .css(AdvancedStyleRule(scope: parseScope(domainPart), content: content))
    }

    private static func parseExtendedCSS(_ text: String) -> AdvancedParsedRule? {
        let exception = text.contains("#@#")
        let delimiter = exception ? "#@#" : "##"
        guard let range = text.range(of: delimiter) else { return nil }
        let domainPart = String(text[..<range.lowerBound])
        let selector = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isExtendedSelector(selector) else { return nil }
        let rule = AdvancedStyleRule(scope: parseScope(domainPart), content: selector)
        return exception ? .extendedCssException(rule) : .extendedCss(rule)
    }

    private static func isExtendedSelector(_ selector: String) -> Bool {
        selector.contains(":has-text") ||
        selector.contains(":-abp-contains") ||
        selector.contains(":contains") ||
        selector.contains(":xpath") ||
        selector.contains(":upward") ||
        selector.contains(":matches-css") ||
        selector.contains(":matches-attr") ||
        selector.contains(":matches-property") ||
        selector.contains(":style(") ||
        selector.contains(":has(") ||
        selector.contains(":remove()")
    }

    private static func parseScope(_ domainPart: String) -> AdvancedDomainScope {
        let normalized = domainPart.replacingOccurrences(of: ",", with: "|")
        var positive: [String] = []
        var negative: [String] = []
        for raw in normalized.split(separator: "|", omittingEmptySubsequences: true) {
            let item = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty else { continue }
            if item.hasPrefix("~") {
                negative.append(String(item.dropFirst()))
            } else {
                positive.append(item)
            }
        }
        return AdvancedDomainScope(ifDomains: positive, unlessDomains: negative)
    }

    private static func parseArguments(_ text: String) -> [String] {
        var args: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        for character in text {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "'" || character == "\"" || character == "`" {
                if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    quote = character
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "," {
                args.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
        }

        args.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return args
    }

    private static func normalizeUBlockScriptletName(_ rawName: String) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return name }
        if name.hasPrefix("ubo-") || name.hasSuffix(".js") {
            return name
        }

        switch name {
        case "set": return "ubo-set"
        case "aopr": return "ubo-aopr"
        case "aopw": return "ubo-aopw"
        case "aost": return "ubo-aost"
        case "acs": return "ubo-acs"
        case "acis": return "ubo-acis"
        case "ra": return "ubo-ra.js"
        default: return "ubo-\(name)"
        }
    }
}

enum AdvancedParsedRule: Equatable {
    case css(AdvancedStyleRule)
    case extendedCss(AdvancedStyleRule)
    case extendedCssException(AdvancedStyleRule)
    case js(AdvancedStyleRule)
    case scriptlet(AdvancedScriptletRule)
    case scriptletException(AdvancedScriptletRule)
}
