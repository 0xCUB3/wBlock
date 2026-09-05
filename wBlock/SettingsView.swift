import SafariServices
import SwiftUI
import UniformTypeIdentifiers
import wBlockCoreService

struct SettingsView: View {
    let filterManager: AppFilterManager
    @ObservedObject private var dataManager = ProtobufDataManager.shared
    @ObservedObject private var syncManager = CloudSyncManager.shared
    private static let autoUpdateIntervalPresets: [Double] = [1, 2, 4, 6, 12, 24, 48, 72, 168]
    private static let reportIssueURL = URL(string: "https://github.com/0xCUB3/wBlock/issues/new/choose")!
    private static let developerURL = URL(string: "https://github.com/0xCUB3")!
    private static let sourceCodeURL = URL(string: "https://github.com/0xCUB3/wBlock")!
    private static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    private static let privacyPolicyURL = URL(string: "https://github.com/0xCUB3/wBlock/blob/main/PRIVACY_POLICY.md")!
    private static let faqURL = URL(string: "https://github.com/0xCUB3/wBlock#faq")!
    private static let contactURL = URL(string: "https://discord.gg/5kmuEbwsut")!
    @AppStorage(LogTimeZonePreference.storageKey) private var logTimeZoneIdentifier: String = LogTimeZonePreference.deviceIdentifier
    @State private var nextScheduleLine = String(localized: "Next: Loading…")
    @State private var isOverdue = false
    @State private var scheduleRefreshTimer = ScheduleRefreshTimer()
    #if os(macOS)
    @State private var launchAgentStatusLine = String(localized: "Checking background agent…")
    @State private var launchAgentNeedsApproval = false
    #endif
    @State private var showingRestartConfirmation = false
    @State private var isRestarting = false
    @State private var showingImportDialog = false
    @State private var showingRestoreBackupConfirmation = false
    @State private var pendingBackup: WBlockBackup? = nil
    @State private var backupStatusMessage: String? = nil
    @State private var showingBackupStatus = false
    @State private var showingSyncAdoptPrompt = false
    @State private var syncAdoptTimestamp: String?
    @State private var showingRuleCapacity = false
    @State private var pauseExceptionSites = BlockingPauseStore.exceptionDomains()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    #if os(iOS)
        @State private var backupDocument: BackupDocument? = nil
        @State private var showingExportSheet = false
        @AppStorage(PortraitOrientationLock.storageKey) private var lockPortraitOrientation = false
    #endif

    // Computed properties backed by protobuf
    private var autoUpdateEnabled: Bool {
        dataManager.autoUpdateEnabled
    }

    private var autoUpdateIntervalHours: Double {
        dataManager.autoUpdateIntervalHours
    }

    private var autoUpdateDiagnostics: AutoUpdateDiagnosticsSnapshot {
        dataManager.autoUpdateDiagnostics
    }

    #if os(macOS)
    private var backgroundAgentDisabled: Bool {
        dataManager.backgroundAgentDisabled
    }
    #endif

