import SwiftUI
import wBlockCoreService

/// One language the regional picker can offer. Shared by onboarding and the
/// Regional category Info sheet so both pick languages the same way (#687).
struct RegionalLanguageOption: Identifiable, Hashable {
    private static let aliasesByCode: [String: [String]] = [
        "de": ["Deutsch", "German"],
        "es": ["español", "Spanish", "espanol"],
        "fr": ["français", "French", "francais"],
        "ja": ["日本語", "Japanese"],
        "zh": ["中文", "Chinese", "zh"],
        "pt": ["português", "Portuguese", "portugues"],
        "ru": ["русский", "Russian"],
        "ar": ["العربية", "Arabic"]
    ]

    let code: String
    /// The name in the app's display language, used for sorting and search.
    let name: String
    let flag: String

    var id: String { code }

    /// The language's own name, which is what the rows show.
    var nativeName: String {
        Locale(identifier: code).localizedString(forLanguageCode: code) ?? name
    }

    var aliases: [String] { Self.aliasesByCode[code] ?? [] }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        return ([nativeName, name, code] + aliases).contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    /// The locale the app is actually displayed in, so names sort the way the
    /// user reads them rather than by the system locale.
    static var displayLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
    }

    /// Every language that at least one regional filter list covers.
    static func fromForeignFilters(
        _ filters: [FilterList],
        locale: Locale = displayLocale
    ) -> [RegionalLanguageOption] {
        var seen = Set<String>()
        var result: [RegionalLanguageOption] = []
        for filter in filters where filter.category == .foreign {
            for language in filter.languages {
                let code = language.lowercased()
                guard seen.insert(code).inserted else { continue }
                result.append(
                    RegionalLanguageOption(
                        code: code,
                        name: locale.localizedString(forLanguageCode: code) ?? code,
                        flag: FilterList.languageToFlag[code] ?? ""
                    )
                )
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Selected languages as removable rows above a search field that lists the
/// matching languages left to add. Same control in onboarding and Regional
/// Info (#687).
struct RegionalLanguagePickerView: View {
    @Binding var selectedLanguages: Set<String>
    let options: [RegionalLanguageOption]

    @State private var searchQuery = ""

    private var selectedOptions: [RegionalLanguageOption] {
        options.filter { selectedLanguages.contains($0.code) }
    }

    private var matchingOptions: [RegionalLanguageOption] {
        options.filter { !selectedLanguages.contains($0.code) && $0.matches(searchQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(selectedOptions.enumerated()), id: \.element.id) { index, language in
                HStack(spacing: 10) {
                    languageLeading(language)
                    Text(language.nativeName)
                    Spacer()
                    Button {
                        selectedLanguages.remove(language.code)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .noFocusRingCompat()
                    .accessibilityLabel(Text("Remove") + Text(" " + language.nativeName))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                if index < selectedOptions.count - 1 {
                    Divider().padding(.leading, 42)
                }
            }

            if !selectedOptions.isEmpty {
                Divider().padding(.leading, 42)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                TextField("Search languages", text: $searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            ForEach(matchingOptions) { language in
                Divider().padding(.leading, 42)
                Button {
                    selectedLanguages.insert(language.code)
                    searchQuery = ""
                } label: {
                    HStack(spacing: 10) {
                        languageLeading(language)
                        Text(language.nativeName)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func languageLeading(_ language: RegionalLanguageOption) -> some View {
        Text(language.flag.isEmpty ? String(language.nativeName.prefix(1)) : language.flag)
            .fontWeight(language.flag.isEmpty ? .semibold : .regular)
            .frame(width: 20)
    }
}
