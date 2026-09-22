import SwiftUI
import AppKit

private struct Item: Identifiable { let id: Int }
private final class Model: ObservableObject { @Published var selected: Item? }
private final class Box { var buttons: [Int: NSView] = [:] }
private struct Marker: NSViewRepresentable {
    let id: Int
    let box: Box
    func makeNSView(context: Context) -> NSView { let view = NSView(); box.buttons[id] = view; return view }
    func updateNSView(_ view: NSView, context: Context) { box.buttons[id] = view }
}
private struct Fixture: View {
    @ObservedObject var model: Model
    let box: Box
    var body: some View {
        HStack(spacing: 120) {
            ForEach([1, 2], id: \.self) { id in
                Button("Info \(id)") { model.selected = Item(id: id) }
                    .background(Marker(id: id, box: box))
                    .infoPopoverAnchor(id)
            }
        }
        .padding(40)
        .infoPresentation(item: $model.selected) { item in
            Text("Info \(item.id)").frame(width: 160, height: 80)
        }
    }
}
private extension NSView {
    var descendants: [NSView] { [self] + subviews.flatMap(\.descendants) }
}

@main @MainActor
struct PopoverWindowShieldTests {
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.35)) }
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = Model(), box = Box()
        let host = NSHostingView(rootView: Fixture(model: model, box: box))
        let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 540, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        pump()

        func shields() -> [PopoverWindowShieldView] { host.descendants.compactMap { $0 as? PopoverWindowShieldView } }
        func popups() -> [NSWindow] { NSApp.windows.filter { $0 !== window && $0.isVisible } }
        precondition(shields().isEmpty && popups().isEmpty, "idle anchors must not shield or show a popup")

        // Exercise the repaired single-host path before its first AppKit readiness callback.
        model.selected = Item(id: 1)
        model.selected = Item(id: 2)
        model.selected = Item(id: 1)
        pump()
        precondition(model.selected?.id == 1, "rapid A->B->A must retain the final selection")
        precondition(shields().count == 1, "rapid A->B->A must install one shield")
        precondition(popups().count == 1, "rapid A->B->A must show exactly one popup")
        let shield = shields()[0]
        let button = box.buttons[1]!
        let anchorRect = shield.convert(shield.bounds, to: nil)
        let buttonRect = button.convert(button.bounds, to: nil)
        precondition(abs(anchorRect.minX - buttonRect.minX) < 1 && abs(anchorRect.minY - buttonRect.minY) < 1 && abs(anchorRect.width - buttonRect.width) < 1 && abs(anchorRect.height - buttonRect.height) < 1, "attachment host must match the button")

        // Switching an already-open popup must reuse its host. A delayed
        // dismissal from the first item must not close the second item.
        let dismissFirst = shield.dismiss
        model.selected = Item(id: 2)
        pump()
        precondition(model.selected?.id == 2 && popups().count == 1,
                     "retargeting an open popup must retain the new selection")
        dismissFirst()
        pump()
        precondition(model.selected?.id == 2 && popups().count == 1,
                     "a stale dismissal must not close the current popup")
        model.selected = nil
        pump()
        precondition(shields().isEmpty && popups().isEmpty, "dismissal must remove the shield")

        // Cancellation before readiness must leave the host idle, then reopening must work.
        model.selected = Item(id: 2)
        model.selected = nil
        pump()
        precondition(model.selected == nil && shields().isEmpty && popups().isEmpty, "cancellation before readiness must leave no popup or shield")
        model.selected = Item(id: 2)
        pump()
        precondition(model.selected?.id == 2 && shields().count == 1 && popups().count == 1, "reopening after cancellation must present one popup")
        let reopened = shields()[0]
        let reopenedButton = box.buttons[2]!
        let reopenedHostRect = reopened.convert(reopened.bounds, to: nil)
        let reopenedButtonRect = reopenedButton.convert(reopenedButton.bounds, to: nil)
        precondition(abs(reopenedHostRect.minX - reopenedButtonRect.minX) < 1 && abs(reopenedHostRect.minY - reopenedButtonRect.minY) < 1 && abs(reopenedHostRect.width - reopenedButtonRect.width) < 1 && abs(reopenedHostRect.height - reopenedButtonRect.height) < 1, "reopened host must match the button")

        model.selected = nil
        pump()
        precondition(shields().isEmpty && popups().isEmpty, "teardown must restore the idle host")

        // Keep the original shield behavior checks in the same one-main standalone fixture.
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let popup = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let standaloneShield = PopoverWindowShieldView()
        var dismissals = 0
        standaloneShield.dismiss = { dismissals += 1 }
        precondition(!standaloneShield.consume(.leftMouseDown, in: parent))
        parent.contentView = standaloneShield
        for event in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            precondition(!standaloneShield.consume(event, in: parent))
            precondition(!standaloneShield.consume(event, in: popup))
        }
        precondition(dismissals == 3)
        precondition(standaloneShield.consume(.scrollWheel, in: parent) && dismissals == 3)
        precondition(!standaloneShield.consume(.scrollWheel, in: popup))
        precondition(!standaloneShield.consume(.leftMouseDown, in: nil))
        precondition(!standaloneShield.consume(.keyDown, in: parent))
        parent.contentView = NSView()
        precondition(standaloneShield.window == nil && !standaloneShield.consume(.leftMouseDown, in: parent))
        window.orderOut(nil)
        print("PASS: rapid A->B->A, pre-readiness cancellation/reopen, exact attachment geometry, and shield isolation")
    }
}
