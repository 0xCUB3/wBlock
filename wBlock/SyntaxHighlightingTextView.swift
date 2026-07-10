//
//  SyntaxHighlightingTextView.swift
//  wBlock
//

import SwiftUI

private let syntaxHighlightingDelayNanoseconds: UInt64 = 150_000_000
private let syntaxHighlightingCharacterLimit = 60_000

@MainActor
fileprivate final class SyntaxHighlightingCoordinatorCore {
    private let highlighter = AdGuardSyntaxHighlighter()
    private var highlightTask: Task<Void, Never>?
    let plainTextAttributes: [NSAttributedString.Key: Any]

    init(plainTextAttributes: [NSAttributedString.Key: Any]) {
        self.plainTextAttributes = plainTextAttributes
    }

    func attributedText(for text: String) -> NSAttributedString {
        guard text.count <= syntaxHighlightingCharacterLimit else {
            return NSAttributedString(string: text, attributes: plainTextAttributes)
        }
        return highlighter.highlight(text)
    }

    func scheduleHighlight(
        for text: String,
        currentText: @escaping @MainActor () -> String?,
        apply: @escaping @MainActor (NSAttributedString) -> Void
    ) {
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: syntaxHighlightingDelayNanoseconds)
            guard !Task.isCancelled, let self, currentText() == text else { return }
            apply(self.attributedText(for: text))
        }
    }

    deinit {
        highlightTask?.cancel()
    }
}

#if os(macOS)
import AppKit

struct SyntaxHighlightingTextView: NSViewRepresentable {
    @Binding var text: String
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
        textView.typingAttributes = context.coordinator.core.plainTextAttributes

        context.coordinator.textView = textView

        let attributed = context.coordinator.core.attributedText(for: text)
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

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightingTextView
        fileprivate let core: SyntaxHighlightingCoordinatorCore
        var isUpdating = false
        weak var textView: NSTextView?

        init(_ parent: SyntaxHighlightingTextView) {
            self.parent = parent
            core = SyntaxHighlightingCoordinatorCore(plainTextAttributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            ])
        }

        private func apply(attributed: NSAttributedString, to textView: NSTextView) {
            isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = core.plainTextAttributes
            let length = textView.string.utf16.count
            let validRanges = selectedRanges.filter { $0.rangeValue.location + $0.rangeValue.length <= length }
            if !validRanges.isEmpty { textView.selectedRanges = validRanges }
            isUpdating = false
        }

        func applyAttributedText(for text: String, to textView: NSTextView) {
            apply(attributed: core.attributedText(for: text), to: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            parent.text = newText
            core.scheduleHighlight(
                for: newText,
                currentText: { [weak self] in self?.textView?.string },
                apply: { [weak self] attributed in
                    guard let self, let textView = self.textView else { return }
                    self.apply(attributed: attributed, to: textView)
                }
            )
        }
    }
}

#elseif os(iOS)
import UIKit

struct SyntaxHighlightingTextView: UIViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView: UITextView
        if #available(iOS 16.0, *) {
            textView = UITextView(usingTextLayoutManager: true)
        } else {
            textView = UITextView()
        }
        textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.typingAttributes = context.coordinator.core.plainTextAttributes

        context.coordinator.textView = textView

        let attributed = context.coordinator.core.attributedText(for: text)
        textView.attributedText = attributed

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let currentText = textView.text ?? ""
        guard currentText != text else { return }
        context.coordinator.applyAttributedText(for: text, to: textView)
    }
    @MainActor
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxHighlightingTextView
        fileprivate let core: SyntaxHighlightingCoordinatorCore
        var isUpdating = false
        weak var textView: UITextView?

        init(_ parent: SyntaxHighlightingTextView) {
            self.parent = parent
            core = SyntaxHighlightingCoordinatorCore(plainTextAttributes: [
                .foregroundColor: UIColor.label,
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            ])
        }

        private func apply(attributed: NSAttributedString, to textView: UITextView) {
            isUpdating = true
            let selectedRange = textView.selectedRange
            textView.attributedText = attributed
            textView.typingAttributes = core.plainTextAttributes
            let length = (textView.text as NSString?)?.length ?? 0
            if selectedRange.location + selectedRange.length <= length { textView.selectedRange = selectedRange }
            isUpdating = false
        }

        func applyAttributedText(for text: String, to textView: UITextView) {
            apply(attributed: core.attributedText(for: text), to: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            let newText = textView.text ?? ""
            parent.text = newText
            core.scheduleHighlight(
                for: newText,
                currentText: { [weak self] in self?.textView?.text },
                apply: { [weak self] attributed in
                    guard let self, let textView = self.textView else { return }
                    self.apply(attributed: attributed, to: textView)
                }
            )
        }
    }
}

#endif
