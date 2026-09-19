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

    /// `.fill.tertiary` is the native capsule fill but needs macOS 14 / iOS 17.
    /// Earlier systems get the matching semantic fill color.
    private var capsuleFill: AnyShapeStyle {
        if #available(macOS 14.0, iOS 17.0, *) {
            return AnyShapeStyle(.fill.tertiary)
        }
        #if os(iOS)
        return AnyShapeStyle(Color(uiColor: .tertiarySystemFill))
        #else
        return AnyShapeStyle(Color(nsColor: .quaternaryLabelColor))
        #endif
    }

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
                                .tint(.primary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Capsule().fill(capsuleFill))
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
