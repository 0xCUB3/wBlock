import SwiftUI
import wBlockCoreService

/// Uses the same resolved fallback chain as foreground and background downloads.
struct FilterFallbacksButton: View {
    let filter: FilterList
    /// Presents from the window instead. A sheet on a macOS popover strands
    /// the window dimmed when a click outside closes the popover (#956).
    var onShow: (() -> Void)? = nil
    @State private var showingFallbacks = false

    var body: some View {
        Button {
            if let onShow { onShow() } else { showingFallbacks = true }
        } label: {
            Label("Fallbacks", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $showingFallbacks) {
            FilterFallbacksView(filter: filter, urls: FilterCatalogRemote.fallbacks(for: filter))
                .infoSheetPresentationCompat()
        }
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
            // with its Copy button under it (#955).
            VStack(alignment: .leading, spacing: 16) {
                Text(filter.localizedDisplayName)
                    .foregroundStyle(.secondary)
                InfoMetadataList {
                    VStack(alignment: .leading, spacing: 6) {
                        InfoMetadataRow(title: "Source URL", value: filter.url.absoluteString, url: filter.url)
                        CopyURLButton(url: filter.url)
                    }
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
            VStack(alignment: .leading, spacing: 6) {
                Link(destination: url) {
                    Text(verbatim: url.absoluteString)
                        .multilineTextAlignment(.leading)
                }
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                CopyURLButton(url: url)
            }
        }
        .font(.callout)
    }
}
