import SwiftUI
import wBlockCoreService

struct UserScriptCategoryInfoView: View {
    let category: UserScriptDisplayCategory
    let defaultScriptNames: [String]
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(LocalizedStringKey(category.rawValue))
                    .font(.title2.weight(.semibold))
                #if os(macOS)
                Spacer()
                SheetDoneButton { dismiss() }
                #endif
            }

            Text(LocalizedStringKey(category.descriptionKey))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Recommended Scripts")
                    .font(.headline)
                if defaultScriptNames.isEmpty {
                    Text("No default scripts")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(defaultScriptNames, id: \.self) { name in
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
        .infoSheetChromeCompat { dismiss() }
    }
}