    var body: some View {
        settingsContent
        .task {
            await updateScheduleLine()
            await MainActor.run { startTimer() }
        }
        .onDisappear { stopTimer() }
        .alert("Restart Onboarding?", isPresented: $showingRestartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restart", role: .destructive) { restartOnboarding() }
        } message: {
            Text(
                "This will remove all filters, userscripts, and preferences, then relaunch the onboarding flow."
            )
        }
        .alert("Restore Settings?", isPresented: $showingRestoreBackupConfirmation) {
            Button("Cancel", role: .cancel) { pendingBackup = nil }
            Button("Restore") { performRestore() }
        } message: {
            if let backup = pendingBackup {
                let dateStr = backup.createdAt.formatted(date: .abbreviated, time: .shortened)
                Text(
                    String.localizedStringWithFormat(
                        NSLocalizedString(
                            "Backup from %@ (app v%@, %@ filters). This will replace your current filter selections, whitelist, and element zapper rules.",
                            comment: "Restore backup confirmation message"
                        ),
                        dateStr,
                        backup.appVersion,
                        backup.filterSelections.count.formatted()
                    )
                )
            } else {
                Text("This will replace your current filter selections, whitelist, and element zapper rules with the backed up settings.")
            }
        }
        .alert("Backup", isPresented: $showingBackupStatus) {
            Button("OK") {}
        } message: {
            Text(backupStatusMessage ?? "")
        }
        .fileImporter(
            isPresented: $showingImportDialog,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        #if os(iOS)
        .fileExporter(
            isPresented: $showingExportSheet,
            document: backupDocument,
            contentType: .json,
            defaultFilename: exportFilename()
        ) { result in
            if case .failure(let error) = result {
                backupStatusMessage = String.localizedStringWithFormat(
                    NSLocalizedString("Export failed: %@", comment: "Backup export failure"),
                    error.localizedDescription
                )
                showingBackupStatus = true
            }
        }
        #endif
        .confirmationDialog(
            "Use existing iCloud setup?",
            isPresented: $showingSyncAdoptPrompt,
            titleVisibility: .visible
        ) {
            Button("Use iCloud Setup") {
                Task {
                    syncManager.setEnabled(true, startSync: false)
                    let applied = await CloudSyncManager.shared.downloadAndApplyLatestRemoteConfig(
                        trigger: "Settings-AdoptRemote"
                    )
                    if !applied {
                        syncManager.setEnabled(true)
                    }
                }
            }
            Button("Start Fresh") {
                syncManager.setEnabled(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let syncAdoptTimestamp {
                Text(
                    String.localizedStringWithFormat(
                        NSLocalizedString(
                            "An existing wBlock configuration was found in iCloud (%@). Would you like to adopt it, or start fresh and upload your current setup?",
                            comment: "iCloud setup adoption prompt"
                        ),
                        syncAdoptTimestamp
                    )
                )
            } else {
                Text("An existing wBlock configuration was found in iCloud. Would you like to adopt it, or start fresh and upload your current setup?")
            }
        }
    }

    // MARK: - Shared section builders

    private var autoUpdateToggleBinding: Binding<Bool> {
        Binding(
            get: { autoUpdateEnabled },
            set: { newValue in
                Task {
                    await dataManager.setAutoUpdateEnabled(newValue)
                    await handleAutoUpdateConfigChange()
                    await MainActor.run {
                        if newValue { startTimer() } else { stopTimer() }
                    }
                }
            }
        )
    }

    private var autoUpdateIntervalBinding: Binding<Double> {
        Binding(
            get: { Self.nearestPreset(to: autoUpdateIntervalHours) },
            set: { newValue in
                Task {
                    await dataManager.setAutoUpdateIntervalHours(newValue)
                    await handleAutoUpdateConfigChange()
                }
            }
        )
    }

    #if os(macOS)
    private var backgroundAgentEnabledBinding: Binding<Bool> {
        Binding(
            get: { !backgroundAgentDisabled },
            set: { newValue in
                Task {
                    await dataManager.setBackgroundAgentDisabled(!newValue)
                    let desired = dataManager.autoUpdateEnabled && !dataManager.backgroundAgentDisabled
                    await MainActor.run {
                        AutoUpdateLaunchAgentManager.shared.reconcileWithAutoUpdateSetting(desired)
                    }
                    await updateScheduleLine(shouldTriggerOverdue: false)
                }
            }
        )
    }
    #endif

    private var syncEnabledBinding: Binding<Bool> {
        Binding(
            get: { syncManager.isEnabled },
            set: { newValue in
                guard syncManager.isCloudKitAvailable else { return }
                if newValue { probeAndEnableSync() } else { syncManager.setEnabled(false) }
            }
        )
    }

    private var pauseBlockingBinding: Binding<Bool> {
        Binding(
            get: { filterManager.isBlockingPaused },
            set: { newValue in
                Task { await filterManager.setBlockingPaused(newValue) }
            }
        )
    }

    private func pauseComponentBinding(_ component: BlockingPauseComponents) -> Binding<Bool> {
        Binding(
            get: { filterManager.pausedComponents.contains(component) },
            set: { newValue in
                var components = filterManager.pausedComponents
                if newValue {
                    components.insert(component)
                } else {
                    components.remove(component)
                }
                Task { await filterManager.setPausedComponents(components) }
            }
        )
    }

    #if os(iOS)
    @ViewBuilder
    private var displaySection: some View {
        Section {
            appearancePicker
            if UIDevice.current.userInterfaceIdiom != .pad {
                Toggle("Lock Portrait Orientation", isOn: $lockPortraitOrientation)
                    .onChangeCompat(of: lockPortraitOrientation) { _ in
                        PortraitOrientationLock.apply()
                    }
            }
        } header: {
            Text("Display")
        } footer: {
            if UIDevice.current.userInterfaceIdiom != .pad {
                Text("Keeps the app in portrait even if the device is rotated.")
            }
        }
    }
    #else
    @ViewBuilder
    private var displaySection: some View {
        Section("Display") {
            appearancePicker
        }
    }
    #endif

    private var appearancePicker: some View {
        Picker("Appearance", selection: $appearance) {
            ForEach(AppAppearance.allCases) { option in
                Text(option.title).tag(option)
            }
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        Section("Advanced") {
            NavigationLink {
                SiteSettingsView()
            } label: {
                Label("Site Settings", systemImage: "globe")
            }

            NavigationLink {
                ElementZapperSettingsView(filterManager: filterManager)
            } label: {
                Label("Element Zapper", systemImage: "wand.and.stars")
            }

            NavigationLink {
                LogsView()
            } label: {
                Label("View Logs", systemImage: "doc.text.magnifyingglass")
            }

            ruleCapacityRow

            cosmeticFilteringControls

            logTimestampControls

            backupButtons
        }
    }

    private var cosmeticFilteringControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Cosmetic Filtering", isOn: cosmeticFilteringBinding)
                .disabled(filterManager.isLoading || filterManager.isApplyInFlight)
            Text("Hides ad placeholders and other page elements with CSS. Turning this off leaves only network blocking, which uses fewer rules and less CPU.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var cosmeticFilteringBinding: Binding<Bool> {
        Binding(
            get: { CosmeticFilteringPreference.isEnabled() },
            set: { newValue in
                CosmeticFilteringPreference.setEnabled(newValue)
                filterManager.markNonSelectionChangesPending()
            }
        )
    }

    private var logTimestampControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Sync timestamps with device timezone", isOn: usesDeviceTimeZoneBinding)
            Text("Controls the time zone used when displaying and exporting log timestamps.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChangeCompat(of: logTimeZoneIdentifier) { _ in
            LogDateFormatters.configureIfNeeded()
        }
    }

    @ViewBuilder
    private var helpSection: some View {
        Section {
            Link(destination: Self.faqURL) {
                Label("FAQ", systemImage: "questionmark.circle")
            }
            Link(destination: Self.reportIssueURL) {
                Label("Report Issues", systemImage: "exclamationmark.triangle")
            }
            Link(destination: Self.contactURL) {
                Label("Contact Us", systemImage: "bubble.left")
            }
            #if os(iOS)
            openSafariSettingsButton
            #endif
        } header: {
            #if os(macOS)
            HStack {
                Text("Help")
                Spacer()
                openSafariSettingsButton
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            #else
            Text("Help")
            #endif
        }
    }

    private var openSafariSettingsButton: some View {
        Button {
            SafariExtensionSetupSupport.openScriptsExtensionSettings()
        } label: {
            Label("Open Safari Settings", systemImage: "gear")
        }
    }

    /// The Safari Rules stat card on the Filters tab opens the same view, but
    /// nothing marks it as tappable, so give it a plain Settings entry too.
    private var ruleCapacityRow: some View {
        Button {
            showingRuleCapacity = true
        } label: {
            Label("Safari Rule Capacity", systemImage: "shield.lefthalf.filled")
        }
        #if os(macOS)
        .buttonStyle(.link)
        .popover(isPresented: $showingRuleCapacity, arrowEdge: .leading) {
            RuleCapacityPopoverView(filterManager: filterManager)
        }
        #else
        .sheet(isPresented: $showingRuleCapacity) {
            RuleCapacityPopoverView(filterManager: filterManager)
        }
        #endif
    }

    @ViewBuilder
    private var backupButtons: some View {
        #if os(macOS)
        CompatibleLabeledContent {
            HStack(spacing: 8) {
                Button {
                    exportBackup()
                } label: {
                    Label("Export", systemImage: "arrow.up.doc")
                }

                Button {
                    showingImportDialog = true
                } label: {
                    Label("Import", systemImage: "arrow.down.doc")
                }
            }
            .buttonStyle(.bordered)
        } label: {
            Label("Backup", systemImage: "square.and.arrow.up.on.square")
        }
        #else
        Button { exportBackup() } label: {
            Label("Export Settings", systemImage: "square.and.arrow.up")
        }
        Button { showingImportDialog = true } label: {
            Label("Import Settings", systemImage: "square.and.arrow.down")
        }
        #endif
    }

    @ViewBuilder
    private var autoUpdateSection: some View {
        Section {
            Toggle("Auto-Update Filters & Userscripts", isOn: autoUpdateToggleBinding)
                #if os(macOS)
                .toggleStyle(.switch)
                #endif

            if autoUpdateEnabled {
                Picker("Update Interval", selection: autoUpdateIntervalBinding) {
                    ForEach(Self.autoUpdateIntervalPresets, id: \.self) { hours in
                        Text(intervalDescription(hours: hours)).tag(hours)
                    }
                }

                #if os(macOS)
                Toggle("Background Update Agent", isOn: backgroundAgentEnabledBinding)
                    .toggleStyle(.switch)
                    .help("Keeps filters updating when wBlock isn't running. Turn off to avoid a persistent login item; updates will then only run while wBlock is open.")
                #endif
            }

            #if os(iOS)
            Button {
                filterManager.applyOrCheckForUpdates()
            } label: {
                Label("Update Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(filterManager.isLoading)

            #endif
            NavigationLink {
                autoUpdateDiagnosticsDetail
            } label: {
                Label("Background Diagnostics", systemImage: "stethoscope")
            }
        } header: {
            #if os(macOS)
            HStack {
                Text("Auto-Update")
                Spacer()
                Button {
                    filterManager.applyOrCheckForUpdates()
                } label: {
                    Label("Update Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(filterManager.isLoading)
            }
            #else
            Text("Auto-Update")
            #endif
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                if autoUpdateEnabled {
                    Text(nextScheduleLine)
                }
            }
        }
    }

    @ViewBuilder
    private var autoUpdateDiagnosticsDetail: some View {
        List {
            Section {
                #if os(macOS)
                diagnosticDetailView(title: "Background Update Agent", detail: launchAgentStatusLine)
                if launchAgentNeedsApproval {
                    Button("Open Login Items") {
                        AutoUpdateLaunchAgentManager.shared.openLoginItemsSettings()
                    }
                }
                diagnosticDetailView(
                    title: "Auto-Update",
                    detail: dataManager.autoUpdateIsRunning ? String(localized: "Updating…")
                        : (autoUpdateEnabled ? String(localized: "Enabled") : String(localized: "Disabled"))
                )
                diagnosticDetailView(title: "Update Interval", detail: intervalDescription(hours: autoUpdateIntervalHours))
                diagnosticDetailView(title: "Next", detail: nextScheduleLine)
                diagnosticDetailView(title: "Last Update Check", detail: formatDiagnosticTime(dataManager.autoUpdateLastCheckTime))
                diagnosticDetailView(title: "Last Successful Update", detail: formatDiagnosticTime(dataManager.autoUpdateLastSuccessfulTime))
                #else
                backgroundTaskDiagnosticsView(
                    title: "App Refresh Task",
                    diagnostics: autoUpdateDiagnostics.bgAppRefresh
                )
                backgroundTaskDiagnosticsView(
                    title: "Processing Task",
                    diagnostics: autoUpdateDiagnostics.bgProcessing
                )
                #endif
                diagnosticDetailView(title: "Foreground Catch-up", detail: foregroundCatchUpDiagnosticsLine)
            } footer: {
                #if os(iOS)
                Text("Filters update in the background, but timing is approximate. Force-quitting wBlock from the app switcher may prevent background updates until you reopen the app.")
                #endif
            }
        }
        .navigationTitle("Background Diagnostics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            _ = await dataManager.refreshFromDiskIfModified(forceRead: true)
            await updateScheduleLine(shouldTriggerOverdue: false)
        }
    }

    @ViewBuilder
    private func backgroundTaskDiagnosticsView(
        title: String,
        diagnostics: BackgroundTaskDiagnosticsSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString("Scheduling: %@", comment: "Background task diagnostics"),
                    diagnosticEventLine(
                        timestamp: diagnostics.lastScheduleAttemptTime,
                        result: diagnostics.lastScheduleResult,
                        error: diagnostics.lastScheduleError,
                        fallback: String(localized: "No submit attempt yet")
                    )
                )
            )
            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString("Execution: %@", comment: "Background task diagnostics"),
                    backgroundTaskExecutionLine(diagnostics)
                )
            )
        }
        .font(.footnote)
    }

    @ViewBuilder
    private func diagnosticDetailView(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.footnote)
        }
    }


