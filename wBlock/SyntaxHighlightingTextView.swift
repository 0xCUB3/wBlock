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
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

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
        textView.delegate = context.coordinator

        context.coordinator.textView = textView

        let attributed = highlighter.highlight(text)
        textView.textStorage?.setAttributedString(attributed)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let currentText = textView.string
        guard currentText != text else { return }

        context.coordinator.isUpdating = true
        let selectedRanges = textView.selectedRanges

        let attributed = highlighter.highlight(text)
        textView.textStorage?.setAttributedString(attributed)

        textView.selectedRanges = selectedRanges
        context.coordinator.isUpdating = false
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightingTextView
        var isUpdating = false
        weak var textView: NSTextView?

        init(_ parent: SyntaxHighlightingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating else { return }
            guard let textView = notification.object as? NSTextView else { return }

            isUpdating = true
            let newText = textView.string
            let selectedRanges = textView.selectedRanges

            parent.text = newText

            let attributed = parent.highlighter.highlight(newText)
            textView.textStorage?.setAttributedString(attributed)

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
        textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator

        context.coordinator.textView = textView

        let attributed = highlighter.highlight(text)
        textView.attributedText = attributed

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let currentText = textView.text ?? ""
        guard currentText != text else { return }

        context.coordinator.isUpdating = true
        let selectedRange = textView.selectedRange

        let attributed = highlighter.highlight(text)
        textView.attributedText = attributed

        if selectedRange.location + selectedRange.length <= (textView.text?.count ?? 0) {
            textView.selectedRange = selectedRange
        }
        context.coordinator.isUpdating = false
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxHighlightingTextView
        var isUpdating = false
        weak var textView: UITextView?

        init(_ parent: SyntaxHighlightingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }

            isUpdating = true
            let newText = textView.text ?? ""
            let selectedRange = textView.selectedRange

            parent.text = newText

            let attributed = parent.highlighter.highlight(newText)
            textView.attributedText = attributed

            if selectedRange.location + selectedRange.length <= newText.count {
                textView.selectedRange = selectedRange
            }
            isUpdating = false
        }
    }
}

#endif
