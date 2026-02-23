# AdGuard Syntax Highlighting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add real-time AdGuard syntax highlighting to the custom filter rule editor on macOS and iOS.

**Architecture:** Replace the plain `TextEditor` in `EditUserListView` with a native `NSTextView`/`UITextView` wrapper that applies `NSAttributedString` coloring via a shared tokenizer. Three new files, one edit to the existing view.

**Tech Stack:** SwiftUI, AppKit (NSTextView), UIKit (UITextView), NSAttributedString, NSRegularExpression

**Issue:** https://github.com/0xCUB3/wBlock/issues/263

**Build verification:** `xcodebuild -scheme wBlock -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`

**Testing:** No test target exists. Verify by building and manual inspection.

---

### Task 1: Create AdGuardSyntaxHighlighter tokenizer

**Files:**
- Create: `wBlock/AdGuardSyntaxHighlighter.swift`

This is the core engine. It takes a plain `String` and returns an `NSAttributedString` with colors applied per-line. It uses `NSRegularExpression` for pattern matching. All colors use platform-adaptive values so they work in both light and dark mode.

**Step 1: Create `wBlock/AdGuardSyntaxHighlighter.swift`**

```swift
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

    // MARK: - Theme Colors (adaptive light/dark)

    struct Theme {
        let comment: PlatformColor       // ! lines
        let sectionHeader: PlatformColor  // [Adblock Plus ...] lines
        let exception: PlatformColor      // @@ prefix
        let elementHiding: PlatformColor  // ## #@# #?# #$#
        let urlBlocking: PlatformColor    // ||domain^ patterns
        let modifier: PlatformColor       // $domain=, $third-party, etc.
        let extendedCSS: PlatformColor    // :has(), :contains(), etc.
        let scriptlet: PlatformColor      // #%#//scriptlet(...)
        let htmlFilter: PlatformColor     // $$ rules
        let regexPattern: PlatformColor   // /regex/
        let defaultText: PlatformColor
        let font: PlatformFont

        static var `default`: Theme {
            Theme(
                comment: PlatformColor.secondaryLabelColor,
                sectionHeader: PlatformColor.secondaryLabelColor,
                exception: PlatformColor.systemGreen,
                elementHiding: PlatformColor.systemPurple,
                urlBlocking: PlatformColor.systemBlue,
                modifier: PlatformColor.systemOrange,
                extendedCSS: PlatformColor.systemTeal,
                scriptlet: PlatformColor.systemPink,
                htmlFilter: PlatformColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1.0),
                regexPattern: PlatformColor.systemCyan,
                defaultText: PlatformColor.labelColor,
                font: PlatformFont.monospacedSystemFont(ofSize: PlatformFont.systemFontSize, weight: .regular)
            )
        }
    }

    // NOTE: On iOS, `secondaryLabelColor` and `labelColor` are only on UIColor,
    // and `systemCyan` requires iOS 15+. The project's minimum target is iOS 15+
    // so this is fine. We use a single typealias with #if canImport to handle
    // the platform difference.

    private let theme: Theme

    // Precompiled regex patterns for performance
    private let commentPattern: NSRegularExpression
    private let sectionHeaderPattern: NSRegularExpression
    private let exceptionPattern: NSRegularExpression
    private let scriptletPattern: NSRegularExpression
    private let htmlFilterPattern: NSRegularExpression
    private let elementHidingPattern: NSRegularExpression
    private let urlBlockingPattern: NSRegularExpression
    private let regexRulePattern: NSRegularExpression
    private let modifierPattern: NSRegularExpression
    private let extendedCSSFunctionPattern: NSRegularExpression

    init(theme: Theme = .default) {
        self.theme = theme

        // Comment: line starts with !
        commentPattern = try! NSRegularExpression(pattern: #"^!.*$"#, options: .anchorsMatchLines)

        // Section header: [Adblock Plus ...] or [uBlock Origin ...] etc.
        sectionHeaderPattern = try! NSRegularExpression(pattern: #"^\[.+\]\s*$"#, options: .anchorsMatchLines)

        // Exception: line starts with @@
        exceptionPattern = try! NSRegularExpression(pattern: #"^@@"#, options: .anchorsMatchLines)

        // Scriptlet: contains #%#//scriptlet or #%#
        scriptletPattern = try! NSRegularExpression(pattern: #"#%#"#)

        // HTML filtering: contains $$ (but not at start of modifiers section)
        htmlFilterPattern = try! NSRegularExpression(pattern: #"\$\$(?!.*\$)"#)

        // Element hiding operators: ##, #@#, #?#, #$#, #$?#
        elementHidingPattern = try! NSRegularExpression(pattern: #"#[@$?]*#"#)

        // URL blocking: ||domain or |url
        urlBlockingPattern = try! NSRegularExpression(pattern: #"^\|{1,2}"#, options: .anchorsMatchLines)

        // Regex rule: starts and ends with /
        regexRulePattern = try! NSRegularExpression(pattern: #"^/.*/$"#, options: .anchorsMatchLines)

        // Modifiers: $modifier at end of line (the $ and everything after it)
        modifierPattern = try! NSRegularExpression(pattern: #"\$[a-zA-Z~_][a-zA-Z0-9~_\-=|,./]*$"#, options: .anchorsMatchLines)

        // Extended CSS functions: :has(), :contains(), :matches-css(), etc.
        extendedCSSFunctionPattern = try! NSRegularExpression(pattern: #":(has|contains|matches-css|matches-attr|matches-property|xpath|nth-ancestor|upward|remove|if|if-not|not)\("#)
    }

    /// Highlight the full text, returning an NSAttributedString.
    func highlight(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .foregroundColor: theme.defaultText,
            .font: theme.font
        ])

        let fullRange = NSRange(location: 0, length: attributed.length)

        // Process each line individually for line-level rules
        text.enumerateSubstrings(in: text.startIndex..., options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
            let nsRange = NSRange(substringRange, in: text)
            let lineStr = String(text[substringRange])

            self.highlightLine(lineStr, in: attributed, lineRange: nsRange)
        }

        // Apply cross-line patterns (extended CSS functions can appear anywhere)
        applyPattern(extendedCSSFunctionPattern, to: attributed, in: fullRange, color: theme.extendedCSS)

        return attributed
    }

    private func highlightLine(_ line: String, in attributed: NSMutableAttributedString, lineRange: NSRange) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Empty lines: skip
        guard !trimmed.isEmpty else { return }

        // Comments: ! prefix — color entire line, stop
        if trimmed.hasPrefix("!") {
            attributed.addAttribute(.foregroundColor, value: theme.comment, range: lineRange)
            return
        }

        // Section headers: [Adblock Plus ...] — color entire line, stop
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            attributed.addAttribute(.foregroundColor, value: theme.sectionHeader, range: lineRange)
            attributed.addAttribute(.font, value: italicFont(), range: lineRange)
            return
        }

        // Exception rules: @@ prefix — color the @@ green, then continue to process rest
        if trimmed.hasPrefix("@@") {
            let prefixRange = NSRange(location: lineRange.location, length: min(2, lineRange.length))
            attributed.addAttribute(.foregroundColor, value: theme.exception, range: prefixRange)
        }

        // Regex rules: /pattern/ — color entire line
        if trimmed.hasPrefix("/") && trimmed.hasSuffix("/") && trimmed.count > 1 {
            attributed.addAttribute(.foregroundColor, value: theme.regexPattern, range: lineRange)
            return
        }

        // Scriptlet rules: contains #%#
        if trimmed.contains("#%#") {
            applyPattern(scriptletPattern, to: attributed, in: lineRange, color: theme.scriptlet)
            return
        }

        // HTML filtering: contains $$
        if trimmed.contains("$$") {
            applyPattern(htmlFilterPattern, to: attributed, in: lineRange, color: theme.htmlFilter)
        }

        // Element hiding: ##, #@#, #?#, #$#
        applyPattern(elementHidingPattern, to: attributed, in: lineRange, color: theme.elementHiding)

        // URL blocking prefix: || or |
        applyPattern(urlBlockingPattern, to: attributed, in: lineRange, color: theme.urlBlocking)

        // Modifiers: $option,option at end of line
        applyPattern(modifierPattern, to: attributed, in: lineRange, color: theme.modifier)
    }

    private func applyPattern(_ pattern: NSRegularExpression, to attributed: NSMutableAttributedString, in range: NSRange, color: PlatformColor) {
        pattern.enumerateMatches(in: attributed.string, range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: matchRange)
        }
    }

    private func italicFont() -> PlatformFont {
        #if canImport(AppKit)
        return NSFontManager.shared.convert(theme.font, toHaveTrait: .italicFontMask)
        #else
        if let descriptor = theme.font.fontDescriptor.withSymbolicTraits(.traitItalic) {
            return PlatformFont(descriptor: descriptor, size: 0)
        }
        return theme.font
        #endif
    }
}
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -scheme wBlock -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add wBlock/AdGuardSyntaxHighlighter.swift
git commit -m "add AdGuard syntax highlighting tokenizer"
```

