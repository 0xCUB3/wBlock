import SwiftUI

struct SiteScopeEditor: View {
    let title: LocalizedStringKey
    let selectedSites: [String]?
    let excludedSites: [String]
    let emptySelectionMessage: LocalizedStringKey
    let excludedMessage: LocalizedStringKey
    let footer: LocalizedStringKey
    var isSaving = false
    let updateSelected: ([String]?) -> Void
    let updateExcluded: ([String]) -> Void

    var body: some View {
        // The footer joins the last group's notes so it doesn't float a full
        // group gap below them (#948).
        let showsExcluded = selectedSites == nil || !excludedSites.isEmpty
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup {
                // A menu picker outside a Form drops its label on iOS, so the
                // label is drawn as text and the picker's own label hidden.
                HStack {
                    Text(title)
                    Spacer(minLength: 12)
                    Picker(title, selection: Binding(
                        get: { selectedSites != nil }, set: { updateSelected($0 ? [] : nil) }
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
            if let selectedSites {
                SettingsGroup(header: "Selected Sites",
                              footer: (selectedSites.isEmpty ? [emptySelectionMessage] : []) + (showsExcluded ? [] : [footer])) {
                    StringListEditor(title: nil, items: selectedSites,
                                     update: { updateSelected($0) }, isSaving: isSaving)
                }
            }
            if showsExcluded {
                SettingsGroup(header: "Excluded Sites", footer: [excludedMessage, footer]) {
                    StringListEditor(title: nil, items: excludedSites,
                                     update: updateExcluded, isSaving: isSaving)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
