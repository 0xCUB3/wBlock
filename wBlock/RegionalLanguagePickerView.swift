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
        "ar": ["العربية", "Arabic"],
        "fa": ["Persian", "Farsi", "Dari", "فارسی", "پارسی", "دری", "فارسي", "پارسي"],
        "cnr": ["Montenegrin", "crnogorski", "црногорски"]
    ]

    let code: String
    /// The name in the app's display language, used for sorting and search.
    let name: String

    var id: String { code }

    /// The language's own name, which is what the rows show.
    var nativeName: String { Locale.nativeLanguageName(for: code) ?? name }

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
        options(for: filters.filter { $0.category == .foreign }.flatMap(\.languages), locale: locale)
    }

    /// Every language a custom regional list can cover (#921, #932): the
    /// languages the system has a locale for, plus those built-in lists name.
    /// ISO 639 alone also lists historical ones such as Old English (#943).
    static func assignable(locale: Locale = displayLocale) -> [RegionalLanguageOption] {
        let living = Locale.availableIdentifiers.compactMap { Locale(identifier: $0).languageCode }
        return options(for: living + ["cnr", "se"], locale: locale)
    }

    private static func options(for codes: [String], locale: Locale) -> [RegionalLanguageOption] {
        var seen = Set<String>()
        return codes.map { $0.lowercased() }.filter { seen.insert($0).inserted }.map { code in
            RegionalLanguageOption(code: code, name: locale.regionalLanguageName(for: code) ?? code)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Picks the languages a custom list covers once Regional is its category.
struct RegionalListLanguagesField: View {
    let category: FilterListCategory
    @Binding var languages: Set<String>

    var body: some View {
        if category == .foreign {
            VStack(alignment: .leading, spacing: 6) {
                Text("Languages").font(.caption).foregroundStyle(.secondary)
                RegionalLanguagePickerView(selectedLanguages: $languages, options: RegionalLanguageOption.assignable())
            }
            .spansFormLabelColumn()
        }
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
                // Hidden label: a macOS Form lifts a field's label into its label
                // column, which pushed every other row to the right (#932).
                TextField("Search languages", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            // Results scroll in a band capped at five rows, so the sheet around
            // the picker stops growing while typing (#932) without leaving empty
            // space under a short or empty match list (#940, #945).
            if !matchingOptions.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
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
                }
                .frame(height: CGFloat(min(matchingOptions.count, 5)) * rowHeight)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 37

    /// The language code rather than a flag: a flag names a country, and many
    /// languages have none of their own (#940).
    private func languageLeading(_ language: RegionalLanguageOption) -> some View {
        LanguageCodeBadge(code: language.code)
    }
}

/// A language's short code in a small capsule, shown where flags used to be.
/// "other" is the onboarding choice for languages without a list.
struct LanguageCodeBadge: View {
    let code: String

    var body: some View {
        Group {
            if code == "other" {
                Image(systemName: "globe")
            } else {
                Text(code.uppercased())
                    .font(.caption2.weight(.semibold).monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(.secondary)
        .frame(minWidth: 28, minHeight: 18)
        .padding(.horizontal, 2)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
    }
}
