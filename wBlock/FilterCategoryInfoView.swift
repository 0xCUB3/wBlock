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
        InfoSheetContainer {
            InfoSheetHeader {
                Text(category.localizedName)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } onDismiss: { dismiss() }
        } content: {

            Text(LocalizedStringKey(FilterCategorySupport.descriptionKey(for: category)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if category == .foreign {
                RegionalLanguagePickerView(
                    selectedLanguages: $selectedLanguages,
                    options: languageOptions
                )
                .onChangeCompat(of: selectedLanguages) { _, newValue in
                    onLanguagesChange(newValue)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(category == .foreign ? "Lists for Your Languages" : "Recommended Filters")
                    .font(.headline)
                if recommendedFilterNames.isEmpty {
                    Text(category == .foreign ? "Choose a language to see its lists." : "No default filters")
                        .foregroundStyle(.secondary)
                } else {
                    RecommendedNamesList(names: recommendedFilterNames)
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

/// Plain bullets: a checkmark beside each name read as "enabled", which these
/// recommendations may not be (#999).
struct RecommendedNamesList: View {
    let names: [String]

    var body: some View {
        ForEach(names, id: \.self) { name in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•")
                Text(LocalizedStringKey(name))
            }
            .foregroundStyle(.secondary)
        }
    }
}