---

### Task 2: Create SyntaxHighlightingTextView representable

**Files:**
- Create: `wBlock/SyntaxHighlightingTextView.swift`

This file wraps the native text views for both platforms behind a single SwiftUI view name. It uses the tokenizer from Task 1 to apply highlighting on every text change. The key challenge is preserving cursor position when re-applying the attributed string.

**Step 1: Create `wBlock/SyntaxHighlightingTextView.swift`**

```swift
//
//  SyntaxHighlightingTextView.swift
//  wBlock
//

import SwiftUI

#if os(macOS)
import AppKit

struct SyntaxHighlightingTextView: NSViewRepresentable {
    @Binding var text: String

    private let highlighter = AdGuardSyntaxHighlighter()

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.delegate = context.coordinator

        // Apply initial highlighting
        let attributed = highlighter.highlight(text)
        textView.textStorage?.setAttributedString(attributed)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if the text actually changed from outside (not from user typing)
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            let attributed = highlighter.highlight(text)
            textView.textStorage?.setAttributedString(attributed)
            textView.selectedRanges = selectedRanges
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightingTextView
        private var isUpdating = false

        init(_ parent: SyntaxHighlightingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            isUpdating = true

            let newText = textView.string
            let selectedRanges = textView.selectedRanges

            // Update binding
            parent.text = newText

            // Re-highlight
            let attributed = parent.highlighter.highlight(newText)
            textView.textStorage?.setAttributedString(attributed)

            // Restore cursor
            textView.selectedRanges = selectedRanges

            isUpdating = false
        }
    }
}

#elseif os(iOS)
import UIKit

struct SyntaxHighlightingTextView: UIViewRepresentable {
    @Binding var text: String

    private let highlighter = AdGuardSyntaxHighlighter()

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()

        textView.isEditable = true
        textView.isScrollEnabled = true
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.font = UIFont.monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator

        // Apply initial highlighting
        let attributed = highlighter.highlight(text)
        textView.attributedText = attributed

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            let selectedRange = textView.selectedRange
            let attributed = highlighter.highlight(text)
            textView.attributedText = attributed
            // Restore cursor if within bounds
            if selectedRange.location + selectedRange.length <= textView.text.count {
                textView.selectedRange = selectedRange
            }
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxHighlightingTextView
        private var isUpdating = false

        init(_ parent: SyntaxHighlightingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            isUpdating = true

            let newText = textView.text ?? ""
            let selectedRange = textView.selectedRange

            // Update binding
            parent.text = newText

            // Re-highlight
            let attributed = parent.highlighter.highlight(newText)
            textView.attributedText = attributed

            // Restore cursor
            if selectedRange.location + selectedRange.length <= textView.text.count {
                textView.selectedRange = selectedRange
            }

            isUpdating = false
        }
    }
}
#endif
```

