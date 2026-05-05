import Foundation
import Testing
@testable import WBlockFilterCompiler

@Test func compilerBuildsAdvancedBundleForScriptletsAndProceduralCosmetics() throws {
    let source = FilterSource(
        identifier: "advanced",
        displayName: "Advanced",
        text: """
        example.com#%#//scriptlet('set-constant', 'foo.bar', 'undefined')
        example.com##.ad:has-text(Sponsored)
        other.com##+js(aopr, adBlockDetected)
        """
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)
    configuration.enabledCapabilities.insert(.proceduralCosmetics)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.advancedRules.ruleCount == 3)
    #expect(result.unsupportedRules.isEmpty)

    let runtime = AdvancedRuleRuntime(bundle: result.advancedRules)
    let example = runtime.lookup(host: "www.example.com")
    #expect(example.scriptlets == [AdvancedScriptlet(name: "set-constant", args: ["foo.bar", "undefined"])])
    #expect(example.extendedCss == [".ad:has-text(Sponsored)"])

    let other = runtime.lookup(host: "other.com")
    #expect(other.scriptlets == [AdvancedScriptlet(name: "ubo-aopr", args: ["adBlockDetected"])])
}

@Test func scriptletArgumentParserPreservesSelectorAttributeQuotes() throws {
    let source = FilterSource(
        identifier: "quoted-selector-scriptlet",
        displayName: "Quoted selector scriptlet",
        text: "example.com##+js(trusted-click-element, .dialog button[aria-label=\"Reject all\"], , 1000)"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.advancedRules.scriptlets == [
        AdvancedScriptletRule(
            scope: AdvancedDomainScope(ifDomains: ["example.com"]),
            name: "ubo-trusted-click-element",
            args: [".dialog button[aria-label=\"Reject all\"]", "", "1000"]
        )
    ])
}

@Test func scriptletArgumentParserPreservesRegexEscapesAndEscapedCommas() throws {
    let source = FilterSource(
        identifier: "escaped-scriptlet",
        displayName: "Escaped scriptlet",
        text: #"example.com##+js(trusted-rpnt, script, (function serverContract(), (()=>{const t=e.replace?.(/(Mozilla\/5\.0 \([^)]+)/\,"$1; channel")})();(function serverContract(), sedCount, 1)"#
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.advancedRules.scriptlets == [
        AdvancedScriptletRule(
            scope: AdvancedDomainScope(ifDomains: ["example.com"]),
            name: "ubo-trusted-rpnt",
            args: ["script", "(function serverContract()", "(()=>{const t=e.replace?.(/(Mozilla\\/5\\.0 \\([^)]+)/,\"$1; channel\")})();(function serverContract()", "sedCount", "1"]
        )
    ])
}

@Test func removeParamNetworkRulesCompileToAdvancedRuntimeScript() throws {
    let source = FilterSource(
        identifier: "removeparam",
        displayName: "Removeparam",
        text: "$removeparam=utm_source|utm_medium,to=example.com"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)
    let runtime = AdvancedRuleRuntime(bundle: result.advancedRules)
    let matched = runtime.lookup(host: "www.example.com")

    #expect(result.safariRuleCount == 0)
    #expect(result.unsupportedRules.isEmpty)
    #expect(matched.js.count == 1)
    #expect(matched.js[0].contains("utm_source|utm_medium"))
    #expect(matched.dnrRules.count == 1)
    #expect(matched.dnrRules[0].action.type == "redirect")
    #expect(matched.dnrRules[0].condition.urlFilter == "*")
    #expect(matched.dnrRules[0].condition.requestDomains == ["example.com"])
    #expect(matched.dnrRules[0].action.redirect?.transform?.queryTransform?.removeParams == ["utm_medium", "utm_source"])
    #expect(runtime.lookup(host: "example.org").js.isEmpty)
}

