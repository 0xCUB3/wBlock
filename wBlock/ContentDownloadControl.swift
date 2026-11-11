import SwiftUI

/// The enable switch for a list or script that isn't downloaded yet.
/// Turning it on downloads the content and enables it; the switch stays on
/// with a spinner beside it until the download finishes. Downloaded rows
/// draw their own switch instead of this view.
struct ContentDownloadControl: View {
    let isDownloading: Bool
    let name: String
    let action: () -> Void

    var body: some View {
        Toggle("", isOn: Binding(get: { isDownloading }, set: { if $0 { action() } }))
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
            .disabled(isDownloading)
            // The spinner takes the switch's place, which keeps its size so the
            // row doesn't shift. Beside it, the iOS 26 glass thumb slid over
            // the spinner as the switch animated (#1111).
            .opacity(isDownloading ? 0 : 1)
            .overlay {
                if isDownloading { ProgressView().controlSize(.small) }
            }
            .accessibilityLabel(
                isDownloading
                    ? LocalizedStrings.text("Downloading…")
                    : LocalizedStrings.format("Download %@", comment: "Download content action", name)
            )
    }
}
