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

    @StateObject private var dataManager: ProtobufDataManager
    
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
    @State private var selectedCountryCode: String
    @State private var selectedRegionalFilters: Set<UUID> = []
    @State private var recommendedRegionalFilters: [FilterList] = []
    @State private var optionalRegionalFilters: [FilterList] = []
    @State private var regionInfoMessage: String?
    @State private var hasManuallyEditedRegionalSelection = false
    @State private var isCommunityExpanded = false
#if os(iOS)
    @State private var wantsReminderNotifications: Bool = true
#endif

    let filterManager: AppFilterManager
    
    private static let selectedCountryDefaultsKey = "onboardingSelectedCountryCode"
    #if os(iOS)
    private static let reminderPreferenceKey = "onboardingWantsReminderNotifications"
    #endif
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

    private static let fallbackLanguagesByCountry: [String: Set<String>] = buildLanguagesByCountry()
    private static let foreignFilterMetadataByURL: [String: FilterList] = buildForeignFilterMetadata()
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

    private static func buildForeignFilterMetadata() -> [String: FilterList] {
        let loader = FilterListLoader(logManager: ConcurrentLogManager.shared)
        return Dictionary(uniqueKeysWithValues: loader.loadFilterLists()
            .filter { $0.category == .foreign }
            .map { ($0.url.absoluteString, $0) })
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
#if os(iOS)
    let storedReminderPreference = defaults.object(forKey: Self.reminderPreferenceKey) as? Bool ?? true
    _wantsReminderNotifications = State(initialValue: storedReminderPreference)
#endif
    }
    private let sharedDefaults: UserDefaults
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
        let candidates = [
            "Bypass Paywalls Filter",
            "Bypass Paywalls",
            "Bypass Paywalls (Custom)"
        ]
        return filterManager.filterLists.first(where: { filter in
            candidates.contains(where: { filter.name.localizedCaseInsensitiveContains($0) })
        })?.name
    }

    private var selectedCountryDescription: String {
        guard !selectedCountryCode.isEmpty else { return "Not selected" }
        return countryName(for: selectedCountryCode)
    }

    private var selectedRegionalFilterNames: [String] {
        let selection = selectedRegionalFilters
        return filterManager.filterLists
            .filter { selection.contains($0.id) }
            .map { $0.name }
            .sorted()
    }

    var body: some View {
        VStack {
            if isApplying {
                OnboardingDownloadView(progress: applyProgress)
            } else {
                if step == 0 {
                    blockingLevelStep
                } else if step == 1 {
                    regionStep
                } else if step == 2 {
                    userscriptStep
                } else if step == 3 {
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
    .onAppear {
        updateRegionalRecommendations(for: selectedCountryCode)
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
                            .symbolRenderingMode(.hierarchical)
                        VStack(alignment: .leading) {
                            Text(level.rawValue)
                                .font(.headline)
                            Text(blockingLevelDescription(level))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
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
        }
    }
    
    var regionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Regional filters")
                        .font(.title2)
                        .bold()
                    Text("Tell us where you browse so we can enable the right regional filters.")
                        .font(.subheadline)

                    Picker("Country or region", selection: $selectedCountryCode) {
                        Text("Skip for now").tag("")
                        ForEach(Self.countryOptions) { option in
                            Text(option.name).tag(option.code)
                        }
                    }
                    .pickerStyle(.menu)

                    if let message = regionInfoMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !recommendedRegionalFilters.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recommended")
                                .font(.headline)
                            ForEach(recommendedRegionalFilters) { filter in
                                regionalToggle(for: filter, expandsCommunity: false)
                            }
                        }
                    }

                    if !optionalRegionalFilters.isEmpty {
                        DisclosureGroup(isExpanded: $isCommunityExpanded) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("These lists are community-maintained. Enable them if you still see regional ads.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(optionalRegionalFilters) { filter in
                                    regionalToggle(for: filter, expandsCommunity: false)
                                }
                            }
                            .padding(.leading, 4)
                        } label: {
                            Text("Community options")
                                .font(.headline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }

            HStack {
                Button("Back") { step -= 1 }
                Spacer()
                Button("Next") { step += 1 }
            }
        }
    }

    private func regionalToggle(for filter: FilterList, expandsCommunity: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(filter.name)
                    .font(.headline)
                if !filter.description.isEmpty {
                    Text(filter.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                let languageSummary = resolvedLanguages(for: filter).map { $0.uppercased() }.sorted().joined(separator: ", ")
                if !languageSummary.isEmpty {
                    Text("Languages: \(languageSummary)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let trust = resolvedTrustLevel(for: filter) {
                    Text("Trust: \(trust.capitalized)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { selectedRegionalFilters.contains(filter.id) },
                set: { isOn in
                    if isOn {
                        selectedRegionalFilters.insert(filter.id)
                    } else {
                        selectedRegionalFilters.remove(filter.id)
                    }
                    hasManuallyEditedRegionalSelection = true
                    if expandsCommunity {
                        isCommunityExpanded = true
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
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
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Show a note if Bypass Paywalls userscript is selected
            if let bypassScript = bypassPaywallsScript, selectedUserscripts.contains(bypassScript.id), let filterName = bypassPaywallsFilterName {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.title3)
                        .symbolRenderingMode(.multicolor)
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
            Text("Country: \(selectedCountryDescription)")
            Text("Regional filters: \(selectedRegionalFilterNames.isEmpty ? "None" : selectedRegionalFilterNames.joined(separator: ", "))")
            Text("Userscripts: \(selectedUserscripts.isEmpty ? "None" : selectedUserscripts.compactMap { id in defaultUserScripts.first(where: { $0.id == id })?.name }.joined(separator: ", "))")

#if os(iOS)
            reminderCard
#endif

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
                "AdGuard Cookie Notices",
                "AdGuard Popups",
                "AdGuard Mobile App Banners",
                "AdGuard Other Annoyances",
                "AdGuard Widgets",
                "EasyPrivacy",
                "AdGuard URL Tracking Filter",
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
        await UserScriptManager.shared.setEnabledScripts(withIDs: selectedScriptIDs)
        
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
#if os(iOS)
            await requestNotificationPermissionIfNeeded()
#endif
            dismiss()
            filterManager.showingApplyProgressSheet = true
        }
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
            regionInfoMessage = "You can always add regional filters later from Settings."
            return
        }

        let languageMatches = languagesForCountry(normalizedCode)
        guard !languageMatches.isEmpty else {
            recommendedRegionalFilters = []
            optionalRegionalFilters = []
            if !hasManuallyEditedRegionalSelection {
                selectedRegionalFilters.removeAll()
            }
            regionInfoMessage = "We don't have language data for \(countryName(for: normalizedCode)). Try enabling filters manually if you see regional ads."
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
            regionInfoMessage = "We don't have regional filters for \(countryName(for: normalizedCode))."
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
            regionInfoMessage = "Only community-maintained lists are available for \(countryName(for: normalizedCode)). Enable them if you're comfortable."
        }
    }

#if os(iOS)
    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reminder notifications")
                        .font(.headline)
                    Text("If you close wBlock with unapplied changes, we'll send a gentle nudge so nothing gets forgotten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "bell.badge")
                    .foregroundStyle(.yellow)
            }

            Toggle("Send me reminders about unapplied changes", isOn: $wantsReminderNotifications)
                .toggleStyle(.switch)
        }
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
        if let canonical = Self.foreignFilterMetadataByURL[filter.url.absoluteString], !canonical.languages.isEmpty {
            return Set(canonical.languages.map { $0.lowercased() })
        }
        if let extracted = extractMetadata(from: filter.description, prefix: "Languages:") {
            return Set(extracted.map { $0.lowercased() })
        }
        return []
    }

    private func resolvedTrustLevel(for filter: FilterList) -> String? {
        if let trust = filter.trustLevel, !trust.isEmpty { return trust }
        if let canonical = Self.foreignFilterMetadataByURL[filter.url.absoluteString], let trust = canonical.trustLevel, !trust.isEmpty {
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
