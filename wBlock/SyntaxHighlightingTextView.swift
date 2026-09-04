//
//  SyntaxHighlightingTextView.swift
//  wBlock
//
//  Editable rules text with viewport syntax colouring. The text storage holds
//  the document with one base attribute run; ViewportSyntaxHighlighter colours
//  the visible lines on scroll and after edits. There is no length cap (#680).
//

import SwiftUI

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
        textView.typingAttributes = context.coordinator.highlighter.baseAttributes

        context.coordinator.textView = textView
        context.coordinator.setDocument(text, on: textView)
        scrollView.documentView = textView

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text else { return }
        context.coordinator.setDocument(text, on: textView)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightingTextView
        let highlighter: ViewportSyntaxHighlighter
        var isUpdating = false
        weak var textView: NSTextView?

        init(_ parent: SyntaxHighlightingTextView) {
            self.parent = parent
            highlighter = ViewportSyntaxHighlighter(baseAttributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            ])
        }

        func setDocument(_ text: String, on textView: NSTextView) {
            isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: highlighter.baseAttributes))
            textView.typingAttributes = highlighter.baseAttributes
            let length = textView.string.utf16.count
            let validRanges = selectedRanges.filter { $0.rangeValue.location + $0.rangeValue.length <= length }
            if !validRanges.isEmpty { textView.selectedRanges = validRanges }
            isUpdating = false
            highlighter.reset()
            highlighter.scheduleHighlight(of: textView, delayNanoseconds: 0)
        }

        @objc func boundsDidChange(_ notification: Notification) {
            guard let textView else { return }
            highlighter.scheduleHighlight(of: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlighter.reset()
            highlighter.scheduleHighlight(of: textView, delayNanoseconds: 150_000_000)
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
        textView.typingAttributes = context.coordinator.highlighter.baseAttributes

        context.coordinator.textView = textView
        context.coordinator.setDocument(text, on: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard (textView.text ?? "") != text else { return }
        context.coordinator.setDocument(text, on: textView)
    }

    @MainActor
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SyntaxHighlightingTextView
        let highlighter: ViewportSyntaxHighlighter
        var isUpdating = false
        weak var textView: UITextView?

        init(_ parent: SyntaxHighlightingTextView) {
            self.parent = parent
            highlighter = ViewportSyntaxHighlighter(baseAttributes: [
                .foregroundColor: UIColor.label,
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            ])
        }

        func setDocument(_ text: String, on textView: UITextView) {
            isUpdating = true
            let selectedRange = textView.selectedRange
            textView.attributedText = NSAttributedString(string: text, attributes: highlighter.baseAttributes)
            textView.typingAttributes = highlighter.baseAttributes
            let length = (textView.text as NSString?)?.length ?? 0
            if selectedRange.location + selectedRange.length <= length { textView.selectedRange = selectedRange }
            isUpdating = false
            highlighter.reset()
            highlighter.scheduleHighlight(of: textView, delayNanoseconds: 0)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView else { return }
            highlighter.scheduleHighlight(of: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            parent.text = textView.text ?? ""
            highlighter.reset()
            highlighter.scheduleHighlight(of: textView, delayNanoseconds: 150_000_000)
        }
    }
}

#endif
