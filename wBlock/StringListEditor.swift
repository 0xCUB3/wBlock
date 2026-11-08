import SwiftUI
import wBlockCoreService

struct StringListEditor: View {
    let title: LocalizedStringKey?
    let items: [String]
    let update: ([String]) -> Void
    var isSaving = false
    var placeholder: LocalizedStringKey = "example.com"
    var normalize: (String) -> String? = DisabledSitesNormalizer.normalizedDomain
    /// Narrows the rows shown; adding and removing still edit every item.
    var query = ""
    @State private var input = ""
    @Environment(\.isInSettingsForm) private var isInSettingsForm

    private var candidate: String? {
        guard let item = normalize(input), !items.contains(item) else { return nil }
        return item
    }

    var body: some View {
        if isInSettingsForm {
            // Form rows: the field, then one row per site.
            entryRow(TextField(placeholder, text: $input, prompt: Text(placeholder)).siteEntryField())
            rows
        } else {
            // The field and its sites share one box, as the form section on
            // the Cosmetic Filtering page does, rows split like the form's
            // (#1096).
            VStack(alignment: .leading, spacing: 8) {
                if let title { Text(title).font(.callout.weight(.medium)) }
                VStack(alignment: .leading, spacing: 8) {
                    entryRow(TextField(placeholder, text: $input, prompt: Text(placeholder)).siteEntryField())
                    ForEach(shownItems, id: \.self) { item in
                        Divider()
                        row(item)
                    }
                }
                .settingsGroup()
            }
        }
    }

    private func entryRow(_ field: some View) -> some View {
        HStack(spacing: 12) {
            // onSubmit rather than onCommit: on macOS the onCommit closure kept
            // the list from the first render, so a second Return replaced the
            // first site instead of adding to it (#948).
            field.onSubmit(addItem)
            AddItemButton(canAdd: candidate != nil && !isSaving, action: addItem)
        }
    }

    private var shownItems: [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? items : items.filter { $0.localizedCaseInsensitiveContains(needle) }
    }

    private var rows: some View {
        ForEach(shownItems, id: \.self, content: row)
    }

    /// A site drawn like a Site Settings row: body text on one line.
    private func row(_ item: String) -> some View {
        HStack {
            Text(verbatim: item)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Button { update(items.filter { $0 != item }) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    #if os(macOS)
                    .frame(minWidth: 28, minHeight: 32)
                    #else
                    .frame(minWidth: 44, minHeight: 44)
                    #endif
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
            .accessibilityValue(item)
            .disabled(isSaving)
        }
    }

    private func addItem() {
        guard !isSaving, let candidate else { return }
        input = ""
        update((items + [candidate]).sorted())
    }
}

extension View {
    /// The one site field, boxed with its placeholder inside, with the round +
    /// to its right, in Site Settings, Cosmetic Filtering, and every list's
    /// site settings alike (#1028, #1088). No autocorrection, and the URL
    /// keyboard on iOS.
    func siteEntryField() -> some View {
        textFieldStyle(.plain)
            .disableAutocorrection(true)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
            // A Form draws a field's title as a label at the leading edge,
            // so the title only serves as the placeholder.
            .labelsHidden()
            .padding(12)
            // A fill relative to what is behind it: a material vanished in a
            // sheet's group, whose background is material too (#1096).
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The round + beside a site field. It turns secondary while there is nothing
/// to add, so an empty field reads as disabled on every sheet (#999).
struct AddItemButton: View {
    let canAdd: Bool
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isBusy ? "hourglass" : "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(canAdd ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                #if os(macOS)
                .frame(minWidth: 28, minHeight: 28)
                #else
                .frame(minWidth: 44, minHeight: 44)
                #endif
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .accessibilityLabel("Add")
        .help("Add")
        .disabled(!canAdd || isBusy)
    }
}
