import SwiftUI
import wBlockCoreService

struct OnboardingView: View {
    enum BlockingLevel: String, CaseIterable, Identifiable {
        case minimal = "Minimal"
        case recommended = "Recommended"
        case complete = "Complete"
        var id: String { rawValue }
    }

    @StateObject private var dataManager = ProtobufDataManager.shared
    
    private var hasCompletedOnboarding: Bool {
        dataManager.hasCompletedOnboarding
    }

    private func setHasCompletedOnboarding(_ value: Bool) {
        Task { @MainActor in
            await dataManager.setHasCompletedOnboarding(value)
        }
    }
    
    private var selectedBlockingLevel: String {
        dataManager.selectedBlockingLevel
    }

    private func setSelectedBlockingLevel(_ value: String) {
        Task { @MainActor in
            await dataManager.setSelectedBlockingLevel(value)
        }
    }
    @State private var selectedUserscripts: Set<String> = []
    @State private var step: Int = 0
    @State private var isApplying: Bool = false
    @State private var applyProgress: Float = 0.0

    let filterManager: AppFilterManager
    @Environment(\.dismiss) private var dismiss

    // Use the real default userscripts from UserScriptManager
    var defaultUserScripts: [(id: String, name: String, description: String)] {
        UserScriptManager.shared.userScripts.map { script in
            (id: script.id.uuidString, name: script.name, description: script.description.isEmpty ? script.url?.absoluteString ?? "" : script.description)
        }
    }

    // Helper to get the Bypass Paywalls userscript and filter list names
    var bypassPaywallsScript: (id: String, name: String)? {
        UserScriptManager.shared.userScripts.first(where: { $0.name.localizedCaseInsensitiveContains("bypass paywalls") })
            .map { ($0.id.uuidString, $0.name) }
    }
    var bypassPaywallsFilterName: String? {
        // Adjust this name to match your actual filter list name
        let candidates = [
            "Bypass Paywalls Filter",
            "Bypass Paywalls",
            "Bypass Paywalls (Custom)"
        ]
        return filterManager.filterLists.first(where: { filter in
            candidates.contains(where: { filter.name.localizedCaseInsensitiveContains($0) })
        })?.name
    }

    var body: some View {
        VStack {
            if isApplying {
                OnboardingDownloadView(progress: applyProgress)
            } else {
                if step == 0 {
                    blockingLevelStep
                } else if step == 1 {
                    userscriptStep
                } else if step == 2 {
                    summaryStep
                }
            }
        }
    .padding()
#if os(macOS)
    .frame(minWidth: 350, maxWidth: 500, minHeight: 350, maxHeight: 600)
#endif
#if os(iOS)
    .background(
        Color(.systemBackground)
        .ignoresSafeArea()
    )
#endif
    }

