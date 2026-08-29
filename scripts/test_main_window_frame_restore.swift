import Cocoa

@main
struct MainWindowFrameRestoreTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared

        let defaultsKey = "NSWindow Frame \(MainWindowFrameRestorer.autosaveName)"
        let previousValue = UserDefaults.standard.object(forKey: defaultsKey)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: defaultsKey)

        let firstWindow = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let firstRestorer = MainWindowFrameRestorer()
        expect(firstRestorer.adopt(firstWindow), "a titled normal-level window should be adopted")
        expect(
            firstWindow.frameAutosaveName == MainWindowFrameRestorer.autosaveName,
            "the adopted window should receive the main-window autosave name"
        )

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            fail("no screen is available for window frame restoration")
        }
        let savedFrame = NSRect(
            x: screen.visibleFrame.minX + 120,
            y: screen.visibleFrame.minY + 80,
            width: 960,
            height: 640
        )
        firstWindow.setFrame(savedFrame, display: false)
        firstRestorer.saveFrame(for: firstWindow)

        let secondWindow = NSWindow(
            contentRect: NSRect(x: 400, y: 300, width: 320, height: 240),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let secondRestorer = MainWindowFrameRestorer()
        expect(secondRestorer.adopt(secondWindow), "a replacement main window should be adopted")
        expectFramesMatch(secondWindow.frame, savedFrame)

        let panel = NSPanel(
            contentRect: NSRect(x: 10, y: 10, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let originalPanelAutosaveName = panel.frameAutosaveName
        let panelRestorer = MainWindowFrameRestorer()
        expect(!panelRestorer.adopt(panel), "an NSPanel should not be adopted")
        expect(panel.frameAutosaveName == originalPanelAutosaveName, "an NSPanel autosave name should stay unchanged")

        print("PASS: main window frame restore")
    }

    private static func expectFramesMatch(_ actual: NSRect, _ expected: NSRect) {
        let tolerance: CGFloat = 1
        expect(
            abs(actual.origin.x - expected.origin.x) <= tolerance,
            "restored x origin \(actual.origin.x) differs from saved value \(expected.origin.x)"
        )
        expect(
            abs(actual.origin.y - expected.origin.y) <= tolerance,
            "restored y origin \(actual.origin.y) differs from saved value \(expected.origin.y)"
        )
        expect(
            abs(actual.size.width - expected.size.width) <= tolerance,
            "restored width \(actual.size.width) differs from saved value \(expected.size.width)"
        )
        expect(
            abs(actual.size.height - expected.size.height) <= tolerance,
            "restored height \(actual.size.height) differs from saved value \(expected.size.height)"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
