import SwiftUI

#if os(macOS)
import AppKit

struct MonospacedTextView: NSViewRepresentable {
    @Binding var text: String
    var softTopEdge = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = makeDocumentScrollView()

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.string = text
        expandDocumentToFit(textView, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        applyTrailingScrollerInset(to: scrollView)
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        expandDocumentToFit(textView, in: scrollView)
    }

    private func makeDocumentScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        applyTrailingScrollerInset(to: scrollView)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        configure(textView: textView)
        scrollView.documentView = textView
        return scrollView
    }

    private func configure(textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
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
        textView.layoutManager?.allowsNonContiguousLayout = true

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false
        }
    }

    private func applyTrailingScrollerInset(to scrollView: NSScrollView) {
        var insets = scrollView.contentView.contentInsets
        let desiredRight: CGFloat
        if scrollView.scrollerStyle == .overlay {
            desiredRight = NSScroller.scrollerWidth(
                for: .regular,
                scrollerStyle: .overlay
            )
        } else {
            desiredRight = 0
        }
        if abs(insets.right - desiredRight) > 0.5 {
            insets.right = desiredRight
            scrollView.contentView.contentInsets = insets
        }
    }

    private func expandDocumentToFit(_ textView: NSTextView, in scrollView: NSScrollView) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let inset = textView.textContainerInset
        let trailingInset = scrollView.contentView.contentInsets.right
        let width = max(
            ceil(used.width + inset.width * 2),
            scrollView.contentSize.width - trailingInset
        )
        let height = max(
            ceil(used.height + inset.height * 2),
            scrollView.contentSize.height
        )
        let newSize = NSSize(width: width, height: height)
        if abs(textView.frame.width - newSize.width) > 0.5 || abs(textView.frame.height - newSize.height) > 0.5 {
            textView.setFrameSize(newSize)
        }
    }
}

#elseif os(iOS)
import UIKit

struct MonospacedTextView: UIViewRepresentable {
    @Binding var text: String
    var softTopEdge = false

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: .zero, textContainer: nil)
        configure(textView: textView)
        textView.text = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        configure(textView: textView)
        guard textView.text != text else { return }

        let selectedRange = textView.selectedRange
        textView.text = text
        textView.selectedRange = selectedRange
    }

    private func configure(textView: UITextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.backgroundColor = .clear
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.alwaysBounceHorizontal = false
        if #available(iOS 26.0, *), softTopEdge {
            textView.topEdgeEffect.style = .soft
        }
        textView.showsVerticalScrollIndicator = true
        textView.showsHorizontalScrollIndicator = false
        textView.contentInsetAdjustmentBehavior = .always
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 20)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.heightTracksTextView = false
        textView.textContainer.lineBreakMode = .byWordWrapping
    }
}

#endif
