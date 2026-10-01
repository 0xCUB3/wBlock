import Foundation
import CoreGraphics

@main
struct InfoPopoverStateTests {
    static func main() {
        // One regional list shown under two language groups shares its ID.
        let upper = UUID(), lower = UUID(), other = UUID()
        let anchors: [InfoPopoverState.Anchor] = [
            .init(token: upper, id: "list", windowNumber: 1, frame: CGRect(x: 300, y: 400, width: 16, height: 16)),
            .init(token: lower, id: "list", windowNumber: 1, frame: CGRect(x: 300, y: 100, width: 16, height: 16)),
            .init(token: other, id: "other", windowNumber: 1, frame: CGRect(x: 300, y: 250, width: 16, height: 16)),
        ]
        var state = InfoPopoverState()
        // The click names its anchor; a selection that SwiftUI reports later,
        // with no mouse event current, still presents from that duplicate.
        state.clicked(lower, id: "list")
        precondition(state.anchor(for: "list", in: anchors) == lower, "the clicked duplicate must present")
        precondition(state.anchor(for: "list", in: anchors) == upper, "a click is consumed by one selection")
        // A menu or keyboard selection of another item drops the click.
        state.clicked(lower, id: "list")
        precondition(state.anchor(for: "other", in: anchors) == other)
        precondition(state.anchor(for: "list", in: anchors) == upper, "no stale click after another selection")
        state.clicked(lower, id: "list")
        precondition(state.anchor(for: "list", in: anchors, fromKeyboard: true) == upper)
        precondition(state.anchor(for: "list", in: anchors) == upper, "a keyboard selection drops the click")
        precondition(state.anchor(for: "missing", in: anchors) == nil)
        state.clicked(lower, id: "list")
        state.clear()
        precondition(state.anchor(for: "list", in: anchors) == upper, "clearing the selection drops the click")

        precondition(state.request(lower, mouseUp: 7) && state.presented == lower)
        // Clicking the open info button closes it; that click's mouse-up must not reopen it.
        precondition(state.dismiss(lower, mouseDown: 8) && state.presented == nil)
        precondition(!state.request(lower, mouseUp: 8) && state.presented == nil)
        // The very next click opens it again.
        precondition(state.request(lower, mouseUp: 9) && state.presented == lower)

        // Closing by clicking a different info button opens that one in the same click.
        precondition(state.dismiss(lower, mouseDown: 10))
        precondition(state.request(upper, mouseUp: 10) && state.presented == upper)
        // A late dismissal from the previous anchor leaves the current one open.
        precondition(!state.dismiss(lower, mouseDown: 11) && state.presented == upper)

        // A close by a non-mouse path (Escape, Done) never suppresses the next click.
        precondition(state.dismiss(upper, mouseDown: nil))
        precondition(state.request(upper, mouseUp: 12) && state.presented == upper)
        print("PASS: info popovers present from the clicked duplicate and reopen on the first click")
    }
}