@Test func removeHeaderAndCSPRulesCompileToDynamicDNR() throws {
    let source = FilterSource(
        identifier: "headers",
        displayName: "Headers",
        text: """
        ||headers.example^$removeheader=set-cookie
        ||headers.example^$removeheader=request:cookie
        ||headers.example^$doc,csp=script-src 'none'
        ||headers.example^$doc,permissions=geolocation=()
        """
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)
    configuration.enabledCapabilities.insert(.headerModification)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)
    let dnr = AdvancedRuleRuntime(bundle: result.advancedRules).lookup(host: "headers.example").dnrRules

    #expect(result.safariRuleCount == 0)
    #expect(result.unsupportedRules.isEmpty)
    #expect(dnr.count == 4)
    #expect(dnr[0].action.type == "modifyHeaders")
    #expect(dnr[0].condition.urlFilter == "||headers.example^")
    #expect(dnr[0].condition.regexFilter == nil)
    #expect(dnr[0].action.responseHeaders == [AdvancedDNRModifyHeader(header: "set-cookie", operation: "remove")])
    #expect(dnr[1].action.requestHeaders == [AdvancedDNRModifyHeader(header: "cookie", operation: "remove")])
    #expect(dnr[2].action.responseHeaders == [AdvancedDNRModifyHeader(header: "content-security-policy", operation: "set", value: "script-src 'none'")])
    #expect(dnr[3].action.responseHeaders == [AdvancedDNRModifyHeader(header: "permissions-policy", operation: "set", value: "geolocation=()")])
}

@Test func redirectRulesCompileToDynamicDNRWhenResourceIsKnown() throws {
    let source = FilterSource(
        identifier: "redirect",
        displayName: "Redirect",
        text: "||cdn.example/ad.js$script,redirect=noopjs"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)
    configuration.enabledCapabilities.insert(.redirects)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)
    let runtime = AdvancedRuleRuntime(bundle: result.advancedRules)
    let matched = runtime.lookup(host: "unrelated.example")

    #expect(result.safariRuleCount == 0)
    #expect(result.unsupportedRules.isEmpty)
    #expect(matched.dnrRules.count == 1)
    #expect(matched.dnrRules[0].condition.urlFilter == "||cdn.example/ad.js")
    #expect(matched.dnrRules[0].condition.regexFilter == nil)
    #expect(matched.dnrRules[0].action.redirect?.extensionPath == "/web_accessible_resources/noop.js")
}

@Test func broadResourceRedirectRulesDoNotCompileToDynamicDNR() throws {
    let source = FilterSource(
        identifier: "broad-redirect",
        displayName: "Broad Redirect",
        text: "*$script,redirect=noopjs"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)
    configuration.enabledCapabilities.insert(.redirects)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)
    let dnr = AdvancedRuleRuntime(bundle: result.advancedRules).lookup(host: "example.com").dnrRules

    #expect(dnr.isEmpty)
}

@Test func rawRegexNetworkRulesDoNotCompileToDynamicDNR() throws {
    let source = FilterSource(
        identifier: "regex-dnr",
        displayName: "Regex DNR",
        text: "/^https?:\\/\\/ads\\.example\\/.*\\.js$/$script,redirect=noopjs"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)
    configuration.enabledCapabilities.insert(.redirects)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)
    let dnr = AdvancedRuleRuntime(bundle: result.advancedRules).lookup(host: "example.com").dnrRules

    #expect(dnr.isEmpty)
}

@Test func urlSkipAndUriTransformCompileToAdvancedRuntimeScripts() throws {
    let source = FilterSource(
        identifier: "urlskip",
        displayName: "URL skip",
        text: """
        /go?target=http$doc,to=redirect.example,urlskip=?target +https
        /ref=$doc,to=shop.example,uritransform=/\\/ref=[^\\/?#]+//
        """
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)
    let runtime = AdvancedRuleRuntime(bundle: result.advancedRules)

    #expect(result.safariRuleCount == 0)
    #expect(result.unsupportedRules.isEmpty)
    #expect(runtime.lookup(host: "redirect.example").js.count == 1)
    #expect(runtime.lookup(host: "shop.example").js.count == 1)
}