    @ViewBuilder
    private var syncSection: some View {
        Section {
            Toggle("iCloud Sync", isOn: syncEnabledBinding)
                .disabled(!syncManager.isCloudKitAvailable)
                #if os(macOS)
                .toggleStyle(.switch)
                #endif

            if syncManager.isCloudKitAvailable && syncManager.isEnabled {
                Button {
                    Task { await syncManager.syncNow(trigger: "Manual") }
                } label: {
                    HStack {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if syncManager.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(syncManager.isSyncing)
            }
        } header: {
            Text("Sync")
        } footer: {
            if !syncManager.isCloudKitAvailable {
                Text("This GitHub/Homebrew build cannot use iCloud Sync. The App Store/TestFlight build can.")
            } else if syncManager.isEnabled {
                VStack(alignment: .leading, spacing: 2) {
                    Text(syncFooterLine)
                    if let error = syncManager.lastErrorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pauseBlockingSection: some View {
        Section {
            Toggle("Pause Blocking", isOn: pauseBlockingBinding)
                .disabled(filterManager.isLoading || filterManager.isApplyInFlight)
                #if os(macOS)
                .toggleStyle(.switch)
                #endif
        } header: {
            Text("Blocking")
        } footer: {
            Text(
                filterManager.isBlockingPaused
                    ? "Pause Blocking is on while any selected component is paused. Resume restores all components."
                    : "Temporarily pause selected components without changing their enabled settings."
            )
        }

        // The component options live in their own section so they read as
        // options of the pause toggle above rather than as more toggles (#604).
        Section {
            Toggle("Filters", isOn: pauseComponentBinding(.filters))
            Toggle("Enabled Userscripts & Userstyles", isOn: pauseComponentBinding(.userScripts))
            Toggle("Element Zapper", isOn: pauseComponentBinding(.elementZapper))
        } header: {
            Text("Paused Components")
        }
        .disabled(
            !filterManager.isBlockingPaused
                || filterManager.isLoading
                || filterManager.isApplyInFlight
        )

        Section {
            SiteDomainListEditor(sites: pauseExceptionSites, knownSites: SiteDomainListEditor.knownSites(in: dataManager)) { sites in
                Task {
                    await filterManager.setPauseExceptionDomains(sites)
                    pauseExceptionSites = BlockingPauseStore.exceptionDomains()
                }
            }
            .disabled(filterManager.isLoading || filterManager.isApplyInFlight)
            .onAppear { pauseExceptionSites = BlockingPauseStore.exceptionDomains() }
        } header: {
            Text("Keep Blocking on These Sites")
        } footer: {
            Text("Paused components continue working on these sites and their subdomains.")
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            CompatibleLabeledContent("Version") {
                Text(
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                        as? String ?? "Unknown"
                )
            }
            Link(destination: Self.developerURL) {
                Label("Developer", systemImage: "person")
            }
            Link(destination: Self.sourceCodeURL) {
                Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(destination: Self.licenseURL) {
                Label("GPL-3.0 License", systemImage: "doc.text")
            }
            Link(destination: Self.privacyPolicyURL) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
        }
    }

    private var usesDeviceTimeZoneBinding: Binding<Bool> {
        Binding(
            get: { logTimeZoneIdentifier.isEmpty },
            set: { newValue in
                if newValue {
                    logTimeZoneIdentifier = LogTimeZonePreference.deviceIdentifier
                } else if logTimeZoneIdentifier.isEmpty {
                    logTimeZoneIdentifier = TimeZone.current.identifier
                }
                LogDateFormatters.configureIfNeeded()
            }
        )
    }

    @ViewBuilder
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showingRestartConfirmation = true
            } label: {
                Label(
                    isRestarting ? "Restarting…" : "Restart Onboarding",
                    systemImage: isRestarting ? "hourglass" : "arrow.counterclockwise"
                )
            }
            .tint(.red)
            #if os(macOS)
            .buttonStyle(.bordered)
            #endif
            .disabled(isRestarting)
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("This will remove all filters, userscripts, and preferences, then relaunch the onboarding flow.")
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        #if os(iOS)
        CompatibleNavigationStack {
            List {
                pauseBlockingSection
                displaySection
                autoUpdateSection
                syncSection
                advancedSection
                helpSection
                aboutSection
                dangerZoneSection
            }
            .unifiedTabListStyle()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        #else
        CompatibleNavigationStack {
            Form {
                pauseBlockingSection
                displaySection
                autoUpdateSection
                syncSection
                advancedSection
                helpSection
                aboutSection
                dangerZoneSection
            }
            .groupedFormStyleCompat()
        }
        #endif
    }

    private func handleAutoUpdateConfigChange() async {
        await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
        await updateScheduleLine()
    }

    private func probeAndEnableSync() {
        guard syncManager.isCloudKitAvailable else { return }
        Task {
            let probe = await CloudSyncManager.shared.probeRemoteConfig()
            guard probe.exists else {
                syncManager.setEnabled(true)
                return
            }

            if let updatedAt = probe.updatedAt {
                let formatter = LocalizedFormatting.relativeDateTimeFormatter(unitsStyle: .short)
                let date = Date(timeIntervalSince1970: updatedAt)
                syncAdoptTimestamp = formatter.localizedString(for: date, relativeTo: Date())
            } else {
                syncAdoptTimestamp = nil
            }
            showingSyncAdoptPrompt = true
        }
    }
}
extension SettingsView {

    // MARK: - Backup/Restore

    private func exportFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "wBlock-Backup-\(formatter.string(from: Date())).json"
    }

    private func exportBackup() {
        Task { @MainActor in
            let backup = await BackupManager.createBackup(filterManager: filterManager)
            guard let data = try? BackupManager.exportData(backup: backup) else {
                backupStatusMessage = String(localized: "Failed to create backup.")
                showingBackupStatus = true
                return
            }

            #if os(macOS)
            // Attach the save panel to the window as a sheet. A free-floating
            // panel let every extra click on Export stack another dialog (#625).
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = exportFilename()
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try url.withSecurityScopedAccess { accessibleURL in
                        try data.write(to: accessibleURL, options: .atomic)
                    }
                } catch {
                    backupStatusMessage = String.localizedStringWithFormat(
                        NSLocalizedString("Export failed: %@", comment: "Backup export failure"),
                        error.localizedDescription
                    )
                    showingBackupStatus = true
                }
            }
            #else
            backupDocument = BackupDocument(data: data)
            showingExportSheet = true
            #endif
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
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
                    backupStatusMessage = String.localizedStringWithFormat(
                        NSLocalizedString("Failed to read backup: %@", comment: "Backup import read failure"),
                        error.localizedDescription
                    )
                    showingBackupStatus = true
                }
            }
        case .failure(let error):
            backupStatusMessage = String.localizedStringWithFormat(
                NSLocalizedString("Import failed: %@", comment: "Backup import failure"),
                error.localizedDescription
            )
            showingBackupStatus = true
        }
    }

    private func performRestore() {
        guard let backup = pendingBackup else { return }
        pendingBackup = nil
        Task {
            await BackupManager.restoreBackup(backup, filterManager: filterManager)
            #if os(iOS)
            PortraitOrientationLock.apply()
            #endif
            await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
            // Apply straight away instead of asking for a manual Apply tap (#630).
            filterManager.forceApplyChanges()
            backupStatusMessage = String(localized: "Settings restored. Applying now.")
            showingBackupStatus = true
        }
    }

    // MARK: - User Defaults / Onboarding

    private func restartOnboarding() {
        guard !isRestarting else { return }
        isRestarting = true
        showingRestartConfirmation = false
        stopTimer()

        Task {
            defer {
                Task { @MainActor in isRestarting = false }
            }
            await filterManager.completeResetForOnboarding()
            await MainActor.run {
                nextScheduleLine = String(localized: "Next: Loading…")
            }
            await updateScheduleLine()
        }
    }

    private static func nearestPreset(to hours: Double) -> Double {
        autoUpdateIntervalPresets.min(by: { abs($0 - hours) < abs($1 - hours) }) ?? 6
    }

    private func intervalDescription(hours: Double) -> String {
        if hours.truncatingRemainder(dividingBy: 24) == 0 {
            let days = Int(hours / 24)
            return localizedIntervalCount("Every %d days", count: days)
        }

        if hours >= 24 {
            let days = Int(hours / 24)
            let remainingHours = Int(hours) % 24
            if remainingHours == 0 {
                return localizedIntervalCount("Every %d days", count: days)
            }
            let duration = TimeInterval(hours * 3600)
            let formattedDuration = LocalizedFormatting.dateComponentsFormatter(
                allowedUnits: [.day, .hour],
                unitsStyle: .abbreviated,
                maximumUnitCount: 2
            ).string(from: duration)

            return String.localizedStringWithFormat(
                NSLocalizedString("Every %@", comment: "Auto-update interval"),
                formattedDuration ?? "\(days) \(remainingHours)"
            )
        }

        return localizedIntervalCount("Every %d hours", count: Int(hours))
    }

    private func localizedIntervalCount(_ key: String, count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString(key, comment: "Auto-update interval"),
            count
        )
    }

