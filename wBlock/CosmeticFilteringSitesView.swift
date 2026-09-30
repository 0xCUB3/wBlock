import SwiftUI
import wBlockCoreService

/// Where cosmetic rules apply (#899), using the same scope editor as a list.
struct CosmeticFilteringSitesView: View {
    @ObservedObject var filterManager: AppFilterManager
    @State private var sites = CosmeticFilteringPreference.sites()

    var body: some View {
        ScrollView {
            SiteScopeEditor(
                title: "Apply on", selectedSites: sites.selectedSites, excludedSites: sites.excludedSites,
                emptySelectionMessage: "No sites selected. Cosmetic filtering will not apply.",
                excludedMessage: "Cosmetic filtering will not apply on these sites. Network blocking still applies.",
                footer: "Sites include their subdomains. Apply changes to update filtering.",
                isSaving: filterManager.isLoading || filterManager.isApplyInFlight,
                updateSelected: { update(CosmeticFilteringPreference.Sites(selectedSites: $0, excludedSites: sites.excludedSites)) },
                updateExcluded: { update(CosmeticFilteringPreference.Sites(selectedSites: sites.selectedSites, excludedSites: $0)) }
            )
            .padding()
        }
        .navigationTitle("Cosmetic Filtering Sites")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func update(_ newSites: CosmeticFilteringPreference.Sites) {
        guard newSites != sites else { return }
        sites = newSites
        CosmeticFilteringPreference.setSites(newSites)
        filterManager.markNonSelectionChangesPending()
    }
}
