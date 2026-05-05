import Foundation
import Testing
@testable import WBlockFilterCompiler

@Test func diagnosticsOnlyCompilerClassifiesBasicRules() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        ! comment
        !#if ext_ublock
        ||example.com^$script,third-party
        example.com##.ad
        example.com#@#.ad
        example.com##+js(set-constant, foo, true)
        example.com##.ad:has-text(Sponsored)
        example.com##^script:has-text(ad)
        ||example.com^$removeparam=utm_source
        """
    )
    var configuration = FilterCompilerConfiguration()
    configuration.target = .diagnosticsOnly
    configuration.preprocessConditionals = false

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.safariRulesJSON == "[]")
    #expect(result.safariRuleCount == 0)
    #expect(result.diagnostics.classifiedRules[.comment] == 1)
    #expect(result.diagnostics.classifiedRules[.preprocessor] == 1)
    #expect(result.diagnostics.classifiedRules[.network] == 1)
    #expect(result.diagnostics.classifiedRules[.cosmetic] == 1)
    #expect(result.diagnostics.classifiedRules[.cosmeticException] == 1)
    #expect(result.diagnostics.classifiedRules[.scriptlet] == 1)
    #expect(result.diagnostics.classifiedRules[.proceduralCosmetic] == 1)
    #expect(result.diagnostics.classifiedRules[.htmlFiltering] == 1)
    #expect(result.diagnostics.classifiedRules[.unsupported] == 1)
    #expect(result.unsupportedRules.count == 4)
}

@Test func advancedCapabilitiesSuppressMatchingUnsupportedDiagnostics() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        example.com##+js(set-constant, foo, true)
        example.com##.ad:has-text(Sponsored)
        """
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities = [.advancedScriptlets, .proceduralCosmetics]

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.unsupportedRules.isEmpty)
}

@Test func compilerEmitsNetworkCosmeticAndExceptionRules() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        ||ads.example.com^$script,third-party,domain=news.example
        @@||ads.example.com/allowed.js$script,domain=news.example
        news.example##.sponsor
        0.0.0.0 tracker.example
        """
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedSafariRules(result.safariRulesJSON)

    #expect(result.safariRuleCount == 4)
    #expect(rules.count == 4)
    #expect(rules[0].action.type == "block")
    #expect(rules[0].trigger.resourceType == ["script"])
    #expect(rules[0].trigger.loadType == ["third-party"])
    #expect(rules[0].trigger.ifDomain == ["news.example"])
    #expect(rules[1].action.type == "block")
    #expect(rules[2].action.type == "css-display-none")
    #expect(rules[2].action.selector == ".sponsor")
    #expect(rules[3].action.type == "ignore-previous-rules")
}

@Test func preprocessorUsesConservativeSafariIdentityByDefault() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        !#if ext_ublock
        ||ublock.example^
        !#else
        ||safari.example^
        !#endif
        """
    )

    let result = try NativeFilterCompiler().compile([source])

    let rules = try decodedSafariRules(result.safariRulesJSON)
    #expect(result.safariRuleCount == 1)
    #expect(rules[0].trigger.urlFilter.contains(#"safari\.example"#))
    #expect(!rules[0].trigger.urlFilter.contains(#"ublock\.example"#))
}

@Test func preprocessorCanOptIntoUBlockCompatibilityIdentity() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        !#if ext_ublock
        ||ublock.example^
        !#else
        ||safari.example^
        !#endif
        """
    )
    var configuration = FilterCompilerConfiguration()
    configuration.platform = .uBlockOriginCompatibility

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    let rules = try decodedSafariRules(result.safariRulesJSON)
    #expect(result.safariRuleCount == 1)
    #expect(rules[0].trigger.urlFilter.contains(#"ublock\.example"#))
    #expect(!rules[0].trigger.urlFilter.contains(#"safari\.example"#))
}

@Test func badfilterSuppressesMatchingRule() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        ||ads.example^$script
        ||ads.example^$script,badfilter
        ||other.example^$script
        """
    )

    let result = try NativeFilterCompiler().compile([source])

    let rules = try decodedSafariRules(result.safariRulesJSON)
    #expect(result.safariRuleCount == 1)
    #expect(!rules[0].trigger.urlFilter.contains(#"ads\.example"#))
    #expect(rules[0].trigger.urlFilter.contains(#"other\.example"#))
}

private struct DecodedRule: Decodable {
    let action: DecodedAction
    let trigger: DecodedTrigger
}

private struct DecodedAction: Decodable {
    let type: String
    let selector: String?
}

private struct DecodedTrigger: Decodable {
    let urlFilter: String
    let resourceType: [String]?
    let loadType: [String]?
    let ifDomain: [String]?

    enum CodingKeys: String, CodingKey {
        case urlFilter = "url-filter"
        case resourceType = "resource-type"
        case loadType = "load-type"
        case ifDomain = "if-domain"
    }
}

private func decodedSafariRules(_ json: String) throws -> [DecodedRule] {
    try JSONDecoder().decode([DecodedRule].self, from: Data(json.utf8))
}
