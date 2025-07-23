import SwiftUI
import wBlockCoreService

struct OnboardingView: View {
    enum BlockingLevel: String, CaseIterable, Identifiable {
        case minimal = "Minimal"
        case recommended = "Recommended"
        case complete = "Complete"
        var id: String { rawValue }
    }

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("selectedBlockingLevel") private var selectedBlockingLevel: String = BlockingLevel.recommended.rawValue
    @State private var selectedUserscripts: Set<String> = []
    @State private var step: Int = 0
    @State private var isApplying: Bool = false
    @State private var applyProgress: Float = 0.0

    let filterManager: AppFilterManager
    let userScriptManager: UserScriptManager

    // Use the real default userscripts from UserScriptManager
    var defaultUserScripts: [(id: String, name: String, description: String)] {
        userScriptManager.userScripts.map { script in
            (id: script.id.uuidString, name: script.name, description: script.description.isEmpty ? script.url?.absoluteString ?? "" : script.description)
        }
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
        .frame(minWidth: 350, maxWidth: 500, minHeight: 350, maxHeight: 600)
        .padding()
    }

    struct OnboardingDownloadView: View {
        let progress: Float
        var body: some View {
            VStack(spacing: 24) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 300)
                VStack(spacing: 4) {
                    Text("Downloading and installing filter lists...")
                        .multilineTextAlignment(.center)
                    Text("Applying filters...")
                        .font(.headline)
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
            Text("Choose your preferred blocking level. You can change this later in settings.")
                .font(.subheadline)
            ForEach(BlockingLevel.allCases) { level in
                Button(action: {
                    selectedBlockingLevel = level.rawValue
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
            Text("Userscripts: \(selectedUserscripts.isEmpty ? "None" : selectedUserscripts.joined(separator: ", "))")
            Divider()
            if selectedBlockingLevel == BlockingLevel.complete.rawValue {
                Text("Warning: Complete mode may break some websites. Proceed with caution.")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            Spacer()
            HStack {
                Button("Back") { step -= 1 }
                Spacer()
                Button("Apply & Finish") {
                    applySettings()
                    hasCompletedOnboarding = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    func applySettings() {
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
        filterManager.filterLists = updatedFilters
        filterManager.saveFilterLists()

        // 2. Enable/disable userscripts based on onboarding selection
        let selectedScriptIDs = Set(selectedUserscripts)
        for i in userScriptManager.userScripts.indices {
            let script = userScriptManager.userScripts[i]
            let shouldEnable = selectedScriptIDs.contains(script.id.uuidString)
            if script.isEnabled != shouldEnable {
                userScriptManager.toggleUserScript(script)
            }
        }

        // 3. Download and install enabled filter lists
        isApplying = true
        let enabledFilters = filterManager.filterLists.filter { $0.isSelected }
        Task { @MainActor in
            await filterManager.downloadAndApplyFilters(filters: enabledFilters, progress: { progress in
                self.applyProgress = progress
            })
            isApplying = false
            hasCompletedOnboarding = true
        }
    }
}
