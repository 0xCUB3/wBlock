import SwiftUI

private struct SheetHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct FittedSheet: View {
    @Binding var presented: Bool
    @State private var height: CGFloat = 600
    @State private var finished = false
    @State private var logs = false

    var body: some View {
        VStack {
            Text(finished ? "Result" : "Progress")
            Color.clear.frame(height: finished ? 120 : 420)
        }
        .padding(20)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: SheetHeight.self, value: ceil(geometry.size.height))
        })
        .applySheetPresentationCompat(
            prefersLarge: false, contentHeight: height, fitsHorizontally: finished
        )
        .onPreferenceChange(SheetHeight.self) { height = $0 }
        .sheet(isPresented: $logs) { Text("Logs") }
        .task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            finished = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            logs = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            logs = false
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            presented = false
        }
    }
}

@main private struct ApplySheetProbe: App {
    @State private var presented = false
    var body: some Scene {
        WindowGroup {
            Text("Sheet presentation probe")
                .sheet(isPresented: $presented) { FittedSheet(presented: $presented) }
                .onChange(of: presented) { _, showing in
                    if !showing {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            print("PASS: fitted sheet, result resizing, nested Logs, dismissal")
                            fflush(stdout)
                            exit(0)
                        }
                    }
                }
                .task {
                    // Runs off the main thread so a layout loop cannot defeat the deadline.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 12) {
                        print("FAIL: sheet presentation stalled")
                        fflush(stdout)
                        exit(2)
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    presented = true
                }
        }
    }
}
