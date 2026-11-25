import SwiftUI

// NavigationStack on macOS pops only through the toolbar back button. This
// gives a pushed page the fluid interactive swipe Safari and Finder use: a
// one-finger Magic Mouse or two-finger Trackpad scroll swipe under "Swipe
// between pages" that tracks the finger live and holds steady in place, a
// three-finger swipe gesture, or Command-[ as in Safari. iOS keeps the
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

    @ViewBuilder
    func swipeBackRootCompat() -> some View {
        #if os(macOS)
        background(SwipeBackRootSnapshotMonitor())
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

/// Pure state machine governing horizontal back-swipe detection and live
/// tracking progress so the gesture lifecycle is deterministic and testable.
struct SwipeBackGestureState: Equatable {
    enum Mode: Equatable {
        case idle
        case pendingAxis(dx: CGFloat, dy: CGFloat)
        case tracking(progress: CGFloat, didRelease: Bool, reduceMotion: Bool)
        case committing
    }

    enum ScrollOutcome: Equatable {
        case passThrough
        case startTracking
    }

    enum TrackAction: Equatable {
        case ignore
        case update(progress: CGFloat)
        case cancel(stop: Bool)
        case commit(stop: Bool)
    }

    /// A swipe declares its axis once this far along; shorter drags stay
    /// ambiguous so a slow vertical scroll does not start a back gesture.
    static let axisDecisionDistance: CGFloat = 8
    static let commitThreshold: CGFloat = 0.5
    /// Once the finger is released and AppKit's settle animation has slid the
    /// page 99.5% off-screen, snap cleanly instead of waiting out the sub-pixel tail.
    static let tailSnapThreshold: CGFloat = 0.995
    static let reduceMotionReleaseThreshold: CGFloat = 0.3

    private(set) var mode: Mode = .idle

    var isActiveTracking: Bool {
        switch mode {
        case .tracking, .committing:
            return true
        case .idle, .pendingAxis:
            return false
        }
    }

    mutating func handleScroll(
        phase: NSEvent.Phase,
        hasMomentum: Bool,
        dx: CGFloat,
        dy: CGFloat,
        swipeEnabled: Bool,
        reduceMotion: Bool
    ) -> ScrollOutcome {
        guard !isActiveTracking, !hasMomentum else { return .passThrough }

        switch phase {
        case .mayBegin:
            mode = .pendingAxis(dx: 0, dy: 0)
            return .passThrough
        case .began:
            return evaluateAxis(dx: dx, dy: dy, swipeEnabled: swipeEnabled, reduceMotion: reduceMotion)
        case .changed:
            guard case .pendingAxis(let accX, let accY) = mode else { return .passThrough }
            return evaluateAxis(
                dx: accX + dx,
                dy: accY + dy,
                swipeEnabled: swipeEnabled,
                reduceMotion: reduceMotion
            )
        default:
            mode = .idle
            return .passThrough
        }
    }

    private mutating func evaluateAxis(
        dx: CGFloat,
        dy: CGFloat,
        swipeEnabled: Bool,
        reduceMotion: Bool
    ) -> ScrollOutcome {
        guard max(abs(dx), abs(dy)) >= Self.axisDecisionDistance else {
            mode = .pendingAxis(dx: dx, dy: dy)
            return .passThrough
        }
        guard abs(dx) > abs(dy), dx > 0, swipeEnabled else {
            mode = .idle
            return .passThrough
        }
        mode = .tracking(progress: 0, didRelease: false, reduceMotion: reduceMotion)
        return .startTracking
    }

    mutating func handleTrackUpdate(
        amount: CGFloat,
        phase: NSEvent.Phase,
        isComplete: Bool
    ) -> TrackAction {
        guard case .tracking(_, var didRelease, let reduceMotion) = mode else {
            return .ignore
        }
        let progress = min(max(abs(amount), 0), 1)
        if phase == .ended || phase == .cancelled {
            didRelease = true
        }

        if reduceMotion {
            if isComplete {
                if progress >= Self.commitThreshold {
                    mode = .committing
                    return .commit(stop: false)
                }
                mode = .idle
                return .cancel(stop: false)
            }
            if phase == .cancelled {
                mode = .idle
                return .cancel(stop: true)
            }
            if phase == .ended {
                if progress >= Self.reduceMotionReleaseThreshold {
                    mode = .committing
                    return .commit(stop: true)
                }
                mode = .idle
                return .cancel(stop: true)
            }
            mode = .tracking(progress: progress, didRelease: didRelease, reduceMotion: true)
            return .update(progress: 0)
        }

        if isComplete {
            if progress >= Self.commitThreshold {
                mode = .committing
                return .commit(stop: false)
            }
            mode = .idle
            return .cancel(stop: false)
        }

        if didRelease && progress >= Self.tailSnapThreshold {
            mode = .committing
            return .commit(stop: true)
        }

        mode = .tracking(progress: progress, didRelease: didRelease, reduceMotion: false)
        return .update(progress: progress)
    }

    mutating func finishCommit() {
        if mode == .committing {
            mode = .idle
        }
    }

    mutating func abort() {
        mode = .idle
    }
}

@MainActor
final class SwipeBackSnapshotCache {
    struct Snapshot {
        let image: CGImage
        let size: CGSize
        let appearanceName: NSAppearance.Name
    }

    private final class Box {
        let snapshot: Snapshot
        init(_ snapshot: Snapshot) { self.snapshot = snapshot }
    }

    static let shared = SwipeBackSnapshotCache()
    private let storage = NSMapTable<NSWindow, Box>.weakToStrongObjects()

    func store(_ snapshot: Snapshot, for window: NSWindow) {
        storage.setObject(Box(snapshot), forKey: window)
    }

    func snapshot(for window: NSWindow) -> Snapshot? {
        storage.object(forKey: window)?.snapshot
    }

    func clear(for window: NSWindow) {
        storage.removeObject(forKey: window)
    }

    static func capture(view: NSView) -> Snapshot? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        view.cacheDisplay(in: bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        return Snapshot(
            image: image,
            size: bounds.size,
            appearanceName: view.effectiveAppearance.name
        )
    }
}

/// Core Animation overlay mounted over the window's content view during a live
/// interactive swipe-back so the pushed page tracks the finger at display rate
/// without SwiftUI relayout or transparent-background bleed-through.
@MainActor
final class SwipeBackTransitionOverlayView: NSView {
    let underlayLayer = CALayer()
    let dimLayer = CALayer()
    let foregroundLayer = CALayer()
    let foregroundContentLayer = CALayer()

    private(set) var progress: CGFloat = 0
    private static let underlayParallaxFraction: CGFloat = 0.25
    private static let maxDimOpacity: Float = 0.14
    private static let maxShadowOpacity: Float = 0.24

    init(
        frame: NSRect,
        current: SwipeBackSnapshotCache.Snapshot,
        previous: SwipeBackSnapshotCache.Snapshot?,
        appearance: NSAppearance,
        scale: CGFloat
    ) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]

        var bgColor = NSColor.windowBackgroundColor.cgColor
        appearance.performAsCurrentDrawingAppearance {
            bgColor = NSColor.windowBackgroundColor.cgColor
        }

        let root = layer!
        root.masksToBounds = true
        root.backgroundColor = bgColor

        underlayLayer.anchorPoint = .zero
        underlayLayer.contentsScale = scale
        underlayLayer.masksToBounds = true
        underlayLayer.backgroundColor = bgColor
        if let previous, Self.matches(previous, bounds: bounds.size, appearance: appearance.name) {
            underlayLayer.contents = previous.image
            underlayLayer.contentsGravity = abs(previous.size.height - bounds.height) < 1 ? .resize : .top
        }

        dimLayer.anchorPoint = .zero
        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.opacity = Self.maxDimOpacity

        foregroundLayer.anchorPoint = .zero
        foregroundLayer.backgroundColor = bgColor
        foregroundLayer.shadowColor = NSColor.black.cgColor
        foregroundLayer.shadowRadius = 14
        foregroundLayer.shadowOffset = CGSize(width: -4, height: 0)
        foregroundLayer.shadowOpacity = Self.maxShadowOpacity

        foregroundContentLayer.anchorPoint = .zero
        foregroundContentLayer.contents = current.image
        foregroundContentLayer.contentsScale = scale
        foregroundContentLayer.contentsGravity = .resize
        foregroundContentLayer.masksToBounds = true

        foregroundLayer.addSublayer(foregroundContentLayer)
        root.addSublayer(underlayLayer)
        root.addSublayer(dimLayer)
        root.addSublayer(foregroundLayer)

        applyLayout(progress: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Absorb stray clicks while the interactive swipe transition is active.
        self
    }

    override func layout() {
        super.layout()
        applyLayout(progress: progress)
    }

    func update(progress newProgress: CGFloat) {
        progress = min(max(newProgress, 0), 1)
        applyLayout(progress: progress)
    }

    private func applyLayout(progress p: CGFloat) {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let rect = CGRect(origin: .zero, size: size)
        underlayLayer.bounds = rect
        underlayLayer.position = CGPoint(x: -size.width * Self.underlayParallaxFraction * (1 - p), y: 0)

        dimLayer.bounds = rect
        dimLayer.position = .zero
        dimLayer.opacity = Self.maxDimOpacity * Float(1 - p)

        foregroundLayer.bounds = rect
        foregroundLayer.position = CGPoint(x: size.width * p, y: 0)
        foregroundLayer.shadowPath = CGPath(rect: rect, transform: nil)
        foregroundLayer.shadowOpacity = p > 0 ? Self.maxShadowOpacity * Float(1 - p) : 0

        foregroundContentLayer.bounds = rect
        foregroundContentLayer.position = .zero

        CATransaction.commit()
    }

    static func matches(
        _ snapshot: SwipeBackSnapshotCache.Snapshot,
        bounds: CGSize,
        appearance: NSAppearance.Name
    ) -> Bool {
        abs(snapshot.size.width - bounds.width) < 1
            && abs(snapshot.size.height - bounds.height) <= 64
            && snapshot.appearanceName == appearance
    }
}

