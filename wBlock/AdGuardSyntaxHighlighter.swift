//
//  AdGuardSyntaxHighlighter.swift
//  wBlock
//

import Foundation

#if canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#endif

struct AdGuardSyntaxHighlighter {

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
        let domain: PlatformColor

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
                htmlFiltering: NSColor.systemYellow,
                regexPattern: NSColor.systemCyan,
                domain: NSColor.labelColor
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
                htmlFiltering: UIColor.systemYellow,
                regexPattern: UIColor.systemCyan,
                domain: UIColor.label
            )
            #endif
        }
    }

    // MARK: - Rule patterns

    private struct RulePattern {
        let regex: NSRegularExpression
        let color: PlatformColor
        let fullLine: Bool
        let italic: Bool

        init(_ pattern: String, color: PlatformColor, fullLine: Bool = false, italic: Bool = false) {
            // swiftlint:disable:next force_try
            self.regex = try! NSRegularExpression(pattern: pattern, options: [])
            self.color = color
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

        // Line-level patterns (checked in order, first match wins for full-line coloring)
        self.linePatterns = [
            RulePattern("^!", color: theme.comment, fullLine: true),
            RulePattern("^\\[Adblock", color: theme.sectionHeader, fullLine: true, italic: true),
            RulePattern("^@@", color: theme.exception, fullLine: true),
            RulePattern("^.+?#%#", color: theme.scriptlet, fullLine: true),
            RulePattern("^.+?\\$\\$", color: theme.htmlFiltering, fullLine: true),
        ]

        // Inline patterns (applied as overlays after line-level coloring)
        self.inlinePatterns = [
            RulePattern("(##|#@#|#\\?#|#\\$#)", color: theme.elementHiding),
            RulePattern("^\\|\\|", color: theme.urlBlocking),
            RulePattern("\\$(~?[\\w-]+(?:=[^,\\s]*)?(?:,~?[\\w-]+(?:=[^,\\s]*)?)*)$", color: theme.modifier),
            RulePattern(":(has|contains|matches-css|matches-attr|matches-property|if|if-not|nth-ancestor|upward|xpath|remove|remove-attr|remove-class)\\(", color: theme.extendedCSS),
            RulePattern("/.+/", color: theme.regexPattern),
        ]
    }

    // MARK: - Highlight

    func highlight(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let attributed = highlightLine(line)
            result.append(attributed)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    private func highlightLine(_ line: String) -> NSAttributedString {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        let attributed = NSMutableAttributedString(string: line, attributes: [
            .foregroundColor: theme.domain,
            .font: baseFont
        ])

        guard !line.isEmpty else { return attributed }

        // Check line-level patterns first
        for pattern in linePatterns {
            if pattern.regex.firstMatch(in: line, options: [], range: fullRange) != nil, pattern.fullLine {
                attributed.addAttribute(.foregroundColor, value: pattern.color, range: fullRange)
                if pattern.italic {
                    attributed.addAttribute(.font, value: italicFont, range: fullRange)
                }
                return attributed
            }
        }

        // Apply inline patterns as overlays
        for pattern in inlinePatterns {
            let matches = pattern.regex.matches(in: line, options: [], range: fullRange)
            for match in matches {
                attributed.addAttribute(.foregroundColor, value: pattern.color, range: match.range)
                if pattern.italic {
                    attributed.addAttribute(.font, value: italicFont, range: match.range)
                }
            }
        }

        return attributed
    }
}
