import SwiftUI
import AppKit

private final class NavModel: ObservableObject {
    @Published var pushed = false
    var dismissCount = 0
}

private struct FixtureView: View {
    @ObservedObject var model: NavModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Websites") {
                    Text("Site Settings")
                    Text("Element Zapper")
                }
                Section("Advanced") {
                    Text("View Logs")
                    Text("Background Diagnostics")
                }
            }
            .formStyle(.grouped)
            .swipeBackRootCompat()
            .navigationDestination(isPresented: $model.pushed) {
                Form {
                    Section("Site Settings") {
                        Text("example.com")
                        Text("improving.duckduckgo.com")
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Site Settings")
                .swipeBackNavigationCompat()
            }
        }
    }
}

private extension NSView {
    var descendants: [NSView] { [self] + subviews.flatMap(\.descendants) }
}

@main @MainActor
struct SwipeBackNavigationTests {
    static func pump(_ seconds: TimeInterval = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func testStateMachine() {
        // 1. Momentum events never start a swipe.
        var state = SwipeBackGestureState()
        precondition(
            state.handleScroll(phase: .began, hasMomentum: true, dx: 24, dy: 0, swipeEnabled: true, reduceMotion: false) == .passThrough
                && state.mode == .idle,
            "momentum events must never start tracking"
        )

        // 2. Vertical scrolls reject and return to idle.
        precondition(
            state.handleScroll(phase: .began, hasMomentum: false, dx: 2, dy: 3, swipeEnabled: true, reduceMotion: false) == .passThrough
                && state.mode == .pendingAxis(dx: 2, dy: 3)
        )
        precondition(
            state.handleScroll(phase: .changed, hasMomentum: false, dx: 1, dy: 10, swipeEnabled: true, reduceMotion: false) == .passThrough
                && state.mode == .idle,
            "vertical drag must return to idle"
        )

        // 3. Leftward horizontal swipe rejects.
        precondition(
            state.handleScroll(phase: .began, hasMomentum: false, dx: -12, dy: 0, swipeEnabled: true, reduceMotion: false) == .passThrough
                && state.mode == .idle,
            "leftward swipe must not start back tracking"
        )

        // 4. Disabled system preference rejects.
        precondition(
            state.handleScroll(phase: .began, hasMomentum: false, dx: 12, dy: 0, swipeEnabled: false, reduceMotion: false) == .passThrough
                && state.mode == .idle
        )

        // 5. Fast Magic Mouse flick exceeding threshold on .began starts tracking immediately.
        precondition(
            state.handleScroll(phase: .began, hasMomentum: false, dx: 10, dy: 1, swipeEnabled: true, reduceMotion: false) == .startTracking
                && state.isActiveTracking
        )

        // 6. Holding finger steady tracks live progress and never commits prematurely.
        precondition(state.handleTrackUpdate(amount: 0.4, phase: .changed, isComplete: false) == .update(progress: 0.4))
        precondition(state.handleTrackUpdate(amount: 0.4, phase: .changed, isComplete: false) == .update(progress: 0.4))
        precondition(state.handleTrackUpdate(amount: 1.0, phase: .changed, isComplete: false) == .update(progress: 1.0))

        // 7. Releasing and settling past tailSnapThreshold snaps and commits once.
        precondition(state.handleTrackUpdate(amount: 0.996, phase: .ended, isComplete: false) == .commit(stop: true))
        precondition(state.mode == .committing)
        // Stray callbacks while committing are ignored and never double-commit.
        precondition(state.handleTrackUpdate(amount: 1.0, phase: [], isComplete: true) == .ignore)
        precondition(state.handleScroll(phase: .began, hasMomentum: false, dx: 20, dy: 0, swipeEnabled: true, reduceMotion: false) == .passThrough)
        state.finishCommit()
        precondition(state.mode == .idle)

        // 8. Releasing early settles back and cancels without committing.
        precondition(state.handleScroll(phase: .mayBegin, hasMomentum: false, dx: 0, dy: 0, swipeEnabled: true, reduceMotion: false) == .passThrough)
        precondition(state.handleScroll(phase: .changed, hasMomentum: false, dx: 9, dy: 0, swipeEnabled: true, reduceMotion: false) == .startTracking)
        precondition(state.handleTrackUpdate(amount: -0.35, phase: .changed, isComplete: false) == .update(progress: 0.35))
        precondition(state.handleTrackUpdate(amount: -0.35, phase: .ended, isComplete: false) == .update(progress: 0.35))
        precondition(state.handleTrackUpdate(amount: 0.0, phase: [], isComplete: true) == .cancel(stop: false))
        precondition(state.mode == .idle)

        // 9. Reduce Motion commits on release without sliding or waiting for AppKit settle tail.
        precondition(state.handleScroll(phase: .began, hasMomentum: false, dx: 12, dy: 0, swipeEnabled: true, reduceMotion: true) == .startTracking)
        precondition(state.handleTrackUpdate(amount: 0.4, phase: .changed, isComplete: false) == .update(progress: 0))
        precondition(state.handleTrackUpdate(amount: 0.4, phase: .ended, isComplete: false) == .commit(stop: true))
        state.finishCommit()
        precondition(state.mode == .idle)

        // 10. Reduce Motion below release threshold cancels immediately on release.
        precondition(state.handleScroll(phase: .began, hasMomentum: false, dx: 12, dy: 0, swipeEnabled: true, reduceMotion: true) == .startTracking)
        precondition(state.handleTrackUpdate(amount: 0.15, phase: .ended, isComplete: false) == .cancel(stop: true))
        precondition(state.mode == .idle)
    }

    static func testLiveInteractiveOverlay() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = NavModel()
        let host = NSHostingView(rootView: FixtureView(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 640, height: 420),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        pump(0.3)

        // Capture root page snapshot right before pushing.
        guard let rootMonitor = host.descendants.compactMap({ $0 as? SwipeBackRootSnapshotView }).first else {
            preconditionFailure("expected SwipeBackRootSnapshotView on root Settings page")
        }
        rootMonitor.captureCurrentContent()
        let cached = SwipeBackSnapshotCache.shared.snapshot(for: window)
        precondition(cached != nil, "root snapshot must be cached before push")
        precondition(abs(cached!.size.width - host.bounds.width) < 1, "snapshot width must match window content")

        // Push detail page.
        model.pushed = true
        pump(0.35)
        guard let backMonitor = host.descendants.compactMap({ $0 as? SwipeBackMonitorView }).first else {
            preconditionFailure("expected SwipeBackMonitorView on pushed page")
        }

        // Start live interactive swipe.
        backMonitor.beginTestingInteractiveSwipe(reduceMotion: false)
        guard let overlay = backMonitor.overlayView else {
            preconditionFailure("interactive swipe must install transition overlay immediately")
        }
        precondition(overlay.superview === host, "overlay must mount directly over window content view")
        precondition(overlay.underlayLayer.contents != nil, "matching-size root snapshot must populate underlay")
        precondition(overlay.foregroundContentLayer.contents != nil, "pushed page snapshot must populate foreground")
        precondition(overlay.foregroundLayer.backgroundColor != nil, "foreground must have opaque backing to prevent bleed-through")

        // Track finger to 40% and hold steady.
        let width = overlay.bounds.width
        backMonitor.applyTrackUpdate(amount: 0.4, phase: .changed, isComplete: false)
        precondition(abs(overlay.foregroundLayer.position.x - width * 0.4) < 0.5, "foreground must track finger 1-to-1")
        precondition(abs(overlay.underlayLayer.position.x - (-width * 0.25 * 0.6)) < 0.5, "underlay must track parallax")
        precondition(model.pushed, "holding mid-swipe must not dismiss")

        // Optional visual capture when requested via environment variable.
        if let capturePath = ProcessInfo.processInfo.environment["SWIPE_BACK_TEST_PNG"],
           let layer = overlay.layer {
            let scale = Int(max(window.backingScaleFactor, 1))
            let pxW = Int(overlay.bounds.width) * scale
            let pxH = Int(overlay.bounds.height) * scale
            if let ctx = CGContext(
                data: nil,
                width: pxW,
                height: pxH,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                layer.render(in: ctx)
                if let cg = ctx.makeImage() {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: capturePath))
                    }
                }
            }
        }

        // Cancel swipe: glides back to 0 and cleans up overlay without dismissing.
        backMonitor.applyTrackUpdate(amount: 0.2, phase: .ended, isComplete: false)
        backMonitor.applyTrackUpdate(amount: 0.0, phase: [], isComplete: true)
        precondition(backMonitor.overlayView == nil && overlay.superview == nil, "cancelled swipe must remove overlay")
        precondition(model.pushed, "cancelled swipe must keep pushed page active")

        // Window resize invalidates stale-dimension underlay snapshot cleanly.
        window.setContentSize(NSSize(width: 760, height: 460))
        pump(0.15)
        backMonitor.beginTestingInteractiveSwipe(reduceMotion: false)
        guard let resizedOverlay = backMonitor.overlayView else {
            preconditionFailure("resized swipe must still install overlay")
        }
        precondition(resizedOverlay.underlayLayer.contents == nil, "mismatched-size snapshot must not be stretched")
        backMonitor.applyTrackUpdate(amount: 0.0, phase: .cancelled, isComplete: true)
        precondition(backMonitor.overlayView == nil, "cancelled resized swipe must clean up")

        // Restore size, re-store a matching snapshot, and commit swipe via tail snap.
        window.setContentSize(NSSize(width: 640, height: 420))
        pump(0.15)
        backMonitor.beginTestingInteractiveSwipe(reduceMotion: false)
        precondition(backMonitor.overlayView?.underlayLayer.contents != nil, "matching-size snapshot must work again")
        var stop: ObjCBool = false
        backMonitor.applyTrackUpdate(amount: 0.55, phase: .changed, isComplete: false, stop: &stop)
        precondition(!stop.boolValue && model.pushed, "drag before release must not stop or dismiss")
        backMonitor.applyTrackUpdate(amount: 0.996, phase: .ended, isComplete: false, stop: &stop)
        precondition(stop.boolValue, "post-release >= 99.5% must stop AppKit's trailing tail immediately")
        pump(0.35)
        precondition(!model.pushed, "committed swipe must pop pushed page")
        precondition(host.subviews.allSatisfy { !($0 is SwipeBackTransitionOverlayView) }, "overlay must be removed after commit handoff")
        precondition(SwipeBackSnapshotCache.shared.snapshot(for: window) == nil, "root snapshot cache must clear after returning to root")

        // Reduce Motion: commits on release with no overlay.
        model.pushed = true
        pump(0.35)
        guard let rmMonitor = host.descendants.compactMap({ $0 as? SwipeBackMonitorView }).first else {
            preconditionFailure("expected SwipeBackMonitorView on second push")
        }
        rmMonitor.beginTestingInteractiveSwipe(reduceMotion: true)
        precondition(rmMonitor.overlayView == nil, "Reduce Motion must not install sliding overlay")
        stop = false
        rmMonitor.applyTrackUpdate(amount: 0.4, phase: .ended, isComplete: false, stop: &stop)
        precondition(stop.boolValue, "Reduce Motion must commit immediately on release")
        pump(0.35)
        precondition(!model.pushed, "Reduce Motion commit must dismiss pushed page")

        window.orderOut(nil)
    }

    static func main() {
        testStateMachine()
        testLiveInteractiveOverlay()
        print("PASS: SwipeBackGestureState and live interactive macOS swipe-back overlay verified")
    }
}
