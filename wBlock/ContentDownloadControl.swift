import SwiftUI

/// Stands in for the enable switch while content is missing or downloading.
/// A filled accent capsule replaces the switch until the download lands, at
/// the switch's own height so the trailing column keeps one rhythm; downloaded
/// rows draw the switch instead of this view.
struct ContentDownloadControl: View {
    let isDownloaded: Bool
    let isDownloading: Bool
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Fixed to the switch frame, so the label scales instead of
                // growing the capsule under larger Dynamic Type.
                Text("Get")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
                    .opacity(isDownloading ? 0 : 1)
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .frame(width: Self.switchWidth, height: Self.switchHeight)
            .foregroundStyle(.white)
            .background(Capsule().fill(Color.accentColor))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
        .noFocusRingCompat()
        .accessibilityLabel(
            isDownloading
                ? LocalizedStrings.text("Downloading…")
                : LocalizedStrings.format("Download %@", comment: "Download content action", name)
        )
        .help("Download")
    }

    // Native switch metrics, so Get sits where the switch will and at its size.
    #if os(macOS)
    private static let switchWidth: CGFloat = 54
    private static let switchHeight: CGFloat = 22
    #else
    private static let switchWidth: CGFloat = 51
    private static let switchHeight: CGFloat = 31
    #endif
}
