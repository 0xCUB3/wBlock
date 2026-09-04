import SwiftUI
import wBlockCoreService
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct FilterInfoView: View {
    let filter: FilterList
    @ObservedObject var filterManager: AppFilterManager

    @Environment(\.dismiss) private var dismiss
    @State private var newSite = ""
    @FocusState private var isSiteFieldFocused: Bool

    private var liveFilter: FilterList {
        filterManager.filterLists.first(where: { $0.id == filter.id }) ?? filter
    }

    private var addableSite: String? {
        guard let normalized = DisabledSitesNormalizer.normalizedDomain(newSite) else { return nil }
        return liveFilter.excludedSites.contains(normalized) ? nil : normalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(liveFilter.localizedDisplayName)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Spacer()
                SheetDoneButton { dismiss() }
            }

            HStack(spacing: 8) {
                ForEach(Array(InfoBadgeSupport.filterBadges(liveFilter).enumerated()), id: \.offset) { _, badge in
                    InfoBadgeView(kind: badge)
                }
            }

            Text(liveFilter.category.localizedName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if !liveFilter.localizedDisplayDescription.isEmpty {
                Text(liveFilter.localizedDisplayDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if liveFilter.url.scheme?.lowercased() == "http" || liveFilter.url.scheme?.lowercased() == "https" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source URL")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(liveFilter.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = liveFilter.url.absoluteString
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(liveFilter.url.absoluteString, forType: .string)
                        #endif
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }
                }
            }

            excludedSitesSection

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 460, minHeight: 320)
    }

    private var excludedSitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStrings.text("Excluded Sites", comment: "Per-list site exclusion heading"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(LocalizedStrings.text(
                "This list will not apply on these sites. Other lists still apply.",
                comment: "Per-list site exclusion explanation"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                TextField("example.com", text: $newSite)
                    .textFieldStyle(.plain)
                    .focused($isSiteFieldFocused)
                    .onSubmit { addExcludedSite() }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    addExcludedSite()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(addableSite == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(addableSite == nil)
            }

            ForEach(liveFilter.excludedSites, id: \.self) { site in
                HStack {
                    Text(site)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        removeExcludedSite(site)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LocalizedStrings.text("Remove", comment: "Remove excluded site"))
                }
            }
        }
    }

    private func addExcludedSite() {
        guard let site = addableSite else { return }
        filterManager.setExcludedSites(liveFilter.excludedSites + [site], for: liveFilter.id)
        newSite = ""
        isSiteFieldFocused = true
    }

    private func removeExcludedSite(_ site: String) {
        filterManager.setExcludedSites(liveFilter.excludedSites.filter { $0 != site }, for: liveFilter.id)
    }
}

struct FilterRulesView: View {
    let filter: FilterList
    @State private var rules = ""
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(filter.localizedDisplayName)
                    .font(.headline)
                Spacer()
                SheetDoneButton { dismiss() }
            }
            .padding(16)
            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rules.isEmpty {
                Text("No Content Available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MonospacedTextView(
                    text: Binding(get: { rules }, set: { _ in }),
                    softTopEdge: true
                )
            }
        }
        .frame(minWidth: 420, idealWidth: 760, minHeight: 360, idealHeight: 620)
        .task {
            rules = FilterListLoader().readLocalFilterContent(filter) ?? ""
            isLoading = false
        }
    }
}
