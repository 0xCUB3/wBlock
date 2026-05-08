import Foundation
import Testing
@testable import WBlockFilterCompiler

@Test func methodNetworkRulesCompileToMethodScopedDynamicDNR() throws {
    let source = FilterSource(
        identifier: "method",
        displayName: "Method",
        text: "/bnf6.txt^$xhr,method=head,to=ublockorigin.github.io|localhost"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.safariRuleCount == 0)
    #expect(result.unsupportedRules.isEmpty)
    #expect(result.advancedRules.dnrRules.count == 1)
    #expect(result.advancedRules.dnrRules[0].action.type == "block")
    #expect(result.advancedRules.dnrRules[0].condition.requestMethods == ["head"])
    #expect(result.advancedRules.dnrRules[0].condition.resourceTypes == ["other", "ping", "websocket", "xmlhttprequest"])
    #expect(result.advancedRules.dnrRules[0].condition.requestDomains == ["localhost", "ublockorigin.github.io"])
}

@Test func uBOLProceduralCosmeticDelimiterKeepsDomainScope() throws {
    let source = FilterSource(
        identifier: "procedural",
        displayName: "Procedural",
        text: "ublockorigin.github.io,localhost#?##pcf7 .fail:has-text(needle)"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.proceduralCosmetics)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.advancedRules.extendedCss == [
        AdvancedStyleRule(
            scope: AdvancedDomainScope(ifDomains: ["localhost", "ublockorigin.github.io"]),
            content: "#pcf7 .fail:has-text(needle)"
        )
    ])
    #expect(AdvancedRuleRuntime(bundle: result.advancedRules).lookup(host: "localhost").extendedCss == ["#pcf7 .fail:has-text(needle)"])
}

@Test func uBlockRemoveParamUsesDNRWithoutGlobalPageScriptFallback() throws {
    let source = FilterSource(
        identifier: "removeparam-dnr",
        displayName: "removeparam DNR",
        text: """
        *$removeparam=fbclid
        *$removeparam
        """
    )
    var configuration = FilterCompilerConfiguration(platform: .uBlockOriginCompatibility)
    configuration.enabledCapabilities.insert(.advancedScriptlets)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.advancedRules.js.isEmpty)
    #expect(result.advancedRules.dnrRules.count == 1)
    #expect(result.advancedRules.dnrRules[0].condition.urlFilter == "^fbclid=")
    #expect(result.advancedRules.dnrRules[0].action.redirect?.transform?.queryTransform?.removeParams == ["fbclid"])
}

@Test func fragileYouTubeNodeTextScriptletsAreSuppressedButRequestEditorsRemainEnabled() throws {
    let source = FilterSource(
        identifier: "youtube-quick-fixes",
        displayName: "YouTube quick fixes",
        text: """
        www.youtube.com##+js(trusted-rpnt, script, (function serverContract(), (()=>{const e=document.getElementById("movie_player"); e.getStatsForNerds?.(); e.loadVideoById("id", 0); window.Promise.prototype.then=new Proxy(window.Promise.prototype.then,{apply:(e,t,o)=>{const n=o[0];return typeof n==="function"&&n.toString().includes("onAbnormalityDetected")&&(o[0]=function(){}),Reflect.apply(e,t,o)}})})();(function serverContract(), sedCount, 1)
        www.youtube.com##+js(trusted-json-edit-xhr-request, [?..userAgent*="channel"]..client[?.clientName=="WEB"]+={"clientScreen":"CHANNEL"}, propsToMatch, /player?)
        www.youtube.com##+js(json-prune-fetch-response, adPlacements adSlots, , propsToMatch, /player?)
        example.com##+js(trusted-json-edit-xhr-request, [?..userAgent*="channel"]..client[?.clientName=="WEB"]+={"clientScreen":"CHANNEL"}, propsToMatch, /player?)
        """
    )
    var configuration = FilterCompilerConfiguration(platform: .uBlockOriginCompatibility)
    configuration.enabledCapabilities.insert(.advancedScriptlets)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)
    let scriptlets = result.advancedRules.scriptlets

    #expect(scriptlets.map(\.name) == ["ubo-trusted-json-edit-xhr-request", "ubo-json-prune-fetch-response", "ubo-trusted-json-edit-xhr-request"])
    #expect(scriptlets[0].scope.matches(host: "www.youtube.com"))
    #expect(scriptlets[1].scope.matches(host: "www.youtube.com"))
    #expect(scriptlets[2].scope.matches(host: "example.com"))
}

@Test func redirect32x32CompilesToPackagedDynamicDNRResource() throws {
    let source = FilterSource(
        identifier: "redirect",
        displayName: "Redirect",
        text: "/anf1.$image,redirect=32x32.png,from=ublockorigin.github.io|localhost"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.redirects)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.safariRuleCount == 0)
    #expect(result.unsupportedRules.isEmpty)
    #expect(result.advancedRules.dnrRules.count == 1)
    #expect(result.advancedRules.dnrRules[0].action.redirect?.extensionPath == "/web_accessible_resources/32x32.png")
    #expect(result.advancedRules.dnrRules[0].condition.initiatorDomains == ["localhost", "ublockorigin.github.io"])
}