    struct OnboardingDownloadView: View {
        let progress: Float
        var body: some View {
            VStack(spacing: 24) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
                VStack(spacing: 4) {
                    Text("Downloading and applying filter lists...")
                        .multilineTextAlignment(.center)
                    Text("This may take awhile")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    var blockingLevelStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to wBlock!")
                .font(.title)
                .bold()
            Text("Choose your preferred blocking level. You can adjust enabled filters later.")
                .font(.subheadline)
            ForEach(BlockingLevel.allCases) { level in
                Button(action: {
                    setSelectedBlockingLevel(level.rawValue)
                }) {
                    HStack {
                        Image(systemName: selectedBlockingLevel == level.rawValue ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading) {
                            Text(level.rawValue)
                                .font(.headline)
                            Text(blockingLevelDescription(level))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(level == .complete)
                .opacity(level == .complete ? 0.5 : 1.0)
            }
            Spacer()
            HStack {
                Spacer()
                Button("Next") { step += 1 }
                    .disabled(selectedBlockingLevel.isEmpty)
            }
        }
    }
    
    func blockingLevelDescription(_ level: BlockingLevel) -> String {
        switch level {
        case .minimal:
            return "Only AdGuard Base filter. Lightest protection, best compatibility."
        case .recommended:
            return "Default filters for balanced blocking and compatibility."
        case .complete:
            return "All filters (except foreign languages). May break some sites, so it is not recommended. Use with caution."
        }
    }
    
    var userscriptStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Userscripts")
                .font(.title2)
                .bold()
            Text("Select any userscripts you want to enable. These add extra features or fixes. You can always add more in the settings later.")
                .font(.subheadline)
            ForEach(defaultUserScripts, id: \.id) { script in
                Toggle(isOn: Binding(
                    get: { selectedUserscripts.contains(script.id) },
                    set: { isOn in
                        if isOn { selectedUserscripts.insert(script.id) }
                        else { selectedUserscripts.remove(script.id) }
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text(script.name)
                        Text(script.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            // Show a note if Bypass Paywalls userscript is selected
            if let bypassScript = bypassPaywallsScript, selectedUserscripts.contains(bypassScript.id), let filterName = bypassPaywallsFilterName {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The \(bypassScript.name) userscript requires the \(filterName)")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("It will be enabled automatically.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            HStack {
                Button("Back") { step -= 1 }
                Spacer()
                Button("Next") { step += 1 }
            }
        }
    }
    
    var summaryStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Summary")
                .font(.title2)
                .bold()
            Text("Review your choices and apply settings.")
                .font(.subheadline)
            Divider()
            Text("Blocking Level: \(selectedBlockingLevel)")
                Text("Userscripts: \(selectedUserscripts.isEmpty ? "None" : selectedUserscripts.compactMap { id in defaultUserScripts.first(where: { $0.id == id })?.name }.joined(separator: ", "))")
            Divider()
            if selectedBlockingLevel == BlockingLevel.complete.rawValue {
                Text("Warning: Complete mode may break some websites. Proceed with caution.")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // Safari extension enablement reminder
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.yellow)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("After filters are applied, you must enable all wBlock extensions in Safari's extension settings.")
                            .font(.headline)
                        Text("You can enable them in Safari > Settings > Extensions (on Mac) or Settings > Safari > Extensions (on iPhone/iPad).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                // Apple support links
                HStack(spacing: 16) {
                    Link("How to enable on iPhone/iPad", destination: URL(string: "https://support.apple.com/guide/iphone/get-extensions-iphab0432bf6/ios")!)
                        .font(.caption)
                        .foregroundColor(.blue)
                    Link("How to enable on Mac", destination: URL(string: "https://support.apple.com/en-us/102343")!)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            Spacer()
            HStack {
                Button("Back") { step -= 1 }
                Spacer()
                Button("Apply & Finish") {
                    Task {
                        await applySettings()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    func applySettings() async {
        // 1. Set filter selection based on chosen blocking level
        var updatedFilters = filterManager.filterLists
        switch BlockingLevel(rawValue: selectedBlockingLevel) ?? .recommended {
        case .minimal:
            for i in updatedFilters.indices {
                updatedFilters[i].isSelected = updatedFilters[i].name == "AdGuard Base Filter"
            }
        case .recommended:
            // Disable all filters first
            for i in updatedFilters.indices {
                updatedFilters[i].isSelected = false
            }
            // Enable only the recommended filters
            let recommendedFilters = [
                "AdGuard Base Filter",
                "AdGuard Tracking Protection Filter",
                "AdGuard Annoyances Filter",
                "EasyPrivacy",
                "Online Malicious URL Blocklist",
                "d3Host List by d3ward",
                "Anti-Adblock List"
            ]
            for i in updatedFilters.indices {
                if recommendedFilters.contains(updatedFilters[i].name) {
                    updatedFilters[i].isSelected = true
                }
            }
        case .complete:
            for i in updatedFilters.indices {
                updatedFilters[i].isSelected = updatedFilters[i].category != .foreign
            }
        }
        // If Bypass Paywalls userscript is selected, also enable the required filter list
        if let bypassScript = bypassPaywallsScript, selectedUserscripts.contains(bypassScript.id), let filterName = bypassPaywallsFilterName {
            for i in updatedFilters.indices {
                if updatedFilters[i].name == filterName {
                    updatedFilters[i].isSelected = true
                }
            }
        }
        filterManager.filterLists = updatedFilters
        await filterManager.saveFilterLists()

        // 2. Enable/disable userscripts based on onboarding selection
        let selectedScriptIDs = Set(selectedUserscripts)
        for script in UserScriptManager.shared.userScripts {
            let shouldEnable = selectedScriptIDs.contains(script.id.uuidString)
            if script.isEnabled != shouldEnable {
                // Await toggle to ensure persistence
                await UserScriptManager.shared.toggleUserScript(script)
            }
        }
        
        // 2.5. Mark userscript initial setup as complete
        UserScriptManager.shared.markInitialSetupComplete()

        // 3. Download and install enabled filter lists
        isApplying = true
        let enabledFilters = filterManager.filterLists.filter { $0.isSelected }
        Task { @MainActor in
            await filterManager.downloadAndApplyFilters(filters: enabledFilters, progress: { progress in
                applyProgress = progress
            })
            isApplying = false
            setHasCompletedOnboarding(true)
            dismiss()
            filterManager.showingApplyProgressSheet = true
        }
    }
}
