import Foundation

enum SafariURLFilterTranslator {
    static func translate(_ pattern: String) -> String {
        var text = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "*" else { return ".*" }

        if text.hasPrefix("/"), text.hasSuffix("/"), text.count > 1 {
            text.removeFirst()
            text.removeLast()
            return text.isEmpty ? ".*" : text
        }

        var output = ""

        if text.hasPrefix("||") {
            output += "^[a-z][a-z0-9+.-]*://([^/?#]+\\.)?"
            text.removeFirst(2)
        } else if text.hasPrefix("|") {
            output += "^"
            text.removeFirst()
        }

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let isLast = text.index(after: index) == text.endIndex

            if character == "|", isLast {
                output += "$"
            } else if character == "*" {
                output += ".*"
            } else if character == "^" {
                output += "(?:[^A-Za-z0-9_\\-.%]|$)"
            } else {
                output += escapedRegexCharacter(character)
            }

            index = text.index(after: index)
        }

        return output.isEmpty ? ".*" : output
    }

    private static func escapedRegexCharacter(_ character: Character) -> String {
        let string = String(character)
        switch character {
        case "\\", ".", "+", "?", "(", ")", "[", "]", "{", "}", "$", "|":
            return "\\" + string
        default:
            return string
        }
    }
}
