import SwiftUI

final class MonospacedTextEditorState {
    fileprivate let initialText: String
    fileprivate var readCurrentText: () -> String

    init(text: String) {
        self.initialText = text
        self.readCurrentText = { text }
    }

    var currentText: String {
        readCurrentText()
    }

    fileprivate func attach(getter: @escaping () -> String) {
        readCurrentText = getter
    }
}

#if os(macOS)
import AppKit

struct MonospacedTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = makeDocumentScrollView(delegate: context.coordinator, isEditable: isEditable)

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.string = text
        context.coordinator.lastRenderedText = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        configure(textView: textView, isEditable: isEditable)

        guard context.coordinator.lastRenderedText != text else { return }

        context.coordinator.isUpdating = true
        let selectedRanges = textView.selectedRanges
        textView.string = text
        textView.selectedRanges = selectedRanges
        context.coordinator.lastRenderedText = text
        context.coordinator.isUpdating = false
    }

    private func makeDocumentScrollView(delegate: NSTextViewDelegate, isEditable: Bool) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        // Use the document-text path with TextKit 2 rather than the lighter UI-component factory.
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.delegate = delegate
        configure(textView: textView, isEditable: isEditable)
        scrollView.documentView = textView
        return scrollView
    }

    private func configure(textView: NSTextView, isEditable: Bool) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = isEditable
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
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
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MonospacedTextView
        var isUpdating = false
        var lastRenderedText: String

        init(_ parent: MonospacedTextView) {
            self.parent = parent
            self.lastRenderedText = parent.text
        }

        func textDidChange(_ notification: Notification) {
            guard parent.isEditable, !isUpdating else { return }
            guard let textView = notification.object as? NSTextView else { return }

            let updatedText = textView.string
            lastRenderedText = updatedText
            parent.text = updatedText
        }
    }
}

struct BufferedMonospacedTextEditor: NSViewRepresentable {
    let state: MonospacedTextEditorState
    var onDirtyStateChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = makeDocumentScrollView(delegate: context.coordinator)

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.string = state.initialText
        let initialText = state.initialText
        state.attach { [weak textView] in
            textView?.string ?? initialText
        }
        context.coordinator.lastIsDirty = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        configure(textView: textView)
        let initialText = state.initialText
        state.attach { [weak textView] in
            textView?.string ?? initialText
        }
        context.coordinator.parent = self
    }

    private func makeDocumentScrollView(delegate: NSTextViewDelegate) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.delegate = delegate
        configure(textView: textView)
        scrollView.documentView = textView
        return scrollView
    }

    private func configure(textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
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
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BufferedMonospacedTextEditor
        var lastIsDirty = false

        init(_ parent: BufferedMonospacedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            let isDirty = textView.string != parent.state.initialText
            guard isDirty != lastIsDirty else { return }

            lastIsDirty = isDirty
            parent.onDirtyStateChange?(isDirty)
        }
    }
}

#elseif os(iOS)
import UIKit

struct MonospacedTextView: UIViewRepresentable {
    @Binding var text: String
    var isEditable = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        configure(textView: textView)
        textView.text = text
        context.coordinator.lastRenderedText = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        configure(textView: textView)
        guard context.coordinator.lastRenderedText != text else { return }

        context.coordinator.isUpdating = true
        let selectedRange = textView.selectedRange
        textView.text = text
        textView.selectedRange = selectedRange
        context.coordinator.lastRenderedText = text
        context.coordinator.isUpdating = false
    }

    private func configure(textView: UITextView) {
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .clear
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MonospacedTextView
        var isUpdating = false
        var lastRenderedText: String

        init(_ parent: MonospacedTextView) {
            self.parent = parent
            self.lastRenderedText = parent.text
        }

        func textViewDidChange(_ textView: UITextView) {
            guard parent.isEditable, !isUpdating else { return }

            let updatedText = textView.text ?? ""
            lastRenderedText = updatedText
            parent.text = updatedText
        }
    }
}

struct BufferedMonospacedTextEditor: UIViewRepresentable {
    let state: MonospacedTextEditorState
    var onDirtyStateChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        configure(textView: textView)
        textView.text = state.initialText
        let initialText = state.initialText
        state.attach { [weak textView] in
            textView?.text ?? initialText
        }
        context.coordinator.lastIsDirty = false
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        configure(textView: textView)
        let initialText = state.initialText
        state.attach { [weak textView] in
            textView?.text ?? initialText
        }
        context.coordinator.parent = self
    }

    private func configure(textView: UITextView) {
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .clear
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: BufferedMonospacedTextEditor
        var lastIsDirty = false

        init(_ parent: BufferedMonospacedTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let isDirty = (textView.text ?? "") != parent.state.initialText
            guard isDirty != lastIsDirty else { return }

            lastIsDirty = isDirty
            parent.onDirtyStateChange?(isDirty)
        }
    }
}

#endif
