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
