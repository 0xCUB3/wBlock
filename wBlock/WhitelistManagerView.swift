import SwiftUI
import wBlockCoreService

struct WhitelistManagerView: View {
    @ObservedObject var filterManager: AppFilterManager
    @State private var newDomain: String = ""
    @State private var whitelistedDomains: [String] = []
    @State private var isAddingDomain: Bool = false
    @State private var isSelectionMode: Bool = false
    @State private var selectedDomains: Set<String> = []
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Add domain section
                addDomainSection

                // Domains list
                if !whitelistedDomains.isEmpty {
                    domainsListView
                } else {
                    emptyStateView
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical)
            .padding(.horizontal)
        }
        .navigationTitle("Whitelisted Domains")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if !whitelistedDomains.isEmpty {
                    if isSelectionMode {
                        Button {
                            deleteSelectedDomains()
                        } label: {
                            Label("Delete Selected", systemImage: "trash")
                        }
                        .disabled(selectedDomains.isEmpty)
                    }

                    Button {
                        toggleSelectionMode()
                    } label: {
                        Label(isSelectionMode ? "Done" : "Select", systemImage: isSelectionMode ? "checkmark" : "checklist")
                    }
                }
            }
        }
        .onAppear(perform: loadWhitelistedDomains)
    }

    private var addDomainSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Domain")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)

            HStack(spacing: 12) {
                TextField("example.com", text: $newDomain)
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        addDomain()
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    addDomain()
                } label: {
                    Image(systemName: isAddingDomain ? "hourglass" : "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(newDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingDomain)
            }
        }
    }

    private var domainsListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Whitelisted Domains")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(whitelistedDomains.indices, id: \.self) { index in
                    domainRowView(domain: whitelistedDomains[index])

                    if index < whitelistedDomains.count - 1 {
                        Divider()
                            .padding(.leading, isSelectionMode ? 48 : 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func domainRowView(domain: String) -> some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Button {
                    toggleDomainSelection(domain)
                } label: {
                    Image(systemName: selectedDomains.contains(domain) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedDomains.contains(domain) ? .accentColor : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Text(domain)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                toggleDomainSelection(domain)
            }
        }
        .contextMenu {
            if !isSelectionMode {
                Button(role: .destructive) {
                    removeDomain(domain)
                } label: {
                    Label("Remove from Whitelist", systemImage: "trash")
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No Whitelisted Domains")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Add domains to disable ad blocking on specific sites")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Logic Methods

    private func loadWhitelistedDomains() {
        let userDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
        whitelistedDomains = userDefaults.stringArray(forKey: "disabledSites") ?? []
    }

    private func addDomain() {
        let trimmed = newDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard isValidDomain(trimmed) else { return }

        isAddingDomain = true

        Task { @MainActor in
            let userDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
            let currentDomains = userDefaults.stringArray(forKey: "disabledSites") ?? []

            guard !currentDomains.contains(trimmed) else {
                isAddingDomain = false
                return
            }

            let updatedDomains = currentDomains + [trimmed]
            userDefaults.set(updatedDomains, forKey: "disabledSites")
            whitelistedDomains = updatedDomains
            newDomain = ""
            isAddingDomain = false
            isTextFieldFocused = true
        }
    }

    private func removeDomain(_ domain: String) {
        Task { @MainActor in
            let userDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
            let currentDomains = userDefaults.stringArray(forKey: "disabledSites") ?? []
            let updatedDomains = currentDomains.filter { $0 != domain }
            userDefaults.set(updatedDomains, forKey: "disabledSites")
            whitelistedDomains = updatedDomains
        }
    }

    private func isValidDomain(_ domain: String) -> Bool {
        let domainRegex = #"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"#
        return domain.range(of: domainRegex, options: .regularExpression) != nil
    }

    private func toggleSelectionMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectionMode.toggle()
            if !isSelectionMode {
                selectedDomains.removeAll()
            }
        }
    }

    private func toggleDomainSelection(_ domain: String) {
        if selectedDomains.contains(domain) {
            selectedDomains.remove(domain)
        } else {
            selectedDomains.insert(domain)
        }
    }

    private func deleteSelectedDomains() {
        Task { @MainActor in
            let userDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
            let currentDomains = userDefaults.stringArray(forKey: "disabledSites") ?? []
            let updatedDomains = currentDomains.filter { !selectedDomains.contains($0) }
            userDefaults.set(updatedDomains, forKey: "disabledSites")
            whitelistedDomains = updatedDomains
            selectedDomains.removeAll()
            isSelectionMode = false
        }
    }
}
