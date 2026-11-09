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
    // The picks are saved as made, so closing the sheet keeps them (#1100).
    @State private var selectedLanguages = Set(
        (Self.defaults.stringArray(forKey: OnboardingView.selectedLanguagesDefaultsKey) ?? []).map { $0.lowercased() }
    )
    private static var defaults: UserDefaults { UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard }
    /// Untouched, the picker shows the choices already on, or Cookie Notices
    /// when none is.
    @State private var pickedChoices: Set<AnnoyanceChoice>?
    @Environment(\.dismiss) private var dismiss

    private var annoyanceChoices: Binding<Set<AnnoyanceChoice>> {
        Binding(
            get: {
                let enabled = AnnoyanceChoice.choices(enabledIn: filterLists)
                return pickedChoices ?? (enabled.isEmpty ? AnnoyanceChoice.recommended : enabled)
            },
            set: { pickedChoices = $0 }
        )
    }

    private var languageOptions: [RegionalLanguageOption] {
        RegionalLanguageOption.fromForeignFilters(filterLists)
    }

    private var recommendedFilters: [FilterList] {
        if category == .annoyances {
            return AnnoyanceChoice.filters(for: annoyanceChoices.wrappedValue, in: filterLists)
        }
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
                .onChangeCompat(of: selectedLanguages) { languages in
                    Self.defaults.set(Array(languages).sorted(), forKey: OnboardingView.selectedLanguagesDefaultsKey)
                }
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

            if category == .annoyances {
                AnnoyanceChoicePicker(selection: annoyanceChoices)
            }

            Button("Enable Recommended") {
                onEnableRecommended(Set(recommendedFilters.map(\.id)))
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

/// One native toggle per choice, naming the lists it turns on.
struct AnnoyanceChoicePicker: View {
    @Binding var selection: Set<AnnoyanceChoice>

    var body: some View {
        SelectableRowGroup(data: AnnoyanceChoice.allCases) { choice in
            let isSelected = selection.contains(choice)
            SelectableRow(
                title: Text(LocalizedStringKey(choice.title)),
                caption: ListFormatter.localizedString(byJoining: choice.filterNames.map {
                    LocalizedStrings.text($0, comment: "Filter list name")
                }),
                subtitle: choice.subtitle,
                isSelected: isSelected
            ) {
                if isSelected { selection.remove(choice) } else { selection.insert(choice) }
            }
        }
    }
}
