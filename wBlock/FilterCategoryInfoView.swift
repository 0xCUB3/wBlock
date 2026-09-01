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

    private var availableLanguages: [String] {
        Set(filterLists.filter { $0.category == .foreign }.flatMap(\.languages).map { $0.lowercased() })
            .sorted { languageName($0).localizedCaseInsensitiveCompare(languageName($1)) == .orderedAscending }
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
                Spacer()
                SheetDoneButton { dismiss() }
            }

            Text(LocalizedStringKey(FilterCategorySupport.descriptionKey(for: category)))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if category == .foreign {
                Menu {
                    ForEach(availableLanguages, id: \.self) { language in
                        Button {
                            if selectedLanguages.contains(language) {
                                selectedLanguages.remove(language)
                            } else {
                                selectedLanguages.insert(language)
                            }
                            onLanguagesChange(selectedLanguages)
                        } label: {
                            Label(languageName(language), systemImage: selectedLanguages.contains(language) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                } label: {
                    Label("Regional & Language", systemImage: "globe")
                }
                .buttonStyle(.bordered)
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
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }
}
