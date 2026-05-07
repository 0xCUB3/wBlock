import Testing
@testable import WBlockFilterCompiler

@Test func translatesCommonABPPatternsToSafariURLFilters() {
    #expect(SafariURLFilterTranslator.translate("||example.com^") == #"^[a-z][a-z0-9+.-]*://([^/?#]+\.)?example\.com(?:[^A-Za-z0-9_\-.%]|$)"#)
    #expect(SafariURLFilterTranslator.translate("|https://example.com/ad.js") == #"^https://example\.com/ad\.js"#)
    #expect(SafariURLFilterTranslator.translate("/ads-[0-9]+\\.js/") == #"ads-[0-9]+\.js"#)
    #expect(SafariURLFilterTranslator.translate("ads*banner") == #"ads.*banner"#)
}
