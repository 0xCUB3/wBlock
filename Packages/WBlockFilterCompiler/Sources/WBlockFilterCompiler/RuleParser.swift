import Foundation

enum RuleParser {
    static func parse(_ sourceLine: SourceLine, configuration: FilterCompilerConfiguration) -> ParsedRule {
        let trimmed = sourceLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = RuleClassifier.classify(trimmed)

        if kind != .cosmeticException,
           let reason = RuleClassifier.unsupportedReason(for: kind, line: trimmed, configuration: configuration) {
            return .unsupported(reason)
        }

        switch kind {
        case .comment:
            return .comment
        case .preprocessor:
            return .preprocessor
        case .network, .networkException:
            if let hostsRule = parseHostsRule(sourceLine) {
                return .network(hostsRule)
            }
            return parseNetworkRule(sourceLine, configuration: configuration) ?? .unsupported(.unknownSyntax)
        case .cosmetic:
            return parseCosmeticRule(sourceLine, delimiter: "##").map(ParsedRule.cosmetic) ?? .unsupported(.unknownSyntax)
        case .cosmeticException:
            return parseCosmeticRule(sourceLine, delimiter: "#@#").map(ParsedRule.cosmeticException) ?? .unsupported(.cosmeticExceptionNeedsPlanner)
        case .scriptlet, .scriptletException, .proceduralCosmetic:
            return .comment
        default:
            return .unsupported(.unknownSyntax)
        }
    }

    private static func parseHostsRule(_ sourceLine: SourceLine) -> NetworkRule? {
        let trimmed = sourceLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count >= 2, ["0.0.0.0", "127.0.0.1", "::", "::1"].contains(parts[0]) else { return nil }
        let host = normalizeDomain(parts[1])
        guard isUsableHost(host) else { return nil }
        let pattern = "||\(host)^"
        return NetworkRule(
            source: sourceLine,
            isException: false,
            action: .block,
            pattern: pattern,
            resourceTypes: [],
            loadType: nil,
            ifDomains: [],
            unlessDomains: [],
            toDomains: [],
            denyAllowDomains: [],
            removeParameters: [],
            urlSkipSteps: nil,
            uriTransform: nil,
            redirectResource: nil,
            matchCase: false,
            important: false,
            isBadfilter: false,
            canonicalIdentity: canonicalIdentity(isException: false, pattern: pattern, options: [])
        )
    }