@Test func genericCosmeticRulesAlsoCompileToAdvancedRuntimeCSS() throws {
    let source = FilterSource(
        identifier: "generic-cosmetic",
        displayName: "Generic cosmetic",
        text: """
        ###ccf #a1 .fail
        ###ccf #a2 .fail:not(.a2)
        ###ccf #a6 .fail-pseudo::before
        """
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.nativeCosmeticRules)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)
    let matched = AdvancedRuleRuntime(bundle: result.advancedRules).lookup(host: "gorhill.github.io")

    #expect(result.safariRuleCount == 1)
    #expect(matched.css == [
        "#ccf #a1 .fail",
        "#ccf #a2 .fail:not(.a2)",
        "#ccf #a6 .fail-pseudo::before",
    ])
}

@Test func gorhillProceduralRemainingSelectorsCompileToAdvancedRuntime() throws {
    let source = FilterSource(
        identifier: "gorhill-procedural-remaining",
        displayName: "Gorhill procedural remaining cosmetics",
        text: """
        gorhill.github.io#?##pcf #a4 .fail:has(:scope + a > b)
        gorhill.github.io#?##pcf #a11 .fail:has(a:matches-css-before(opacity: 0))
        gorhill.github.io#?##pcf #a12 .fail:has(b:matches-css-after(opacity: 0))
        gorhill.github.io#?##pcf #a15 .fail:min-text-length(300)
        gorhill.github.io#?##pcf #a20 .fail:has(~ a:has(b))
        """
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.proceduralCosmetics)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.advancedRules.extendedCss.map(\.content) == [
        "#pcf #a4 .fail:has(:scope + a > b)",
        "#pcf #a11 .fail:has(a:matches-css-before(opacity: 0))",
        "#pcf #a12 .fail:has(b:matches-css-after(opacity: 0))",
        "#pcf #a15 .fail:min-text-length(300)",
        "#pcf #a20 .fail:has(~ a:has(b))",
    ])
}

@Test func gorhillProceduralHTMLFiltersCompileToRemovalRuntime() throws {
    let source = FilterSource(
        identifier: "gorhill-procedural-html",
        displayName: "Gorhill procedural HTML filters",
        text: """
        gorhill.github.io##^#phf #a1 .fail:has(b)
        gorhill.github.io##^#phf #a8:xpath(.//b/../..)
        gorhill.github.io##^#phf #a9 .fail:min-text-length(300)
        """
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.proceduralCosmetics)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.advancedRules.extendedCss == [
        AdvancedStyleRule(scope: AdvancedDomainScope(ifDomains: ["gorhill.github.io"]), content: "^#phf #a1 .fail:has(b)"),
        AdvancedStyleRule(scope: AdvancedDomainScope(ifDomains: ["gorhill.github.io"]), content: "^#phf #a8:xpath(.//b/../..)"),
        AdvancedStyleRule(scope: AdvancedDomainScope(ifDomains: ["gorhill.github.io"]), content: "^#phf #a9 .fail:min-text-length(300)"),
    ])
}

@Test func gorhillProceduralNthAncestorCompilesToAdvancedRuntime() throws {
    let source = FilterSource(
        identifier: "gorhill-procedural",
        displayName: "Gorhill procedural cosmetics",
        text: "gorhill.github.io#?##pcf #a13 .fail > a > b:nth-ancestor(2)"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.proceduralCosmetics)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.advancedRules.extendedCss == [
        AdvancedStyleRule(
            scope: AdvancedDomainScope(ifDomains: ["gorhill.github.io"]),
            content: "#pcf #a13 .fail > a > b:nth-ancestor(2)"
        )
    ])
}

@Test func descendantFrameScriptletScopeNormalizesUBlockDomainSuffix() throws {
    let source = FilterSource(
        identifier: "descendant-frame-scriptlet",
        displayName: "Descendant frame scriptlet",
        text: "ublockorigin.github.io>>,localhost>>##+js(set, sf3Sentinel, undefined)"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.advancedRules.scriptlets == [
        AdvancedScriptletRule(
            scope: AdvancedDomainScope(ifDomains: ["localhost", "ublockorigin.github.io"]),
            name: "ubo-set",
            args: ["sf3Sentinel", "undefined"]
        )
    ])
}

@Test func uBOLTestFilterCompilerCoverage() throws {
    let source = FilterSource(
        identifier: "ubol-test-filters",
        displayName: "uBO Lite Test Filters",
        text: ubolTestFilters
    )
    var configuration = FilterCompilerConfiguration(platform: .uBlockOriginCompatibility)
    configuration.enabledCapabilities = [.nativeCosmeticRules, .advancedScriptlets, .proceduralCosmetics, .redirects, .headerModification]

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)
    let unsupported = Dictionary(grouping: result.unsupportedRules, by: \.reason).mapValues(\.count)

    #expect(result.safariRuleCount == 8)
    #expect(result.advancedRules.dnrRules.count == 4)
    #expect(result.advancedRules.extendedCss.count >= 24)
    #expect(result.advancedRules.scriptlets.count == 7)
    #expect(unsupported == [
        .noSafariEquivalent: 1,
        .responseBodyReplacement: 1,
    ])
}

