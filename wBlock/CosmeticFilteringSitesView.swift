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
            VStack(alignment: .leading, spacing: 14) {
                // Not locked during an apply (#936): the run snapshots this setting
                // and a change made meanwhile stays pending for the next one.
                // Generic Rules shares the box since it only narrows cosmetic
                // filtering (#999); it and the scope are hidden while it's off.
                SettingsGroup {
                    Toggle(isOn: Binding(get: { isEnabled }, set: setEnabled)) {
                        toggleLabel("Cosmetic Filtering", detail: "Hides ad placeholders and other page elements with CSS. Turning this off leaves only network blocking, which uses fewer rules and less CPU.")
                    }
                    .settingsSwitch()
                    if isEnabled {
                        Divider()
                        Toggle(isOn: Binding(
                            get: { sites.includesGeneric },
                            set: { update(sites.selectedSites, sites.excludedSites, includesGeneric: $0) }
                        )) {
                            toggleLabel("Generic Rules", detail: "Hides elements on every site with rules that don't name one. Turning this off keeps site-specific hiding and makes pages lighter, especially busy web apps.")
                        }
                        .settingsSwitch()
                    }
                }
                if isEnabled {
                    SiteScopeEditor(
                        title: "Apply on", selectedSites: sites.selectedSites, excludedSites: sites.excludedSites,
                        emptySelectionMessage: "No sites selected. Cosmetic filtering will not apply.",
                        excludedMessage: "Cosmetic filtering will not apply on these sites. Network blocking still applies.",
                        footer: "Sites include their subdomains. Apply changes to update filtering.",
                        updateSelected: { update($0, sites.excludedSites) },
                        updateExcluded: { update(sites.selectedSites, $0) }
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

    private func toggleLabel(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        CosmeticFilteringPreference.setEnabled(enabled)
        filterManager.markNonSelectionChangesPending()
    }

    private func update(_ selected: [String]?, _ excluded: [String], includesGeneric: Bool? = nil) {
        let newSites = CosmeticFilteringPreference.Sites(
            selectedSites: selected, excludedSites: excluded,
            includesGeneric: includesGeneric ?? sites.includesGeneric
        )
        guard newSites != sites else { return }
        sites = newSites
        CosmeticFilteringPreference.setSites(newSites)
        filterManager.markNonSelectionChangesPending()
    }
}
