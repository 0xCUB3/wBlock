#if os(macOS)
import Cocoa

@MainActor
final class MainWindowFrameRestorer: NSObject {
    static let frameDefaultsKey = "wBlock.MainWindowFrame"

    private weak var adoptedWindow: NSWindow?
    private var isInstalled = false
    private var isRestoring = false

    func install(application: NSApplication) {
        guard !isInstalled else { return }
        isInstalled = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMoveOrResize(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMoveOrResize(_:)),
            name: NSWindow.didResizeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        for window in application.windows where adoptedWindow == nil {
            adopt(window)
        }
    }

    @discardableResult
    func adopt(_ window: NSWindow) -> Bool {
        guard adoptedWindow == nil || adoptedWindow === window else { return false }
        guard isMainWindowCandidate(window) else { return false }

        adoptedWindow = window
        guard let restoredFrame = restoredFrame() else { return true }

        isRestoring = true
        apply(restoredFrame, to: window)

        // SwiftUI may impose its initial scene size during more than one layout pass.
        // Keep move and resize notifications muted until the final frame is reapplied.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.adoptedWindow === window else { return }
            self.apply(restoredFrame, to: window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.adoptedWindow === window else { return }
                self.apply(restoredFrame, to: window)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak window] in
            guard let self, let window, self.adoptedWindow === window else { return }
            self.apply(restoredFrame, to: window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.adoptedWindow === window else { return }
                self.isRestoring = false
            }
        }
        return true
    }

    func saveFrame(for window: NSWindow) {
        guard adoptedWindow === window, !isRestoring else { return }
        guard let frame = clampedFrame(window.frame) else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameDefaultsKey)
    }

    func saveAdoptedWindow() {
        guard let adoptedWindow else { return }
        saveFrame(for: adoptedWindow)
    }

    private func restoredFrame() -> NSRect? {
        guard let encoded = UserDefaults.standard.string(forKey: Self.frameDefaultsKey) else {
            return nil
        }
        return clampedFrame(NSRectFromString(encoded))
    }

    private func clampedFrame(_ frame: NSRect) -> NSRect? {
        let values = [frame.origin.x, frame.origin.y, frame.width, frame.height]
        guard values.allSatisfy(\.isFinite), !frame.isEmpty else { return nil }

        let targetScreen = NSScreen.screens
            .map { screen in (screen, NSIntersectionRect(frame, screen.frame).width * NSIntersectionRect(frame, screen.frame).height) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
        guard let targetScreen else { return nil }

        let visibleFrame = targetScreen.visibleFrame
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func apply(_ frame: NSRect, to window: NSWindow) {
        window.setFrame(frame, display: false)
    }

    private func isMainWindowCandidate(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel) else { return false }
        guard window.styleMask.contains(.titled), window.level == .normal else { return false }
        guard window.sheetParent == nil else { return false }
        guard !window.styleMask.contains(.utilityWindow), !window.styleMask.contains(.hudWindow) else { return false }
        return true
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        adopt(window)
    }

    @objc private func windowDidMoveOrResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        saveFrame(for: window)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, adoptedWindow === window else { return }
        saveFrame(for: window)
        adoptedWindow = nil
        isRestoring = false
    }
}
#endif
