import SwiftUI

/// Stands in for the enable switch while content is missing or downloading.
/// A capsule Get button, the App Store idiom, replaces the switch until the
/// download lands; downloaded rows draw the switch instead of this view.
struct ContentDownloadControl: View {
    let isDownloaded: Bool
    let isDownloading: Bool
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text("Get")
                    .fontWeight(.semibold)
                    .opacity(isDownloading ? 0 : 1)
                if isDownloading {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(.bordered)
        .modifier(CapsuleBorderIfAvailable())
        .controlSize(.small)
        .disabled(isDownloading)
        .noFocusRingCompat()
        .accessibilityLabel(
            isDownloading
                ? LocalizedStrings.text("Downloading…")
                : LocalizedStrings.format("Download %@", comment: "Download content action", name)
        )
        .help("Download")
    }
}

/// The capsule border shape needs macOS 14; older macOS keeps the default.
private struct CapsuleBorderIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, iOS 15.0, *) {
            content.buttonBorderShape(.capsule)
        } else {
            content
        }
    }
}
