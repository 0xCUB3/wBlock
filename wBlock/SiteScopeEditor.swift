import SwiftUI
import wBlockCoreService

struct SiteScopeEditor: View {
    let title: LocalizedStringKey
    let onlySelectedSites: Bool
    let selectedSites: [String]
    /// Nil hides the excluded sites while they don't apply.
    let excludedSites: [String]?
    let emptySelectionMessage: LocalizedStringKey
    let excludedMessage: LocalizedStringKey
    let footer: LocalizedStringKey
    var isSaving = false
    let updateMode: (Bool) -> Void
    let updateSelected: ([String]) -> Void
    let updateExcluded: ([String]) -> Void

    var body: some View {
        // The footer joins the last group's notes so it doesn't float a full
        // group gap below them (#948).
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup {
                // A menu picker outside a Form drops its label on iOS, so the
                // label is drawn as text and the picker's own label hidden.
                HStack {
                    Text(title)
                    Spacer(minLength: 12)
                    Picker(title, selection: Binding(
                        get: { onlySelectedSites }, set: updateMode
                    )) {
                        Text("All matching sites").tag(false)
                        Text("Only selected sites").tag(true)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(isSaving)
            }
            if onlySelectedSites {
                SettingsGroup(header: "Selected Sites", isBoxed: false,
                              footer: (selectedSites.isEmpty ? [emptySelectionMessage] : []) + (excludedSites == nil ? [footer] : [])) {
                    StringListEditor(title: nil, items: selectedSites,
                                     update: updateSelected, isSaving: isSaving,
                                     normalize: FilterListSiteExclusion.normalizedDomain)
                }
            }
            if let excludedSites {
                SettingsGroup(header: "Excluded Sites", isBoxed: false, footer: [excludedMessage, footer]) {
                    StringListEditor(title: nil, items: excludedSites,
                                     update: updateExcluded, isSaving: isSaving,
                                     normalize: FilterListSiteExclusion.normalizedDomain)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
