//
//  ViewportSyntaxHighlighter.swift
//  wBlock
//
//  Colours only the lines that are on screen. A whole-document attributed
//  string for a 3 MB list has hundreds of thousands of attribute runs, and
//  NSTextStorage's run array is O(runs) per insert, so building and setting
//  it froze the main thread long enough for the iOS watchdog to kill the app
//  (cameren, Discord). The same cost was why the editor stopped highlighting
//  above 60k characters (#680). Keeping the storage at one base run and
//  applying attributes to the visible range on scroll keeps both paths cheap
//  no matter how long the text is.
//

import SwiftUI

#if os(macOS)
import AppKit
typealias HighlightPlatformColor = NSColor
typealias HighlightPlatformTextView = NSTextView
#else
import UIKit
typealias HighlightPlatformColor = UIColor
typealias HighlightPlatformTextView = UITextView
#endif

/// Background tint per zero-based line index, for the rules viewer's
/// advanced / unsupported / duplicate markers.
typealias HighlightLineTints = [Int: HighlightPlatformColor]

@MainActor
final class ViewportSyntaxHighlighter {
    private let highlighter = AdGuardSyntaxHighlighter()
    let baseAttributes: [NSAttributedString.Key: Any]
    private var highlightedRange: NSRange?
    private var scheduled: Task<Void, Never>?
    private var lineStartsTask: Task<Void, Never>?
    private var lineStarts: [Int] = []
    private var lineStartsTextLength = -1
    var lineTints: HighlightLineTints = [:] {
        didSet { highlightedRange = nil }
    }

    /// Lines above and below the viewport that get coloured too, so a short
    /// scroll does not show plain text before the debounce fires.
    private let overscanLines = 40

    init(baseAttributes: [NSAttributedString.Key: Any]) {
        self.baseAttributes = baseAttributes
    }

    /// Forget what was highlighted; call after the document text is replaced.
    func reset() {
        highlightedRange = nil
        lineStarts = []
        lineStartsTextLength = -1
        lineStartsTask?.cancel()
        lineStartsTask = nil
    }

    func scheduleHighlight(of textView: HighlightPlatformTextView, delayNanoseconds: UInt64 = 60_000_000) {
        scheduled?.cancel()
        scheduled = Task { [weak self, weak textView] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self, let textView else { return }
            self.highlightVisibleLines(of: textView)
        }
    }

    func highlightVisibleLines(of textView: HighlightPlatformTextView) {
        guard let storage = Self.storage(of: textView) else { return }
        let text = storage.string as NSString
        let length = text.length
        guard length > 0 else { return }

        var visible = Self.visibleCharacterRange(of: textView, length: length)
        visible = text.lineRange(for: visible)
        visible = expand(visible, in: text, by: overscanLines)

        if let previous = highlightedRange, previous == visible { return }

        storage.beginEditing()
        if let previous = highlightedRange {
            let clamped = NSIntersectionRange(previous, NSRange(location: 0, length: length))
            if clamped.length > 0 {
                storage.setAttributes(baseAttributes, range: clamped)
            }
        }

        let chunk = text.substring(with: visible)
        let highlighted = highlighter.highlight(chunk)
        if highlighted.length == visible.length {
            highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) { attributes, range, _ in
                storage.setAttributes(attributes, range: NSRange(location: visible.location + range.location, length: range.length))
            }
        }
        applyTints(in: visible, text: text, storage: storage)
        storage.endEditing()
        highlightedRange = visible
    }

    private func expand(_ range: NSRange, in text: NSString, by lines: Int) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        for _ in 0..<lines where start > 0 {
            start = text.lineRange(for: NSRange(location: start - 1, length: 0)).location
        }
        for _ in 0..<lines where end < text.length {
            end = NSMaxRange(text.lineRange(for: NSRange(location: end, length: 0)))
        }
        return NSRange(location: start, length: end - start)
    }

    private func applyTints(in range: NSRange, text: NSString, storage: NSTextStorage) {
        guard !lineTints.isEmpty else { return }
        ensureLineStarts(for: text)
        guard !lineStarts.isEmpty else { return }
        var lineIndex = lineIndexFor(offset: range.location)
        var cursor = range.location
        let end = NSMaxRange(range)
        while cursor < end, lineIndex < lineStarts.count {
            let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
            if let tint = lineTints[lineIndex], lineRange.length > 0 {
                storage.addAttribute(.backgroundColor, value: tint, range: lineRange)
            }
            cursor = NSMaxRange(lineRange)
            if cursor == lineRange.location { break }
            lineIndex += 1
        }
    }

    private func lineIndexFor(offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Line starts are computed once per document, synchronously; a 3 MB
    /// scan with getLineStart is a few milliseconds, well under a frame.
    private func ensureLineStarts(for text: NSString) {
        guard lineStartsTextLength != text.length else { return }
        var starts: [Int] = [0]
        starts.reserveCapacity(text.length / 32)
        var index = 0
        let length = text.length
        while index < length {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
            if lineEnd <= index { break }
            if lineEnd < length { starts.append(lineEnd) }
            index = lineEnd
        }
        lineStarts = starts
        lineStartsTextLength = length
    }

    private static func storage(of textView: HighlightPlatformTextView) -> NSTextStorage? {
        #if os(macOS)
        return textView.textStorage
        #else
        return textView.textStorage
        #endif
    }

    /// Character range for the text on screen, computed through hit testing
    /// so it works with TextKit 1 and TextKit 2 alike.
    private static func visibleCharacterRange(of textView: HighlightPlatformTextView, length: Int) -> NSRange {
        #if os(macOS)
        let rect = textView.visibleRect
        let inset = textView.textContainerInset
        let topLeft = NSPoint(x: rect.minX + inset.width, y: rect.minY + inset.height)
        let bottomLeft = NSPoint(x: rect.minX + inset.width, y: rect.maxY)
        let start = textView.characterIndexForInsertion(at: topLeft)
        let end = textView.characterIndexForInsertion(at: bottomLeft)
        #else
        let bounds = textView.bounds
        let inset = textView.textContainerInset
        let topLeft = CGPoint(x: bounds.minX + inset.left, y: bounds.minY + inset.top)
        let bottomLeft = CGPoint(x: bounds.minX + inset.left, y: bounds.maxY)
        let startPosition = textView.closestPosition(to: topLeft) ?? textView.beginningOfDocument
        let endPosition = textView.closestPosition(to: bottomLeft) ?? textView.endOfDocument
        let start = textView.offset(from: textView.beginningOfDocument, to: startPosition)
        let end = textView.offset(from: textView.beginningOfDocument, to: endPosition)
        #endif
        let lower = max(0, min(start, end, length))
        let upper = max(lower, min(max(start, end), length))
        return NSRange(location: lower, length: upper - lower)
    }
}
