import SwiftUI

/// Stands in for the enable switch while content is missing or downloading.
/// A hidden native switch is the layout base and the Get capsule is drawn
/// over it, so the control takes the switch's exact frame on every OS version
/// and platform. Downloaded rows draw the real switch instead of this view.
struct ContentDownloadControl: View {
    let isDownloaded: Bool
    let isDownloading: Bool
    let name: String
    let action: () -> Void

    var body: some View {
        Toggle("", isOn: .constant(false))
            .labelsHidden()
            .toggleStyle(.switch)
            .hidden()
            .accessibilityHidden(true)
            .fixedSize()
            .overlay {
                Button(action: action) {
                    ZStack {
                        // The frame is fixed to the switch, so the label scales
                        // instead of growing the capsule under larger Dynamic Type.
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
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
}