    private func formatSchedule(scheduledAt: Date?, remaining: TimeInterval?, isOverdue: Bool, isRunning: Bool)
        -> String
    {
        guard let scheduledAt, let remaining else {
            return String(localized: "Waiting")
        }

        if isOverdue || remaining <= 0 {
            if isRunning {
                return String(localized: "Updating…")
            }
            return String(localized: "due now")
        }

        let componentsFormatter = LocalizedFormatting.dateComponentsFormatter(
            allowedUnits: [.day, .hour, .minute],
            unitsStyle: .short,
            maximumUnitCount: 2
        )
        let relative = componentsFormatter.string(from: remaining) ?? String(localized: "soon")

        let timeFormatter = LocalizedFormatting.timeFormatter()
        let timeString = timeFormatter.string(from: scheduledAt)

        return String.localizedStringWithFormat(
            NSLocalizedString("in %@ (%@)", comment: "Relative schedule"),
            relative,
            timeString
        )
    }

    private var foregroundCatchUpDiagnosticsLine: String {
        let timestamp = autoUpdateDiagnostics.lastForegroundCatchUpTime
        guard timestamp > 0 else {
            return String(localized: "No foreground catch-up recorded")
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("%@ %@", comment: "Diagnostic event summary"),
            humanReadableDiagnosticResult(autoUpdateDiagnostics.lastForegroundCatchUpReason),
            formatDiagnosticTime(timestamp)
        )
    }

