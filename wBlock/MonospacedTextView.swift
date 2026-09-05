import SwiftUI

/// Read-only monospaced text. When `lineTints` is set, the visible lines are
/// syntax coloured and tinted on scroll instead of building one attributed
/// string for the whole document, which froze the phone on multi-megabyte
/// lists (cameren, Discord).
#if os(macOS)
import AppKit

struct MonospacedTextView: NSViewRepresentable {
    @Binding var text: String
    /// Background tint per line index; presence turns on viewport highlighting.
    var lineTints: HighlightLineTints?
    var softTopEdge = false
    var isLineWrappingEnabled = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = makeDocumentScrollView()

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        context.coordinator.textView = textView
        apply(to: textView, coordinator: context.coordinator)
        expandDocumentToFit(textView, in: scrollView)

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
        applyTrailingScrollerInset(to: scrollView)
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let selectedRanges = textView.selectedRanges
        if apply(to: textView, coordinator: context.coordinator) {
            textView.selectedRanges = selectedRanges.filter {
                NSMaxRange($0.rangeValue) <= (textView.string as NSString).length
            }
        }
        expandDocumentToFit(textView, in: scrollView)
    }

    /// Returns true when the document changed.
    @discardableResult
    private func apply(to textView: NSTextView, coordinator: Coordinator) -> Bool {
        var changed = false
        if textView.string != text {
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: text, attributes: coordinator.highlighter.baseAttributes)
            )
            coordinator.highlighter.reset()
            changed = true
        }
        if let lineTints {
            if changed || coordinator.appliedTintsIdentity != lineTints.count || coordinator.tintsDirty {
                coordinator.highlighter.lineTints = lineTints
                coordinator.appliedTintsIdentity = lineTints.count
                coordinator.tintsDirty = false
                coordinator.highlighter.scheduleHighlight(of: textView, delayNanoseconds: 0)
            }
            coordinator.highlightingEnabled = true
        } else {
            coordinator.highlightingEnabled = false
        }
        return changed
    }

    @MainActor
    final class Coordinator: NSObject {
        let highlighter = ViewportSyntaxHighlighter(baseAttributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        ])
        weak var textView: NSTextView?
        var highlightingEnabled = false
        var appliedTintsIdentity = -1
        var tintsDirty = true

        @objc func boundsDidChange(_ notification: Notification) {
            guard highlightingEnabled, let textView else { return }
            highlighter.scheduleHighlight(of: textView)
        }
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
        let availableWidth = max(0, scrollView.contentSize.width - scrollView.contentView.contentInsets.right)
        textView.isHorizontallyResizable = !isLineWrappingEnabled
        scrollView.hasHorizontalScroller = !isLineWrappingEnabled
        textContainer.widthTracksTextView = isLineWrappingEnabled
        textContainer.containerSize.width = isLineWrappingEnabled
            ? max(0, availableWidth - textView.textContainerInset.width * 2)
            : CGFloat.greatestFiniteMagnitude
        if isLineWrappingEnabled { textView.setFrameSize(NSSize(width: availableWidth, height: textView.frame.height)) }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let inset = textView.textContainerInset
        let trailingInset = scrollView.contentView.contentInsets.right
        let width = isLineWrappingEnabled ? availableWidth : max(
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
    /// Background tint per line index; presence turns on viewport highlighting.
    var lineTints: HighlightLineTints?
    var softTopEdge = false
    var isLineWrappingEnabled = true

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: .zero, textContainer: nil)
        configure(textView: textView)
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        apply(to: textView, coordinator: context.coordinator)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        configure(textView: textView)
        let selectedRange = textView.selectedRange
        if apply(to: textView, coordinator: context.coordinator) {
            let length = (textView.text as NSString?)?.length ?? 0
            if NSMaxRange(selectedRange) <= length { textView.selectedRange = selectedRange }
        }
    }

    /// Returns true when the document changed.
    @discardableResult
    private func apply(to textView: UITextView, coordinator: Coordinator) -> Bool {
        var changed = false
        if (textView.text ?? "") != text {
            textView.attributedText = NSAttributedString(string: text, attributes: coordinator.highlighter.baseAttributes)
            coordinator.highlighter.reset()
            changed = true
        }
        if let lineTints {
            if changed || coordinator.appliedTintsIdentity != lineTints.count || coordinator.tintsDirty {
                coordinator.highlighter.lineTints = lineTints
                coordinator.appliedTintsIdentity = lineTints.count
                coordinator.tintsDirty = false
                coordinator.highlighter.scheduleHighlight(of: textView, delayNanoseconds: 0)
            }
            coordinator.highlightingEnabled = true
        } else {
            coordinator.highlightingEnabled = false
        }
        return changed
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let highlighter = ViewportSyntaxHighlighter(baseAttributes: [
            .foregroundColor: UIColor.label,
            .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular),
        ])
        weak var textView: UITextView?
        var highlightingEnabled = false
        var appliedTintsIdentity = -1
        var tintsDirty = true

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard highlightingEnabled, let textView else { return }
            highlighter.scheduleHighlight(of: textView)
        }
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
        textView.alwaysBounceHorizontal = !isLineWrappingEnabled
        if #available(iOS 26.0, *), softTopEdge {
            textView.topEdgeEffect.style = .soft
        }
        textView.showsVerticalScrollIndicator = true
        textView.showsHorizontalScrollIndicator = !isLineWrappingEnabled
        textView.contentInsetAdjustmentBehavior = .always
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 20)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = isLineWrappingEnabled
        textView.textContainer.size.width = isLineWrappingEnabled
            ? max(0, textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right)
            : CGFloat.greatestFiniteMagnitude
        textView.textContainer.heightTracksTextView = false
        textView.textContainer.lineBreakMode = .byWordWrapping
    }
}

#endif
