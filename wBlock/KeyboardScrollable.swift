import SwiftUI

#if os(macOS)
import AppKit

// SwiftUI's ScrollView on macOS ignores the keyboard unless something inside it
// is first responder. This attaches a key monitor to the window that scrolls the
// enclosing NSScrollView with the arrow keys, Page Up/Down, Home/End, and
// Command plus Up/Down for the top and bottom of the page, while leaving text
// editing views alone.
extension View {
    func keyboardScrollable() -> some View {
        background(KeyboardScrollMonitor())
    }
}

private struct KeyboardScrollMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> KeyboardScrollMonitorView {
        KeyboardScrollMonitorView()
    }

    func updateNSView(_ nsView: KeyboardScrollMonitorView, context: Context) {}
}

final class KeyboardScrollMonitorView: NSView {
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
    }

    deinit {
        removeMonitor()
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private var hostScrollView: NSScrollView? {
        var view: NSView? = superview
        while let current = view {
            if let scrollView = current as? NSScrollView { return scrollView }
            view = current.superview
        }
        return nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.attachedSheet == nil else { return false }
        if let responder = window.firstResponder as? NSView, responder is NSTextView || responder is NSTextField {
            return false
        }
        guard let scrollView = hostScrollView, let action = Self.action(for: event) else { return false }
        scroll(scrollView, action)
        return true
    }

    private enum ScrollAction {
        case lines(CGFloat)
        case pages(CGFloat)
        case top
        case bottom
    }

    private static func action(for event: NSEvent) -> ScrollAction? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isSubset(of: [.command, .function, .numericPad]) else { return nil }
        let command = flags.contains(.command)
        switch event.keyCode {
        case 126: return command ? .top : .lines(-1)
        case 125: return command ? .bottom : .lines(1)
        case 116: return command ? nil : .pages(-1)
        case 121: return command ? nil : .pages(1)
        case 115: return command ? nil : .top
        case 119: return command ? nil : .bottom
        default: return nil
        }
    }

    private func scroll(_ scrollView: NSScrollView, _ action: ScrollAction) {
        let clip = scrollView.contentView
        let visible = clip.bounds
        let documentHeight = scrollView.documentView?.frame.height ?? visible.height
        let maxY = max(0, documentHeight - visible.height)
        let lineStep = max(scrollView.verticalLineScroll, 40)
        let target: CGFloat
        switch action {
        case .lines(let count): target = visible.origin.y + count * lineStep
        case .pages(let count): target = visible.origin.y + count * max(visible.height - lineStep, lineStep)
        case .top: target = 0
        case .bottom: target = maxY
        }
        let clamped = min(max(0, target), maxY)
        guard clamped != visible.origin.y else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            clip.animator().setBoundsOrigin(NSPoint(x: visible.origin.x, y: clamped))
        }
        scrollView.reflectScrolledClipView(clip)
    }
}
#endif
