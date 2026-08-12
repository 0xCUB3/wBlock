import SwiftUI

struct FilterCategoryInfoView: View {
    let category: FilterListCategory
    let defaultFilterNames: [String]
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(category.localizedName)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderless)
            }

            Text(LocalizedStringKey(FilterCategorySupport.descriptionKey(for: category)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Recommended Filters")
                    .font(.headline)
                if defaultFilterNames.isEmpty {
                    Text("No default filters")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(defaultFilterNames, id: \.self) { name in
                        Label(LocalizedStringKey(name), systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button("Reset to Default") {
                onReset()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 420, minHeight: 260)
    }
}
