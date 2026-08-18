import Foundation
import wBlockCoreService

@main
struct SafariRuleLimitCapTests {
    static func main() {
        expectEqual(
            ContentBlockerService.safariContentBlockerRuleLimit,
            150_000,
            "Safari per-extension limit must stay at 150,000"
        )

        let threeRuleJSON = compactJSON([
            blockRule("a"),
            blockRule("b"),
            blockRule("c"),
        ])

        let unchanged = ContentBlockerService.finalizeContentBlockerJSON(
            baseJSON: threeRuleJSON,
            disabledSites: [],
            knownBaseCount: 3
        )
        expectEqual(unchanged.ruleCount, 3, "empty disabled sites should keep the base count")
        expectEqual(unchanged.json, threeRuleJSON, "empty disabled sites should keep the base JSON")

        let underLimit = ContentBlockerService.finalizeContentBlockerJSON(
            baseJSON: threeRuleJSON,
            disabledSites: ["example.com"],
            knownBaseCount: 3
        )
        let underRules = rules(in: underLimit.json)
        expectEqual(underLimit.ruleCount, 4, "under-limit lists should gain one ignore rule")
        expectEqual(underRules.count, 4, "under-limit JSON should contain the extra ignore rule")
        expectEqual(filterOf(underRules[0]), "a", "existing rules should stay in front")
        expect(isIgnoreRule(underRules[3], for: "*example.com"), "ignore rule should be last")

        let atLimit = ContentBlockerService.finalizeContentBlockerJSON(
            baseJSON: threeRuleJSON,
            disabledSites: ["example.com"],
            knownBaseCount: 3,
            ruleLimit: 3
        )
        let atLimitRules = rules(in: atLimit.json)
        expectEqual(atLimit.ruleCount, 3, "150k + 1 disabled site must stay at the Safari limit")
        expectEqual(atLimitRules.count, 3, "capped JSON must not exceed the limit")
        expectEqual(filterOf(atLimitRules[0]), "a", "the first converted rule should be kept")
        expectEqual(filterOf(atLimitRules[1]), "b", "the second converted rule should be kept")
        expect(isIgnoreRule(atLimitRules[2], for: "*example.com"), "the dropped rule must be a converted rule, not the ignore rule")

        let twoSites = ContentBlockerService.finalizeContentBlockerJSON(
            baseJSON: threeRuleJSON,
            disabledSites: ["one.example", "two.example"],
            knownBaseCount: 3,
            ruleLimit: 3
        )
        let twoSiteRules = rules(in: twoSites.json)
        expectEqual(twoSites.ruleCount, 3, "two ignore rules should reserve two slots")
        expectEqual(filterOf(twoSiteRules[0]), "a", "only the first converted rule should remain")
        expect(isIgnoreRule(twoSiteRules[1], for: "*one.example"), "first ignore rule should be preserved")
        expect(isIgnoreRule(twoSiteRules[2], for: "*two.example"), "second ignore rule should be preserved")

        let emptyBase = ContentBlockerService.finalizeContentBlockerJSON(
            baseJSON: "[]",
            disabledSites: ["example.com"],
            knownBaseCount: 0
        )
        let emptyRules = rules(in: emptyBase.json)
        expectEqual(emptyBase.ruleCount, 1, "an empty list should still receive ignore rules")
        expect(isIgnoreRule(emptyRules[0], for: "*example.com"), "empty lists should inject the ignore rule")

        let normalized = ContentBlockerService.finalizeContentBlockerJSON(
            baseJSON: threeRuleJSON,
            disabledSites: [" Example.com ", "EXAMPLE.com", "not a host"],
            knownBaseCount: 3
        )
        expectEqual(normalized.ruleCount, 4, "duplicate and invalid sites should not add extra ignore rules")
        expect(isIgnoreRule(rules(in: normalized.json)[3], for: "*example.com"), "normalized domain should be injected once")

        let ignoreOnly = ContentBlockerService.finalizeContentBlockerJSON(
            baseJSON: threeRuleJSON,
            disabledSites: ["one.example", "two.example"],
            knownBaseCount: 3,
            ruleLimit: 1
        )
        let ignoreOnlyRules = rules(in: ignoreOnly.json)
        expectEqual(ignoreOnly.ruleCount, 1, "ignore rules themselves must not exceed the limit")
        expect(isIgnoreRule(ignoreOnlyRules[0], for: "*one.example"), "the first ignore rule should win when even ignore rules must be capped")

        let overLimitBase = ContentBlockerService.finalizeContentBlockerJSON(
            baseJSON: threeRuleJSON,
            disabledSites: [],
            knownBaseCount: 3,
            ruleLimit: 2
        )
        expectEqual(overLimitBase.ruleCount, 2, "an over-limit base list should be truncated")
        expectEqual(rules(in: overLimitBase.json).count, 2, "truncated JSON should match the reported count")

        print("ok")
    }

    private static func blockRule(_ filter: String) -> [String: Any] {
        [
            "trigger": ["url-filter": filter],
            "action": ["type": "block"],
        ]
    }

    private static func compactJSON(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private static func rules(in json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            fputs("FAIL: could not parse content blocker JSON: \(json)\n", stderr)
            exit(1)
        }
        return parsed
    }

    private static func filterOf(_ rule: [String: Any]) -> String? {
        let trigger = rule["trigger"] as? [String: Any]
        return trigger?["url-filter"] as? String
    }

    private static func isIgnoreRule(_ rule: [String: Any], for domain: String) -> Bool {
        let action = rule["action"] as? [String: Any]
        let trigger = rule["trigger"] as? [String: Any]
        let domains = trigger?["if-domain"] as? [String]
        return action?["type"] as? String == "ignore-previous-rules"
            && trigger?["url-filter"] as? String == ".*"
            && domains == [domain]
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fputs("FAIL: \(message)\nactual: \(actual)\nexpected: \(expected)\n", stderr)
            exit(1)
        }
    }
}
