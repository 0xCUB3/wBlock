import SwiftUI
import wBlockCoreService

struct FilterCategoryInfoView: View {
    let category: FilterListCategory
    let filterLists: [FilterList]
    /// Enable Recommended: exactly these lists stay on in the category, and the
    /// rest, custom ones included, go off.
    let onEnableRecommended: (Set<UUID>) -> Void

    // Picking languages only previews their lists; Enable Recommended applies
    // them, so a tap in the picker can't switch lists on behind the sheet (#1087).
    @State private var selectedLanguages = Set(
        ((UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard)
            .stringArray(forKey: OnboardingView.selectedLanguagesDefaultsKey) ?? []).map { $0.lowercased() }
    )
    @Environment(\.dismiss) private var dismiss

    private var languageOptions: [RegionalLanguageOption] {
        RegionalLanguageOption.fromForeignFilters(filterLists)
    }

    private var recommendedFilters: [FilterList] {
        let matching = filterLists.filter {
            $0.category == .foreign
                && !Set($0.languages.map { $0.lowercased() }).isDisjoint(with: selectedLanguages)
        }
        return ForeignFilterOrganizer.recommendationBuckets(from: matching).recommended
    }

    var body: some View {
        InfoSheetContainer {
            InfoSheetHeader {
                Text(category.localizedName)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } onDismiss: { dismiss() }
        } content: {

            Text(LocalizedStringKey(FilterCategorySupport.descriptionKey(for: category) ?? ""))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if category == .foreign {
                RegionalLanguagePickerView(
                    selectedLanguages: $selectedLanguages,
                    options: languageOptions
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lists for Your Languages")
                        .font(.headline)
                    if recommendedFilters.isEmpty {
                        Text("Choose a language to see its lists.")
                            .foregroundStyle(.secondary)
                    } else {
                        RecommendedNamesList(names: recommendedFilters.map(\.name))
                    }
                }
            }

            Button("Enable Recommended") {
                enableRecommended()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        .frame(width: 420)
        #endif
    }

    private func enableRecommended() {
        (UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard)
            .set(Array(selectedLanguages).sorted(), forKey: OnboardingView.selectedLanguagesDefaultsKey)
        onEnableRecommended(Set(recommendedFilters.map(\.id)))
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
