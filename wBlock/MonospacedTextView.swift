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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        guard textView.string != text else { return }

        let selectedRanges = textView.selectedRanges
        textView.string = text
        textView.selectedRanges = selectedRanges
    }

    private func makeDocumentScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

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
}

#elseif os(iOS)
import UIKit

private final class ProgressiveBlurTextView: UITextView {
    let topBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let topBlurMask = CAGradientLayer()
    var showsProgressiveTopBlur = false

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        topBlurView.isUserInteractionEnabled = false
        topBlurMask.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
        topBlurMask.locations = [0, 1]
        topBlurView.layer.mask = topBlurMask
        addSubview(topBlurView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        topBlurView.isHidden = !showsProgressiveTopBlur
        topBlurView.frame = CGRect(
            x: contentOffset.x,
            y: contentOffset.y,
            width: bounds.width,
            height: 56
        )
        topBlurMask.frame = topBlurView.bounds
        bringSubviewToFront(topBlurView)
    }
}

struct MonospacedTextView: UIViewRepresentable {
    @Binding var text: String
    var softTopEdge = false

    func makeUIView(context: Context) -> UITextView {
        let textView = ProgressiveBlurTextView(frame: .zero, textContainer: nil)
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
        textView.alwaysBounceHorizontal = true
        if let textView = textView as? ProgressiveBlurTextView {
            textView.showsProgressiveTopBlur = softTopEdge
        }
        textView.showsVerticalScrollIndicator = true
        textView.showsHorizontalScrollIndicator = true
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.heightTracksTextView = false
        textView.textContainer.size = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer.lineBreakMode = .byClipping
    }
}

#endif
