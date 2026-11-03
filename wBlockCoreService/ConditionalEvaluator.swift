//
//  ConditionalEvaluator.swift
//  wBlockCoreService
//
//  Evaluates !#if / !#else / !#endif conditional blocks in filter list content.
//
//  Algorithm derived from AdGuard FiltersDownloader resolveConditions +
//  resolveExpression (https://github.com/AdguardTeam/FiltersDownloader).
//

import Foundation

/// Evaluates `!#if` / `!#else` / `!#endif` conditional blocks in filter list lines.
///
/// Input is a slice of filter list lines (already split by newline).
/// Output is the subset of lines that apply for the current platform.
/// Directive lines (`!#if`, `!#else`, `!#endif`) are never present in the output.
/// Nesting is supported. Malformed blocks are treated as no-ops (block excluded, orphaned
/// directives skipped silently).
///
/// The expression language supports:
/// - `||`  OR  (lowest precedence)
/// - `&&`  AND
/// - `!`   NOT (unary prefix)
/// - `(…)` Parentheses (highest precedence)
/// - Identifiers — looked up via `PlatformConstants.value(for:)`
///
/// Unknown identifiers return `false` (PREP-08). The literal tokens `true` and `false`
/// are also recognised by `PlatformConstants`.
public enum ConditionalEvaluator {

    /// Processes filter list lines and returns only the lines that should be
    /// included for the current platform.
    ///
    /// - Parameter lines: Raw filter list lines (may include `!#if` / `!#else` / `!#endif`)
    /// - Returns: Lines with conditional blocks resolved; all directive lines removed.
    ///            Non-directive lines are preserved verbatim (not trimmed or modified).
    public static func evaluate(lines: [String]) -> [String] {
        resolveConditions(lines)
    }

    // MARK: - Block processor

    private static func resolveConditions(_ lines: [String]) -> [String] {
        var result: [String] = []
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed == "!#if" || trimmed.hasPrefix("!#if ") {
                // Find the matching !#endif (respects nesting)
                let endIndex = findBlockEnd(
                    lines: lines,
                    seeking: "!#endif",
                    from: i + 1,
                    to: lines.count
                )

                guard endIndex != -1 else {
                    // Unmatched !#if — skip the directive, continue
                    i += 1
                    continue
                }

                // Find a same-level !#else within this block (if any)
                let elseIndex = findBlockEnd(
                    lines: lines,
                    seeking: "!#else",
                    from: i + 1,
                    to: endIndex
                )

                let conditionMet = evaluateCondition(trimmed)

                if conditionMet {
                    let trueSlice = Array(lines[(i + 1)..<(elseIndex == -1 ? endIndex : elseIndex)])
                    result += resolveConditions(trueSlice)
                } else if elseIndex != -1 {
                    let falseSlice = Array(lines[(elseIndex + 1)..<endIndex])
                    result += resolveConditions(falseSlice)
                }
                // Skip past the entire block (including the !#endif line)
                i = endIndex + 1

            } else if trimmed.hasPrefix("!#else") || trimmed.hasPrefix("!#endif") {
                // Orphaned directive — skip silently
                i += 1

            } else {
                // Non-directive line — preserve verbatim (never trim)
                result.append(lines[i])
                i += 1
            }
        }

        return result
    }

    // MARK: - Nesting finder

    /// Finds the index of a matching directive (`!#else` or `!#endif`) at the same nesting
    /// level as the `!#if` that preceded `start`. Returns `-1` if not found in `[start, end)`.
    ///
    /// Depth logic: increment on every `!#if`; decrement on every `!#endif` (regardless of
    /// what target we're seeking). Return when `depth == 0` AND line matches `target`.
    /// This correctly skips over nested `!#if...!#endif` pairs when searching for `!#else`.
    private static func findBlockEnd(
        lines: [String],
        seeking target: String,
        from start: Int,
        to end: Int
    ) -> Int {
        var depth = 0

        for i in start..<end {
            let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed == "!#if" || trimmed.hasPrefix("!#if ") {
                depth += 1
            } else if trimmed.hasPrefix("!#endif") {
                if depth == 0 {
                    // This !#endif closes the block we were called from
                    if target == "!#endif" { return i }
                    // We were looking for !#else but found the closing !#endif — not found
                    return -1
                }
                depth -= 1
            } else if trimmed.hasPrefix(target) && depth == 0 {
                return i
            }
        }

        return -1 // target not found
    }

    // MARK: - Expression evaluator

    /// Strips the `!#if ` prefix and delegates to `evaluateExpression(_:)`.
    private static func evaluateCondition(_ ifLine: String) -> Bool {
        let prefix = "!#if "
        guard ifLine.hasPrefix(prefix) else { return false }
        let expression = String(ifLine.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespaces)
        guard !expression.isEmpty else { return false }
        return evaluateExpression(expression)
    }

    /// Recursively evaluates a boolean expression.
    ///
    /// Precedence (lowest to highest): `||`, `&&`, `!`, parentheses.
    /// Parentheses are resolved first by substituting the innermost group, then recursing.
    private static func evaluateExpression(_ raw: String) -> Bool {
        let expr = raw.trimmingCharacters(in: .whitespaces)
        guard !expr.isEmpty else { return false }

        // Step 1: Resolve innermost parenthesized group first (highest precedence)
        if let openIdx = expr.lastIndex(of: "("),
           let afterOpen = expr.index(openIdx, offsetBy: 1, limitedBy: expr.endIndex),
           let closeIdx = expr[afterOpen...].firstIndex(of: ")") {
            let inner = String(expr[afterOpen..<closeIdx])
            let innerResult = evaluateExpression(inner)
            let before = expr[..<openIdx]
            let after = expr[expr.index(after: closeIdx)...]
            let rebuilt = before + (innerResult ? "true" : "false") + after
            return evaluateExpression(String(rebuilt))
        }

        // Step 2: OR has lowest precedence — split on first occurrence
        if let orRange = expr.range(of: "||") {
            let left = String(expr[..<orRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(expr[orRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return evaluateExpression(left) || evaluateExpression(right)
        }

        // Step 3: AND
        if let andRange = expr.range(of: "&&") {
            let left = String(expr[..<andRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(expr[andRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return evaluateExpression(left) && evaluateExpression(right)
        }

        // Step 4: NOT — only recognised at position 0
        if expr.hasPrefix("!") {
            let operand = String(expr.dropFirst()).trimmingCharacters(in: .whitespaces)
            return !evaluateExpression(operand)
        }

        // Step 5: Base case — constant lookup (PREP-08: unknown name → false)
        return PlatformConstants.value(for: expr)
    }
}
