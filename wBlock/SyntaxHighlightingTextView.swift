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
    private let highlightDelayNanoseconds: UInt64 = 150_000_000
    private let highlightingCharacterLimit = 60_000

    private var plainTextAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        ]
    }

    private func attributedText(for text: String) -> NSAttributedString {
        guard text.count <= highlightingCharacterLimit else {
            return NSAttributedString(string: text, attributes: plainTextAttributes)
        }
        return highlighter.highlight(text)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
        }
        textView.delegate = context.coordinator
        textView.typingAttributes = plainTextAttributes

        context.coordinator.textView = textView

        let attributed = attributedText(for: text)
        textView.textStorage?.setAttributedString(attributed)
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let currentText = textView.string
        guard currentText != text else { return }
        context.coordinator.applyAttributedText(for: text, to: textView)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightingTextView
        var isUpdating = false
        weak var textView: NSTextView?
        var highlightTask: Task<Void, Never>?

        init(_ parent: SyntaxHighlightingTextView) {
            self.parent = parent
        }

        func applyAttributedText(for text: String, to textView: NSTextView) {
            isUpdating = true
            let selectedRanges = textView.selectedRanges
            let attributed = parent.attributedText(for: text)
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = parent.plainTextAttributes

            let newLength = textView.string.utf16.count
            let validRanges = selectedRanges.compactMap { rangeValue -> NSValue? in
                let range = rangeValue.rangeValue
                guard range.location + range.length <= newLength else { return nil }
                return rangeValue
            }
            if !validRanges.isEmpty {
                textView.selectedRanges = validRanges as [NSValue]
            }
            isUpdating = false
        }

        func scheduleHighlight(for text: String) {
            highlightTask?.cancel()
            let delay = parent.highlightDelayNanoseconds
            highlightTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let textView = self.textView, textView.string == text else { return }
                    self.applyAttributedText(for: text, to: textView)
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating else { return }
            guard let textView = notification.object as? NSTextView else { return }

            let newText = textView.string

            parent.text = newText
            scheduleHighlight(for: newText)
        }
    }
}

#elseif os(iOS)
import UIKit

struct SyntaxHighlightingTextView: UIViewRepresentable {
    @Binding var text: String
    private let highlighter = AdGuardSyntaxHighlighter()
    private let highlightDelayNanoseconds: UInt64 = 150_000_000
    private let highlightingCharacterLimit = 60_000

    private var plainTextAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: UIColor.label,
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        ]
    }

    private func attributedText(for text: String) -> NSAttributedString {
        guard text.count <= highlightingCharacterLimit else {
            return NSAttributedString(string: text, attributes: plainTextAttributes)
        }
        return highlighter.highlight(text)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.typingAttributes = plainTextAttributes

        context.coordinator.textView = textView

        let attributed = attributedText(for: text)
        textView.attributedText = attributed

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let currentText = textView.text ?? ""
        guard currentText != text else { return }
        context.coordinator.applyAttributedText(for: text, to: textView)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxHighlightingTextView
        var isUpdating = false
        weak var textView: UITextView?
        var highlightTask: Task<Void, Never>?

        init(_ parent: SyntaxHighlightingTextView) {
            self.parent = parent
        }

        func applyAttributedText(for text: String, to textView: UITextView) {
            isUpdating = true
            let selectedRange = textView.selectedRange
            textView.attributedText = parent.attributedText(for: text)
            textView.typingAttributes = parent.plainTextAttributes

            let utf16Length = (textView.text as NSString?)?.length ?? 0
            if selectedRange.location + selectedRange.length <= utf16Length {
                textView.selectedRange = selectedRange
            }
            isUpdating = false
        }

        func scheduleHighlight(for text: String) {
            highlightTask?.cancel()
            let delay = parent.highlightDelayNanoseconds
            highlightTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let textView = self.textView, (textView.text ?? "") == text else { return }
                    self.applyAttributedText(for: text, to: textView)
                }
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }

            let newText = textView.text ?? ""

            parent.text = newText
            scheduleHighlight(for: newText)
        }
    }
}

#endif
