import CryptoKit
import Foundation
import os.log

/// Builds the WebExtension DNR rules used for the subset of `$removeparam` that
/// Safari can express: literal query parameter names and strip-all query rules.
///
/// This is intentionally conservative. Regex-valued, inverted, malformed, and
/// otherwise unsupported rules are skipped rather than widened into rules that
/// would strip parameters on the wrong requests.
public enum RemoveParamDNRRuleGenerator {
    public static let rulesFilename = "removeparam_dnr_rules.json"
    public static let ruleIDBase = 1_500_000
    public static let ruleIDLimit = 1_650_000

    // Safari's dynamic DNR quota is more constrained than static content blocker
    // quotas. Keep generated rules within the older 5k dynamic-rule budget so a
    // large pair of URL-cleaning lists degrades by skipping tail rules instead
    // of failing the whole dynamic ruleset install.
    private static let maxGeneratedRules = min(ruleIDLimit - ruleIDBase, 5_000)
    private static let urlFilterSpecialCharacters = CharacterSet(charactersIn: "|*^")
    private static let skippedOptionNames: Set<String> = [
        "app", "cname", "content", "cookie", "csp", "denyallow", "header",
        "hls", "jsonprune", "permissions", "redirect", "referrerpolicy",
        "removeheader", "replace", "strict1p", "strict3p", "urlblock", "webrtc"
    ]

    private static let resourceTypeMap: [String: [String]] = [
        "document": ["main_frame", "sub_frame"],
        "main_frame": ["main_frame"],
        "subdocument": ["sub_frame"],
        "sub_frame": ["sub_frame"],
        "stylesheet": ["stylesheet"],
        "script": ["script"],
        "image": ["image"],
        "font": ["font"],
        "object": ["object"],
        "xmlhttprequest": ["xmlhttprequest"],
        "xhr": ["xmlhttprequest"],
        "ping": ["ping"],
        "media": ["media"],
        "websocket": ["websocket"],
        "other": ["other"]
    ]

    public struct Summary: Equatable {
        public let generatedRules: Int
        public let removeParamRules: Int
        public let exceptionRules: Int
        public let skippedRules: Int
        public let disabledSiteAllowRules: Int
        public let version: String
    }

    public struct DeclarativeRule: Codable, Equatable {
        public var id: Int
        public var priority: Int
        public var action: RuleAction
        public var condition: RuleCondition
    }

    public struct RuleAction: Codable, Equatable {
        public var type: String
        public var redirect: Redirect?
    }

    public struct Redirect: Codable, Equatable {
        public var transform: URLTransform
    }

    public struct URLTransform: Codable, Equatable {
        public var query: String?
        public var queryTransform: QueryTransform?
    }

    public struct QueryTransform: Codable, Equatable {
        public var removeParams: [String]
    }

    public struct RuleCondition: Codable, Equatable {
        public var urlFilter: String? = nil
        public var resourceTypes: [String]? = nil
        public var initiatorDomains: [String]? = nil
        public var excludedInitiatorDomains: [String]? = nil
        public var requestDomains: [String]? = nil
        public var excludedRequestDomains: [String]? = nil
        public var domainType: String? = nil
        public var isUrlFilterCaseSensitive: Bool? = nil
    }

    private struct ParsedRule {
        var isException: Bool
        var pattern: String
        var removeParamValue: String?
        var options: [String]
    }

    private struct BuildResult {
        var rule: DeclarativeRule?
        var wasRemoveParamRule: Bool
        var wasExceptionRule: Bool
        var skipped: Bool
    }

    public static func generateRules(
        from rulesText: String,
        disabledSites: [String] = []
    ) -> (rules: [DeclarativeRule], summary: Summary) {
        var rules = makeDisabledSiteAllowRules(
            disabledSites,
            startingID: ruleIDBase,
            remainingCapacity: maxGeneratedRules
        )
        rules.reserveCapacity(1024)
        let disabledAllowRulesCount = rules.count

        var removeParamRules = 0
        var exceptionRules = 0
        var skippedRules = 0

        for rawLine in rulesText.split(whereSeparator: \.isNewline) {
            let result = buildRule(from: String(rawLine), nextID: ruleIDBase + rules.count)
            if result.wasRemoveParamRule { removeParamRules += 1 }
            if result.wasExceptionRule { exceptionRules += 1 }
            if result.skipped { skippedRules += 1 }
            if let rule = result.rule {
                if rules.count < maxGeneratedRules {
                    rules.append(rule)
                } else {
                    skippedRules += 1
                }
            }
        }

        let version = versionHex(for: rules)
        let summary = Summary(
            generatedRules: rules.count,
            removeParamRules: removeParamRules,
            exceptionRules: exceptionRules,
            skippedRules: skippedRules,
            disabledSiteAllowRules: disabledAllowRulesCount,
            version: version
        )
        return (rules, summary)
    }

