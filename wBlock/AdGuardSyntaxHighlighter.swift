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

    // MARK: - Rule patterns

    private struct RulePattern {
        let regex: NSRegularExpression
        let color: PlatformColor
        let fullLine: Bool
        let italic: Bool

        init(_ pattern: String, color: PlatformColor, fullLine: Bool = false, italic: Bool = false, options: NSRegularExpression.Options = []) {
            // swiftlint:disable:next force_try
            self.regex = try! NSRegularExpression(pattern: pattern, options: options)
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
            RulePattern("^\\[.+\\]\\s*$", color: theme.sectionHeader, fullLine: true, italic: true),
            RulePattern("^.+?#%#", color: theme.scriptlet, fullLine: true),
            RulePattern("^.+?\\$\\$", color: theme.htmlFiltering, fullLine: true),
        ]

        // Inline patterns (applied as overlays after line-level coloring)
        self.inlinePatterns = [
            RulePattern("^@@", color: theme.exception),
            RulePattern("(##|#@#|#\\?#|#\\$#)", color: theme.elementHiding),
            RulePattern("^\\|\\|", color: theme.urlBlocking),
            RulePattern("\\$(~?[\\w-]+(?:=[^,\\s]*)?(?:,~?[\\w-]+(?:=[^,\\s]*)?)*)$", color: theme.modifier),
            RulePattern(":(has|contains|matches-css|matches-attr|matches-property|if|if-not|nth-ancestor|upward|xpath|remove|remove-attr|remove-class|not)\\(", color: theme.extendedCSS),
            RulePattern("^/.*/$", color: theme.regexPattern),
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

    private func highlightLine(_ line: String) -> NSAttributedString {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        let attributed = NSMutableAttributedString(string: line, attributes: [
            .foregroundColor: theme.defaultText,
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
