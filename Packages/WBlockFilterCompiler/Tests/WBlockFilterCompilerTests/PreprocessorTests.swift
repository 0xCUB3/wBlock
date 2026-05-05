import Testing
@testable import WBlockFilterCompiler

@Test func foldsUBlockLineContinuationsBeforeParsing() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        ||example.com^$script, \\
          third-party
        """
    )

    let result = try NativeFilterCompiler().compile([source])

    #expect(result.unsupportedRules.isEmpty)
    #expect(result.safariRuleCount == 1)
    #expect(result.safariRulesJSON.contains("third-party"))
}

@Test func nestedConditionalsAreEvaluated() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: """
        !#if env_safari
        !#if ext_ublock
        ||ubo.example^
        !#else
        ||safari.example^
        !#endif
        !#endif
        """
    )

    let result = try NativeFilterCompiler().compile([source])

    #expect(result.safariRuleCount == 1)
    #expect(result.safariRulesJSON.contains("safari"))
}
