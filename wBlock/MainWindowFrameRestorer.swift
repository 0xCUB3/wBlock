#if os(macOS)
import Cocoa

@MainActor
final class MainWindowFrameRestorer: NSObject {
    static let autosaveName = "wBlock.MainWindow"

    private weak var adoptedWindow: NSWindow?
    private var isInstalled = false

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
        window.setFrameAutosaveName(Self.autosaveName)
        window.setFrameUsingName(Self.autosaveName)

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.adoptedWindow === window else { return }
            window.setFrameUsingName(Self.autosaveName)
        }
        return true
    }

    func saveFrame(for window: NSWindow) {
        guard adoptedWindow === window else { return }
        window.saveFrame(usingName: Self.autosaveName)
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

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, adoptedWindow === window else { return }
        saveFrame(for: window)
        adoptedWindow = nil
    }
}
#endif
