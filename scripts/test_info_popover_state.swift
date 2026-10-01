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
        precondition(InfoPopoverState.anchor(for: "list", in: anchors, click: (1, CGPoint(x: 305, y: 105))) == lower,
                     "the clicked duplicate must present")
        precondition(InfoPopoverState.anchor(for: "list", in: anchors, click: (1, CGPoint(x: 305, y: 405))) == upper)
        precondition(InfoPopoverState.anchor(for: "list", in: anchors, click: (2, CGPoint(x: 305, y: 105))) == upper,
                     "a menu click falls back to the topmost anchor")
        precondition(InfoPopoverState.anchor(for: "list", in: anchors, click: nil) == upper)
        precondition(InfoPopoverState.anchor(for: "missing", in: anchors, click: nil) == nil)

        var state = InfoPopoverState()
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
