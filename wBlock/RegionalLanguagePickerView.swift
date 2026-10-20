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
            RegionalLanguagePickerView(selectedLanguages: $languages, options: RegionalLanguageOption.assignable())
        }
    }
}

/// A Languages row naming the chosen languages. It opens a searchable list
/// with a checkmark per language, like Language & Region in Settings (#1018).
/// Same control in onboarding, Regional Info, and the Add sheets (#687).
struct RegionalLanguagePickerView: View {
    @Binding var selectedLanguages: Set<String>
    let options: [RegionalLanguageOption]

    @State private var isChoosing = false

    private var summary: String {
        let names = options.filter { selectedLanguages.contains($0.code) }.map(\.nativeName)
        return names.isEmpty ? String(localized: "None") : ListFormatter.localizedString(byJoining: names)
    }

    var body: some View {
        #if os(macOS)
        HStack {
            Text("Languages")
            Spacer()
            Text(verbatim: summary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            // A popover: a sheet can't open from the Regional Info popover.
            Button("Edit…") { isChoosing = true }
                .popover(isPresented: $isChoosing) { list }
        }
        #else
        Button { isChoosing = true } label: {
            HStack {
                Text("Languages").foregroundStyle(.primary)
                Spacer()
                Text(verbatim: summary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isChoosing) { list }
        #endif
    }

    private var list: some View {
        RegionalLanguageList(selectedLanguages: $selectedLanguages, options: options)
    }
}

/// Every option with a checkmark on the chosen ones. Chosen languages lead
/// the list as it opens and stay put while you tap, so rows never jump.
/// iOS shows it in a sheet with a search bar; macOS in a popover with a
/// search field on top, which closes when you click outside it.
private struct RegionalLanguageList: View {
    @Binding var selectedLanguages: Set<String>
    let options: [RegionalLanguageOption]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var order: [RegionalLanguageOption] = []

    private var visible: [RegionalLanguageOption] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? order : order.filter { $0.matches(query) }
    }

    var body: some View {
        content.onAppear {
        order = options.filter { selectedLanguages.contains($0.code) }
            + options.filter { !selectedLanguages.contains($0.code) }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        VStack(spacing: 0) {
        TextField("Search languages", text: $query, prompt: Text("Search languages"))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .padding(10)
        Divider()
        list
        }
        .frame(width: 320, height: 400)
        #else
        CompatibleNavigationStack {
        list
            .searchable(text: $query, prompt: Text("Search languages"))
            .navigationTitle(Text("Languages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #endif
    }

    private var list: some View {
        List(visible) { language in
            Button {
                if selectedLanguages.contains(language.code) {
                    selectedLanguages.remove(language.code)
                } else {
                    selectedLanguages.insert(language.code)
                }
            } label: {
                HStack(spacing: 10) {
                    LanguageCodeBadge(code: language.code)
                    Text(verbatim: language.nativeName).foregroundStyle(.primary)
                    Spacer()
                    if selectedLanguages.contains(language.code) {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedLanguages.contains(language.code) ? .isSelected : [])
        }
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
