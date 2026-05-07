import Foundation

enum FilterPreprocessorEngine {
    static func evaluateConditionals(_ lines: [SourceLine], platform: FilterPlatform) -> [SourceLine] {
        resolveConditions(lines, platform: platform)
    }

    private static func resolveConditions(_ lines: [SourceLine], platform: FilterPlatform) -> [SourceLine] {
        var result: [SourceLine] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed == "!#if" || trimmed.hasPrefix("!#if ") {
                let endIndex = findBlockEnd(lines: lines, seeking: "!#endif", from: index + 1, to: lines.count)
                guard endIndex != -1 else {
                    index += 1
                    continue
                }

                let elseIndex = findBlockEnd(lines: lines, seeking: "!#else", from: index + 1, to: endIndex)
                let conditionMet = evaluateCondition(trimmed, platform: platform)

                if conditionMet {
                    let end = elseIndex == -1 ? endIndex : elseIndex
                    result += resolveConditions(Array(lines[(index + 1)..<end]), platform: platform)
                } else if elseIndex != -1 {
                    result += resolveConditions(Array(lines[(elseIndex + 1)..<endIndex]), platform: platform)
                }

                index = endIndex + 1
            } else if trimmed.hasPrefix("!#else") || trimmed.hasPrefix("!#endif") {
                index += 1
            } else {
                result.append(lines[index])
                index += 1
            }
        }

        return result
    }

    private static func findBlockEnd(lines: [SourceLine], seeking target: String, from start: Int, to end: Int) -> Int {
        var depth = 0

        for index in start..<end {
            let trimmed = lines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "!#if" || trimmed.hasPrefix("!#if ") {
                depth += 1
            } else if trimmed.hasPrefix("!#endif") {
                if depth == 0 {
                    return target == "!#endif" ? index : -1
                }
                depth -= 1
            } else if trimmed.hasPrefix(target) && depth == 0 {
                return index
            }
        }

        return -1
    }

    private static func evaluateCondition(_ ifLine: String, platform: FilterPlatform) -> Bool {
        let prefix = "!#if "
        guard ifLine.hasPrefix(prefix) else { return false }
        let expression = String(ifLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        guard !expression.isEmpty else { return false }
        return ConditionalExpressionEvaluator(platform: platform).evaluate(expression)
    }
}

private struct ConditionalExpressionEvaluator {
    let platform: FilterPlatform

    func evaluate(_ raw: String) -> Bool {
        let expression = raw.trimmingCharacters(in: .whitespaces)
        guard !expression.isEmpty else { return false }

        if let openIndex = expression.lastIndex(of: "("),
           let afterOpen = expression.index(openIndex, offsetBy: 1, limitedBy: expression.endIndex),
           let closeIndex = expression[afterOpen...].firstIndex(of: ")") {
            let inner = String(expression[afterOpen..<closeIndex])
            let innerResult = evaluate(inner)
            let rebuilt = expression[..<openIndex] + (innerResult ? "true" : "false") + expression[expression.index(after: closeIndex)...]
            return evaluate(String(rebuilt))
        }

        if let range = expression.range(of: "||") {
            return evaluate(String(expression[..<range.lowerBound])) || evaluate(String(expression[range.upperBound...]))
        }

        if let range = expression.range(of: "&&") {
            return evaluate(String(expression[..<range.lowerBound])) && evaluate(String(expression[range.upperBound...]))
        }

        if expression.hasPrefix("!") {
            return !evaluate(String(expression.dropFirst()))
        }

        return platformConstant(expression)
    }

    private func platformConstant(_ name: String) -> Bool {
        switch name.trimmingCharacters(in: .whitespaces) {
        case "true": return true
        case "false": return false
        case "env_safari": return true
        case "env_mobile":
            #if os(iOS)
            return true
            #else
            return false
            #endif
        case "ext_ublock": return platform == .uBlockOriginCompatibility
        case "adguard", "adguard_ext_safari": return platform == .safariCompatible
        default: return false
        }
    }
}
