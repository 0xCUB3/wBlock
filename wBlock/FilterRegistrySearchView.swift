import SwiftUI
import wBlockCoreService

/// The Browse tab of Add Filter List: wBlock's own lists first, then lists from
/// AdGuard's Safari filter registry that wBlock doesn't have yet.
struct FilterRegistrySearchSections: View {
    @ObservedObject var filterManager: AppFilterManager
    /// Owned by the Add sheet so Back from a list's review keeps the search (#987).
    @Binding var query: String
    let onAdd: (AdGuardRegistryList) -> Void

    @Environment(\.locale) private var locale
    @State private var registryLists: [AdGuardRegistryList] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var wBlockMatches: [FilterList] {
        guard !trimmedQuery.isEmpty else { return [] }
        return filterManager.filterLists.filter {
            !$0.category.isUserScriptOnly && $0.matchesSearch(trimmedQuery, locale: locale)
        }
    }

    private var registryMatches: [AdGuardRegistryList] {
        let existing = filterManager.filterLists.map(\.url)
        return registryLists.filter { list in
            !existing.contains(where: list.isSameList(as:)) && list.filter.matchesSearch(trimmedQuery, locale: locale)
        }
    }

    var body: some View {
        Section {
            TextField("Search", text: $query, prompt: Text("Name, language, or topic"))
                .labelsHidden()
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .autocorrectionDisabled()
        } footer: {
            AddContentNote(text: "Searches wBlock’s lists and AdGuard’s filter registry for Safari.")
        }
        .task { await load() }
        #if os(macOS)
        // Column-style forms don't scroll on macOS, so the results scroll on their own.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { results }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
        }
        .frame(maxHeight: .infinity)
        .spansFormLabelColumn()
        #else
        results
        #endif
    }

    @ViewBuilder
    private var results: some View {
        if !wBlockMatches.isEmpty {
            Section {
                ForEach(wBlockMatches) { filter in
                    HStack {
                        row(filter, note: nil)
                        Spacer()
                        Toggle("On", isOn: Binding(
                            get: { filter.isSelected },
                            set: { filterManager.setFilterListSelection(id: filter.id, selected: $0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                }
            } header: {
                sectionHeader("In wBlock")
            }
        }
        Section {
            if registryLists.isEmpty, isLoading {
                ProgressView().controlSize(.small)
            } else if registryLists.isEmpty, let loadError {
                Text(loadError).foregroundStyle(.orange)
                Button("Try Again") { Task { await load() } }
            } else if registryMatches.isEmpty {
                Text(trimmedQuery.isEmpty
                    ? "wBlock already includes every list in the registry."
                    : "No matching lists.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(registryMatches) { list in
                    HStack {
                        row(list.filter, note: list.knownURLs.contains(where: FilterListLoader.wasBuiltInURL)
                            ? LocalizedStrings.text("No longer built into wBlock", comment: "Registry list wBlock removed from its built-ins")
                            : nil)
                        Spacer()
                        Button("Add") { onAdd(list) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        } header: {
            sectionHeader("AdGuard Filter Registry")
        }
    }

    /// macOS lays these sections out in a plain stack, where a default header
    /// reads like another list name (#981).
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            #if os(macOS)
            .font(.title3.weight(.semibold))
            .padding(.top, 4)
            #endif
    }

    private func row(_ filter: FilterList, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: filter.localizedDisplayName)
            if !filter.localizedDisplayDescription.isEmpty {
                Text(verbatim: filter.localizedDisplayDescription)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            // No languages: the registry lists them for only some regional
            // lists, so a few rows stood out (#987). Search still matches them.
            Text(verbatim: ContentRowMetadata.summary([filter.category.localizedName, note]))
            .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard registryLists.isEmpty, !isLoading else { return }
        isLoading = true
        loadError = nil
        do {
            registryLists = try await AdGuardFilterRegistry.load()
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
