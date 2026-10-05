import SwiftUI
import wBlockCoreService

/// The cosmetic filtering switch (#610) and, while it is on, where cosmetic
/// rules apply (#899), using the same scope editor as a list.
struct CosmeticFilteringSitesView: View {
    @ObservedObject var filterManager: AppFilterManager
    @State private var isEnabled = CosmeticFilteringPreference.isEnabled()
    @State private var sites = CosmeticFilteringPreference.sites()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Toggle(isOn: Binding(get: { isEnabled }, set: setEnabled)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cosmetic Filtering")
                        Text("Hides ad placeholders and other page elements with CSS. Turning this off leaves only network blocking, which uses fewer rules and less CPU.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                #if os(macOS)
                .toggleStyle(MacTrailingSwitchToggleStyle())
                #endif
                // Not locked during an apply (#936): the run snapshots this setting
                // and a change made meanwhile stays pending for the next one.
                // The scope only matters while the switch is on, so it is
                // hidden rather than left editable with no effect.
                if isEnabled {
                    SiteScopeEditor(
                        title: "Apply on", selectedSites: sites.selectedSites, excludedSites: sites.excludedSites,
                        emptySelectionMessage: "No sites selected. Cosmetic filtering will not apply.",
                        excludedMessage: "Cosmetic filtering will not apply on these sites. Network blocking still applies.",
                        footer: "Sites include their subdomains. Apply changes to update filtering.",
                        updateSelected: { update(CosmeticFilteringPreference.Sites(selectedSites: $0, excludedSites: sites.excludedSites)) },
                        updateExcluded: { update(CosmeticFilteringPreference.Sites(selectedSites: sites.selectedSites, excludedSites: $0)) }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Cosmetic Filtering")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        CosmeticFilteringPreference.setEnabled(enabled)
        filterManager.markNonSelectionChangesPending()
    }

    private func update(_ newSites: CosmeticFilteringPreference.Sites) {
        guard newSites != sites else { return }
        sites = newSites
        CosmeticFilteringPreference.setSites(newSites)
        filterManager.markNonSelectionChangesPending()
    }
}