    private static func parseNetworkRule(_ sourceLine: SourceLine, configuration: FilterCompilerConfiguration) -> ParsedRule? {
        let trimmed = sourceLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isException = trimmed.hasPrefix("@@")
        let withoutException = isException ? String(trimmed.dropFirst(2)) : trimmed
        let split = splitPatternAndOptions(withoutException)
        let rawPattern = split.pattern.trimmingCharacters(in: .whitespaces)
        let pattern = rawPattern.isEmpty && !split.options.isEmpty ? "*" : rawPattern
        guard !pattern.isEmpty else { return nil }

        var action = NetworkAction.block
        var resourceTypes = Set<SafariResourceType>()
        var excludedResourceTypes = Set<SafariResourceType>()
        var loadType: SafariLoadType?
        var ifDomains: [String] = []
        var unlessDomains: [String] = []
        var toDomains: [String] = []
        var denyAllowDomains: [String] = []
        var removeParameters: [String] = []
        var urlSkipSteps: String?
        var uriTransform: String?
        var redirectResource: String?
        var matchCase = false
        var important = false
        var isBadfilter = false
        var canonicalOptions: [String] = []

        for rawOption in split.options {
            let option = rawOption.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !option.isEmpty else { continue }
            let lower = option.lowercased()

            if lower == "badfilter" {
                isBadfilter = true
                continue
            }
            if lower == "important" {
                important = true
                canonicalOptions.append("important")
                continue
            }
            if lower == "match-case" {
                matchCase = true
                canonicalOptions.append("match-case")
                continue
            }
            if lower == "third-party" || lower == "3p" {
                loadType = .thirdParty
                canonicalOptions.append("third-party")
                continue
            }
            if lower == "~third-party" || lower == "~3p" {
                loadType = .firstParty
                canonicalOptions.append("~third-party")
                continue
            }
            if lower == "first-party" || lower == "1p" {
                loadType = .firstParty
                canonicalOptions.append("first-party")
                continue
            }
            if lower == "strict1p" {
                loadType = .firstParty
                canonicalOptions.append("strict1p")
                continue
            }
            if lower == "~first-party" || lower == "~1p" {
                loadType = .thirdParty
                canonicalOptions.append("~first-party")
                continue
            }
            if lower == "strict3p" {
                loadType = .thirdParty
                canonicalOptions.append("strict3p")
                continue
            }
            if lower == "all" {
                canonicalOptions.append("all")
                continue
            }
            if lower == "cookie" || lower.hasPrefix("cookie=") {
                action = .blockCookies
                canonicalOptions.append("cookie")
                continue
            }
            if lower.hasPrefix("domain=") || lower.hasPrefix("from=") {
                let value = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .dropFirst()
                    .first
                    .map(String.init) ?? ""
                let domains = parseDomainList(value)
                ifDomains.append(contentsOf: domains.positive)
                unlessDomains.append(contentsOf: domains.negative)
                let positive = domains.positive.joined(separator: "|")
                let negative = domains.negative.map { "~\($0)" }.joined(separator: "|")
                canonicalOptions.append(["domain", positive, negative].joined(separator: "="))
                continue
            }

            if lower.hasPrefix("~"), let type = resourceType(for: String(lower.dropFirst())) {
                excludedResourceTypes.insert(type)
                canonicalOptions.append(lower)
                continue
            }

            if let type = resourceType(for: lower) {
                resourceTypes.insert(type)
                canonicalOptions.append(type.rawValue)
                continue
            }

            if lower.hasPrefix("denyallow=") {
                guard !isException else { return .unsupported(.denyAllowNeedsPlanner) }
                let value = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .dropFirst()
                    .first
                    .map(String.init) ?? ""
                let domains = parseDomainList(value)
                guard !domains.positive.isEmpty, domains.negative.isEmpty else { return .unsupported(.denyAllowNeedsPlanner) }
                denyAllowDomains.append(contentsOf: domains.positive)
                canonicalOptions.append("denyallow=\(domains.positive.joined(separator: "|"))")
                continue
            }

            if lower.hasPrefix("to=") {
                let value = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .dropFirst()
                    .first
                    .map(String.init) ?? ""
                let domains = parseDomainList(value)
                if !domains.positive.isEmpty, domains.negative.isEmpty {
                    toDomains.append(contentsOf: domains.positive)
                    canonicalOptions.append("to=\(domains.positive.joined(separator: "|"))")
                    continue
                }
                if pattern == "*", domains.positive.isEmpty, !domains.negative.isEmpty, !isException {
                    denyAllowDomains.append(contentsOf: domains.negative)
                    canonicalOptions.append("to=\(domains.negative.map { "~\($0)" }.joined(separator: "|"))")
                    continue
                }
                return .unsupported(.noSafariEquivalent)
            }

            if lower.hasPrefix("reason=") {
                canonicalOptions.append(lower)
                continue
            }

            if lower.hasPrefix("rewrite=") {
                guard !isException else { return .unsupported(.noSafariEquivalent) }
                canonicalOptions.append(lower)
                continue
            }

            if lower == "removeparam" || lower == "queryprune" {
                guard configuration.enabledCapabilities.contains(.advancedScriptlets) || configuration.enabledCapabilities.contains(.removeQueryParameters) else {
                    return .unsupported(.removeParamRequiresAdvancedRuntime)
                }
                removeParameters.append("*")
                canonicalOptions.append("removeparam=*")
                continue
            }

            if lower.hasPrefix("removeparam=") || lower.hasPrefix("queryprune=") {
                guard configuration.enabledCapabilities.contains(.advancedScriptlets) || configuration.enabledCapabilities.contains(.removeQueryParameters) else {
                    return .unsupported(.removeParamRequiresAdvancedRuntime)
                }
                let value = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .dropFirst()
                    .first
                    .map(String.init) ?? ""
                guard !value.isEmpty else { return .unsupported(.removeParamRequiresAdvancedRuntime) }
                removeParameters.append(value)
                canonicalOptions.append("removeparam=\(value.lowercased())")
                continue
            }

            if lower.hasPrefix("urlskip=") {
                guard configuration.enabledCapabilities.contains(.advancedScriptlets) else { return .unsupported(.noSafariEquivalent) }
                let value = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .dropFirst()
                    .first
                    .map(String.init) ?? ""
                guard !value.isEmpty else { return .unsupported(.noSafariEquivalent) }
                urlSkipSteps = value
                canonicalOptions.append("urlskip=\(value.lowercased())")
                continue
            }

            if lower.hasPrefix("uritransform=") {
                guard configuration.enabledCapabilities.contains(.advancedScriptlets) else { return .unsupported(.noSafariEquivalent) }
                let value = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .dropFirst()
                    .first
                    .map(String.init) ?? ""
                guard !value.isEmpty else { return .unsupported(.noSafariEquivalent) }
                uriTransform = value
                canonicalOptions.append("uritransform=\(value.lowercased())")
                continue
            }

            if lower.hasPrefix("redirect=") {
                guard !isException else { return .unsupported(.noSafariEquivalent) }
                let value = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .dropFirst()
                    .first
                    .map(String.init) ?? ""
                if configuration.enabledCapabilities.contains(.redirects), !value.isEmpty {
                    redirectResource = value
                }
                canonicalOptions.append(lower)
                continue
            }

            if lower.hasPrefix("redirect-rule=") {
                guard !isException else { return .unsupported(.noSafariEquivalent) }
                let value = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .dropFirst()
                    .first
                    .map(String.init) ?? ""
                guard configuration.enabledCapabilities.contains(.redirects), !value.isEmpty else { return .unsupported(.noSafariEquivalent) }
                redirectResource = value
                canonicalOptions.append(lower)
                continue
            }

            if lower == "redirect" || lower == "redirect-rule" {
                return .unsupported(.noSafariEquivalent)
            }

            if lower == "popunder" {
                resourceTypes.insert(.popup)
                canonicalOptions.append("popup")
                continue
            }

            if lower.hasPrefix("method=") || lower == "inline-script" || lower == "inline-font" || lower == "elemhide" || lower == "generichide" || lower == "genericblock" || lower == "jsinject" || lower == "shide" || lower == "ehide" || lower == "ghide" || lower == "specifichide" || lower == "cname" || lower.hasPrefix("cname=") {
                return .unsupported(.noSafariEquivalent)
            }

            return .unsupported(.unknownModifier)
        }

        if !excludedResourceTypes.isEmpty {
            let expanded = Set(SafariResourceType.allCases).subtracting(excludedResourceTypes)
            resourceTypes = resourceTypes.isEmpty ? expanded : resourceTypes.subtracting(excludedResourceTypes)
        }

        if isException && !ifDomains.isEmpty && !unlessDomains.isEmpty {
            return .unsupported(.mixedDomainOptionsNeedSplitting)
        }

        let identity = canonicalIdentity(isException: isException, pattern: pattern, options: canonicalOptions)
        return .network(
            NetworkRule(
                source: sourceLine,
                isException: isException,
                action: action,
                pattern: pattern,
                resourceTypes: resourceTypes,
                loadType: loadType,
                ifDomains: Array(Set(ifDomains)).sorted(),
                unlessDomains: Array(Set(unlessDomains)).sorted(),
                toDomains: Array(Set(toDomains)).sorted(),
                denyAllowDomains: Array(Set(denyAllowDomains)).sorted(),
                removeParameters: Array(Set(removeParameters)).sorted(),
                urlSkipSteps: urlSkipSteps,
                uriTransform: uriTransform,
                redirectResource: redirectResource,
                matchCase: matchCase,
                important: important,
                isBadfilter: isBadfilter,
                canonicalIdentity: identity
            )
        )
    }