    public static func saveRules(
        for filters: [FilterList],
        disabledSites: [String],
        groupIdentifier: String
    ) throws -> Summary {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        var combinedRules = ""
        combinedRules.reserveCapacity(filters.count * 4096)

        for filter in filters {
            guard let sourceURL = SafariContentBlockerAffinityProcessor.sourceURL(
                for: filter,
                containerURL: containerURL
            ) else {
                continue
            }

            guard let contents = try? String(contentsOf: sourceURL, encoding: .utf8) else {
                continue
            }

            if !combinedRules.isEmpty { combinedRules.append("\n") }
            combinedRules.append(contents)
        }

        let generated = generateRules(from: combinedRules, disabledSites: disabledSites)
        try saveRules(generated.rules, groupIdentifier: groupIdentifier)
        os_log(
            .info,
            "Saved %d removeparam DNR rules (%d source removeparam, %d exceptions, %d skipped, %d disabled-site allow rules)",
            generated.summary.generatedRules,
            generated.summary.removeParamRules,
            generated.summary.exceptionRules,
            generated.summary.skippedRules,
            generated.summary.disabledSiteAllowRules
        )
        return generated.summary
    }

    public static func clearSavedRules(groupIdentifier: String) throws -> Summary {
        let rules: [DeclarativeRule] = []
        try saveRules(rules, groupIdentifier: groupIdentifier)
        return Summary(
            generatedRules: 0,
            removeParamRules: 0,
            exceptionRules: 0,
            skippedRules: 0,
            disabledSiteAllowRules: 0,
            version: versionHex(for: rules)
        )
    }

    public static func loadRulesPayload(
        groupIdentifier: String,
        offset: Int,
        limit: Int
    ) -> [String: Any] {
        let safeOffset = max(0, offset)
        let safeLimit = max(1, min(limit, 500))
        guard let data = savedRulesData(groupIdentifier: groupIdentifier) else {
            return [
                "ok": true,
                "version": versionHex(for: []),
                "offset": safeOffset,
                "limit": safeLimit,
                "count": 0,
                "rules": [] as [[String: Any]]
            ]
        }

        let version = sha256Hex(data: data)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return [
                "ok": false,
                "error": "Failed to decode saved removeparam DNR rules",
                "version": version,
                "offset": safeOffset,
                "limit": safeLimit,
                "count": 0,
                "rules": [] as [[String: Any]]
            ]
        }

