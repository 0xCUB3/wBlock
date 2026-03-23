import Foundation

public enum ZapperContentBlockerRuleGenerator {
    public static func generatedRules(from rulesByHost: [String: [String]]) -> [String] {
        rulesByHost
            .keys
            .sorted()
            .flatMap { host in
                generatedRules(forHost: host, selectors: rulesByHost[host] ?? [])
            }
    }

    public static func generatedRules(forHost host: String, selectors: [String]) -> [String] {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
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
