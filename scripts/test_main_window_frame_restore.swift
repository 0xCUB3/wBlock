import Cocoa

@main
struct MainWindowFrameRestoreTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared

        let defaultsKey = MainWindowFrameRestorer.frameDefaultsKey
        let previousValue = UserDefaults.standard.object(forKey: defaultsKey)
        defer {
            if let previousValue {
                UserDefaults.standard.set(previousValue, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: defaultsKey)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            fail("no screen is available for window frame restoration")
        }
        let visibleFrame = screen.visibleFrame
        let savedFrame = NSRect(
            x: visibleFrame.minX + visibleFrame.width * 0.12,
            y: visibleFrame.minY + visibleFrame.height * 0.12,
            width: visibleFrame.width * 0.7,
            height: visibleFrame.height * 0.7
        )

        let firstWindow = makeWindow(frame: NSRect(x: 20, y: 20, width: 500, height: 400))
        let firstRestorer = MainWindowFrameRestorer()
        expect(firstRestorer.adopt(firstWindow), "a titled normal-level window should be adopted")
        firstWindow.setFrame(savedFrame, display: true)
        firstRestorer.saveFrame(for: firstWindow)
        let persistedSavedFrame = persistedFrame(defaultsKey: defaultsKey)

        let secondWindow = makeWindow(frame: NSRect(x: 400, y: 300, width: 320, height: 240))
        let secondRestorer = MainWindowFrameRestorer()
        expect(secondRestorer.adopt(secondWindow), "a replacement main window should be adopted")
        expectFramesMatch(secondWindow.frame, persistedSavedFrame)

        let swiftUIShrink = NSRect(
            x: visibleFrame.midX - 180,
            y: visibleFrame.midY - 140,
            width: 360,
            height: 280
        )
        secondWindow.setFrame(swiftUIShrink, display: true)
        secondRestorer.saveFrame(for: secondWindow)
        expectFramesMatch(persistedFrame(defaultsKey: defaultsKey), persistedSavedFrame)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        expectFramesMatch(secondWindow.frame, persistedSavedFrame)
        expectFramesMatch(persistedFrame(defaultsKey: defaultsKey), persistedSavedFrame)

        let userFrame = NSRect(
            x: visibleFrame.minX + visibleFrame.width * 0.18,
            y: visibleFrame.minY + visibleFrame.height * 0.16,
            width: visibleFrame.width * 0.62,
            height: visibleFrame.height * 0.6
        )
        secondWindow.setFrame(userFrame, display: true)
        secondRestorer.saveFrame(for: secondWindow)
        let persistedUserFrame = persistedFrame(defaultsKey: defaultsKey)

        let thirdWindow = makeWindow(frame: swiftUIShrink)
        let thirdRestorer = MainWindowFrameRestorer()
        expect(thirdRestorer.adopt(thirdWindow), "the main window should be adopted on a later launch")
        expectFramesMatch(thirdWindow.frame, persistedUserFrame)

        let panel = NSPanel(
            contentRect: NSRect(x: 10, y: 10, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let panelRestorer = MainWindowFrameRestorer()
        expect(!panelRestorer.adopt(panel), "an NSPanel should not be adopted")

        print("PASS: main window frame restore")
    }

    private static func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.orderFront(nil)
        window.setIsVisible(true)
        return window
    }

    private static func persistedFrame(defaultsKey: String) -> NSRect {
        guard let encoded = UserDefaults.standard.string(forKey: defaultsKey) else {
            fail("no main window frame was persisted")
        }
        return NSRectFromString(encoded)
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