@Test func styleActionCosmeticsCompileToAdvancedRuntimeOnly() throws {
    let source = FilterSource(
        identifier: "style-action",
        displayName: "Style action",
        text: "example.com##body:style(overflow: auto !important;)"
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.proceduralCosmetics)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.safariRuleCount == 0)
    #expect(result.advancedRules.extendedCss.map(\.content) == ["body:style(overflow: auto !important;)"])
}

@Test func advancedExceptionsRemoveExactMatchingRules() throws {
    let source = FilterSource(
        identifier: "advanced-exceptions",
        displayName: "Advanced exceptions",
        text: """
        example.com##+js(aopr, adBlockDetected)
        example.com#@#+js(aopr, adBlockDetected)
        example.com##.ad:has-text(Sponsored)
        example.com#@#.ad:has-text(Sponsored)
        """
    )
    var configuration = FilterCompilerConfiguration()
    configuration.enabledCapabilities.insert(.advancedScriptlets)
    configuration.enabledCapabilities.insert(.proceduralCosmetics)

    let result = try NativeFilterCompiler().compile([source], configuration: configuration)

    #expect(result.advancedRules.ruleCount == 0)
}

@Test func advancedRuntimeRespectsDomainScopesAndJSONRoundTrip() throws {
    let bundle = AdvancedRuleBundle(
        css: [AdvancedStyleRule(scope: AdvancedDomainScope(ifDomains: ["example.com"], unlessDomains: ["excluded.example.com"]), content: ".ad")],
        scriptlets: [AdvancedScriptletRule(scope: AdvancedDomainScope(ifDomains: ["example.com"]), name: "ubo-set", args: ["x", "false"])]
    )

    let decoded = try AdvancedRuleBundle.decode(jsonString: try bundle.jsonString())
    let runtime = AdvancedRuleRuntime(bundle: decoded)

    let matched = runtime.lookup(host: "sub.example.com")
    #expect(matched.css == [".ad"])
    #expect(matched.scriptlets == [AdvancedScriptlet(name: "ubo-set", args: ["x", "false"])])

    let excluded = runtime.lookup(host: "excluded.example.com")
    #expect(excluded.css.isEmpty)
    #expect(excluded.scriptlets == [AdvancedScriptlet(name: "ubo-set", args: ["x", "false"])])

    let unrelated = runtime.lookup(host: "example.org")
    #expect(unrelated.css.isEmpty)
    #expect(unrelated.scriptlets.isEmpty)
}

@Test func advancedBundleCombineAppliesExceptionsAcrossBundles() throws {
    let scope = AdvancedDomainScope(ifDomains: ["www.youtube.com"])
    let disabledQuickFix = AdvancedScriptletRule(
        scope: scope,
        name: "ubo-trusted-rpnt",
        args: ["script", "needle", "replacement", "sedCount", "1"]
    )
    let activeBundle = AdvancedRuleBundle(scriptlets: [disabledQuickFix])
    let exceptionBundle = AdvancedRuleBundle(scriptletExceptions: [disabledQuickFix])

    let combined = AdvancedRuleBundle.combine([activeBundle, exceptionBundle])

    #expect(combined.scriptlets.isEmpty)
    #expect(combined.scriptletExceptions == [disabledQuickFix])
}

@Test func advancedRuleBundleDecodesLegacyJSONWithoutExceptionFields() throws {
    let legacyJSON = #"{"css":[],"engineTimestamp":1,"extendedCss":[],"formatVersion":"wblock-advanced-rules-v1","js":[],"scriptlets":[]}"#

    let decoded = try AdvancedRuleBundle.decode(jsonString: legacyJSON)

    #expect(decoded.extendedCssExceptions.isEmpty)
    #expect(decoded.scriptletExceptions.isEmpty)
    #expect(decoded.dnrRules.isEmpty)
}
