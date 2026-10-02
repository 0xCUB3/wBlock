import Foundation

/// Distinguishes response documents from HTML strings embedded in script or resource source.
enum UserScriptContentValidation {
    static func downloadedSource(from data: Data) throws -> String {
        guard let content = String(data: data, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              htmlDocument(content) == nil else {
            throw URLError(.cannotParseResponse)
        }
        return content
    }

    static func isProtectionPage(_ content: String) -> Bool {
        guard let document = htmlDocument(content) else { return false }
        let lowerContent = document.lowercased()
        return lowerContent.contains("ddos-guard") || lowerContent.contains("ddos protection")
            || lowerContent.contains("checking your browser")
            || (document.prefix(256).lowercased().hasPrefix("<!doctype") && lowerContent.contains("challenge"))
    }

    private static func htmlDocument(_ content: String) -> Substring? {
        var document = content[...]
        // HTML responses may start with a BOM, comments or an XHTML declaration.
        while true {
            document = document.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" })
            if document.hasPrefix("<!--") {
                guard let end = document.range(of: "-->") else { return nil }
                document = document[end.upperBound...]
            } else if document.hasPrefix("<?xml") {
                guard let end = document.range(of: "?>") else { return nil }
                document = document[end.upperBound...]
            } else {
                break
            }
        }

        let prefix = document.prefix(256).lowercased()
        guard prefix.range(of: #"^<(?:!doctype\s+html|html|head|body)(?:\s|>)"#,
                           options: .regularExpression) != nil else {
            return nil
        }
        return document
    }
}
