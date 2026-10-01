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
            HStack {
                TextField(placeholder, text: $input, onCommit: addItem)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                Button(action: addItem) {
                    Image(systemName: "plus.circle.fill").font(.title2)
                        #if os(macOS)
                        .frame(minWidth: 28, minHeight: 28)
                        #else
                        .frame(minWidth: 44, minHeight: 44)
                        #endif
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add")
                .disabled(candidate == nil || isSaving)
            }
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(verbatim: item).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { update(items.filter { $0 != item }) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(.secondary)
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