        let end = min(json.count, safeOffset + safeLimit)
        let slice: [[String: Any]] = safeOffset < json.count ? Array(json[safeOffset..<end]) : []
        return [
            "ok": true,
            "version": version,
            "offset": safeOffset,
            "limit": safeLimit,
            "count": json.count,
            "rules": slice,
            "ruleIdBase": ruleIDBase,
            "ruleIdLimit": ruleIDLimit
        ]
    }

    private static func saveRules(_ rules: [DeclarativeRule], groupIdentifier: String) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(rules)
        let url = containerURL.appendingPathComponent(rulesFilename)
        try data.write(to: url, options: .atomic)
    }

    private static func savedRulesData(groupIdentifier: String) -> Data? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }
        let url = containerURL.appendingPathComponent(rulesFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func buildRule(from rawLine: String, nextID: Int) -> BuildResult {
        guard let parsed = parseRule(rawLine) else {
            return BuildResult(rule: nil, wasRemoveParamRule: false, wasExceptionRule: false, skipped: false)
        }

        let options = parsed.options.map { optionNameAndValue($0).name }
        if options.contains("badfilter") || parsed.options.contains(where: { $0.hasPrefix("~removeparam") }) {
            return BuildResult(rule: nil, wasRemoveParamRule: true, wasExceptionRule: parsed.isException, skipped: true)
        }

        guard let condition = makeCondition(parsed: parsed) else {
            return BuildResult(rule: nil, wasRemoveParamRule: true, wasExceptionRule: parsed.isException, skipped: true)
        }

        let priority = parsed.isException ? 10_000 : (options.contains("important") ? 1_000 : 1)
        let action: RuleAction
        if parsed.isException {
            action = RuleAction(type: "allow", redirect: nil)
        } else if let value = parsed.removeParamValue, !value.isEmpty {
            guard let decoded = decodeRemoveParamValue(value), isSupportedLiteralParameterName(decoded) else {
                return BuildResult(rule: nil, wasRemoveParamRule: true, wasExceptionRule: false, skipped: true)
            }
            action = RuleAction(
                type: "redirect",
                redirect: Redirect(
                    transform: URLTransform(
                        query: nil,
                        queryTransform: QueryTransform(removeParams: [decoded])
                    )
                )
            )
        } else {
            action = RuleAction(
                type: "redirect",
                redirect: Redirect(transform: URLTransform(query: "", queryTransform: nil))
            )
        }

        return BuildResult(
            rule: DeclarativeRule(id: nextID, priority: priority, action: action, condition: condition),
            wasRemoveParamRule: true,
            wasExceptionRule: parsed.isException,
            skipped: false
        )
    }

    private static func parseRule(_ rawLine: String) -> ParsedRule? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        guard !line.hasPrefix("!") && !line.hasPrefix("#") && !line.hasPrefix("[") else { return nil }

        let isException = line.hasPrefix("@@")
        if isException { line.removeFirst(2) }

        guard let dollarIndex = line.lastIndex(of: "$") else { return nil }
        let pattern = String(line[..<dollarIndex]).trimmingCharacters(in: .whitespaces)
        let optionsText = String(line[line.index(after: dollarIndex)...])
        let options = splitOptions(optionsText)
        guard options.contains(where: { optionNameAndValue($0).name == "removeparam" }) else { return nil }

        let removeParamValue = options.compactMap { option -> String? in
            let pair = optionNameAndValue(option)
            guard pair.name == "removeparam" else { return nil }
            return pair.value ?? ""
        }.first ?? ""

        return ParsedRule(
            isException: isException,
            pattern: pattern,
            removeParamValue: removeParamValue,
            options: options
        )
    }

    private static func splitOptions(_ optionsText: String) -> [String] {
        optionsText.split(separator: ",", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func optionNameAndValue(_ option: String) -> (name: String, value: String?) {
        let parts = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = parts.count > 1 ? String(parts[1]) : nil
        return (name, value)
    }

    private static func makeCondition(parsed: ParsedRule) -> RuleCondition? {
        let optionPairs = parsed.options.map(optionNameAndValue)

        guard !containsUnsupportedCriticalOptions(optionPairs) else { return nil }

        let removeValue = parsed.removeParamValue ?? ""
        guard isSupportedRemoveParamValue(removeValue) else { return nil }

        var urlFilter = normalizeURLFilterPattern(parsed.pattern)
        if !removeValue.isEmpty, let decoded = decodeRemoveParamValue(removeValue) {
            guard let token = removeParamURLFilterToken(for: decoded) else { return nil }
            urlFilter = urlFilter.map { $0 + "*" + token } ?? token
        }

        var condition = RuleCondition()
        condition.urlFilter = urlFilter
        condition.resourceTypes = resourceTypes(from: optionPairs)
        if condition.resourceTypes == nil {
            condition.resourceTypes = ["main_frame", "sub_frame"]
        }

        let domains = parseDomainOption(named: "domain", from: optionPairs)
        if !domains.included.isEmpty { condition.initiatorDomains = domains.included }
        if !domains.excluded.isEmpty { condition.excludedInitiatorDomains = domains.excluded }

        let toDomains = parseDomainOption(named: "to", from: optionPairs)
        if !toDomains.included.isEmpty { condition.requestDomains = toDomains.included }
        if !toDomains.excluded.isEmpty { condition.excludedRequestDomains = toDomains.excluded }

        if optionPairs.contains(where: { $0.name == "third-party" }) {
            condition.domainType = "thirdParty"
        } else if optionPairs.contains(where: { $0.name == "~third-party" }) {
            condition.domainType = "firstParty"
        }

        if optionPairs.contains(where: { $0.name == "match-case" }) {
            condition.isUrlFilterCaseSensitive = true
        }

        return condition
    }

    private static func containsUnsupportedCriticalOptions(_ options: [(name: String, value: String?)]) -> Bool {
        for option in options {
            if option.name.hasPrefix("~"), resourceTypeMap[String(option.name.dropFirst())] != nil {
                return true
            }
            if skippedOptionNames.contains(option.name) { return true }
            if option.name == "method" { return true }
        }
        return false
    }

    private static func normalizeURLFilterPattern(_ rawPattern: String) -> String? {
        var pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return nil }
        guard !(pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 1) else { return nil }
        if pattern.hasPrefix("||*") {
            pattern.removeFirst(2)
        }
        return pattern.isEmpty ? nil : pattern
    }

    private static func resourceTypes(from options: [(name: String, value: String?)]) -> [String]? {
        var ordered: [String] = []
        var seen = Set<String>()
        for option in options {
            guard let mapped = resourceTypeMap[option.name] else { continue }
            for resourceType in mapped where !seen.contains(resourceType) {
                seen.insert(resourceType)
                ordered.append(resourceType)
            }
        }
        return ordered.isEmpty ? nil : ordered
    }

    private static func parseDomainOption(
        named optionName: String,
        from options: [(name: String, value: String?)]
    ) -> (included: [String], excluded: [String]) {
        guard let value = options.first(where: { $0.name == optionName })?.value else {
            return ([], [])
        }

        var included: [String] = []
        var excluded: [String] = []
        for rawDomain in value.split(separator: "|", omittingEmptySubsequences: true) {
            var domain = String(rawDomain).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isExcluded = domain.hasPrefix("~")
            if isExcluded { domain.removeFirst() }
            guard isSupportedDomain(domain) else { continue }
            if isExcluded {
                excluded.append(domain)
            } else {
                included.append(domain)
            }
        }
        return (included.sorted(), excluded.sorted())
    }

    private static func isSupportedDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty else { return false }
        guard !domain.contains("*") && !domain.contains("/") && !domain.contains(":") else { return false }
        return domain.allSatisfy { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
        }
    }

    private static func isSupportedRemoveParamValue(_ value: String) -> Bool {
        guard !value.hasPrefix("~") && !value.hasPrefix("/") else { return false }
        if value.contains("|") { return false }
        if value.isEmpty { return true }
        guard let decoded = decodeRemoveParamValue(value) else { return false }
        return isSupportedLiteralParameterName(decoded)
    }

    private static func decodeRemoveParamValue(_ value: String) -> String? {
        value.removingPercentEncoding
    }

    private static func isSupportedLiteralParameterName(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        guard value.trimmingCharacters(in: .whitespacesAndNewlines) == value else { return false }
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        return true
    }

    private static func removeParamURLFilterToken(for decodedValue: String) -> String? {
        guard isSupportedLiteralParameterName(decodedValue) else { return nil }
        guard decodedValue.rangeOfCharacter(from: urlFilterSpecialCharacters) == nil else { return nil }
        return "^\(decodedValue)="
    }

    private static func makeDisabledSiteAllowRules(
        _ disabledSites: [String],
        startingID: Int,
        remainingCapacity: Int
    ) -> [DeclarativeRule] {
        var rules: [DeclarativeRule] = []
        let domains = disabledSites
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter(isSupportedDomain)
            .uniqued()

        for domain in domains where rules.count + 2 <= remainingCapacity {
            rules.append(DeclarativeRule(
                id: startingID + rules.count,
                priority: 20_000,
                action: RuleAction(type: "allow", redirect: nil),
                condition: RuleCondition(
                    urlFilter: nil,
                    resourceTypes: ["main_frame", "sub_frame"],
                    initiatorDomains: nil,
                    excludedInitiatorDomains: nil,
                    requestDomains: [domain],
                    excludedRequestDomains: nil,
                    domainType: nil,
                    isUrlFilterCaseSensitive: nil
                )
            ))
            rules.append(DeclarativeRule(
                id: startingID + rules.count,
                priority: 20_000,
                action: RuleAction(type: "allow", redirect: nil),
                condition: RuleCondition(
                    urlFilter: nil,
                    resourceTypes: ["main_frame", "sub_frame", "xmlhttprequest"],
                    initiatorDomains: [domain],
                    excludedInitiatorDomains: nil,
                    requestDomains: nil,
                    excludedRequestDomains: nil,
                    domainType: nil,
                    isUrlFilterCaseSensitive: nil
                )
            ))
        }

        return rules
    }

    private static func versionHex(for rules: [DeclarativeRule]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(rules)) ?? Data()
        return sha256Hex(data: data)
    }

    private static func sha256Hex(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        for element in self where !seen.contains(element) {
            seen.insert(element)
            result.append(element)
        }
        return result
    }
}
