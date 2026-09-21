import SwiftUI

// NavigationStack on macOS pops only through the toolbar back button. This
// gives a pushed page the trackpad gesture Safari and Finder use: a two-finger
// swipe under the "Swipe between pages" preference (tracked through scroll
// events, so it follows natural scrolling and bounces back when released
// early) or a three-finger swipe delivered as a gesture event. iOS keeps the
// interactive pop its navigation stack already provides.
extension View {
    @ViewBuilder
    func swipeBackNavigationCompat() -> some View {
        #if os(macOS)
        modifier(MacSwipeBackNavigation())
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

private struct MacSwipeBackNavigation: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.background(SwipeBackMonitor(goBack: { dismiss() }))
    }
}

private struct SwipeBackMonitor: NSViewRepresentable {
    let goBack: () -> Void

    func makeNSView(context: Context) -> SwipeBackMonitorView {
        SwipeBackMonitorView()
    }

    func updateNSView(_ nsView: SwipeBackMonitorView, context: Context) {
        nsView.goBack = goBack
    }
}

private final class SwipeBackMonitorView: NSView {
    var goBack: () -> Void = {}
    private var monitor: Any?
    /// Accumulated deltas of a scroll gesture whose axis is still undecided;
    /// nil once the gesture is vertical, tracked as a swipe, or over.
    private var pendingDelta: CGSize?
    private var isTracking = false

    /// A swipe declares its axis once this far along; shorter drags stay
    /// ambiguous so a slow vertical scroll does not start a back gesture.
    private static let axisDecisionDistance: CGFloat = 8

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
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

    private var isActivePage: Bool {
        guard let window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
        return !isHiddenOrHasHiddenAncestor
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, isActivePage else { return false }
        switch event.type {
        case .swipe:
            // Gesture events arrive only with the three-finger preference;
            // a positive delta is the page moving right, toward the past.
            guard event.deltaX > 0 else { return false }
            goBack()
            return true
        case .scrollWheel:
            return handleScroll(event)
        default:
            return false
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard !isTracking, event.momentumPhase == [] else { return false }
        switch event.phase {
        case .began:
            pendingDelta = .zero
            return false
        case .changed:
            guard var delta = pendingDelta else { return false }
            delta.width += event.scrollingDeltaX
            delta.height += event.scrollingDeltaY
            pendingDelta = delta
            guard max(abs(delta.width), abs(delta.height)) >= Self.axisDecisionDistance else { return false }
            pendingDelta = nil
            guard abs(delta.width) > abs(delta.height), delta.width > 0,
                  NSEvent.isSwipeTrackingFromScrollEventsEnabled else { return false }
            track(event)
            return true
        default:
            pendingDelta = nil
            return false
        }
    }

    private func track(_ event: NSEvent) {
        isTracking = true
        event.trackSwipeEvent(options: .lockDirection, dampenAmountThresholdMin: -1, max: 1) { [weak self] amount, _, isComplete, _ in
            guard isComplete, let self else { return }
            self.isTracking = false
            // The amount settles on ±1 for a committed swipe and 0 for one
            // released before the threshold.
            if abs(amount) >= 0.5 { self.goBack() }
        }
    }
}
#endif
