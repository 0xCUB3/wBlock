//
//  NativeFilterCompilerAdapter.swift
//  wBlockCoreService
//
//  Bridge from wBlockCoreService to the modular WBlockFilterCompiler package.
//

import Foundation
internal import WBlockFilterCompiler

enum NativeFilterCompilerAdapter {
    struct ConversionResult: Sendable, Equatable {
        let safariRulesJSON: String
        let safariRulesCount: Int
        let advancedRulesText: String?
        let unsupportedRuleCount: Int
        let diagnostics: CompilationDiagnostics
    }

    static func convert(
        rules: String,
        sourceIdentifier: String = "inline",
        displayName: String = "Inline rules",
        configuration: FilterCompilerConfiguration = FilterCompilerConfiguration(
            platform: .uBlockOriginCompatibility,
            enabledCapabilities: [.nativeCosmeticRules, .advancedScriptlets, .proceduralCosmetics, .redirects, .headerModification]
        )
    ) throws -> ConversionResult {
        let source = FilterSource(
            identifier: sourceIdentifier,
            displayName: displayName,
            text: rules
        )
        let result = try NativeFilterCompiler().compile([source], configuration: configuration)

        return ConversionResult(
            safariRulesJSON: result.safariRulesJSON,
            safariRulesCount: result.safariRuleCount,
            advancedRulesText: (result.advancedRules.ruleCount + result.advancedRules.exceptionRuleCount) > 0 ? try result.advancedRules.jsonString() : nil,
            unsupportedRuleCount: result.unsupportedRules.count,
            diagnostics: result.diagnostics
        )
    }
}
