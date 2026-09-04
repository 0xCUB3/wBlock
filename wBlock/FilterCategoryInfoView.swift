import SwiftUI
import wBlockCoreService

struct FilterCategoryInfoView: View {
    let category: FilterListCategory
    let defaultFilterNames: [String]
    let filterLists: [FilterList]
    let onLanguagesChange: (Set<String>) -> Void
    let onReset: () -> Void

    @State private var selectedLanguages = Set(
        ((UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard)
            .stringArray(forKey: "onboardingSelectedLanguages") ?? []).map { $0.lowercased() }
    )
    @Environment(\.dismiss) private var dismiss

    private var languageOptions: [RegionalLanguageOption] {
        RegionalLanguageOption.fromForeignFilters(filterLists)
    }

    private var recommendedFilterNames: [String] {
        guard category == .foreign else { return defaultFilterNames }
        let matching = filterLists.filter {
            $0.category == .foreign
                && !Set($0.languages.map { $0.lowercased() }).isDisjoint(with: selectedLanguages)
        }
        return ForeignFilterOrganizer.recommendationBuckets(from: matching).recommended.map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(category.localizedName)
                    .font(.title2.weight(.semibold))
                #if os(macOS)
                Spacer()
                SheetDoneButton { dismiss() }
                #endif
            }

            Text(LocalizedStringKey(FilterCategorySupport.descriptionKey(for: category)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if category == .foreign {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Regional & Language", systemImage: "globe")
                        .font(.headline)
                    RegionalLanguagePickerView(
                        selectedLanguages: $selectedLanguages,
                        options: languageOptions
                    )
                    .onChangeCompat(of: selectedLanguages) { _, newValue in
                        onLanguagesChange(newValue)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recommended Filters")
                    .font(.headline)
                if recommendedFilterNames.isEmpty {
                    Text("No default filters")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recommendedFilterNames, id: \.self) { name in
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
