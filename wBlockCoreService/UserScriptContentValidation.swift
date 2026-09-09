import Foundation

/// Detects challenge documents without treating words inside script or resource source as a response page.
enum UserScriptContentValidation {
    static func isProtectionPage(_ content: String) -> Bool {
        var document = content[...]
        // HTML responses may start with a BOM, comments or an XHTML declaration.
        while true {
            document = document.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" })
            if document.hasPrefix("<!--") {
                guard let end = document.range(of: "-->") else { return false }
                document = document[end.upperBound...]
            } else if document.hasPrefix("<?xml") {
                guard let end = document.range(of: "?>") else { return false }
                document = document[end.upperBound...]
            } else {
                break
            }
        }

        let prefix = document.prefix(256).lowercased()
        guard prefix.range(of: #"^<(?:!doctype\s+html|html|head|body)(?:\s|>)"#,
                           options: .regularExpression) != nil else {
            return false
        }
        let lowerContent = document.lowercased()
        return lowerContent.contains("ddos-guard") || lowerContent.contains("ddos protection")
            || lowerContent.contains("checking your browser")
            || (prefix.hasPrefix("<!doctype") && lowerContent.contains("challenge"))
    }
}
