import SwiftUI
import wBlockCoreService

struct StringListEditor: View {
    let title: LocalizedStringKey?
    let items: [String]
    let update: ([String]) -> Void
    var isSaving = false
    var placeholder: LocalizedStringKey = "example.com"
    var normalize: (String) -> String? = DisabledSitesNormalizer.normalizedDomain
    @State private var input = ""

    private var candidate: String? {
        guard let item = normalize(input), !items.contains(item) else { return nil }
        return item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title { Text(title).font(.callout.weight(.medium)) }
            HStack(spacing: 12) {
                // onSubmit rather than onCommit: on macOS the onCommit closure kept
                // the list from the first render, so a second Return replaced the
                // first site instead of adding to it (#948).
                TextField(placeholder, text: $input)
                    .onSubmit(addItem)
                    .listEntryField()
                AddItemButton(canAdd: candidate != nil && !isSaving, action: addItem)
            }
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(verbatim: item).font(.callout).textSelection(.enabled)
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
        }
    }

    private func addItem() {
        guard !isSaving, let candidate else { return }
        input = ""
        update((items + [candidate]).sorted())
    }
}

extension View {
    /// The site field Site Settings opens with, shared by every site list (#1028).
    func listEntryField() -> some View {
        textFieldStyle(.plain)
            .disableAutocorrection(true)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
