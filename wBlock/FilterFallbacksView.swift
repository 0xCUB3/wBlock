import SwiftUI
import wBlockCoreService

/// Opens the list's fallbacks. The owner presents them: macOS from the
/// window, since a sheet on a popover strands the window dimmed when a click
/// outside closes the popover (#956), and iOS from the info sheet's root.
struct FilterFallbacksButton: View {
    let onShow: () -> Void

    var body: some View {
        Button(action: onShow) {
            Label("Fallbacks", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct FilterFallbacksView: View {
    let filter: FilterList
    let urls: [URL]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        InfoSheetContainer {
            InfoSheetHeader {
                Text("Fallbacks")
                    .font(.title2.weight(.semibold))
            } onDismiss: { dismiss() }
        } content: {
            // Same cards as the info view: every URL sits at one leading edge
            // with its copy button after it (#955).
            VStack(alignment: .leading, spacing: 16) {
                Text(filter.localizedDisplayName)
                    .foregroundStyle(.secondary)
                InfoMetadataList {
                    InfoMetadataRow(title: "Source URL", value: filter.url.absoluteString, url: filter.url, copiesURL: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(urls.isEmpty
                         ? "No fallback URLs are configured for this list."
                         : "If the source URL fails, wBlock tries these URLs in order.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !urls.isEmpty {
                        InfoMetadataList {
                            ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                                fallbackRow(number: index + 1, url: url)
                            }
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 460)
        #endif
    }

    private func fallbackRow(number: Int, url: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(number)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Link(destination: url) {
                Text(verbatim: url.absoluteString)
                    .multilineTextAlignment(.leading)
            }
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            CopyURLButton(url: url)
        }
        .font(.callout)
    }
}
