import SwiftUI
import wBlockCoreService
#if os(iOS)
import UserNotifications
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
    @State private var isApplying: Bool = false
    @State private var applyProgress: Float = 0.0
    @State private var selectedCountryCode: String
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

    let filterManager: AppFilterManager
    
    private static let selectedCountryDefaultsKey = "onboardingSelectedCountryCode"
    #if os(iOS)
    private static let reminderPreferenceKey = "onboardingWantsReminderNotifications"
    #endif
    private static let cloudSyncEnabledDefaultsKey = "cloudSyncEnabled"
    private static let fallbackLocale = Locale(identifier: "en_US")
    private static let manualCountryLanguageOverrides: [String: [String]] = [
        // North America
        "US": ["en"],
        "CA": ["en", "fr"],
        "MX": ["es"],
        "PR": ["es", "en"],
        "DO": ["es"],
        "GT": ["es"],
        "HN": ["es"],
        "NI": ["es"],
        "CR": ["es"],
        "PA": ["es"],
        "CU": ["es"],
        "SV": ["es"],
        // South America
        "AR": ["es"],
        "CL": ["es"],
        "CO": ["es"],
        "PE": ["es"],
        "VE": ["es"],
        "EC": ["es"],
        "BO": ["es", "qu"],
        "PY": ["es", "gn"],
        "UY": ["es"],
        "BR": ["pt"],
        // Europe
        "GB": ["en"],
        "IE": ["en"],
        "FR": ["fr"],
        "BE": ["fr", "nl", "de"],
        "LU": ["fr", "de"],
        "DE": ["de"],
        "AT": ["de"],
        "CH": ["de", "fr", "it"],
        "IT": ["it"],
        "ES": ["es", "ca", "eu", "gl"],
        "PT": ["pt"],
        "NL": ["nl"],
        "DK": ["da"],
        "NO": ["no"],
        "SE": ["sv"],
        "FI": ["fi", "sv"],
        "IS": ["is"],
        "EE": ["et"],
        "LV": ["lv"],
        "LT": ["lt"],
        "PL": ["pl"],
        "CZ": ["cs"],
        "SK": ["sk"],
        "HU": ["hu"],
        "SI": ["sl"],
        "HR": ["hr"],
        "RS": ["sr"],
        "BA": ["bs", "hr", "sr"],
        "ME": ["sr"],
        "MK": ["mk"],
        "BG": ["bg"],
        "RO": ["ro"],
        "MD": ["ro"],
        "GR": ["el"],
        "CY": ["el", "tr"],
        "UA": ["uk"],
        "BY": ["be", "ru"],
        "RU": ["ru"],
        // Middle East & Africa
        "IL": ["he"],
        "TR": ["tr"],
        "IR": ["fa"],
        "AE": ["ar"],
        "SA": ["ar"],
        "MA": ["ar"],
        "TN": ["ar"],
        "DZ": ["ar"],
        "EG": ["ar"],
        "QA": ["ar"],
        "KW": ["ar"],
        "BH": ["ar"],
        "OM": ["ar"],
        "JO": ["ar"],
        "LB": ["ar"],
        // Asia-Pacific
        "CN": ["zh"],
        "TW": ["zh"],
        "HK": ["zh"],
        "MO": ["zh"],
        "SG": ["zh", "en"],
        "JP": ["ja"],
        "KR": ["ko"],
        "TH": ["th"],
        "VN": ["vi"],
        "PH": ["tl", "en"],
        "ID": ["id"],
        "MY": ["ms", "en"],
        "IN": ["hi", "en"],
        "PK": ["ur", "en"],
        "NP": ["ne"],
        "LK": ["si", "ta"],
        "BD": ["bn"],
        "KH": ["km"],
        "LA": ["lo"],
        "MM": ["my"],
        "MN": ["mn"],
        "KZ": ["kk", "ru"],
        "KG": ["ky", "ru"],
        "TJ": ["tg", "ru"],
        "UZ": ["uz"],
        "AZ": ["az"],
        // Oceania
        "AU": ["en"],
        "NZ": ["en"],
        "FJ": ["en"],
        "PG": ["en"],
        // Africa (selected)
        "ZA": ["en", "af"],
        "NG": ["en"],
        "KE": ["en", "sw"],
        "UG": ["en", "sw"],
        "TZ": ["sw", "en"],
        "GH": ["en"],
        "CM": ["fr", "en"],
        "SN": ["fr"],
        "CI": ["fr"],
        "BJ": ["fr"],
        "BF": ["fr"],
        "NE": ["fr"],
        "ML": ["fr"],
        "GN": ["fr"],
        "RW": ["rw", "en", "fr"],
        "LY": ["ar"],
        "ET": ["am"],
        "SD": ["ar"],
    ]

    // Computed lazily on background queue to avoid main thread freeze
    private static let fallbackLanguagesByCountry: [String: Set<String>] = buildLanguagesByCountry()
    private static let countryOptions: [CountryOption] = {
        let current = Locale.current
        return Locale.isoRegionCodes.compactMap { code -> CountryOption? in
            let localizedName = current.localizedString(forRegionCode: code) ?? fallbackLocale.localizedString(forRegionCode: code)
            guard let name = localizedName else { return nil }
            return CountryOption(code: code, name: name)
        }
        .sorted { $0.name < $1.name }
    }()

    struct CountryOption: Identifiable {
        let code: String
        let name: String
        var id: String { code }
    }

    private static func buildLanguagesByCountry() -> [String: Set<String>] {
        let languageKey = NSLocale.Key.languageCode.rawValue
        let countryKey = NSLocale.Key.countryCode.rawValue
        var mapping: [String: Set<String>] = [:]
        for identifier in Locale.availableIdentifiers {
            let components = Locale.components(fromIdentifier: identifier)
            guard let country = components[countryKey]?.uppercased(),
                  !country.isEmpty,
                  let language = components[languageKey]?.lowercased(),
                  !language.isEmpty else { continue }
            mapping[country, default: []].insert(language)
        }
        return mapping
    }

    // Helper to look up canonical filter metadata from filterManager instead of loading separately
    private func foreignFilterMetadata(for url: String) -> FilterList? {
        filterManager.filterLists.first { $0.url.absoluteString == url && $0.category == .foreign }
    }

    init(filterManager: AppFilterManager) {
        self.filterManager = filterManager
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
        self.sharedDefaults = defaults
        let storedCountry = defaults.string(forKey: Self.selectedCountryDefaultsKey) ?? ""
        let localeCountry = Locale.current.regionCode ?? ""
        let sanitizedStored = storedCountry.uppercased()
        let sanitizedLocale = localeCountry.uppercased()
        _dataManager = StateObject(wrappedValue: ProtobufDataManager.shared)
        let initialCandidate = sanitizedStored.isEmpty ? sanitizedLocale : sanitizedStored
        let resolvedCountry = Self.countryOptions.contains(where: { $0.code == initialCandidate }) ? initialCandidate : ""
        _selectedCountryCode = State(initialValue: resolvedCountry)
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
            if isApplying {
                OnboardingDownloadView(
                    progress: applyProgress,
                    isSyncingFromICloud: isAdoptingRemoteConfig
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                onboardingHeader

                ScrollView {
                    stepContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }

                onboardingFooter
            }
        }
        .padding()
    #if os(macOS)
        .frame(minWidth: 520, maxWidth: 680, minHeight: 560, maxHeight: 760)
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
            updateRegionalRecommendations(for: selectedCountryCode)
            probeForExistingICloudSetupIfNeeded()
            userScriptManager.prefetchDefaultUserScriptMetadataIfNeeded()
            seedSelectedUserscriptsIfNeeded()
        }
        .task {
            await userScriptManager.waitUntilReady()
            seedSelectedUserscriptsIfNeeded()
            userScriptManager.prefetchDefaultUserScriptMetadataIfNeeded()
        }
        .onChange(of: selectedCountryCode) { newValue in
            let sanitized = newValue.uppercased()
            sharedDefaults.set(sanitized, forKey: Self.selectedCountryDefaultsKey)
            hasManuallyEditedRegionalSelection = false
            updateRegionalRecommendations(for: sanitized)
        }
        .onChange(of: filterManager.filterLists) { _ in
            updateRegionalRecommendations(for: selectedCountryCode)
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

    struct OnboardingDownloadView: View {
        let progress: Float
        let isSyncingFromICloud: Bool
        var body: some View {
            VStack(spacing: 24) {
                if progress > 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 300)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                VStack(spacing: 4) {
                    Text(primaryText)
                        .multilineTextAlignment(.center)
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }

        private var primaryText: String {
            isSyncingFromICloud
                ? String(localized: "Syncing iCloud configuration…")
                : String(localized: "Downloading and applying filter lists…")
        }

        private var secondaryText: String {
            String(localized: "This may take a while")
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

            Button(step == .sync ? "Apply & Finish" : "Next") {
                if step == .sync {
                    Task {
                        await applySettings()
                    }
                } else {
                    advanceToNextStep()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                step == .protection
                    && selectedBlockingLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .keyboardShortcut(.defaultAction)
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

    private var regionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Country or region", selection: $selectedCountryCode) {
                    Text("Skip for now").tag("")
                    ForEach(Self.countryOptions) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(14)
            .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)

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

        if let fallback = userscriptDescriptionFallbacksByName[script.name.lowercased()] {
            return fallback
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
        sharedDefaults.set(selectedCountryCode.uppercased(), forKey: Self.selectedCountryDefaultsKey)
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

        // 3. Download and install enabled filter lists
        isApplying = true
        let enabledFilters = filterManager.filterLists.filter { $0.isSelected }
        Task { @MainActor in
            await filterManager.downloadAndApplyFilters(filters: enabledFilters, progress: { progress in
                applyProgress = progress
            })
            isApplying = false
            CloudSyncManager.shared.setEnabled(wantsCloudSync)
            setHasCompletedOnboarding(true)
#if os(iOS)
            await requestNotificationPermissionIfNeeded()
#endif
            dismiss()
            filterManager.showingApplyProgressSheet = true
        }
    }

    private func probeForExistingICloudSetupIfNeeded() {
        guard !hasProbedRemoteConfig else { return }
        guard !hasCompletedOnboarding else { return }
        guard step == .protection else { return }
        guard !isApplying else { return }

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
        applyProgress = 0
        isApplying = true

        filterManager.showingApplyProgressSheet = true
        CloudSyncManager.shared.setEnabled(true, startSync: false)

        let applied = await CloudSyncManager.shared.downloadAndApplyLatestRemoteConfig(
            trigger: "Onboarding-AdoptRemote"
        )

        isApplying = false

        guard applied else { return }
        setHasCompletedOnboarding(true)
        dismiss()
    }

    private func updateRegionalRecommendations(for countryCode: String) {
        guard !filterManager.filterLists.isEmpty else { return }
        let normalizedCode = countryCode.uppercased()
        guard !normalizedCode.isEmpty else {
            recommendedRegionalFilters = []
            optionalRegionalFilters = []
            if !hasManuallyEditedRegionalSelection {
                selectedRegionalFilters.removeAll()
            }
            regionInfoMessage = String(localized: "You can always add regional filters later from Settings.")
            return
        }

        let languageMatches = languagesForCountry(normalizedCode)
        guard !languageMatches.isEmpty else {
            recommendedRegionalFilters = []
            optionalRegionalFilters = []
            if !hasManuallyEditedRegionalSelection {
                selectedRegionalFilters.removeAll()
            }
            regionInfoMessage = String.localizedStringWithFormat(
                NSLocalizedString("We don't have language data for %@. Try enabling filters manually if you see regional ads.", comment: "Regional recommendation hint"),
                countryName(for: normalizedCode)
            )
            return
        }

        let foreignFilters = filterManager.filterLists.filter { $0.category == .foreign }
        let matchingFilters = foreignFilters.compactMap { filter -> FilterList? in
            let filterLanguages = resolvedLanguages(for: filter)
            guard !filterLanguages.isEmpty && !filterLanguages.isDisjoint(with: languageMatches) else { return nil }
            return filter
        }

        guard !matchingFilters.isEmpty else {
            recommendedRegionalFilters = []
            optionalRegionalFilters = []
            if !hasManuallyEditedRegionalSelection {
                selectedRegionalFilters.removeAll()
            }
            regionInfoMessage = String.localizedStringWithFormat(
                NSLocalizedString("We don't have regional filters for %@.", comment: "Regional recommendation hint"),
                countryName(for: normalizedCode)
            )
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
            regionInfoMessage = String.localizedStringWithFormat(
                NSLocalizedString("Only community-maintained lists are available for %@. Enable them if you're comfortable.", comment: "Regional recommendation hint"),
                countryName(for: normalizedCode)
            )
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

    private func languagesForCountry(_ code: String) -> Set<String> {
        let normalized = code.uppercased()
        if let manual = Self.manualCountryLanguageOverrides[normalized] {
            return Set(manual.map { $0.lowercased() })
        }
        let baseLanguages = Self.fallbackLanguagesByCountry[normalized] ?? []
        return Set(baseLanguages.map { $0.lowercased() })
    }

    private func countryName(for code: String) -> String {
        let normalized = code.uppercased()
        let current = Locale.current.localizedString(forRegionCode: normalized)
        return current ?? Self.fallbackLocale.localizedString(forRegionCode: normalized) ?? normalized
    }

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
