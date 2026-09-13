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
        VStack(alignment: .leading, spacing: 8) {
            Picker(title, selection: Binding(
                get: { selectedSites != nil }, set: { updateSelected($0 ? [] : nil) }
            )) {
                Text("All matching sites").tag(false)
                Text("Only selected sites").tag(true)
            }
            .pickerStyle(.menu)
            .disabled(isSaving)
            if let selectedSites {
                VStack(alignment: .leading, spacing: 4) {
                    SiteHostListEditor(title: "Selected Sites", hosts: selectedSites,
                                       update: { updateSelected($0) }, isSaving: isSaving)
                    if selectedSites.isEmpty { hint(emptySelectionMessage) }
                }
            }
            if selectedSites == nil || !excludedSites.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SiteHostListEditor(title: "Excluded Sites", hosts: excludedSites,
                                       update: updateExcluded, isSaving: isSaving)
                    hint(excludedMessage)
                }
            }
            hint(footer)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
