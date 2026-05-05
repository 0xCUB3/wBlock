import Foundation
import Testing
@testable import WBlockFilterCompiler

@Test func regexRuleOptionsSplitAtTrailingDelimiter() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: #"/ads-[0-9]+\.js$/$script,1p,domain=example.com"#
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedDetailedNetworkRules(result.safariRulesJSON)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.safariRuleCount == 1)
    #expect(rules[0].trigger.urlFilter == #"ads-[0-9]+\.js$"#)
    #expect(rules[0].trigger.resourceType == ["script"])
    #expect(rules[0].trigger.loadType == ["first-party"])
    #expect(rules[0].trigger.ifDomain == ["example.com"])
}

@Test func cookieRulesEmitSafariBlockCookiesAction() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: "||tracker.example^$cookie,third-party"
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedNetworkRules(result.safariRulesJSON)

    #expect(result.safariRuleCount == 1)
    #expect(rules[0].action.type == "block-cookies")
}

@Test func negatedPartyOptionsMapToOppositeSafariLoadType() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        ||adblock-tester.com/banners/$~third-party
        ||cdn.example/ad.js$~first-party
        """
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedDetailedNetworkRules(result.safariRulesJSON)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.safariRuleCount == 2)
    #expect(rules[0].trigger.loadType == ["first-party"])
    #expect(rules[1].trigger.loadType == ["third-party"])
}

@Test func redirectBlockRulesFallBackToBlocking() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: "||googletagmanager.com/gtag/js$script,xhr,redirect=googletagmanager_gtm.js:5"
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedDetailedNetworkRules(result.safariRulesJSON)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.safariRuleCount == 1)
    #expect(rules[0].action.type == "block")
    #expect(Set(rules[0].trigger.resourceType ?? []) == ["raw", "script"])
}

@Test func slashPrefixedPlainPatternsStillSplitOptions() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: "/banners/pr_advertising_ads_banner.$image,domain=adblock-tester.com"
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedDetailedNetworkRules(result.safariRulesJSON)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.safariRuleCount == 1)
    #expect(rules[0].trigger.urlFilter == #"/banners/pr_advertising_ads_banner\."#)
    #expect(rules[0].trigger.resourceType == ["image"])
    #expect(rules[0].trigger.ifDomain == ["adblock-tester.com"])
}

@Test func strictPartyOptionsMapToNearestSafariLoadType() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        ||first.example^$strict1p
        ||third.example^$strict3p
        """
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedDetailedNetworkRules(result.safariRulesJSON)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.safariRuleCount == 2)
    #expect(rules[0].trigger.loadType == ["first-party"])
    #expect(rules[1].trigger.loadType == ["third-party"])
}

@Test func denyAllowExpandsToScopedSafariExceptions() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: "*$script,3p,denyallow=google.com|gstatic.com,domain=example.com"
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedDetailedNetworkRules(result.safariRulesJSON)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.safariRuleCount == 3)
    #expect(rules[0].action.type == "block")
    #expect(rules[0].trigger.urlFilter == ".*")
    #expect(rules[0].trigger.ifDomain == ["example.com"])
    #expect(rules[1].action.type == "ignore-previous-rules")
    #expect(rules[1].trigger.urlFilter == #"^[a-z][a-z0-9+.-]*://([^/?#]+\.)?google\.com(?:[^A-Za-z0-9_\-.%]|$)"#)
    #expect(rules[2].action.type == "ignore-previous-rules")
    #expect(rules[2].trigger.urlFilter == #"^[a-z][a-z0-9+.-]*://([^/?#]+\.)?gstatic\.com(?:[^A-Za-z0-9_\-.%]|$)"#)
}

@Test func wildcardToDomainsExpandToDestinationRules() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: "*$xhr,to=amazon.*|x.com"
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedDetailedNetworkRules(result.safariRulesJSON)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.safariRuleCount == 2)
    #expect(rules.map { $0.action.type } == ["block", "block"])
    #expect(rules.map { $0.trigger.resourceType ?? [] } == [["raw"], ["raw"]])
    #expect(rules[0].trigger.urlFilter == #"^[a-z][a-z0-9+.-]*://([^/?#]+\.)?amazon\..*(?:[^A-Za-z0-9_\-.%]|$)"#)
    #expect(rules[1].trigger.urlFilter == #"^[a-z][a-z0-9+.-]*://([^/?#]+\.)?x\.com(?:[^A-Za-z0-9_\-.%]|$)"#)
}

@Test func mixedBlockingDomainOptionsEmitContextException() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: "||ads.example^$script,domain=example.com|~accounts.example.com"
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedDetailedNetworkRules(result.safariRulesJSON)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.safariRuleCount == 2)
    #expect(rules[0].action.type == "block")
    #expect(rules[0].trigger.ifDomain == ["example.com"])
    #expect(rules[1].action.type == "ignore-previous-rules")
    #expect(rules[1].trigger.ifDomain == ["accounts.example.com"])
}

@Test func importantBlockingRulesAreEmittedAfterNormalExceptions() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        ||ads.example^
        @@||ads.example^
        ||ads.example^$important
        """
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try decodedNetworkRules(result.safariRulesJSON)

    #expect(rules.map { $0.action.type } == ["block", "ignore-previous-rules", "block"])
}

private struct DecodedNetworkRule: Decodable {
    let action: DecodedNetworkAction
}

private struct DecodedDetailedNetworkRule: Decodable {
    let action: DecodedNetworkAction
    let trigger: DecodedNetworkTrigger
}

private struct DecodedNetworkAction: Decodable {
    let type: String
}

private struct DecodedNetworkTrigger: Decodable {
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

private func decodedNetworkRules(_ json: String) throws -> [DecodedNetworkRule] {
    try JSONDecoder().decode([DecodedNetworkRule].self, from: Data(json.utf8))
}

private func decodedDetailedNetworkRules(_ json: String) throws -> [DecodedDetailedNetworkRule] {
    try JSONDecoder().decode([DecodedDetailedNetworkRule].self, from: Data(json.utf8))
}