    private static func parseCosmeticRule(_ sourceLine: SourceLine, delimiter: String) -> CosmeticRule? {
        let text = sourceLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: delimiter) else { return nil }
        let domainPart = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let selector = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty else { return nil }

        let domains = parseDomainList(domainPart.replacingOccurrences(of: ",", with: "|"))
        return CosmeticRule(
            source: sourceLine,
            selector: selector,
            ifDomains: domains.positive,
            unlessDomains: domains.negative
        )
    }

    private static func splitPatternAndOptions(_ text: String) -> (pattern: String, options: [String]) {
        let separator: String.Index?
        if text.hasPrefix("/"), let regexSeparator = regexOptionsSeparator(in: text) {
            separator = regexSeparator
        } else {
            separator = text.firstIndex(of: "$")
        }

        guard let dollar = separator else { return (text, []) }
        let pattern = String(text[..<dollar])
        let options = text[text.index(after: dollar)...].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return (pattern, options)
    }

    private static func regexOptionsSeparator(in text: String) -> String.Index? {
        var escaped = false
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "/" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "$" {
                    return next
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func parseDomainList(_ value: String) -> (positive: [String], negative: [String]) {
        guard !value.isEmpty else { return ([], []) }
        var positive: [String] = []
        var negative: [String] = []

        for rawItem in value.split(separator: "|", omittingEmptySubsequences: true) {
            let rawDomain = String(rawItem).trimmingCharacters(in: .whitespacesAndNewlines)
            let isNegative = rawDomain.hasPrefix("~")
            let domain = normalizeDomain(isNegative ? String(rawDomain.dropFirst()) : rawDomain)
            guard isUsableHost(domain) else { continue }
            if isNegative {
                negative.append(domain)
            } else {
                positive.append(domain)
            }
        }

        return (Array(Set(positive)).sorted(), Array(Set(negative)).sorted())
    }

    private static func normalizeDomain(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private static func isUsableHost(_ host: String) -> Bool {
        !host.isEmpty && host != "localhost" && !host.contains("#")
    }

    private static func resourceType(for option: String) -> SafariResourceType? {
        switch option {
        case "document", "doc", "popup": return option == "popup" ? .popup : .document
        case "subdocument", "frame": return .document
        case "image": return .image
        case "stylesheet", "style-sheet", "css": return .styleSheet
        case "script": return .script
        case "font": return .font
        case "media", "object", "object-subrequest": return .media
        case "xmlhttprequest", "xhr", "ping", "websocket", "webrtc", "other", "empty", "beacon": return .raw
        default: return nil
        }
    }

    static func canonicalIdentity(isException: Bool, pattern: String, options: [String]) -> String {
        let normalizedOptions = options.filter { $0.lowercased() != "badfilter" }.map { $0.lowercased() }.sorted()
        return "\(isException ? "@@" : "")\(pattern)|$\(normalizedOptions.joined(separator: ","))"
    }
}
