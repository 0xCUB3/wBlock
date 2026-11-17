import Foundation
import CoreGraphics

@main
struct InfoPopoverStateTests {
    static func main() {
        // Two rows of one regional list share an ID. Frames order them: the upper row is the topmost.
        let upper = UUID(), lower = UUID()
        let anchors: [InfoPopoverState.Anchor] = [
            .init(token: upper, id: "list", windowNumber: 1, frame: CGRect(x: 300, y: 400, width: 16, height: 16)),
            .init(token: lower, id: "list", windowNumber: 1, frame: CGRect(x: 300, y: 100, width: 16, height: 16)),
        ]
        var state = InfoPopoverState()
        precondition(state.anchor(for: "list", in: anchors) == upper, "without a click the topmost duplicate by frame must present")
        // A click presents from its own duplicate even when another duplicate sits higher.
        state.clicked(lower, id: "list")
        precondition(state.anchor(for: "list", in: anchors) == lower, "the clicked duplicate must present")
        state.clicked(lower, id: "list")
        precondition(state.anchor(for: "list", in: anchors, fromKeyboard: true) == upper, "a keyboard selection must show the topmost duplicate")
        print("PASS: info popovers present from the clicked duplicate, otherwise from the topmost frame")
    }
}
