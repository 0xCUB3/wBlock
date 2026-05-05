import Foundation
import Testing
@testable import WBlockFilterCompiler

@Test func groupsCosmeticRulesWithSameScope() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        example.com##.ad
        example.com##.sponsor
        other.example##.ad
        """
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedRules(result.safariRulesJSON)

    #expect(result.safariRuleCount == 2)
    #expect(rules.filter { $0.action.type == "css-display-none" }.count == 2)
    #expect(rules.contains { $0.action.selector == ".ad,.sponsor" && $0.trigger.ifDomain == ["example.com"] })
}

@Test func exactCosmeticExceptionRemovesMatchingCosmeticRule() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        example.com##.ad
        example.com#@#.ad
        example.com##.sponsor
        """
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedRules(result.safariRulesJSON)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.safariRuleCount == 1)
    #expect(rules[0].action.selector == ".sponsor")
}

@Test func domainCosmeticExceptionAddsUnlessDomainToGenericRule() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        ##.ad
        example.com#@#.ad
        """
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedRules(result.safariRulesJSON)

    #expect(result.safariRuleCount == 1)
    #expect(rules[0].action.selector == ".ad")
    #expect(rules[0].trigger.unlessDomain == ["example.com"])
}

private struct DecodedRuleForCosmetics: Decodable {
    let action: DecodedActionForCosmetics
    let trigger: DecodedTriggerForCosmetics
}

private struct DecodedActionForCosmetics: Decodable {
    let type: String
    let selector: String?
}

private struct DecodedTriggerForCosmetics: Decodable {
    let ifDomain: [String]?
    let unlessDomain: [String]?

    enum CodingKeys: String, CodingKey {
        case ifDomain = "if-domain"
        case unlessDomain = "unless-domain"
    }
}

private func decodedRules(_ json: String) throws -> [DecodedRuleForCosmetics] {
    try JSONDecoder().decode([DecodedRuleForCosmetics].self, from: Data(json.utf8))
}