private let ubolTestFilters = """
! Title: uBO Lite Test Filters
! Description: Filters used to test uBO Lite
! Homepage: https://ublockorigin.github.io/uBOL-home/tests/test-filters.html

! Basic network filtering
/bnf1.$script,to=ublockorigin.github.io|localhost
/bnf2.$image,to=ublockorigin.github.io|localhost
/bnf5.js^$script,to=ublockorigin.github.io|localhost
/bnf6.txt^$xhr,method=head,to=ublockorigin.github.io|localhost

! Advanced network filtering
/anf1.$image,redirect=32x32.png,from=ublockorigin.github.io|localhost
/anf2.html$frame,csp=script-src 'none',to=ublockorigin.github.io|localhost
/anf3.html$removeparam=b,to=ublockorigin.github.io|localhost

! Specific cosmetic filtering
ublockorigin.github.io,localhost###ccf1 .fail
ublockorigin.github.io,localhost###ccf2 .fail:not(.a4)
ublockorigin.github.io,localhost###ccf3 .fail:style(visibility: hidden)
ublockorigin.github.io,localhost###ccf4 .fail-pseudo::before
ublockorigin.github.io,localhost###ccf5 .fail-pseudo::before:style(visibility: hidden)

! Procedural cosmetic filtering
ublockorigin.github.io,localhost#?##pcf1 .fail:has(b)
ublockorigin.github.io,localhost#?##pcf2 .fail:has(> a > b)
ublockorigin.github.io,localhost#?##pcf3 .fail:has(+ a > b)
ublockorigin.github.io,localhost#?##pcf5 .fail:has(:is(.pass a > b))
ublockorigin.github.io,localhost#?##pcf6 .fail:not(:has(c))
ublockorigin.github.io,localhost#?##pcf7 .fail:has-text(needle)
ublockorigin.github.io,localhost#?##pcf8 .fail:has-text(/NEEDLE/i)
ublockorigin.github.io,localhost#?##pcf9 .fail:not(:has-text(haystack))
ublockorigin.github.io,localhost#?##pcf10 .fail:matches-css(position: absolute)
ublockorigin.github.io,localhost#?##pcf11 .fail:has(a:matches-css-before(opacity: 0))
ublockorigin.github.io,localhost#?##pcf12 .fail:has(b:matches-css-after(opacity: 0))
ublockorigin.github.io,localhost#?##pcf13 .fail > a > b:upward(2)
ublockorigin.github.io,localhost#?##pcf14:xpath(.//b/../..)
ublockorigin.github.io,localhost#?##pcf15 .fail:min-text-length(300)
ublockorigin.github.io,localhost#?##pcf16 .pass > a:has(b) + .fail
ublockorigin.github.io,localhost#?##pcf17 .pass > a:has(b) + .fail:has(b)
ublockorigin.github.io,localhost#?##pcf18 .pass:watch-attr(class) > .fail:has(b.notok)
ublockorigin.github.io,localhost#?##pcf19 .fail:has(+ a)
ublockorigin.github.io,localhost#?##pcf20 .fail:has(~ a:has(b))
ublockorigin.github.io,localhost#?##pcf21 .fail:remove()
ublockorigin.github.io,localhost#?##pcf22 b:upward(2)
ublockorigin.github.io,localhost#?##pcf23 b:upward(.fail)
ublockorigin.github.io,localhost#?##pcf24 b:upward(.fail):style(visibility: hidden !important)

! Scriptlets filtering
ublockorigin.github.io,localhost##+js(set, sf1Sentinel, undefined)
ublockorigin.github.io,localhost##+js(nostif, sf2Sentinel)
ublockorigin.github.io>>,localhost>>##+js(set, sf3Sentinel, undefined)
ublockorigin.github.io,localhost##+js(jsonl-edit-xhr-response, .b, propsToMatch, /sample.jsonl)
ublockorigin.github.io,localhost##+js(jsonl-edit-fetch-response, .b, propsToMatch, /sample.jsonl)
ublockorigin.github.io,localhost##+js(trusted-prevent-dom-bypass, Node.prototype.appendChild, Element.prototype.getElementsByTagName)
ublockorigin.github.io,localhost##+js(prevent-innerHTML, #sf7 .fail, <b>)

! Generic cosmetic filters
###gcf #gcf1 .fail
! Override EasyList's generichide exception
*$generichide,important,to=ublockorigin.github.io|localhost

! Exception filters
/bnf3.
@@/bnf3\\.js$/$from=ublockorigin.github.io|localhost
###ef #gcf2 .fail
ublockorigin.github.io,localhost#@##ef #gcf2 .fail

! Firefox MV2 uBO
/sample.json|$xhr,replace='json:..price=0',to=ublockorigin.github.io|localhost
ublockorigin.github.io/uBOL-home/tests/test-filters,localhost/test-filters.html##^#ffubo2 > script
"""
