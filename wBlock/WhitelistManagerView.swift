#if os(macOS)
import SwiftUI
import wBlockCoreService
import SafariServices

struct WhitelistManagerView: View {
    @ObservedObject var filterManager: AppFilterManager
    @State private var newDomain: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var whitelistedDomains: [String] = []
    @State private var selectedDomains: Set<String> = []
    @State private var isProcessing: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(selection: $selectedDomains) {
                    ForEach(whitelistedDomains, id: \.self) { domain in
                        Text(domain)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .tag(domain)
                    }
                }

                Divider()

                HStack {
                    TextField("Add domain (e.g. example.com)", text: $newDomain, onCommit: addDomain)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(minWidth: 200)
                }
                .padding()
            }
            .navigationTitle("Whitelisted Domains")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        selectedDomains = Set(whitelistedDomains)
                    } label: {
                        Label("Select All", systemImage: "checklist")
                    }
                    .disabled(whitelistedDomains.isEmpty || isProcessing)

                    Button {
                        addDomain()
                    } label: {
                        Label("Add Domain", systemImage: "plus")
                    }
                    .disabled(newDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)

                    Button {
                        deleteSelectedDomains()
                    } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                    .disabled(selectedDomains.isEmpty || isProcessing)
                }
            }
            .onAppear(perform: loadWhitelistedDomains)
        }
        .frame(minWidth: 520, idealWidth: 600, maxWidth: .infinity,
               minHeight: 500, idealHeight: 650, maxHeight: .infinity)
    }

    private func loadWhitelistedDomains() {
        let userDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
        whitelistedDomains = userDefaults.stringArray(forKey: "disabledSites") ?? []
    }
    
    private func addDomain() {
        let trimmed = newDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isProcessing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let userDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
            let currentDomains = userDefaults.stringArray(forKey: "disabledSites") ?? []
            guard !currentDomains.contains(trimmed) else {
                showError = true
                errorMessage = "Domain already whitelisted."
                isProcessing = false
                return
            }
            let updatedDomains = currentDomains + [trimmed]
            userDefaults.set(updatedDomains, forKey: "disabledSites")
            whitelistedDomains = updatedDomains
            newDomain = ""
            showError = false
            isProcessing = false
        }
    }
    
    private func deleteSelectedDomains() {
        isProcessing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let userDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
            let currentDomains = userDefaults.stringArray(forKey: "disabledSites") ?? []
            let updatedDomains = currentDomains.filter { !selectedDomains.contains($0) }
            userDefaults.set(updatedDomains, forKey: "disabledSites")
            whitelistedDomains = updatedDomains
            selectedDomains.removeAll()
            isProcessing = false
        }
    }
}
#endif
