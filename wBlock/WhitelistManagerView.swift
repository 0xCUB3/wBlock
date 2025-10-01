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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Whitelisted Domains") {
                dismiss()
            }

            List {
                let paddedDomains = whitelistedDomains + Array(repeating: "", count: max(0, 10 - whitelistedDomains.count))
                ForEach(paddedDomains.indices, id: \ .self) { idx in
                    let domain = paddedDomains[idx]
                    HStack {
                        if domain.isEmpty {
                            Text("")
                        } else {
                            Toggle(isOn: Binding(
                                get: { selectedDomains.contains(domain) },
                                set: { checked in
                                    if checked {
                                        selectedDomains.insert(domain)
                                    } else {
                                        selectedDomains.remove(domain)
                                    }
                                }
                            )) {
                                Text(domain)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxHeight: 300)
            HStack {
                TextField("Add domain (e.g. example.com)", text: $newDomain, onCommit: addDomain)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 200)
                Button("Add") {
                    addDomain()
                }
                .disabled(newDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            }
            .padding()
            SheetBottomToolbar {
                Button("Select All") {
                    selectedDomains = Set(whitelistedDomains)
                }
                .buttonStyle(.bordered)
                .disabled(whitelistedDomains.isEmpty || isProcessing)
                Button("Delete Selected") {
                    deleteSelectedDomains()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDomains.isEmpty || isProcessing)
                Spacer()
            }
        }
        .padding()
        .frame(width: 400, height: 400)
        .onAppear(perform: loadWhitelistedDomains)
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
