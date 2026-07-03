//
//  AdGuardSyntaxHighlighter.swift
//  wBlock
//

import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct AdGuardSyntaxHighlighter {

    // MARK: - Platform typealiases

    #if canImport(AppKit)
    typealias PlatformColor = NSColor
    typealias PlatformFont = NSFont
    #elseif canImport(UIKit)
    typealias PlatformColor = UIColor
    typealias PlatformFont = UIFont
    #endif

    // MARK: - Theme

    struct Theme {
        let comment: PlatformColor
        let sectionHeader: PlatformColor
        let elementHiding: PlatformColor
        let urlBlocking: PlatformColor
        let exception: PlatformColor
        let modifier: PlatformColor
        let extendedCSS: PlatformColor
        let scriptlet: PlatformColor
        let htmlFiltering: PlatformColor
        let regexPattern: PlatformColor
        let defaultText: PlatformColor

        /// Custom amber for HTML filtering rules (systemYellow has poor contrast on light backgrounds)
        private static let amberColor = PlatformColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1.0)

        static var `default`: Theme {
            #if canImport(AppKit)
            return Theme(
                comment: NSColor.secondaryLabelColor,
                sectionHeader: NSColor.secondaryLabelColor,
                elementHiding: NSColor.systemPurple,
                urlBlocking: NSColor.systemBlue,
                exception: NSColor.systemGreen,
                modifier: NSColor.systemOrange,
                extendedCSS: NSColor.systemTeal,
                scriptlet: NSColor.systemPink,
                htmlFiltering: amberColor,
                regexPattern: NSColor.systemCyan,
                defaultText: NSColor.labelColor
            )
            #else
            return Theme(
                comment: UIColor.secondaryLabel,
                sectionHeader: UIColor.secondaryLabel,
                elementHiding: UIColor.systemPurple,
                urlBlocking: UIColor.systemBlue,
                exception: UIColor.systemGreen,
                modifier: UIColor.systemOrange,
                extendedCSS: UIColor.systemTeal,
                scriptlet: UIColor.systemPink,
                htmlFiltering: amberColor,
                regexPattern: UIColor.systemCyan,
                defaultText: UIColor.label
            )
            #endif
        }
    }

    /// Semantic token categories used by `tokenize(_:)`.
    ///
    /// Each `TokenType` maps deterministically to a highlight `Theme` color (`.plain`
    /// maps to `defaultText`). `SyntaxHighlightingTextView` and `tokenize(_:)` share
    /// these categories so tests can assert against a stable vocabulary independent of
    /// the attributed-string run layout.
    enum TokenType: String, Equatable {
        case plain
        case comment
        case sectionHeader
        case elementHiding
        case urlBlocking
        case exception
        case modifier
        case extendedCSS
        case scriptlet
        case htmlFiltering
        case regexPattern
    }

    // MARK: - Rule patterns

    private struct RulePattern {
        let regex: NSRegularExpression
        let tokenType: TokenType
        let fullLine: Bool
        let italic: Bool

        init(_ pattern: String, tokenType: TokenType, fullLine: Bool = false, italic: Bool = false, options: NSRegularExpression.Options = []) {
            // swiftlint:disable:next force_try
            self.regex = try! NSRegularExpression(pattern: pattern, options: options)
            self.tokenType = tokenType
            self.fullLine = fullLine
            self.italic = italic
        }
    }

    private let theme: Theme
    private let linePatterns: [RulePattern]
    private let inlinePatterns: [RulePattern]
    private let baseFont: PlatformFont
    private let italicFont: PlatformFont

    // MARK: - Init

    init(theme: Theme = .default, fontSize: CGFloat = 13) {
        self.theme = theme

        #if canImport(AppKit)
        self.baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        self.italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        #else
        self.baseFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
            self.italicFont = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            self.italicFont = baseFont
        }
        #endif

        // Line-level patterns (checked in order, first match wins for full-line coloring).
        //
        // The hash-comment pattern comes *before* the scriptlet/html-filtering patterns
        // AND uses a negative-lookahead-style guard (`[^#@?%$]|$` as the second char):
        // a leading `#` that is NOT immediately followed by a cosmetic-marker character
        // (@, ?, %, $, or the second `#`) is a comment, mirroring AdGuard's
        // `RuleFactory.isComment`. This keeps `# comment`, `#comment`, `#+comment`,
        // `# ########################`, and lone `#` from being mis-colored as cosmetic
        // while leaving real markers (`##`, `#@#`, `#?#`, `#%#`, `#$#`, ...) untouched.
        self.linePatterns = [
            RulePattern("^!", tokenType: .comment, fullLine: true),
            RulePattern("^#([^#@?%$]|$)", tokenType: .comment, fullLine: true),
            RulePattern("^\\[.+\\]\\s*$", tokenType: .sectionHeader, fullLine: true, italic: true),
            RulePattern("^.+?#%#", tokenType: .scriptlet, fullLine: true),
            RulePattern("^.+?\\$\\$", tokenType: .htmlFiltering, fullLine: true),
        ]

        // Inline patterns (applied as overlays after line-level coloring).
        // Later patterns overwrite earlier ones on overlapping ranges, matching the
        // previous addAttribute(_:value:range:) overlay semantics.
        self.inlinePatterns = [
            RulePattern("^@@", tokenType: .exception),
            RulePattern("(##|#@#|#\\?#|#\\$#)", tokenType: .elementHiding),
            RulePattern("^\\|\\|", tokenType: .urlBlocking),
            RulePattern("\\$(~?[\\w-]+(?:=[^,\\s]*)?(?:,~?[\\w-]+(?:=[^,\\s]*)?)*)$", tokenType: .modifier),
            RulePattern(":(has|contains|matches-css|matches-attr|matches-property|if|if-not|nth-ancestor|upward|xpath|remove|remove-attr|remove-class|not)\\(", tokenType: .extendedCSS),
            RulePattern("^/.*/$", tokenType: .regexPattern),
        ]
    }

    // MARK: - Highlight

    func highlight(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")

        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.defaultText,
            .font: baseFont
        ]

        for (index, line) in lines.enumerated() {
            let attributed = highlightLine(line)
            result.append(attributed)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: defaultAttributes))
            }
        }

        return result
    }

    /// Tokenizes `text` into ordered `(TokenType, substring)` pairs covering every
    /// character (line breaks included). Suitable for unit testing the classifier
    /// without round-tripping through an `NSAttributedString`. The visible output
    /// of `highlight(_:)` is produced from the same per-line classification, so the
    /// two are guaranteed to agree.
    ///
    /// Each input line is classified as follows:
    /// 1. If a full-line pattern matches, the whole line gets that pattern's type.
    /// 2. Otherwise every character starts as `.plain`, then each inline pattern
    ///    overwrites the types of its matched ranges in declaration order (later
    ///    patterns win on overlap), reproducing the prior overlay coloring.
    /// Consecutive equal-type characters are merged into one token.
    func tokenize(_ text: String) -> [(token: TokenType, str: String)] {
        let lines = text.components(separatedBy: "\n")
        var result: [(token: TokenType, str: String)] = []
        result.reserveCapacity(lines.count * 2)

        for (index, line) in lines.enumerated() {
            for (token, str) in tokenizeLineSegments(line) {
                result.append((token, str))
            }
            if index < lines.count - 1 {
                result.append((.plain, "\n"))
            }
        }
        return result
    }

    // MARK: - Internals

    private func highlightLine(_ line: String) -> NSAttributedString {
        let segments = tokenizeLineSegments(line)

        if segments.count == 1, let segment = segments.first {
            return NSAttributedString(string: segment.str, attributes: attributes(for: segment.token))
        }

        let attributed = NSMutableAttributedString()
        for (token, str) in segments {
            attributed.append(NSAttributedString(string: str, attributes: attributes(for: token)))
        }
        return attributed
    }

    private func tokenizeLineSegments(_ line: String) -> [(token: TokenType, str: String)] {
        let nsLine = line as NSString
        let length = nsLine.length
        if length == 0 { return [] }

        // 1. Full-line patterns: first match wins, whole line gets that type.
        let fullRange = NSRange(location: 0, length: length)
        for pattern in linePatterns where pattern.fullLine {
            if pattern.regex.firstMatch(in: line, options: [], range: fullRange) != nil {
                return [(pattern.tokenType, line)]
            }
        }

        // 2. Inline overlay patterns over a `.plain` baseline.
        var classes = Array(repeating: TokenType.plain, count: length)
        for pattern in inlinePatterns {
            let matches = pattern.regex.matches(in: line, options: [], range: fullRange)
            for match in matches {
                let r = match.range
                guard r.location != NSNotFound, r.location + r.length <= length else { continue }
                for i in 0..<r.length {
                    classes[r.location + i] = pattern.tokenType
                }
            }
        }

        // 3. Merge consecutive equal types into one token.
        var segments: [(token: TokenType, str: String)] = []
        var i = 0
        while i < length {
            let t = classes[i]
            var j = i + 1
            while j < length, classes[j] == t { j += 1 }
            let range = NSRange(location: i, length: j - i)
            segments.append((t, nsLine.substring(with: range)))
            i = j
        }
        return segments
    }

    private func attributes(for token: TokenType) -> [NSAttributedString.Key: Any] {
        let color: PlatformColor
        switch token {
        case .plain:           color = theme.defaultText
        case .comment:          color = theme.comment
        case .sectionHeader:    color = theme.sectionHeader
        case .elementHiding:    color = theme.elementHiding
        case .urlBlocking:      color = theme.urlBlocking
        case .exception:        color = theme.exception
        case .modifier:         color = theme.modifier
        case .extendedCSS:      color = theme.extendedCSS
        case .scriptlet:        color = theme.scriptlet
        case .htmlFiltering:    color = theme.htmlFiltering
        case .regexPattern:     color = theme.regexPattern
        }
        var attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: baseFont
        ]
        if token == .sectionHeader {
            attrs[.font] = italicFont
        }
        return attrs
    }
}