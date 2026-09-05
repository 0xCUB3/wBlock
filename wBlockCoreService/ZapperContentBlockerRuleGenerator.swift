import Foundation
import PublicSuffixList

public enum ZapperContentBlockerRuleGenerator {
    public static func scope(forHost host: String) -> String {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard normalized.hasPrefix("www.") else { return normalized }
        let parent = String(normalized.dropFirst(4))
        guard PublicSuffixList.effectiveTLDPlusOne(parent) != nil else { return normalized }
        return parent
    }

    public static func applies(storedHost: String, toHost host: String) -> Bool {
        HostMatcher.isHostDisabled(host: scope(forHost: host), disabledSites: [scope(forHost: storedHost)])
    }

    public static func generatedRules(from rulesByHost: [String: [String]]) -> [String] {
        rulesByHost
            .keys
            .sorted()
            .flatMap { host in
                generatedRules(forHost: host, selectors: rulesByHost[host] ?? [])
            }
    }

    public static func generatedRules(forHost host: String, selectors: [String]) -> [String] {
        let trimmedHost = scope(forHost: host)
        guard !trimmedHost.isEmpty else { return [] }

        let normalizedSelectors = selectors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedSelectors.isEmpty else { return [] }

        return Array(Set(normalizedSelectors))
            .sorted()
            .map { "\(trimmedHost)##\($0)" }
    }

    public static func generatedRulesText(from rulesByHost: [String: [String]]) -> String? {
        let rules = generatedRules(from: rulesByHost)
        guard !rules.isEmpty else { return nil }
        return rules.joined(separator: "\n")
    }
}
