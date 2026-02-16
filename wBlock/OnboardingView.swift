import SwiftUI
import wBlockCoreService
#if os(iOS)
import UserNotifications
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OnboardingView: View {
    enum BlockingLevel: String, CaseIterable, Identifiable {
        case minimal = "Minimal"
        case recommended = "Recommended"
        var id: String { rawValue }
    }

    enum OnboardingStep: Int, CaseIterable, Identifiable {
        case protection
        case region
        case userscripts
        case sync
        case setup

        var id: Int { rawValue }
    }

    @StateObject private var dataManager: ProtobufDataManager
    @StateObject private var userScriptManager = UserScriptManager.shared
    
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
    @State private var step: OnboardingStep = .protection
    @State private var selectedLanguages: Set<String>
    @State private var selectedRegionalFilters: Set<UUID> = []
    @State private var recommendedRegionalFilters: [FilterList] = []
    @State private var optionalRegionalFilters: [FilterList] = []
    @State private var regionInfoMessage: String?
    @State private var hasManuallyEditedRegionalSelection = false
    @State private var isCommunityExpanded = false
    @State private var wantsCloudSync: Bool = false
    @State private var hasProbedRemoteConfig: Bool = false
    @State private var remoteConfigUpdatedAtText: String?
    @State private var showRemoteConfigPrompt: Bool = false
    @State private var isAdoptingRemoteConfig: Bool = false
    @State private var hasSeededUserscriptSelection = false
#if os(iOS)
    @State private var wantsReminderNotifications: Bool = true
#endif
    @State private var hasEnabledContentBlockers = false
    @State private var hasEnabledAdvanced = false

    let filterManager: AppFilterManager
    
    private static let selectedLanguagesDefaultsKey = "onboardingSelectedLanguages"
    #if os(iOS)
    private static let reminderPreferenceKey = "onboardingWantsReminderNotifications"
    #endif
    private static let cloudSyncEnabledDefaultsKey = "cloudSyncEnabled"

    // Helper to look up canonical filter metadata from filterManager instead of loading separately
    private func foreignFilterMetadata(for url: String) -> FilterList? {
        filterManager.filterLists.first { $0.url.absoluteString == url && $0.category == .foreign }
    }

    init(filterManager: AppFilterManager) {
        self.filterManager = filterManager
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
        self.sharedDefaults = defaults
        _dataManager = StateObject(wrappedValue: ProtobufDataManager.shared)

        let stored = defaults.stringArray(forKey: Self.selectedLanguagesDefaultsKey)
        if let stored, !stored.isEmpty {
            _selectedLanguages = State(initialValue: Set(stored))
        } else {
            // Auto-detect from system preferred languages
            let systemLangs = Locale.preferredLanguages.compactMap {
                Locale(identifier: $0).language.languageCode?.identifier.lowercased()
            }
            _selectedLanguages = State(initialValue: Set(systemLangs))
        }

        _selectedRegionalFilters = State(initialValue: [])
        _recommendedRegionalFilters = State(initialValue: [])
        _optionalRegionalFilters = State(initialValue: [])
        _regionInfoMessage = State(initialValue: nil)
        _wantsCloudSync = State(initialValue: defaults.bool(forKey: Self.cloudSyncEnabledDefaultsKey))
#if os(iOS)
    let storedReminderPreference = defaults.object(forKey: Self.reminderPreferenceKey) as? Bool ?? true
    _wantsReminderNotifications = State(initialValue: storedReminderPreference)
#endif
    }
    private let sharedDefaults: UserDefaults
    @Environment(\.dismiss) private var dismiss

    struct OnboardingUserScriptItem: Identifiable {
        let id: String
        let name: String
        let description: String
        let version: String
        let sourceHost: String?
    }

    private let userscriptDescriptionFallbacksByName: [String: String] = [
        "return youtube dislike":
            "Return of the YouTube Dislike.",
        "bypass paywalls clean":
            "Bypass paywalls of news sites.",
        "youtube classic":
            "Reverts YouTube to its classic design and behavior.",
        "adguard extra":
            "Handles advanced anti-adblock cases that filter rules miss."
    ]

    private var defaultUserScripts: [OnboardingUserScriptItem] {
        userScriptManager.userScripts
            .filter { userScriptManager.isDefaultUserScript($0) }
            .map { script in
                OnboardingUserScriptItem(
                    id: script.id.uuidString,
                    name: script.name,
                    description: resolvedUserscriptDescription(for: script),
                    version: script.version.trimmingCharacters(in: .whitespacesAndNewlines),
                    sourceHost: script.url?.host
                )
            }
    }

    // Helper to get the Bypass Paywalls userscript and filter list names
    var bypassPaywallsScript: (id: String, name: String)? {
        userScriptManager.userScripts.first(where: {
            userScriptManager.isDefaultUserScript($0)
                && $0.name.localizedCaseInsensitiveContains("bypass paywalls")
        })
        .map { ($0.id.uuidString, $0.name) }
    }
    var bypassPaywallsFilterName: String? {
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
        VStack(alignment: .leading, spacing: 16) {
            onboardingHeader

            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }

            onboardingFooter
        }
        .padding()
    #if os(macOS)
        .frame(minWidth: 440, maxWidth: 540, minHeight: 620, maxHeight: 820)
    #endif
    #if os(iOS)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemBackground),
                    Color.accentColor.opacity(0.07)
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    #endif
        .onAppear {
            updateRegionalRecommendations(for: selectedLanguages)
            probeForExistingICloudSetupIfNeeded()
            userScriptManager.prefetchDefaultUserScriptMetadataIfNeeded()
            seedSelectedUserscriptsIfNeeded()
        }
        .task {
            await userScriptManager.waitUntilReady()
            seedSelectedUserscriptsIfNeeded()
            userScriptManager.prefetchDefaultUserScriptMetadataIfNeeded()
        }
        .onChange(of: selectedLanguages) { _, newValue in
            sharedDefaults.set(Array(newValue), forKey: Self.selectedLanguagesDefaultsKey)
            hasManuallyEditedRegionalSelection = false
            updateRegionalRecommendations(for: newValue)
        }
        .onChange(of: filterManager.filterLists) { _ in
            updateRegionalRecommendations(for: selectedLanguages)
        }
        .onChange(of: userScriptManager.userScripts) { _ in
            seedSelectedUserscriptsIfNeeded()
        }
        .onChange(of: step) { _, newStep in
            if newStep == .protection {
                probeForExistingICloudSetupIfNeeded()
            }
        }
        .confirmationDialog(
            "Use existing iCloud setup?",
            isPresented: $showRemoteConfigPrompt,
            titleVisibility: .visible
        ) {
            Button("Use iCloud Setup") {
                Task { await adoptRemoteICloudSetup() }
            }
            Button("Continue Setup", role: .cancel) {}
        } message: {
            if let remoteConfigUpdatedAtText {
                Text("We found an existing wBlock configuration in iCloud (\(remoteConfigUpdatedAtText)). You can skip onboarding and use that instead.")
            } else {
                Text("We found an existing wBlock configuration in iCloud. You can skip onboarding and use that instead.")
            }
        }
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up wBlock")
                        .font(.title2.bold())
                }

                Spacer()

                Text("\(step.rawValue + 1)/\(OnboardingStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .protection:
            blockingLevelStep
        case .region:
            regionStep
        case .userscripts:
            userscriptStep
        case .sync:
            syncStep
        case .setup:
            setupStep
        }
    }

    private var onboardingFooter: some View {
        HStack(spacing: 12) {
            if step != .protection {
                Button("Back") {
                    retreatToPreviousStep()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button(step == .setup ? "Apply & Finish" : "Next") {
                if step == .setup {
                    Task {
                        await applySettings()
                    }
                } else {
                    advanceToNextStep()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(footerButtonDisabled)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var footerButtonDisabled: Bool {
        switch step {
        case .protection:
            return selectedBlockingLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .setup:
            return !hasEnabledContentBlockers || !hasEnabledAdvanced
        default:
            return false
        }
    }

    private func advanceToNextStep() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = next
        }
    }

    private func retreatToPreviousStep() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = previous
        }
    }

    private var blockingLevelStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(BlockingLevel.allCases) { level in
                blockingLevelCard(for: level)
            }
        }
    }

    private func blockingLevelCard(for level: BlockingLevel) -> some View {
        let isSelected =
            selectedBlockingLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == level.rawValue.lowercased()

        return Button {
            setSelectedBlockingLevel(level.rawValue)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(level.rawValue))
                            .font(.headline)
                    }

                    Text(blockingLevelDescription(level))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(.plain)
        .liquidGlassCompat(
            cornerRadius: 16,
            material: isSelected ? .thickMaterial : .regularMaterial
        )
    }

    func blockingLevelDescription(_ level: BlockingLevel) -> String {
        switch level {
        case .minimal:
            return String(localized: "Base filter only.")
        case .recommended:
            return String(localized: "Balanced defaults.")
        }
    }

    private struct LanguageOption: Identifiable {
        let code: String
        let name: String
        let flag: String
        var id: String { code }
    }

    private var availableFilterLanguages: [LanguageOption] {
        var seen = Set<String>()
        var result: [LanguageOption] = []
        for filter in filterManager.filterLists where filter.category == .foreign {
            for lang in filter.languages {
                let lc = lang.lowercased()
                guard seen.insert(lc).inserted else { continue }
                let name = Locale.current.localizedString(forLanguageCode: lc) ?? lc
                let flag = FilterList.languageToFlag[lc] ?? ""
                result.append(LanguageOption(code: lc, name: name, flag: flag))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func languageToggle(for lang: LanguageOption) -> some View {
        let isOn = selectedLanguages.contains(lang.code)
        return Button {
            if isOn {
                selectedLanguages.remove(lang.code)
            } else {
                selectedLanguages.insert(lang.code)
            }
        } label: {
            HStack(spacing: 6) {
                if !lang.flag.isEmpty {
                    Text(lang.flag)
                }
                Text(lang.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .liquidGlassCompat(
            cornerRadius: 10,
            material: isOn ? .thickMaterial : .regularMaterial
        )
    }

    private var regionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(availableFilterLanguages) { lang in
                    languageToggle(for: lang)
                }
            }

            if let message = regionInfoMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if !recommendedRegionalFilters.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recommended")
                        .font(.headline)
                    ForEach(recommendedRegionalFilters) { filter in
                        regionalToggle(for: filter, expandsCommunity: false)
                    }
                }
            }

            if !optionalRegionalFilters.isEmpty {
                DisclosureGroup(isExpanded: $isCommunityExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(optionalRegionalFilters) { filter in
                            regionalToggle(for: filter, expandsCommunity: false)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Community options")
                        .font(.headline)
                }
                .padding(14)
                .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
            }
        }
    }

    private func regionalToggle(for filter: FilterList, expandsCommunity: Bool = true) -> some View {
        let isSelected = selectedRegionalFilters.contains(filter.id)

        return Button {
            if isSelected {
                selectedRegionalFilters.remove(filter.id)
            } else {
                selectedRegionalFilters.insert(filter.id)
            }
            hasManuallyEditedRegionalSelection = true
            if expandsCommunity {
                isCommunityExpanded = true
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(filter.name)
                        .font(.headline)

                    if !filter.description.isEmpty {
                        Text(filter.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(.plain)
        .liquidGlassCompat(
            cornerRadius: 16,
            material: isSelected ? .thickMaterial : .regularMaterial
        )
    }

    private var userscriptStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if defaultUserScripts.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Loading userscripts…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
            } else {
                ForEach(defaultUserScripts) { script in
                    userscriptCard(for: script)
                }
            }

            if let bypassScript = bypassPaywallsScript,
                selectedUserscripts.contains(bypassScript.id),
                let filterName = bypassPaywallsFilterName
            {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.title3)
                        .symbolRenderingMode(.multicolor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The \(bypassScript.name) userscript requires the \(filterName)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(12)
                .liquidGlassCompat(cornerRadius: 14, material: .regularMaterial)
            }
        }
    }

    private var syncStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync your filter selections, custom lists, userscripts, and whitelist across devices.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            cloudSyncCard

#if os(iOS)
            Divider()
            reminderCard
#endif
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enable the Safari extensions so wBlock can block ads.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Setup Instructions")
                        .font(.headline)
                    Spacer()
                    Button {
                        openSafariExtensionsSettings()
                    } label: {
                        Label("Open Safari Settings", systemImage: "gear")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("1.")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            #if os(macOS)
                            Text("Safari → Settings → Extensions")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Enable all 5 Content Blocker extensions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            #else
                            Text("Settings → Apps → Safari → Extensions")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Enable all 5 Content Blocker extensions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            #endif
                        }

                        Spacer()

                        Toggle("", isOn: $hasEnabledContentBlockers)
                            .labelsHidden()
                    }

                    Divider()
                        .padding(.leading, 30)

                    HStack(alignment: .top, spacing: 10) {
                        Text("2.")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            #if os(macOS)
                            Text("Enable 'wBlock Advanced' → Always Allow on Every Website")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Required for YouTube ad blocking and much more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            #else
                            Text("Enable 'wBlock Scripts' → Always Allow on Every Website")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Required for YouTube ad blocking and much more")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            #endif
                        }

                        Spacer()

                        Toggle("", isOn: $hasEnabledAdvanced)
                            .labelsHidden()
                    }
                }
            }
            .padding(14)
            .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)

            Text("Already done this? Just check the boxes above.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
    }

    private func openSafariExtensionsSettings() {
        #if os(macOS)
        let runningApps = NSWorkspace.shared.runningApplications
        if let safariApp = runningApps.first(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
            safariApp.activate()
            let script = """
            tell application "Safari"
                activate
            end tell
            tell application "System Events"
                tell process "Safari"
                    click menu item "Settings…" of menu "Safari" of menu bar 1
                end tell
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if error != nil {
                    safariApp.activate()
                }
            }
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Safari.app"))
        }
        #else
        if let url = URL(string: "App-prefs:SAFARI&path=EXTENSIONS") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "App-prefs:") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func userscriptCard(for script: OnboardingUserScriptItem) -> some View {
        let isSelected = selectedUserscripts.contains(script.id)

        return Button {
            if isSelected {
                selectedUserscripts.remove(script.id)
            } else {
                selectedUserscripts.insert(script.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(script.name)
                        .font(.headline)
                    Text(script.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(.plain)
        .liquidGlassCompat(
            cornerRadius: 16,
            material: isSelected ? .thickMaterial : .regularMaterial
        )
    }

    private func resolvedUserscriptDescription(for script: UserScript) -> String {
        // Prefer curated fallback descriptions for known scripts
        if let fallback = userscriptDescriptionFallbacksByName[script.name.lowercased()] {
            return fallback
        }

        let trimmedDescription = script.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = trimmedDescription.lowercased()

        let isPlaceholder =
            normalizedDescription.isEmpty
            || normalizedDescription == "default userscript"
            || normalizedDescription == "default userscript - downloading..."
            || normalizedDescription == "ready to enable"

        guard isPlaceholder else { return trimmedDescription }

        if userScriptManager.isPrefetchingDefaultMetadata {
            return String(localized: "Loading metadata…")
        }

        return String(localized: "No description provided by the script metadata.")
    }

    private func seedSelectedUserscriptsIfNeeded() {
        guard !hasSeededUserscriptSelection else { return }

        let defaultScripts = userScriptManager.userScripts.filter {
            userScriptManager.isDefaultUserScript($0)
        }
        guard !defaultScripts.isEmpty else { return }

        selectedUserscripts = Set(defaultScripts.filter(\.isEnabled).map { $0.id.uuidString })
        hasSeededUserscriptSelection = true
    }
    
    func applySettings() async {
        // 1. Set filter selection based on chosen blocking level
        var updatedFilters = filterManager.filterLists
        switch selectedBlockingLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "minimal":
            for i in updatedFilters.indices {
                updatedFilters[i].isSelected = updatedFilters[i].name == "AdGuard Base Filter"
            }
        default:
            // Disable all filters first
            for i in updatedFilters.indices {
                updatedFilters[i].isSelected = false
            }
            // Enable only the recommended filters
            let recommendedFilters = [
                "AdGuard Base Filter",
                "AdGuard Tracking Protection Filter",
                "AdGuard Cookie Notices",
                "AdGuard Popups",
                "AdGuard Mobile App Banners",
                "AdGuard Other Annoyances",
                "AdGuard Widgets",
                "EasyPrivacy",
                "Online Security Filter",
                "d3Host List by d3ward",
                "Anti-Adblock List"
            ]
            for i in updatedFilters.indices {
                if recommendedFilters.contains(updatedFilters[i].name) {
                    updatedFilters[i].isSelected = true
                }
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
        if !selectedRegionalFilters.isEmpty {
            for i in updatedFilters.indices {
                if selectedRegionalFilters.contains(updatedFilters[i].id) {
                    updatedFilters[i].isSelected = true
                }
            }
        }
        sharedDefaults.set(Array(selectedLanguages), forKey: Self.selectedLanguagesDefaultsKey)
#if os(iOS)
    sharedDefaults.set(wantsReminderNotifications, forKey: Self.reminderPreferenceKey)
#endif
        filterManager.filterLists = updatedFilters
        await filterManager.saveFilterLists()

        // 2. Enable/disable userscripts based on onboarding selection
        let selectedScriptIDs = Set(selectedUserscripts.compactMap { UUID(uuidString: $0) })
        // Single, deterministic batch apply
        await userScriptManager.setEnabledScripts(withIDs: selectedScriptIDs)
        
        // 2.5. Mark userscript initial setup as complete
        userScriptManager.markInitialSetupComplete()

        // 3. Save setup checklist state
        await dataManager.setHasEnabledContentBlockers(hasEnabledContentBlockers)
        await dataManager.setHasEnabledPlatformExtension(hasEnabledAdvanced)
        await dataManager.setHasSetAllWebsitesPermission(hasEnabledAdvanced)

        // 4. Set sync and mark onboarding complete
        CloudSyncManager.shared.setEnabled(wantsCloudSync)
        setHasCompletedOnboarding(true)
#if os(iOS)
        await requestNotificationPermissionIfNeeded()
#endif

        // 5. Dismiss onboarding and let the main view handle download + apply
        dismiss()
        filterManager.checkAndEnableFilters(forceReload: true)
    }

    private func probeForExistingICloudSetupIfNeeded() {
        guard !hasProbedRemoteConfig else { return }
        guard !hasCompletedOnboarding else { return }
        guard step == .protection else { return }

        hasProbedRemoteConfig = true

        Task {
            let probe = await CloudSyncManager.shared.probeRemoteConfig()
            guard probe.exists else { return }
            guard !wantsCloudSync else { return }

            if let updatedAt = probe.updatedAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
                let date = Date(timeIntervalSince1970: updatedAt)
                remoteConfigUpdatedAtText = String.localizedStringWithFormat(
                    NSLocalizedString("last updated %@", comment: "Remote config update timestamp"),
                    formatter.localizedString(for: date, relativeTo: Date())
                )
            } else {
                remoteConfigUpdatedAtText = nil
            }

            showRemoteConfigPrompt = true
        }
    }

    @MainActor
    private func adoptRemoteICloudSetup() async {
        guard !isAdoptingRemoteConfig else { return }
        isAdoptingRemoteConfig = true
        defer { isAdoptingRemoteConfig = false }

        wantsCloudSync = true

        filterManager.showingApplyProgressSheet = true
        CloudSyncManager.shared.setEnabled(true, startSync: false)

        let applied = await CloudSyncManager.shared.downloadAndApplyLatestRemoteConfig(
            trigger: "Onboarding-AdoptRemote"
        )

        guard applied else { return }
        setHasCompletedOnboarding(true)
        dismiss()
    }

    private func updateRegionalRecommendations(for languages: Set<String>) {
        guard !filterManager.filterLists.isEmpty else { return }
        guard !languages.isEmpty else {
            recommendedRegionalFilters = []
            optionalRegionalFilters = []
            if !hasManuallyEditedRegionalSelection {
                selectedRegionalFilters.removeAll()
            }
            regionInfoMessage = String(localized: "You can always add regional filters later from Settings.")
            return
        }

        let foreignFilters = filterManager.filterLists.filter { $0.category == .foreign }
        let matchingFilters = foreignFilters.compactMap { filter -> FilterList? in
            let filterLanguages = resolvedLanguages(for: filter)
            guard !filterLanguages.isEmpty && !filterLanguages.isDisjoint(with: languages) else { return nil }
            return filter
        }

        guard !matchingFilters.isEmpty else {
            recommendedRegionalFilters = []
            optionalRegionalFilters = []
            if !hasManuallyEditedRegionalSelection {
                selectedRegionalFilters.removeAll()
            }
            regionInfoMessage = nil
            return
        }

        let primary = matchingFilters.filter { (resolvedTrustLevel(for: $0) ?? "").lowercased() != "low" }
            .sorted { $0.name < $1.name }
        let secondary = matchingFilters.filter { (resolvedTrustLevel(for: $0) ?? "").lowercased() == "low" }
            .sorted { $0.name < $1.name }

        recommendedRegionalFilters = primary
        optionalRegionalFilters = secondary

        let matchingIDs = Set(matchingFilters.map { $0.id })
        if hasManuallyEditedRegionalSelection {
            selectedRegionalFilters = selectedRegionalFilters.intersection(matchingIDs)
        } else if !primary.isEmpty {
            selectedRegionalFilters = Set(primary.map { $0.id })
        } else {
            selectedRegionalFilters.removeAll()
        }

        if optionalRegionalFilters.isEmpty {
            isCommunityExpanded = false
        } else if recommendedRegionalFilters.isEmpty || optionalRegionalFilters.contains(where: { selectedRegionalFilters.contains($0.id) }) {
            isCommunityExpanded = true
        }

        if !primary.isEmpty {
            regionInfoMessage = nil
        } else {
            regionInfoMessage = String(localized: "Only community-maintained lists available. Enable them if you're comfortable.")
        }
    }

    private var cloudSyncCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("iCloud Sync")
                    .font(.headline)
            } icon: {
                Image(systemName: "icloud")
                    .foregroundStyle(.blue)
            }

            Toggle("Sync across devices", isOn: $wantsCloudSync)
                .toggleStyle(.switch)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

#if os(iOS)
    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Reminders")
                    .font(.headline)
            } icon: {
                Image(systemName: "bell.badge")
                    .foregroundStyle(.yellow)
            }

            Toggle("Notify me", isOn: $wantsReminderNotifications)
                .toggleStyle(.switch)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @MainActor
    private func requestNotificationPermissionIfNeeded() async {
        guard wantsReminderNotifications else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                let metadata: [String: String] = [
                    "granted": granted ? "true" : "false"
                ]
                await ConcurrentLogManager.shared.info(.startup, "Requested notification permission during onboarding", metadata: metadata)
            } catch {
                await ConcurrentLogManager.shared.error(.startup, "Failed to request notification permission", metadata: ["error": error.localizedDescription])
            }
        case .denied, .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            break
        }
    }
#endif

    private func resolvedLanguages(for filter: FilterList) -> Set<String> {
        if !filter.languages.isEmpty {
            return Set(filter.languages.map { $0.lowercased() })
        }
        if let canonical = foreignFilterMetadata(for: filter.url.absoluteString), !canonical.languages.isEmpty {
            return Set(canonical.languages.map { $0.lowercased() })
        }
        if let extracted = extractMetadata(from: filter.description, prefix: "Languages:") {
            return Set(extracted.map { $0.lowercased() })
        }
        return []
    }

    private func resolvedTrustLevel(for filter: FilterList) -> String? {
        if let trust = filter.trustLevel, !trust.isEmpty { return trust }
        if let canonical = foreignFilterMetadata(for: filter.url.absoluteString), let trust = canonical.trustLevel, !trust.isEmpty {
            return trust
        }
        if let extracted = extractMetadata(from: filter.description, prefix: "Trust:")?.first {
            return extracted.lowercased()
        }
        return nil
    }

    private func extractMetadata(from description: String, prefix: String) -> [String]? {
        let lines = description.components(separatedBy: "\n")
        guard let line = lines.first(where: { $0.localizedCaseInsensitiveContains(prefix) }) else { return nil }
        guard let range = line.range(of: prefix, options: [.caseInsensitive]) else { return nil }
        let values = line[range.upperBound...]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }
}
