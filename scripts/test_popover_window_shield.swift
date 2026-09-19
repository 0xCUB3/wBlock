import AppKit

@main
@MainActor
struct PopoverWindowShieldTests {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let popup = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                             styleMask: [.titled], backing: .buffered, defer: false)
        let shield = PopoverWindowShieldView()
        var dismissals = 0
        shield.dismiss = { dismissals += 1 }
        precondition(!shield.consume(.leftMouseDown, in: parent))
        parent.contentView = shield
        for event in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            precondition(!shield.consume(event, in: parent), "outside click must be retargeted after dismissal")
            precondition(!shield.consume(event, in: popup), "popup controls must stay interactive")
        }
        precondition(dismissals == 3)
        precondition(shield.consume(.scrollWheel, in: parent), "parent scrolling must be blocked")
        precondition(dismissals == 3, "scrolling outside must not dismiss the popup")
        precondition(!shield.consume(.scrollWheel, in: popup), "popup content must remain scrollable")
        precondition(!shield.consume(.leftMouseDown, in: nil))
        precondition(!shield.consume(.keyDown, in: parent))
        parent.contentView = NSView()
        precondition(shield.window == nil)
        precondition(!shield.consume(.leftMouseDown, in: parent), "detached shields must stop blocking")
        print("PASS: popup dismissal and retargeting, scroll isolation, and teardown")
    }
}
