import Testing
@testable import WBlockFilterCompiler

@Test func validatorAcceptsCompilerOutputAndChecksRuleCount() throws {
    let source = FilterSource(
        identifier: "fixture",
        displayName: "Fixture",
        text: "||example.com^\nexample.com##.ad"
    )

    let result = try NativeFilterCompiler().compile([source])

    try SafariContentBlockerJSONValidator.validate(
        result.safariRulesJSON,
        expectedRuleCount: result.safariRuleCount
    )
    #expect(try SafariContentBlockerJSONValidator.ruleCount(in: result.safariRulesJSON) == 2)
}
