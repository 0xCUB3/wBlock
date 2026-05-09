import Foundation
import Testing
@testable import WBlockFilterCompiler

@Test func translatesCommonABPPatternsToSafariURLFilters() {
    #expect(SafariURLFilterTranslator.translate("||example.com^") == #"^[a-z][a-z0-9+.-]*://([^/?#]+\.)?example\.com[^A-Za-z0-9_.%-]?"#)
    #expect(SafariURLFilterTranslator.translate("|https://example.com/ad.js") == #"^https://example\.com/ad\.js"#)
    #expect(SafariURLFilterTranslator.translate("/ads-[0-9]+\\.js/") == #"ads-[0-9]+\.js"#)
    #expect(SafariURLFilterTranslator.translate("ads*banner") == #"ads.*banner"#)
}

@Test func compilerSkipsSafariUnsupportedRawRegexRules() throws {
    let source = FilterSource(
        identifier: "raw-regex",
        displayName: "Raw regex",
        text: #"""
        /(https?:\/\/)\w{30,}\.me\/\w{30,}\./
        /^https:\/\/supervideo\.cc/[0-9]+\.js\b/
        /\/img\/(?!new).+\.gif/
        """#
    )

    let result = try NativeFilterCompiler().compile([source])

    #expect(result.safariRuleCount == 0)
    #expect(result.unsupportedRules.map(\.reason) == [.noSafariEquivalent, .noSafariEquivalent, .noSafariEquivalent])
}

@Test func compilerPunycodeEncodesAndFiltersSafariDomainConditions() throws {
    let source = FilterSource(
        identifier: "idn-domain",
        displayName: "IDN domain",
        text: "||ads.example^$domain=täst.de|MÜNCHEN.de|/^main\\.uxsyplayer[a-z0-9-]+\\.click$/"
    )

    let result = try NativeFilterCompiler().compile([source])
    let rules = try #require(JSONSerialization.jsonObject(with: Data(result.safariRulesJSON.utf8)) as? [[String: Any]])
    let trigger = try #require(rules[0]["trigger"] as? [String: Any])

    #expect(trigger["if-domain"] as? [String] == ["xn--mnchen-3ya.de", "xn--tst-qla.de"])
}
