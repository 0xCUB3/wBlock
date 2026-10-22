import SwiftUI

// SwiftUI pages on macOS scroll only with the trackpad or mouse. This gives
// them Safari's keys: the arrows step, Space and Shift-Space, Page Up/Down and
// Option-arrows page, and Home, End and Command-arrows jump to either end,
// each animated the way Safari glides. A focused list, text field or control
// that uses the key keeps it.
extension View {
    @ViewBuilder
    func keyboardScrollingCompat() -> some View {
        #if os(macOS)
        background(KeyboardScrollMonitor())
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

private struct KeyboardScrollMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> KeyboardScrollMonitorView { KeyboardScrollMonitorView() }
    func updateNSView(_ nsView: KeyboardScrollMonitorView, context: Context) {}
}

private final class KeyboardScrollMonitorView: NSView {
    private enum Step {
        case line(CGFloat)
        case page(CGFloat)
        case end(CGFloat)
    }

    private var monitor: Any?
    /// Where the running animation is headed, so key repeat keeps adding to
    /// the destination instead of to a position mid-glide.
    private var pending: (clip: NSClipView, y: CGFloat)?

    /// Safari's arrow step.
    private static let lineHeight: CGFloat = 40

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.attachedSheet == nil,
              let step = Self.step(for: event),
              !Self.keepsKey(event, responder: window.firstResponder),
              let scrollView = pageScrollView(in: window) else { return false }
        scroll(scrollView, by: step)
        return true
    }

    private static func step(for event: NSEvent) -> Step? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (Int(event.keyCode), flags) {
        case (126, []): return .line(-1)
        case (125, []): return .line(1)
        case (126, .option), (116, []): return .page(-1)
        case (125, .option), (121, []): return .page(1)
        case (49, []): return .page(1)
        case (49, .shift): return .page(-1)
        case (126, .command), (115, []): return .end(-1)
        case (125, .command), (119, []): return .end(1)
        default: return nil
        }
    }

    /// Text and value controls already act on these keys, a focused list
    /// moves its selection with all but Space, and Space presses whichever
    /// button holds keyboard focus.
    private static func keepsKey(_ event: NSEvent, responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView else { return false }
        if view is NSText || view is NSTextField || view is NSSlider || view is NSStepper
            || view is NSPopUpButton || view is NSDatePicker
            || view.isDescendant(ofClassNamed: "WKWebView") {
            return true
        }
        let isSpace = event.keyCode == 49
        if view is NSTableView { return !isSpace }
        return isSpace && view is NSControl
    }

    /// The largest visible vertical scroller: the page itself, not a strip of
    /// pills or a sidebar, and not a page in a tab that is hidden.
    private func pageScrollView(in window: NSWindow) -> NSScrollView? {
        guard let root = window.contentView else { return nil }
        var best: (view: NSScrollView, area: CGFloat)?
        func visit(_ view: NSView) {
            guard !view.isHidden, view.alphaValue > 0 else { return }
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               document.frame.height > scroll.contentView.bounds.height + 1 {
                let visible = scroll.convert(scroll.bounds, to: nil).intersection(root.convert(root.bounds, to: nil))
                let area = visible.width * visible.height
                if area > (best?.area ?? 0) { best = (scroll, area) }
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return best?.view
    }

    private func scroll(_ scrollView: NSScrollView, by step: Step) {
        let clip = scrollView.contentView
        guard let document = scrollView.documentView else { return }
        let insets = clip.contentInsets
        let minY = -insets.top
        let maxY = max(minY, document.frame.height - clip.bounds.height + insets.bottom)
        let start = pending.flatMap { $0.clip === clip ? $0.y : nil } ?? clip.bounds.origin.y
        // Flipped documents grow downward; otherwise down means a smaller y.
        let direction: CGFloat = document.isFlipped ? 1 : -1
        let target: CGFloat
        switch step {
        case .line(let sign):
            target = start + sign * direction * Self.lineHeight
        case .page(let sign):
            // Safari keeps a line of the previous page in view.
            target = start + sign * direction * max(Self.lineHeight, clip.bounds.height - insets.top - Self.lineHeight)
        case .end(let sign):
            target = sign * direction > 0 ? maxY : minY
        }
        let y = min(max(target, minY), maxY)
        guard y != start else { return }
        pending = (clip, y)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: y))
        } completionHandler: { [weak self] in
            if self?.pending?.clip === clip, self?.pending?.y == y { self?.pending = nil }
        }
        scrollView.reflectScrolledClipView(clip)
    }
}

private extension NSView {
    func isDescendant(ofClassNamed name: String) -> Bool {
        var view: NSView? = self
        while let current = view {
            if NSStringFromClass(type(of: current)).contains(name) { return true }
            view = current.superview
        }
        return false
    }
}
#endif