**Step 2: Build to verify compilation**

Run: `xcodebuild -scheme wBlock -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add wBlock/SyntaxHighlightingTextView.swift
git commit -m "add syntax highlighting text view for macOS and iOS"
```

---

### Task 3: Integrate into EditUserListView

**Files:**
- Modify: `wBlock/ContentView.swift:1566-1569` (iOS TextEditor)
- Modify: `wBlock/ContentView.swift:1657-1669` (macOS TextEditor)

Replace both `TextEditor(text: $rules)` calls in `EditUserListView` with `SyntaxHighlightingTextView(text: $rules)`, preserving the existing frame and styling.

**Step 1: Replace iOS TextEditor (line ~1567)**

In `wBlock/ContentView.swift`, find the iOS section inside `EditUserListView.body`:

```swift
// OLD (lines 1566-1570):
Section("Rules") {
    TextEditor(text: $rules)
        .font(.system(.body, design: .monospaced))
        .frame(minHeight: 260)
}
```

Replace with:

```swift
Section("Rules") {
    SyntaxHighlightingTextView(text: $rules)
        .frame(minHeight: 260)
}
```

(Remove `.font(...)` since the highlighter sets the font via attributed string.)

**Step 2: Replace macOS TextEditor (line ~1657)**

Find the macOS section:

