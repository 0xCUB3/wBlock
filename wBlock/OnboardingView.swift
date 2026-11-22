import SwiftUI
import UniformTypeIdentifiers
import wBlockCoreService
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OnboardingView: View {
    enum OnboardingStep: Int, CaseIterable, Identifiable {
        case welcome
        case quickReview
        case regional
        case annoyances
        case userscripts
        case sync
        case setup

        var id: Int { rawValue }
    }

    @StateObject private var dataManager: ProtobufDataManager
    @StateObject private var userScriptManager = UserScriptManager.shared
    @StateObject private var setupHealth = SafariHealthMonitor()
    
    private var hasCompletedOnboarding: Bool {
        dataManager.hasCompletedOnboarding
    }

    @State private var chosenMode: AppMode = .basic
    @State private var selectedUserscripts: Set<String> = []
    @State private var step: OnboardingStep = .welcome
    @State private var selectedLanguages: Set<String>
    @State private var selectedRegionalFilters: Set<UUID> = []
    @State private var regionalFilters: [FilterList] = []
    @State private var hasManuallyEditedRegionalSelection = false
    @State private var selectedAnnoyances = AnnoyanceChoice.recommended
    @State private var wantsCloudSync: Bool = false
    @State private var hasProbedRemoteConfig: Bool = false
    @State private var remoteConfigUpdatedAtText: String?
    @State private var showRemoteConfigPrompt: Bool = false
    /// Start Fresh at the iCloud prompt: turning sync on replaces the iCloud setup.
    @State private var startsFreshInICloud = false
    @State private var isAdoptingRemoteConfig: Bool = false
    @State private var hasSeededUserscriptSelection = false
    @State private var manuallySelectedUserscripts: Set<String> = []
    @State private var manuallyDeselectedBaselineUserscripts: Set<String> = []
    @State private var hasEnabledContentBlockers = false
    @State private var hasEnabledAdvanced = false
    @State private var detectedScriptsExtensionEnabled: Bool?
    @State private var isRefreshingScriptsExtensionState = false
    @State private var detectedContentBlockerStates: [SafariExtensionSetupSupport.ContentBlockerSlotState] = []
    @State private var isRefreshingContentBlockers = false
    @State private var showingBackupImporter = false
    @State private var showingRestoreBackupConfirmation = false
    @State private var pendingBackup: WBlockBackup?
    /// A restored backup already carries the user's choices, so it only needs the Safari setup step.
    /// Stored so relaunching mid-setup can't send the user through choices that would overwrite it.
    @AppStorage("onboardingRestoredFromBackup") private var restoredFromBackup = false
    @State private var backupRestoreError: String?
    @State private var isApplyingSettings = false

    @ObservedObject var filterManager: AppFilterManager
    
    static let selectedLanguagesDefaultsKey = "onboardingSelectedLanguages"
    private static let cloudSyncEnabledDefaultsKey = "cloudSyncEnabled"
    private static let englishLanguageCode = "en"
    private static let otherLanguagesCode = "other"

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
                Locale(identifier: $0).languageCode.map(RegionalLanguageOption.canonicalCode)
            }
            // Languages without a regional list or recommendation fallback stay Other (#935).
            let covered = Set(RegionalLanguageOption.fromForeignFilters(filterManager.filterLists).map(\.code))
            _selectedLanguages = State(initialValue: Set(systemLangs.map {
                $0 == Self.englishLanguageCode || covered.contains($0) ? $0 : Self.otherLanguagesCode
            }))
        }

        _selectedRegionalFilters = State(initialValue: [])
        _regionalFilters = State(initialValue: [])
        _wantsCloudSync = State(initialValue: defaults.bool(forKey: Self.cloudSyncEnabledDefaultsKey))
    }
    private let sharedDefaults: UserDefaults
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    struct OnboardingUserScriptItem: Identifiable {
        let id: String
        let name: String
        let description: String
        let isBaselineEnabledByDefault: Bool
        let languageCodes: [String]
        let isBeta: Bool
    }

    private let userscriptDescriptionFallbacksByName: [String: String] = [
        "return youtube dislike":
            LocalizedStrings.text(
                "Shows dislike counts on YouTube again, using data from the Return YouTube Dislike community.",
                comment: "Default userscript description"
            ),
        "bypass paywalls clean":
            LocalizedStrings.text(
                "Gets past paywalls on English-language news sites, and some in other languages.",
                comment: "Default userscript description"
            )
    ]

    private var defaultUserScripts: [OnboardingUserScriptItem] {
        userScriptManager.userScripts
            .filter(userScriptManager.isDefaultUserScript)
            .filter { !userScriptManager.isBeta(for: $0) }
            .filter { script in
                let languages = userScriptManager.builtInLanguages(for: script)
                return languages.isEmpty || !Set(languages).isDisjoint(with: selectedLanguages)
            }
            .map { script in
                OnboardingUserScriptItem(
                    id: script.id.uuidString,
                    name: script.localizedDisplayName,
                    description: resolvedUserscriptDescription(for: script),
                    isBaselineEnabledByDefault: isBaselineUserscriptEnabledByDefault(script),
                    languageCodes: userScriptManager.builtInLanguages(for: script),
                    isBeta: userScriptManager.isBeta(for: script)
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
        filterManager.filterLists.first(where: BasicBundle.isPairedBypassPaywallsFilter)?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            onboardingHeader
                .padding(.horizontal)

            // Padded inside the scroll view, which clipped the sides of the
            // setup box's glass shadow into bands above and below it (#1099).
            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 2)
            }

            // Outside the scroll view so it stays in sight however many
            // languages and lists the step shows (#940).
            if step == .regional {
                Label("English and languages without a regional list are covered by the default filters.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
            }

            onboardingFooter
                .padding(.horizontal)
        }
        .padding(.vertical)
        .interactiveDismissDisabled(!hasCompletedOnboarding)
    #if os(macOS)
        // One height for every step: the sheet sized itself to the content and
        // grew with each regional list, though the step already scrolls (#1028).
        .frame(minWidth: 440, maxWidth: 540)
        .frame(height: 680)
        .environment(\.controlActiveState, .active)
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
            if restoredFromBackup { step = .setup }
            syncStoredCriticalSetupState()
            updateRegionalRecommendations(for: selectedLanguages)
            probeForExistingICloudSetupIfNeeded()
            userScriptManager.prefetchDefaultUserScriptMetadataIfNeeded()
            seedSelectedUserscriptsIfNeeded()
            syncBaselineUserscriptSelection()
            setupHealth.startIfNeeded()
        }
        .task {
            await userScriptManager.waitUntilReady()
            seedSelectedUserscriptsIfNeeded()
            syncBaselineUserscriptSelection()
            userScriptManager.prefetchDefaultUserScriptMetadataIfNeeded()
            await refreshScriptsExtensionState(retryingWhenDisabled: true)
            await refreshContentBlockerStates()
            await setupHealth.refreshNow()
        }
        .onChangeCompat(of: scenePhase) { _, newValue in
            setupHealth.setSceneActive(newValue == .active)
            guard newValue == .active else { return }
            Task {
                await refreshScriptsExtensionState(retryingWhenDisabled: true)
                await refreshContentBlockerStates()
                await setupHealth.refreshNow()
            }
        }
        .onChangeCompat(of: setupHealth.blockerSlots.map(\.isEnabled)) { _, _ in
            guard !setupHealth.blockerSlots.isEmpty else { return }
            detectedContentBlockerStates = setupHealth.blockerSlots
            if setupHealth.blockerSlots.allSatisfy(\.isEnabled) {
                hasEnabledContentBlockers = true
            }
        }
        .onChangeCompat(of: setupHealth.scriptsExtensionEnabled) { _, enabled in
            guard let enabled else { return }
            detectedScriptsExtensionEnabled = enabled
            if enabled { hasEnabledAdvanced = true }
        }
        .onChangeCompat(of: wantsCloudSync) { _, wantsSync in
            if wantsSync { probeForExistingICloudSetupIfNeeded() }
        }
        .onChangeCompat(of: selectedLanguages) { _, newValue in
            hasManuallyEditedRegionalSelection = false
            updateRegionalRecommendations(for: newValue)
            syncBaselineUserscriptSelection()
        }
        .onChangeCompat(of: filterManager.filterLists) { _, _ in
            updateRegionalRecommendations(for: selectedLanguages)
        }
        .onChangeCompat(of: userScriptManager.userScripts) { _, _ in
            seedSelectedUserscriptsIfNeeded()
            syncBaselineUserscriptSelection()
        }
        .fileImporter(
            isPresented: $showingBackupImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleBackupImportResult(result)
        }
        .alert("Restore Settings?", isPresented: $showingRestoreBackupConfirmation, presenting: pendingBackup) { _ in
            Button("Cancel", role: .cancel) { pendingBackup = nil }
            Button("Restore", role: .destructive) {
                Task { await performBackupRestore() }
            }
        } message: { backup in
            Text(backup.restoreConfirmation)
        }
        .alert("Backup", isPresented: Binding(
            get: { backupRestoreError != nil },
            set: { if !$0 { backupRestoreError = nil } }
        )) {
            Button("OK", role: .cancel) { backupRestoreError = nil }
        } message: {
            Text(backupRestoreError ?? "")
        }
        .alert("Use existing iCloud setup?", isPresented: $showRemoteConfigPrompt) {
            Button("Use iCloud Setup") {
                Task { await adoptRemoteICloudSetup() }
            }
            Button("Start Fresh", role: .cancel) { startsFreshInICloud = true }
        } message: {
            if let remoteConfigUpdatedAtText {
                Text(
                    LocalizedStrings.format(
                        "An existing wBlock configuration was found in iCloud (%@). Would you like to adopt it, or start fresh and upload your current setup?",
                        comment: "Onboarding iCloud setup adoption prompt",
                        remoteConfigUpdatedAtText
                    )
                )
            } else {
                Text("An existing wBlock configuration was found in iCloud. Would you like to adopt it, or start fresh and upload your current setup?")
            }
        }
    }

    private var activeOnboardingSteps: [OnboardingStep] {
        switch chosenMode {
        case .basic:
            [.welcome, .quickReview, .setup]
        case .advanced:
            [.welcome, .regional, .annoyances, .userscripts, .sync, .setup]
        }
    }

    private var currentStepIndex: Int {
        activeOnboardingSteps.firstIndex(of: step) ?? 0
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up wBlock")
                        .font(.title2.bold())
                }

                Spacer()

                stepCounterText
            }

        }
    }

    @ViewBuilder
    private var stepCounterText: some View {
        let label = Text(
            LocalizedStrings.format(
                "%d/%d",
                comment: "Onboarding step counter",
                currentStepIndex + 1,
                activeOnboardingSteps.count
            )
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)

        if #available(iOS 16.0, macOS 13.0, *) {
            label
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: activeOnboardingSteps.count)
                .animation(.easeInOut(duration: 0.2), value: currentStepIndex)
        } else {
            label
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .quickReview:
            quickReviewStep
        case .regional:
            regionalStep
        case .annoyances:
            annoyancesStep
        case .userscripts:
            userscriptsStep
        case .sync:
            syncStep
        case .setup:
            setupStep
        }
    }

    private var onboardingFooter: some View {
        HStack(spacing: 12) {
            if step == .welcome {
                Button(String(localized: "Restore from backup…")) {
                    showingBackupImporter = true
                }
                .glassButtonStyleCompat()
            }
            if step != .welcome && !restoredFromBackup {
                Button("Back") {
                    retreatToPreviousStep()
                }
                .glassButtonStyleCompat()
            }

            Spacer()

            Button(step == .welcome ? "Get Started" : (step == .setup ? "Apply & Finish" : "Next")) {
                if step == .setup {
                    Task {
                        await applySettings()
                    }
                } else {
                    if step == .welcome {
                        chosenMode = .basic
                    }
                    advanceToNextStep()
                }
            }
            .glassButtonStyleCompat(prominent: true)
            .disabled(footerButtonDisabled)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var footerButtonDisabled: Bool {
        switch step {
        case .welcome:
            return false
        case .regional:
            return !hasLanguagePickerSelection
        case .setup:
            return isApplyingSettings || !hasEnabledContentBlockers || !hasEnabledAdvanced
        default:
            return false
        }
    }

    private func advanceToNextStep() {
        let steps = activeOnboardingSteps
        guard let currentIndex = steps.firstIndex(of: step), currentIndex < steps.index(before: steps.endIndex) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = steps[steps.index(after: currentIndex)]
        }
    }

    private func retreatToPreviousStep() {
        let steps = activeOnboardingSteps
        guard let currentIndex = steps.firstIndex(of: step), currentIndex > steps.startIndex else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = steps[steps.index(before: currentIndex)]
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            #if os(macOS)
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            #else
            Image("AppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            #endif

            VStack(spacing: 6) {
                Text("Welcome to wBlock!")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("wBlock sets up recommended blocking for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            ModeChooserCards {
                chosenMode = .advanced
                advanceToNextStep()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Basic mode step 2: single scroll page with sensible defaults preselected
    /// so Next is always enabled.
    private var quickReviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Here are your selected starting options (change later).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Detected languages
            VStack(alignment: .leading, spacing: 8) {
                Text("Languages")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    languagePicker
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            // Annoyances: primary everyday defaults only (3 on iOS, 2 on macOS), Cookie Notices preselected
            VStack(alignment: .leading, spacing: 8) {
                Text("Annoyances")
                    .font(.headline)
                let primaryAnnoyances = AnnoyanceChoice.basicPrimaryChoices()

                VStack(spacing: 0) {
                    ForEach(Array(primaryAnnoyances.enumerated()), id: \.element.id) { index, choice in
                        let isOn = selectedAnnoyances.contains(choice)
                        HStack(spacing: 12) {
                            IconBadge(
                                systemName: choice.symbolName,
                                tint: choice.tint,
                                isOn: isOn
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(LocalizedStringKey(choice.title))
                                        .font(.subheadline.weight(.medium))
                                    if choice == .cookies {
                                        Text("Recommended")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(choice.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Toggle("", isOn: Binding(
                                get: { isOn },
                                set: { enabled in
                                    if enabled { selectedAnnoyances.insert(choice) }
                                    else { selectedAnnoyances.remove(choice) }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .fixedSize()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        if index < primaryAnnoyances.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                Text("More options like social, chat, and AI are in Filters, though they can break some sites.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Featured non-beta extras (tinyShield remains silently enabled in baseline)
            let featuredExtras = basicOnboardingFeaturedExtras
            if !featuredExtras.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Extras")
                        .font(.headline)
                    SelectableRowGroup(data: featuredExtras) { item in
                        userscriptCard(for: item)
                    }
                }
            }

            // iCloud Sync
            if CloudSyncManager.shared.isCloudKitAvailable {
                cloudSyncCard
            }
        }
    }

    private var basicOnboardingFeaturedExtras: [OnboardingUserScriptItem] {
        userScriptManager.userScripts
            .filter { script in
                userScriptManager.builtInTier(for: script) == .featured
                    && !userScriptManager.isBeta(for: script)
            }
            .filter { script in
                let languages = userScriptManager.builtInLanguages(for: script)
                return languages.isEmpty || !Set(languages).isDisjoint(with: selectedLanguages)
            }
            .map { script in
                OnboardingUserScriptItem(
                    id: script.id.uuidString,
                    name: script.localizedDisplayName,
                    description: resolvedUserscriptDescription(for: script),
                    isBaselineEnabledByDefault: isBaselineUserscriptEnabledByDefault(script),
                    languageCodes: userScriptManager.builtInLanguages(for: script),
                    isBeta: userScriptManager.isBeta(for: script)
                )
            }
    }

    private var availableFilterLanguages: [RegionalLanguageOption] {
        RegionalLanguageOption.fromForeignFilters(filterManager.filterLists)
    }

    private var pinnedLanguagePickerOptions: [RegionalLanguageOption] {
        var options: [RegionalLanguageOption] = []
        if !availableFilterLanguages.contains(where: { $0.code == Self.englishLanguageCode }) {
            options.append(RegionalLanguageOption(code: Self.englishLanguageCode))
        }
        options.append(
            RegionalLanguageOption(code: Self.otherLanguagesCode, name: String(localized: "Other"))
        )
        return options
    }

    private var languagePickerOptions: [RegionalLanguageOption] {
        pinnedLanguagePickerOptions + availableFilterLanguages
    }

    private var hasLanguagePickerSelection: Bool {
        languagePickerOptions.contains { selectedLanguages.contains($0.code) }
    }

    private var selectedLanguagePickerOptions: [RegionalLanguageOption] {
        languagePickerOptions.filter { selectedLanguages.contains($0.code) }
    }

    private var languagePicker: some View {
        RegionalLanguagePickerView(
            selectedLanguages: $selectedLanguages,
            options: languagePickerOptions
        )
    }

    private var regionalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Select the languages you browse in. wBlock will automatically recommend matching regional filters and features.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            languagePicker

            // One flat list for the chosen languages (#935); each row names the
            // selected languages it covers (#940).
            if !regionalFilters.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizedStrings.text("Regional", comment: "Filter list category"))
                        .font(.headline)
                    SelectableRowGroup(data: ForeignFilterOrganizer.sortedFilters(regionalFilters)) { filter in
                        regionalToggle(for: filter)
                    }
                }
            }

        }
    }

    private var annoyancesStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose the annoyances to hide. You can change this later in Annoyances Info.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            AnnoyanceChoicePicker(selection: $selectedAnnoyances)
        }
    }

    private var userscriptsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Userscripts")
                .font(.title2.bold())
            Text("Select any userscripts you want to enable. These add extra features or fixes. You can always add more in the settings later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let general = defaultUserScripts.filter { $0.languageCodes.isEmpty }
            let localized = defaultUserScripts.filter { !$0.languageCodes.isEmpty }
            if !general.isEmpty {
                userscriptList(general)
            }
            ForEach(selectedLanguagePickerOptions) { language in
                let scripts = localized.filter { $0.languageCodes.contains(language.code) }
                if !scripts.isEmpty {
                    Text(language.nativeName)
                        .font(.headline)
                        .padding(.top, 2)
                    userscriptList(scripts)
                }
            }
        }
    }

    private func userscriptList(_ scripts: [OnboardingUserScriptItem]) -> some View {
        SelectableRowGroup(data: scripts) { userscriptCard(for: $0) }
    }

    private func regionalToggle(for filter: FilterList) -> some View {
        let isSelected = selectedRegionalFilters.contains(filter.id)

        let languages = filter.nativeLanguageNames(among: RegionalLanguageOption.expanding(selectedLanguages)).joined(separator: ", ")
        return SelectableRow(
            title: Text(filter.localizedDisplayName),
            caption: languages,
            subtitle: filter.localizedDisplayDescription,
            isSelected: isSelected
        ) {
            if isSelected {
                selectedRegionalFilters.remove(filter.id)
            } else {
                selectedRegionalFilters.insert(filter.id)
            }
            hasManuallyEditedRegionalSelection = true
        }
    }

    private var syncStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sync your filter selections, custom lists, userscripts, and whitelist across devices.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            cloudSyncCard
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setupRingStatus: SafariHealthStatus {
        let blockerBools = detectedContentBlockerStates.isEmpty
            ? setupHealth.blockerSlots.map(\.isEnabled)
            : detectedContentBlockerStates.map(\.isEnabled)
        let effectiveScripts = detectedScriptsExtensionEnabled ?? setupHealth.scriptsExtensionEnabled
        let blockersAllOn = !blockerBools.isEmpty && blockerBools.allSatisfy { $0 }
        let scriptsOK = !setupHealth.isScriptsStateKnowable || effectiveScripts == true || hasEnabledAdvanced
        let welded = (hasEnabledContentBlockers || blockersAllOn) && scriptsOK
        return SafariHealthResolver.resolve(
            SafariHealthInput(
                hasReadExtensions: !blockerBools.isEmpty || setupHealth.hysteresis.hasReadOnce,
                blockerStates: blockerBools,
                scriptsEnabled: effectiveScripts,
                isScriptsStateKnowable: setupHealth.isScriptsStateKnowable,
                isWelded: welded,
                pausedComponents: [],
                hasHitRuleLimit: false,
                isApplying: false,
                hasFailed: false,
                failedDuringUpdate: false,
                lastUpdatedDate: nil
            )
        )
    }

    private var setupArcStates: [Bool] {
        let slotBools: [Bool]
        if !detectedContentBlockerStates.isEmpty {
            slotBools = detectedContentBlockerStates.map(\.isEnabled)
        } else if !setupHealth.blockerSlots.isEmpty {
            slotBools = setupHealth.blockerSlots.map(\.isEnabled)
        } else {
            slotBools = Array(repeating: hasEnabledContentBlockers, count: 5)
        }
        if setupHealth.isScriptsStateKnowable {
            let scriptsOn = (detectedScriptsExtensionEnabled ?? setupHealth.scriptsExtensionEnabled) == true
            return slotBools + [scriptsOn]
        }
        return slotBools
    }

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ExtensionStatusRing(
                    arcStates: setupArcStates,
                    isWelded: setupRingStatus.isProtected,
                    status: setupRingStatus,
                    weldCelebrationCount: setupHealth.weldCelebrationCount,
                    medallionSize: 54
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(setupRingStatus.isProtected ? String(localized: "Safari is ready") : setupRingStatus.title)
                        .font(.headline)
                    Text("Enable the Safari extensions so wBlock can block ads and run userscripts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Setup Instructions")
                        .font(.headline)
                    Spacer()
                    Button {
                        openSafariExtensionsSettings()
                    } label: {
                        Label("Open Safari Extension Settings", systemImage: "gear")
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
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            #if os(macOS)
                            Text("Safari → Settings → Extensions")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Enable all 5 Content Blocker extensions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            #else
                            Text("Settings → Apps → Safari → Extensions")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Enable all 5 Content Blocker extensions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            #endif
                        }

                        Spacer()

                        Toggle("", isOn: contentBlockerSetupBinding)
                            .labelsHidden()
                            .disabled(isRefreshingContentBlockers)
                    }

                    if !detectedContentBlockerStates.isEmpty {
                        // All five on one line where they fit (the Mac sheet, #932, #944);
                        // otherwise two tight rows. A grid spread the chips apart.
                        Group {
                            if #available(iOS 16.0, macOS 13.0, *) {
                                ViewThatFits(in: .horizontal) {
                                    contentBlockerChipRow(detectedContentBlockerStates[...])
                                    contentBlockerChipRows
                                }
                            } else {
                                contentBlockerChipRows
                            }
                        }
                        .padding(.leading, 30)
                    }

                    Divider()
                        .padding(.leading, 30)

                    HStack(alignment: .top, spacing: 10) {
                        Text("2.")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable 'wBlock Scripts' → Always Allow on Every Website")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text(
                                detectedScriptsExtensionEnabled == false && !hasEnabledAdvanced
                                    ? "wBlock Scripts must be enabled and set to 'Always Allow on All Websites' for userscripts and advanced blocking."
                                    : "Required for userscripts, advanced ad blocking, and cleaner features"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                detectedScriptsExtensionEnabled == false && !hasEnabledAdvanced
                                    ? .red : .secondary
                            )

                            Text("If you use Private Browsing, also enable Allow in Private Browsing for wBlock Scripts and the 5 content blockers. Cookie notices and other scriptlets will not run in Private windows without it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: advancedSetupBinding)
                            .labelsHidden()
                            .disabled(isRefreshingScriptsExtensionState)
                    }
                }
            }
            .padding(14)
            .liquidGlassCompat()

            Text("Already done this? Just check the boxes above.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
    }

    private func openSafariExtensionsSettings() {
        SafariExtensionSetupSupport.openScriptsExtensionSettings()
    }

    private var advancedSetupBinding: Binding<Bool> {
        Binding(
            get: { hasEnabledAdvanced },
            set: { newValue in
                guard !isRefreshingScriptsExtensionState else { return }
                guard newValue else {
                    hasEnabledAdvanced = false
                    return
                }
                Task {
                    await confirmAdvancedSetupEnabled()
                }
            }
        )
    }

    /// Checking the box re-reads Safari's state; it only sticks when all five
    /// blockers are on, or when Safari can't report their state (#959).
    private var contentBlockerSetupBinding: Binding<Bool> {
        Binding(
            get: { hasEnabledContentBlockers },
            set: { newValue in
                guard newValue else {
                    hasEnabledContentBlockers = false
                    return
                }
                Task {
                    await refreshContentBlockerStates()
                    if detectedContentBlockerStates.isEmpty {
                        hasEnabledContentBlockers = true
                    }
                }
            }
        )
    }

    private func syncStoredCriticalSetupState() {
        hasEnabledContentBlockers = dataManager.hasEnabledContentBlockers
        hasEnabledAdvanced =
            dataManager.hasEnabledPlatformExtension && dataManager.hasSetAllWebsitesPermission
    }

    @MainActor
    private func confirmAdvancedSetupEnabled() async {
        await refreshScriptsExtensionState(retryingWhenDisabled: true)
        if detectedScriptsExtensionEnabled != false {
            hasEnabledAdvanced = true
        }
    }

    @MainActor
    private func refreshContentBlockerStates() async {
        isRefreshingContentBlockers = true
        defer { isRefreshingContentBlockers = false }
        let states = await SafariExtensionSetupSupport.contentBlockerSlotStates()
        detectedContentBlockerStates = states
        if !states.isEmpty && states.allSatisfy(\.isEnabled) {
            hasEnabledContentBlockers = true
        }
    }

    private var contentBlockerChipRows: some View {
        let split = (detectedContentBlockerStates.count + 1) / 2
        return VStack(alignment: .leading, spacing: 4) {
            contentBlockerChipRow(detectedContentBlockerStates.prefix(split))
            contentBlockerChipRow(detectedContentBlockerStates.dropFirst(split))
        }
    }

    private func contentBlockerChipRow(_ states: ArraySlice<SafariExtensionSetupSupport.ContentBlockerSlotState>) -> some View {
        HStack(spacing: 4) {
            ForEach(states) { slotState in
                contentBlockerChip(slotState)
            }
        }
    }

    private func contentBlockerChip(_ slotState: SafariExtensionSetupSupport.ContentBlockerSlotState) -> some View {
        HStack(spacing: 2) {
            Image(systemName: slotState.isEnabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(slotState.isEnabled ? .green : .orange)
            Text(slotState.name)
                .foregroundStyle(slotState.isEnabled ? .primary : .secondary)
        }
        .font(.caption2)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    @MainActor
    private func refreshScriptsExtensionState(retryingWhenDisabled: Bool = false) async {
        isRefreshingScriptsExtensionState = true
        defer { isRefreshingScriptsExtensionState = false }

        let maxAttempts = retryingWhenDisabled ? 4 : 1
        var state: Bool?

        for attempt in 0..<maxAttempts {
            state = await SafariExtensionSetupSupport.scriptsExtensionEnabledState()
            if state != false {
                break
            }
            guard attempt < maxAttempts - 1 else { break }
            try? await TaskSleep.sleep(for: .milliseconds(350))
        }

        detectedScriptsExtensionEnabled = state
        switch state {
        case true:
            hasEnabledAdvanced = true
        case false:
            hasEnabledAdvanced = false
        case nil:
            break
        }
    }

    private func userscriptCard(for script: OnboardingUserScriptItem) -> some View {
        let isSelected = selectedUserscripts.contains(script.id)

        return SelectableRow(
            title: Text(script.name),
            subtitle: script.description,
            badge: script.isBeta ? "Beta" : nil,
            isSelected: isSelected
        ) {
            if isSelected {
                selectedUserscripts.remove(script.id)
                manuallySelectedUserscripts.remove(script.id)
                if script.isBaselineEnabledByDefault {
                    manuallyDeselectedBaselineUserscripts.insert(script.id)
                }
            } else {
                selectedUserscripts.insert(script.id)
                manuallyDeselectedBaselineUserscripts.remove(script.id)
                if !script.isBaselineEnabledByDefault {
                    manuallySelectedUserscripts.insert(script.id)
                }
            }
        }
    }

    private func resolvedUserscriptDescription(for script: UserScript) -> String {
        // Prefer curated fallback descriptions for known remote scripts whose
        // metadata may still be downloading.
        if let fallback = userscriptDescriptionFallbacksByName[script.name.lowercased()] {
            return fallback
        }

        let rawDescription = script.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = rawDescription.lowercased()

        let isPlaceholder =
            normalizedDescription.isEmpty
            || normalizedDescription == "default userscript"
            || normalizedDescription == "default userscript - downloading..."
            || normalizedDescription == "ready to enable"

        // Match the userscript manager: localize known short descriptions, and
        // leave already-resolved metadata (including locale-aware cleaner copy)
        // untouched via NSLocalizedString identity fallback.
        guard isPlaceholder else { return script.localizedDisplayDescription }

        if userScriptManager.isPrefetchingDefaultMetadata {
            return String(localized: "Loading metadata…")
        }

        return String(localized: "No description provided by the script metadata.")
    }

    private func seedSelectedUserscriptsIfNeeded() {
        guard !hasSeededUserscriptSelection else { return }

        let defaultScripts = userScriptManager.userScripts.filter {
            userScriptManager.isDefaultUserScript($0) && !userScriptManager.isBeta(for: $0)
        }
        guard !defaultScripts.isEmpty else { return }

        selectedUserscripts = Set(defaultScripts.filter(\.isEnabled).map { $0.id.uuidString })
        hasSeededUserscriptSelection = true
        syncBaselineUserscriptSelection()
    }

    private func syncBaselineUserscriptSelection() {
        let defaultScripts = userScriptManager.userScripts.filter {
            userScriptManager.isDefaultUserScript($0) && !userScriptManager.isBeta(for: $0)
        }
        guard !defaultScripts.isEmpty else { return }

        let visibleDefaultIDs = Set(defaultUserScripts.map(\.id))
        let visibleBaselineIDs = Set(defaultScripts.compactMap { script -> String? in
            guard isBaselineUserscriptEnabledByDefault(script) else { return nil }
            guard visibleDefaultIDs.contains(script.id.uuidString) else { return nil }
            return script.id.uuidString
        })

        selectedUserscripts = selectedUserscripts.intersection(visibleDefaultIDs)
        selectedUserscripts.formUnion(visibleBaselineIDs.subtracting(manuallyDeselectedBaselineUserscripts))
        selectedUserscripts.formUnion(manuallySelectedUserscripts.intersection(visibleDefaultIDs))
    }

    private func isBaselineUserscriptEnabledByDefault(_ script: UserScript) -> Bool {
        userScriptManager.isEnabledByDefault(script)
    }
    
    func applySettings() async {
        guard !isApplyingSettings else { return }
        isApplyingSettings = true
        defer { isApplyingSettings = false }
        await filterManager.waitUntilReady()
        await userScriptManager.waitUntilReady()
        if !restoredFromBackup { await applyOnboardingChoices() }
        userScriptManager.markInitialSetupComplete()

        await dataManager.setHasEnabledContentBlockers(hasEnabledContentBlockers)
        await dataManager.setHasEnabledPlatformExtension(hasEnabledAdvanced)
        await dataManager.setHasSetAllWebsitesPermission(hasEnabledAdvanced)
        UserDefaults.standard.set(chosenMode.rawValue, forKey: AppMode.storageKey)

        if !restoredFromBackup {
            if wantsCloudSync && startsFreshInICloud {
                CloudSyncManager.shared.enableReplacingRemote()
            } else {
                CloudSyncManager.shared.setEnabled(wantsCloudSync)
            }
        }
        filterManager.markFreshInstallMigrationsComplete(preservingPendingHandover: restoredFromBackup)
        guard await dataManager.setHasCompletedOnboarding(true) else { return }
        restoredFromBackup = false

        // Dismiss onboarding onto Filters, where the apply runs; a restart
        // from Settings would otherwise leave the user there (#1087).
        dismiss()
        NotificationCenter.default.post(name: .wBlockSelectTabRequest, object: 0)
        NotificationCenter.default.post(name: .wBlockScrollFiltersToTopRequest, object: nil)
        filterManager.checkAndEnableFilters(forceReload: true)
    }

    private func applyOnboardingChoices() async {
        // Snapshot the then-current manager array and apply choices by stable IDs.
        let currentFilters = filterManager.filterLists
        var selectedFilterIDs = Set(currentFilters.filter { FilterListLoader.recommendedFilterNames.contains($0.name) }.map(\.id))
        if let bypassScript = bypassPaywallsScript,
           selectedUserscripts.contains(bypassScript.id),
           let filterName = bypassPaywallsFilterName,
           let filter = currentFilters.first(where: { $0.name == filterName })
        {
            selectedFilterIDs.insert(filter.id)
        }
        selectedFilterIDs.formUnion(selectedRegionalFilters)
        selectedFilterIDs.formUnion(AnnoyanceChoice.filters(for: selectedAnnoyances, in: currentFilters).map(\.id))

        sharedDefaults.set(Array(selectedLanguages), forKey: Self.selectedLanguagesDefaultsKey)
        for filter in currentFilters {
            filterManager.setFilterListSelection(
                id: filter.id,
                selected: selectedFilterIDs.contains(filter.id)
            )
        }
        await filterManager.saveFilterLists()

        // 2. Enable/disable userscripts based on onboarding selection
        let selectedScriptIDs = Set(selectedUserscripts.compactMap { UUID(uuidString: $0) })
        // Single, deterministic batch apply
        await userScriptManager.setEnabledScripts(withIDs: selectedScriptIDs)
    }

    private func probeForExistingICloudSetupIfNeeded() {
        guard !hasProbedRemoteConfig else { return }
        guard !hasCompletedOnboarding else { return }

        hasProbedRemoteConfig = true

        Task {
            let probe = await CloudSyncManager.shared.probeRemoteConfig()
            // Ask again when sync is turned on, so a failed check never reads as an empty iCloud.
            if probe.error != nil { hasProbedRemoteConfig = false }
            guard probe.exists else { return }

            if let updatedAt = probe.updatedAt {
                let formatter = LocalizedFormatting.relativeDateTimeFormatter(unitsStyle: .short)
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

        filterManager.prepareApplyRunState()
        filterManager.showingApplyProgressSheet = true
        CloudSyncManager.shared.setEnabled(true, startSync: false)

        let applied = await CloudSyncManager.shared.downloadAndApplyLatestRemoteConfig(
            trigger: "Onboarding-AdoptRemote"
        )

        guard applied else {
            filterManager.isLoading = false
            filterManager.showingApplyProgressSheet = false
            filterManager.applyProgressViewModel.cancelProgressRun()
            CloudSyncManager.shared.setEnabled(false, startSync: false)
            wantsCloudSync = false
            return
        }
        UserDefaults.standard.set(chosenMode.rawValue, forKey: AppMode.storageKey)
        filterManager.markFreshInstallMigrationsComplete(preservingPendingHandover: false)
        guard await dataManager.setHasCompletedOnboarding(true) else { return }
        dismiss()
        NotificationCenter.default.post(name: .wBlockSelectTabRequest, object: 0)
        NotificationCenter.default.post(name: .wBlockScrollFiltersToTopRequest, object: nil)
    }

    private func updateRegionalRecommendations(for languages: Set<String>) {
        guard !filterManager.filterLists.isEmpty else { return }
        guard !languages.isEmpty else {
            regionalFilters = []
            if !hasManuallyEditedRegionalSelection {
                selectedRegionalFilters.removeAll()
            }
            return
        }

        let languages = RegionalLanguageOption.expanding(languages)
        let foreignFilters = filterManager.filterLists.filter { $0.category == .foreign }
        let matchingFilters = foreignFilters.compactMap { filter -> FilterList? in
            let filterLanguages = resolvedLanguages(for: filter)
            guard !filterLanguages.isEmpty && !filterLanguages.isDisjoint(with: languages) else { return nil }
            var hydrated = filter
            if hydrated.languages.isEmpty {
                hydrated.languages = Array(filterLanguages).sorted()
            }
            return hydrated
        }

        guard !matchingFilters.isEmpty else {
            regionalFilters = []
            if !hasManuallyEditedRegionalSelection {
                selectedRegionalFilters.removeAll()
            }
            return
        }

        let hydratedMatches = matchingFilters.map { filter -> FilterList in
            var hydrated = filter
            if hydrated.trustLevel == nil || hydrated.trustLevel?.isEmpty == true {
                hydrated.trustLevel = resolvedTrustLevel(for: filter)
            }
            return hydrated
        }
        // Show every matching list; only the recommended ones are marked and preselected.
        let buckets = ForeignFilterOrganizer.recommendationBuckets(from: hydratedMatches)
        let primary = buckets.recommended

        regionalFilters = primary + buckets.optional

        let matchingIDs = Set(matchingFilters.map { $0.id })
        if hasManuallyEditedRegionalSelection {
            selectedRegionalFilters = selectedRegionalFilters.intersection(matchingIDs)
        } else if !primary.isEmpty {
            selectedRegionalFilters = Set(primary.map { $0.id })
        } else {
            selectedRegionalFilters.removeAll()
        }
    }

    private var cloudSyncCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("iCloud Sync")
                    .font(.headline)
            } icon: {
                Image(systemName: "icloud")
                    .foregroundStyle(Color.accentColor)
            }

            HStack {
                Text("Sync across devices")
                Spacer()
                Toggle("Sync across devices", isOn: $wantsCloudSync)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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

    private func handleBackupImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { @MainActor in
                do {
                    try url.withSecurityScopedAccess { accessibleURL in
                        let data = try Data(contentsOf: accessibleURL)
                        let backup = try BackupManager.importData(from: data)
                        pendingBackup = backup
                        showingRestoreBackupConfirmation = true
                    }
                } catch {
                    backupRestoreError = String.localizedStringWithFormat(
                        NSLocalizedString("Failed to read backup: %@", comment: "Backup import read failure"),
                        error.localizedDescription
                    )
                }
            }
        case .failure(let error):
            backupRestoreError = String.localizedStringWithFormat(
                NSLocalizedString("Import failed: %@", comment: "Backup import failure"),
                error.localizedDescription
            )
        }
    }

    @MainActor
    private func performBackupRestore() async {
        guard let backup = pendingBackup else { return }
        pendingBackup = nil
        do {
            try await BackupManager.restoreBackup(backup, filterManager: filterManager)
        } catch {
            backupRestoreError = String.localizedStringWithFormat(
                NSLocalizedString("Import failed: %@", comment: "Backup import failure"),
                error.localizedDescription
            )
            return
        }
        restoredFromBackup = true
        withAnimation(.easeInOut(duration: 0.2)) { step = .setup }
    }
}
