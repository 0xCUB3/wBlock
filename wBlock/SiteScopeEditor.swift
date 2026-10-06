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
                SettingsGroup(header: "Selected Sites", footer: selectedSites.isEmpty ? [emptySelectionMessage] : []) {
                    StringListEditor(title: nil, items: selectedSites,
                                     update: { updateSelected($0) }, isSaving: isSaving)
                }
            }
            if selectedSites == nil || !excludedSites.isEmpty {
                SettingsGroup(header: "Excluded Sites", footer: [excludedMessage]) {
                    StringListEditor(title: nil, items: excludedSites,
                                     update: updateExcluded, isSaving: isSaving)
                }
            }
            Text(footer).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
