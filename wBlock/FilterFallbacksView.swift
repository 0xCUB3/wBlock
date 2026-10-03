import SwiftUI
import wBlockCoreService

/// Uses the same resolved fallback chain as foreground and background downloads.
struct FilterFallbacksButton: View {
    let filter: FilterList
    @State private var showingFallbacks = false

    var body: some View {
        Button {
            showingFallbacks = true
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

private struct FilterFallbacksView: View {
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
            VStack(alignment: .leading, spacing: 16) {
                Text(filter.localizedDisplayName)
                    .font(.headline)
                InfoMetadataRow(title: "Source URL", value: filter.url.absoluteString, url: filter.url)
                Text("If the source URL fails, wBlock tries these URLs in order.")
                    .foregroundStyle(.secondary)
                if urls.isEmpty {
                    Text("No fallback URLs are configured for this list.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(urls.enumerated()), id: \.element) { index, url in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(index + 1).")
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
                }
            }
        }
        #if os(macOS)
        .frame(width: 460)
        #endif
    }
}