private struct MacSwipeBackNavigation: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.background(SwipeBackMonitor(
            goBackAnimated: {
                withAnimation(reduceMotion ? nil : .default) { dismiss() }
            },
            goBackImmediately: {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { dismiss() }
            }
        ))
    }
}

private struct SwipeBackRootSnapshotMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> SwipeBackRootSnapshotView {
        SwipeBackRootSnapshotView()
    }

    func updateNSView(_ nsView: SwipeBackRootSnapshotView, context: Context) {}
}

/// Captures the root page right before a click or keyboard activation pushes a
/// destination so interactive swipe-back can reveal the exact scrolled root page.
@MainActor
final class SwipeBackRootSnapshotView: NSView {
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard let window else { return }
        SwipeBackSnapshotCache.shared.clear(for: window)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            self?.captureIfNeeded(for: event)
            return event
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    func captureCurrentContent() {
        guard let window, let contentView = window.contentView,
              let snapshot = SwipeBackSnapshotCache.capture(view: contentView) else {
            return
        }
        SwipeBackSnapshotCache.shared.store(snapshot, for: window)
    }

    private func captureIfNeeded(for event: NSEvent) {
        guard let window, event.window === window,
              window.attachedSheet == nil, NSApp.modalWindow == nil,
              !isHiddenOrHasHiddenAncestor else {
            return
        }
        switch event.type {
        case .leftMouseDown:
            let localPoint = convert(event.locationInWindow, from: nil)
            guard bounds.contains(localPoint) else { return }
            captureCurrentContent()
        case .keyDown:
            // Return (36), Enter (76), or Space (49) can activate a focused NavigationLink.
            guard event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 else { return }
            captureCurrentContent()
        default:
            return
        }
    }
}

