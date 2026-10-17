import SwiftUI
import wBlockCoreService

struct UserScriptCategoryInfoView: View {
    let category: UserScriptDisplayCategory
    let defaultScriptNames: [String]
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        InfoSheetContainer {
            InfoSheetHeader {
                Text(LocalizedStringKey(category.rawValue))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } onDismiss: { dismiss() }
        } content: {

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
                    RecommendedNamesList(names: defaultScriptNames)
                }
            }

            Button("Reset to Default") {
                onReset()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        .frame(width: 420)
        #endif
    }
}