    private func formatDiagnosticTime(_ timestamp: Int64) -> String {
        guard timestamp > 0 else { return String(localized: "never") }
        let formatter = LocalizedFormatting.relativeDateTimeFormatter(unitsStyle: .short)
        return formatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            relativeTo: Date()
        )
    }

    private func diagnosticEventLine(
        timestamp: Int64,
        result: String,
        error: String,
        fallback: String
    ) -> String {
        guard timestamp > 0 else { return fallback }
        let normalizedResult = result.isEmpty ? AutoUpdateDiagnosticResult.recorded.rawValue : result
        let status = humanReadableDiagnosticResult(normalizedResult)
        if error.isEmpty {
            return String.localizedStringWithFormat(
                NSLocalizedString("%@ %@", comment: "Diagnostic event summary"),
                status,
                formatDiagnosticTime(timestamp)
            )
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("%@ %@, %@", comment: "Diagnostic event summary with error"),
            status,
            formatDiagnosticTime(timestamp),
            error
        )
    }

    private func backgroundTaskExecutionLine(_ diagnostics: BackgroundTaskDiagnosticsSnapshot) -> String {
        if diagnostics.lastExpirationTime >= diagnostics.lastCompletionTime,
           diagnostics.lastExpirationTime >= diagnostics.lastStartTime,
           diagnostics.lastExpirationTime > 0
        {
            return String.localizedStringWithFormat(
                NSLocalizedString("Expired %@", comment: "Background task execution status"),
                formatDiagnosticTime(diagnostics.lastExpirationTime)
            )
        }

        if diagnostics.lastCompletionTime > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("%@ %@", comment: "Diagnostic event summary"),
                humanReadableDiagnosticResult(diagnostics.lastCompletionResult),
                formatDiagnosticTime(diagnostics.lastCompletionTime)
            )
        }

        if diagnostics.lastStartTime > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("Started %@", comment: "Background task execution status"),
                formatDiagnosticTime(diagnostics.lastStartTime)
            )
        }

        return String(localized: "No background run recorded")
    }

    private func humanReadableDiagnosticResult(_ value: String) -> String {
        guard let result = AutoUpdateDiagnosticResult(
            rawValue: value.isEmpty ? AutoUpdateDiagnosticResult.recorded.rawValue : value
        ) else {
            return value.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }

        switch result {
        case .registered:
            return String(localized: "Registered")
        case .failed:
            return String(localized: "Failed")
        case .submitted:
            return String(localized: "Submitted")
        case .infoPlistMissing:
            return String(localized: "Info.plist missing")
        case .tooManyPending:
            return String(localized: "Too many pending tasks")
        case .unavailable:
            return String(localized: "Unavailable")
        case .schedulerError:
            return String(localized: "Scheduler error")
        case .submitFailed:
            return String(localized: "Submit failed")
        case .completed:
            return String(localized: "Completed")
        case .timedOut:
            return String(localized: "Timed out")
        case .deferred:
            return String(localized: "Deferred")
        case .overdue:
            return String(localized: "Overdue catch-up")
        case .dueSoon:
            return String(localized: "Due soon catch-up")
        case .recorded:
            return String(localized: "Recorded")
        @unknown default:
            return value.replacingOccurrences(of: "_", with: " ").localizedCapitalized
        }
    }


    private var syncFooterLine: String {
        if syncManager.lastErrorMessage != nil {
            return syncManager.statusLine
        }

        switch syncManager.status {
        case .checking, .downloading, .uploading, .working:
            return syncManager.statusLine
        default:
            return syncManager.lastSyncLine
        }
    }


    private func updateScheduleLine(shouldTriggerOverdue: Bool = true) async {
        #if os(macOS)
        let launchAgentStatus = await MainActor.run {
            AutoUpdateLaunchAgentManager.shared.currentStatus()
        }
        let agentIntentionallyOff = backgroundAgentDisabled && !launchAgentStatus.isRegistered
        let launchAgentDetail = agentIntentionallyOff
            ? String(localized: "Background agent off (updates run while wBlock is open)")
            : launchAgentStatus.detail
        let launchAgentApproval = agentIntentionallyOff ? false : launchAgentStatus.needsApproval
        #endif

        guard autoUpdateEnabled else {
            await MainActor.run {
                nextScheduleLine = String(localized: "Disabled")
                isOverdue = false
                #if os(macOS)
                launchAgentStatusLine = launchAgentDetail
                launchAgentNeedsApproval = launchAgentApproval
                #endif
            }
            return
        }

        let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()

        let scheduleDescription = formatSchedule(
            scheduledAt: status.scheduledAt, remaining: status.remaining,
            isOverdue: status.isOverdue, isRunning: status.isRunning)
        await MainActor.run {
            nextScheduleLine = scheduleDescription
            isOverdue = status.isOverdue
            #if os(macOS)
            launchAgentStatusLine = launchAgentDetail
            launchAgentNeedsApproval = launchAgentApproval
            #endif
        }

        // Trigger overdue updates ONLY on first call (not recursive)
        if shouldTriggerOverdue && status.isOverdue && !status.isRunning {
            await SharedAutoUpdateManager.shared.forceNextUpdate()
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(
                trigger: "SettingsOverdueDetection", force: true)
            // Refresh display WITHOUT retriggering overdue check
            await updateScheduleLine(shouldTriggerOverdue: false)
        }
    }

    @MainActor
    private func startTimer() {
        guard autoUpdateEnabled else {
            scheduleRefreshTimer.stop()
            return
        }
        scheduleRefreshTimer.start(interval: 30) {
            await updateScheduleLine()
        }
    }

    @MainActor
    private func stopTimer() {
        scheduleRefreshTimer.stop()
    }
}

/// Owns the settings schedule-refresh timer so it can be invalidated without
/// relying on a SwiftUI value-type method capture staying alive.
@MainActor
private final class ScheduleRefreshTimer {
    private var timer: Timer?
    private var onTick: (@MainActor () async -> Void)?

    func start(interval: TimeInterval, onTick: @escaping @MainActor () async -> Void) {
        stop()
        self.onTick = onTick
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let onTick = self.onTick else { return }
                await onTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onTick = nil
    }

    deinit {
        timer?.invalidate()
    }
}
