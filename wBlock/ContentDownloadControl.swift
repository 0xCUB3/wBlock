import SwiftUI

/// Shown only while a download is running or when the content is missing;
/// downloaded rows draw nothing here so the toggle sits flush.
struct ContentDownloadControl: View {
    let isDownloaded: Bool
    let isDownloading: Bool
    let name: String
    let action: () -> Void

    var body: some View {
        Group {
            if isDownloading {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Downloading…")
            } else if !isDownloaded {
                Button(action: action) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()
                .accessibilityLabel(LocalizedStrings.format("Download %@", comment: "Download content action", name))
                .help("Download")
            }
        }
        .font(.body)
        #if os(iOS)
        .frame(width: 32, height: 44)
        #else
        .frame(width: 24, height: 24)
        #endif
    }
}