```swift
// OLD (lines 1657-1669):
TextEditor(text: $rules)
    .font(.system(.body, design: .monospaced))
    .frame(minHeight: 260)
    .scrollContentBackground(.hidden)
    .padding(10)
    .background(
        .background,
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(.quaternary, lineWidth: 1)
    )
```

Replace with:

```swift
SyntaxHighlightingTextView(text: $rules)
    .frame(minHeight: 260)
    .padding(10)
    .background(
        .background,
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(.quaternary, lineWidth: 1)
    )
```

(Remove `.font(...)` and `.scrollContentBackground(.hidden)` since the native text view handles its own appearance. The macOS NSScrollView handles scrolling internally.)

**Step 3: Build to verify compilation**

Run: `xcodebuild -scheme wBlock -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add wBlock/ContentView.swift
git commit -m "wire syntax highlighting into custom filter rule editor"
```

---

### Task 4: Fix platform-specific color API differences

**Files:**
- Modify: `wBlock/AdGuardSyntaxHighlighter.swift`

The `Theme.default` uses `secondaryLabelColor` and `labelColor` which have slightly different APIs on iOS (`UIColor.secondaryLabel` vs `NSColor.secondaryLabelColor`). After the initial build, fix any platform compilation errors.

**Step 1: Verify iOS compilation**

Run: `xcodebuild -scheme wBlock -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`

If errors appear for color names, update the Theme to use platform-conditional colors:

```swift
static var `default`: Theme {
    #if canImport(AppKit)
    return Theme(
        comment: NSColor.secondaryLabelColor,
        sectionHeader: NSColor.secondaryLabelColor,
        exception: NSColor.systemGreen,
        elementHiding: NSColor.systemPurple,
        urlBlocking: NSColor.systemBlue,
        modifier: NSColor.systemOrange,
        extendedCSS: NSColor.systemTeal,
        scriptlet: NSColor.systemPink,
        htmlFilter: NSColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1.0),
        regexPattern: NSColor.systemCyan,
        defaultText: NSColor.labelColor,
        font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    )
    #else
    return Theme(
        comment: UIColor.secondaryLabel,
        sectionHeader: UIColor.secondaryLabel,
        exception: UIColor.systemGreen,
        elementHiding: UIColor.systemPurple,
        urlBlocking: UIColor.systemBlue,
        modifier: UIColor.systemOrange,
        extendedCSS: UIColor.systemTeal,
        scriptlet: UIColor.systemPink,
        htmlFilter: UIColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 1.0),
        regexPattern: UIColor.systemCyan,
        defaultText: UIColor.label,
        font: UIFont.monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
    )
    #endif
}
```

**Step 2: Build both platforms**

Run macOS: `xcodebuild -scheme wBlock -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Run iOS: `xcodebuild -scheme wBlock -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: Both BUILD SUCCEEDED

**Step 3: Commit (if changes were needed)**

```bash
git add wBlock/AdGuardSyntaxHighlighter.swift
git commit -m "fix platform color API differences for iOS"
```

---

### Task 5: Manual testing and polish

**Files:**
- Possibly modify: `wBlock/AdGuardSyntaxHighlighter.swift` (regex tuning)
- Possibly modify: `wBlock/SyntaxHighlightingTextView.swift` (UX polish)

**Step 1: Run the app and open Edit User List**

1. Build and run in Xcode on macOS
2. Create or edit a user list
3. Paste test content:

```
! This is a comment
[Adblock Plus 2.0]
||example.com^
||ads.tracker.net^$third-party,domain=example.org
@@||example.com/allowed$document
example.com##.ad-banner
example.com#@#.ad-banner
example.com#?#div:has(> .ad-label)
example.com#%#//scriptlet('abort-on-property-read', 'ads')
/banner\d+/
```

**Step 2: Verify each rule type is colored correctly**

- `!` comment lines: gray
- `[Adblock Plus 2.0]`: gray italic
- `||` prefix: blue
- `$third-party,domain=...`: orange
- `@@` prefix: green
- `##.ad-banner`: purple `##`
- `#?#div:has(...)`: purple `#?#`, teal `:has(`
- `#%#//scriptlet(...)`: pink
- `/banner\d+/`: cyan

**Step 3: Verify cursor doesn't jump while typing**

Type new rules character-by-character and confirm the cursor stays in place.

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "polish syntax highlighting colors and cursor handling"
```
