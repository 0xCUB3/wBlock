import Foundation

/// User-defined regex URL redirects compiled into Safari DNR `regexSubstitution` rules (#1176).
public enum RegexRedirectPreference {
    public static let storageKey = "regexRedirectRules"

    public struct Rule: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var pattern: String
        public var replacement: String
        public var isEnabled: Bool
        /// True limits matching to top-level navigations (`main_frame`); false matches all request types.
        public var isDocumentOnly: Bool

        public init(
            id: UUID = UUID(),
            pattern: String,
            replacement: String,
            isEnabled: Bool = true,
            isDocumentOnly: Bool = true
        ) {
            self.id = id
            self.pattern = pattern
            self.replacement = replacement
            self.isEnabled = isEnabled
            self.isDocumentOnly = isDocumentOnly
        }
    }

    /// Parses a raw regex or slash-delimited `/pattern/flags` literal into a DNR `regexFilter`
    /// and case-sensitivity flag (`nil` when empty or invalid).
    public static func parsedRegexFilter(from rawPattern: String) -> (filter: String, isCaseSensitive: Bool)? {
        let trimmed = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var body = trimmed
        var isCaseSensitive = false
        if trimmed.hasPrefix("/"), trimmed.count > 2,
           let closing = lastUnescapedSlash(in: trimmed), closing > trimmed.startIndex {
            let flags = trimmed[trimmed.index(after: closing)...]
            if flags.allSatisfy({ "dgimsuvy".contains($0) }) {
                let inner = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closing])
                body = unescapeSlashes(inner)
                isCaseSensitive = !flags.contains("i")
            }
        }
        guard !body.isEmpty, (try? NSRegularExpression(pattern: body)) != nil else { return nil }
        return (body, isCaseSensitive)
    }

    /// Rewrites `$1`..`$N` capture references into DNR `regexSubstitution` `\1`..`\N` syntax.
    public static func normalizedSubstitution(from rawReplacement: String) -> String? {
        let trimmed = rawReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return rewriteDollarCaptureGroups(trimmed)
    }

    /// Returns a user-facing validation error message, or nil when valid.
    public static func validationError(pattern: String, replacement: String) -> String? {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPattern.isEmpty else { return "Enter a regular expression pattern." }
        guard parsedRegexFilter(from: trimmedPattern) != nil else { return "Invalid regular expression." }
        guard !trimmedReplacement.isEmpty else { return "Enter a destination URL." }
        return nil
    }

    public static func rules(groupIdentifier: String = GroupIdentifier.shared.value) -> [Rule] {
        guard let data = UserDefaults(suiteName: groupIdentifier)?.data(forKey: storageKey),
              let rules = try? JSONDecoder().decode([Rule].self, from: data)
        else { return [] }
        return rules
    }

    public static func setRules(_ rules: [Rule], groupIdentifier: String = GroupIdentifier.shared.value) {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return }
        if rules.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func rewriteDollarCaptureGroups(_ text: String) -> String {
        var substitution = ""
        substitution.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "$" {
                let digitsStart = text.index(after: index)
                var digitsEnd = digitsStart
                while digitsEnd < text.endIndex, text[digitsEnd].isASCII, text[digitsEnd].isNumber {
                    digitsEnd = text.index(after: digitsEnd)
                }
                if digitsEnd > digitsStart {
                    substitution.append("\\")
                    substitution.append(contentsOf: text[digitsStart..<digitsEnd])
                    index = digitsEnd
                    continue
                }
            }
            substitution.append(text[index])
            index = text.index(after: index)
        }
        return substitution
    }

    private static func lastUnescapedSlash(in text: String) -> String.Index? {
        var candidate: String.Index? = nil
        var index = text.index(after: text.startIndex)
        var backslashes = 0
        while index < text.endIndex {
            let char = text[index]
            if char == "/" && backslashes % 2 == 0 {
                candidate = index
            }
            backslashes = char == "\\" ? backslashes + 1 : 0
            index = text.index(after: index)
        }
        return candidate
    }

    private static func unescapeSlashes(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var backslashes = 0
        for char in text {
            if char == "/" {
                if backslashes % 2 == 1 { _ = out.popLast() }
                backslashes = 0
            } else if char == "\\" {
                backslashes += 1
            } else {
                backslashes = 0
            }
            out.append(char)
        }
        return out
    }
}
