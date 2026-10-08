import SwiftUI
import wBlockCoreService

extension RegionalLanguageOption {
    /// Languages built-in lists name that the system has no locale for, such
    /// as Montenegrin and some Sámi languages.
    private static let builtInListLanguages = FilterListLoader().getDefaultFilterLists().flatMap(\.languages)

    /// Every language a custom regional list can cover (#921, #932): the
    /// languages the system has a locale for, plus those built-in lists name.
    /// ISO 639 alone also lists historical ones such as Old English (#943).
    static func assignable(locale: Locale = displayLocale) -> [RegionalLanguageOption] {
        let living = Locale.availableIdentifiers.compactMap { Locale(identifier: $0).languageCode }
        return options(for: living + builtInListLanguages, locale: locale)
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
