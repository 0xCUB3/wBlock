import Foundation

enum RuleClassifier {
    static func classify(_ line: String) -> RuleKind {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") {
            return trimmed.hasPrefix("!#") ? .preprocessor : .comment
        }

        if trimmed.hasPrefix("@@") {
            return .networkException
        }

        if trimmed.contains("##^") {
            return .htmlFiltering
        }

        if trimmed.contains("##+js") || trimmed.contains("#%#") {
            return .scriptlet
        }

        if trimmed.contains("#@%#") {
            return .scriptletException
        }

        if isProceduralCosmetic(trimmed) {
            return .proceduralCosmetic
        }

        if trimmed.contains("#@#") {
            return .cosmeticException
        }

        if trimmed.contains("##") {
            return .cosmetic
        }

        if containsKnownUnsupportedModifier(trimmed) {
            return .unsupported
        }

        return .network
    }

    static func unsupportedReason(
        for kind: RuleKind,
        line: String,
        configuration: FilterCompilerConfiguration
    ) -> UnsupportedReason? {
        switch kind {
        case .htmlFiltering:
            return .htmlFiltering
        case .scriptlet, .scriptletException:
            return configuration.enabledCapabilities.contains(.advancedScriptlets) ? nil : .scriptletRequiresAdvancedRuntime
        case .proceduralCosmetic:
            return configuration.enabledCapabilities.contains(.proceduralCosmetics) ? nil : .proceduralCosmeticRequiresAdvancedRuntime
        case .cosmeticException:
            return .cosmeticExceptionNeedsPlanner
        case .unsupported:
            return reasonForUnsupportedModifier(line) ?? .unknownSyntax
        default:
            return nil
        }
    }

    private static func isProceduralCosmetic(_ line: String) -> Bool {
        line.contains("#?#") ||
        line.contains(":has-text") ||
        line.contains(":xpath") ||
        line.contains(":upward") ||
        line.contains(":remove()") ||
        line.contains(":matches-css") ||
        line.contains(":matches-attr") ||
        line.contains(":matches-property") ||
        line.contains(":watch-attr")
    }

    private static func containsKnownUnsupportedModifier(_ line: String) -> Bool {
        reasonForUnsupportedModifier(line) != nil
    }

    private static func reasonForUnsupportedModifier(_ line: String) -> UnsupportedReason? {
        guard let dollar = line.firstIndex(of: "$") else { return nil }
        let options = String(line[line.index(after: dollar)...]).lowercased()
        let tokens = options.split(separator: ",").map(String.init)

        for token in tokens {
            let name = token.split(separator: "=", maxSplits: 1).first.map(String.init) ?? token
            switch name.trimmingCharacters(in: .whitespaces) {
            case "header": return .responseHeaderFiltering
            case "replace": return .responseBodyReplacement
            default: continue
            }
        }

        return nil
    }
}
