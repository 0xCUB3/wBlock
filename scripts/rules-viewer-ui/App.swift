import SwiftUI
@main struct ScrollProbe: App {
    var body: some Scene { WindowGroup { Fixture() } }
}
struct Fixture: View {
    @State var wraps = false
    @State var status = "waiting"
    @State var text = (0..<300).map { "||BEGIN_\($0).example/" + String(repeating: "visible-colored-text-", count: 30) + "END_\($0)^" }.joined(separator: "\n")
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack {
            Toggle("Wrap", isOn: $wraps)
            Text(status).font(.caption).accessibilityIdentifier("geometry")
            MonospacedTextView(text: $text, lineTints: Dictionary(uniqueKeysWithValues: (0..<300).map { ($0, $0 % 2 == 0 ? UIColor.systemTeal : UIColor.systemOrange) }), isLineWrappingEnabled: wraps)
        }
        .padding(.top, 20)
        .onReceive(timer) { _ in
            func find(_ v: UIView) -> UITextView? {
                if let t = v as? UITextView { return t }
                for child in v.subviews { if let t = find(child) { return t } }
                return nil
            }
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first, let v = find(root) {
                let horizontal = v.superview as? UIScrollView ?? v
                status = "x=\(Int(horizontal.contentOffset.x)) y=\(Int(v.contentOffset.y)) width=\(Int(horizontal.contentSize.width))"
            }
        }
    }
}