private struct SwipeBackMonitor: NSViewRepresentable {
    let goBackAnimated: () -> Void
    let goBackImmediately: () -> Void

    func makeNSView(context: Context) -> SwipeBackMonitorView {
        SwipeBackMonitorView()
    }

    func updateNSView(_ nsView: SwipeBackMonitorView, context: Context) {
        nsView.goBackAnimated = goBackAnimated
        nsView.goBackImmediately = goBackImmediately
    }
}

@MainActor
final class SwipeBackMonitorView: NSView {
    var goBackAnimated: () -> Void = {}
    var goBackImmediately: () -> Void = {}

    private var monitor: Any?
    private(set) var gestureState = SwipeBackGestureState()
    private(set) var overlayView: SwipeBackTransitionOverlayView?
    private var trackingGeneration: UInt64 = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        abortInteractiveTransition()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe, .keyDown]) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        let overlay = overlayView
        MainActor.assumeIsolated {
            overlay?.removeFromSuperview()
        }
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
            // Gesture events arrive with the three-finger (or Magic Mouse
            // two-finger) preference; positive deltaX moves toward the past.
            guard !gestureState.isActiveTracking, event.deltaX > 0 else { return false }
            goBackAnimated()
            return true
        case .scrollWheel:
            return handleScroll(event)
        case .keyDown:
            guard !gestureState.isActiveTracking,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
                  event.charactersIgnoringModifiers == "[" else { return false }
            goBackAnimated()
            return true
        default:
            return false
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard !gestureState.isActiveTracking else { return false }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let outcome = gestureState.handleScroll(
            phase: event.phase,
            hasMomentum: event.momentumPhase != [],
            dx: event.scrollingDeltaX,
            dy: event.scrollingDeltaY,
            swipeEnabled: NSEvent.isSwipeTrackingFromScrollEventsEnabled,
            reduceMotion: reduceMotion
        )
        guard outcome == .startTracking else { return false }
        if canScrollHorizontallyLeft(at: event) {
            gestureState.abort()
            return false
        }
        startInteractiveTrack(event, reduceMotion: reduceMotion)
        return true
    }

    private func canScrollHorizontallyLeft(at event: NSEvent) -> Bool {
        guard let contentView = window?.contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        var current = contentView.hitTest(point)
        while let view = current {
            if let scrollView = view as? NSScrollView, let document = scrollView.documentView {
                let clip = scrollView.contentView
                let minX = -clip.contentInsets.left
                if document.frame.width > clip.bounds.width + 1, clip.bounds.minX > minX + 1 {
                    return true
                }
            }
            current = view.superview
        }
        return false
    }

    private func startInteractiveTrack(_ event: NSEvent, reduceMotion: Bool) {
        trackingGeneration &+= 1
        let generation = trackingGeneration

        if !reduceMotion {
            installOverlay()
        }

        event.trackSwipeEvent(
            options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: -1,
            max: 1
        ) { [weak self] amount, phase, isComplete, stop in
            MainActor.assumeIsolated {
                guard let self, self.trackingGeneration == generation else {
                    stop.pointee = true
                    return
                }
                if self.window == nil || self.window?.attachedSheet != nil || NSApp.modalWindow != nil {
                    self.abortInteractiveTransition()
                    stop.pointee = true
                    return
                }
                self.applyTrackUpdate(amount: amount, phase: phase, isComplete: isComplete, stop: stop)
            }
        }
    }

    func beginTestingInteractiveSwipe(reduceMotion: Bool = false) {
        trackingGeneration &+= 1
        _ = gestureState.handleScroll(
            phase: .began,
            hasMomentum: false,
            dx: SwipeBackGestureState.axisDecisionDistance,
            dy: 0,
            swipeEnabled: true,
            reduceMotion: reduceMotion
        )
        if !reduceMotion {
            installOverlay()
        }
    }

    func applyTrackUpdate(
        amount: CGFloat,
        phase: NSEvent.Phase,
        isComplete: Bool,
        stop: UnsafeMutablePointer<ObjCBool>? = nil
    ) {
        let action = gestureState.handleTrackUpdate(amount: amount, phase: phase, isComplete: isComplete)
        switch action {
        case .ignore:
            stop?.pointee = true
        case .update(let progress):
            overlayView?.update(progress: progress)
        case .cancel(let shouldStop):
            if shouldStop { stop?.pointee = true }
            removeOverlay()
        case .commit(let shouldStop):
            if shouldStop { stop?.pointee = true }
            completeCommit()
        }
    }

    private func installOverlay() {
        removeOverlay()
        guard let window, let contentView = window.contentView,
              let current = SwipeBackSnapshotCache.capture(view: contentView) else {
            return
        }
        let previous = SwipeBackSnapshotCache.shared.snapshot(for: window)
        let overlay = SwipeBackTransitionOverlayView(
            frame: contentView.bounds,
            current: current,
            previous: previous,
            appearance: contentView.effectiveAppearance,
            scale: window.backingScaleFactor
        )
        contentView.addSubview(overlay)
        overlayView = overlay
    }

    private func completeCommit() {
        overlayView?.update(progress: 1)
        let overlay = overlayView
        let windowRef = window
        let contentView = window?.contentView
        // Detach the overlay ownership from this view before dismissing so
        // viewDidMoveToWindow(nil) during pop doesn't yank it away before
        // Settings has rendered one frame underneath.
        overlayView = nil
        goBackImmediately()
        DispatchQueue.main.async { [weak self] in
            contentView?.layoutSubtreeIfNeeded()
            overlay?.removeFromSuperview()
            if let windowRef {
                SwipeBackSnapshotCache.shared.clear(for: windowRef)
            }
            self?.gestureState.finishCommit()
        }
    }

    private func removeOverlay() {
        overlayView?.removeFromSuperview()
        overlayView = nil
    }

    private func abortInteractiveTransition() {
        trackingGeneration &+= 1
        gestureState.abort()
        removeOverlay()
    }
}
#endif
