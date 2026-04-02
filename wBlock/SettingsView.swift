import SafariServices
import SwiftUI
import UniformTypeIdentifiers
import wBlockCoreService

struct SettingsView: View {
    let filterManager: AppFilterManager
    @ObservedObject private var dataManager = ProtobufDataManager.shared
    @ObservedObject private var syncManager = CloudSyncManager.shared
    private static let autoUpdateIntervalPresets: [Double] = [1, 2, 4, 6, 12, 24, 48, 72, 168]
    @State private var nextScheduleLine = String(localized: "Next: Loading…")
    @State private var isOverdue = false
    @State private var timer: Timer?
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
    #if os(iOS)
        @State private var backupDocument: BackupDocument? = nil
        @State private var showingExportSheet = false
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

    private var overdueWaitLine: String {
        #if os(iOS)
        return String(localized: "Waiting for iOS background wake or app open")
        #else
        return String(localized: "Waiting for background agent or app open")
        #endif
    }

    private var compactStatusLine: String {
        if isOverdue {
            return overdueWaitLine
        }
        return nextScheduleLine
    }

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
                Text("Backup from \(dateStr) (app v\(backup.appVersion), \(backup.filterSelections.count) filters). This will replace your current filter selections, whitelist, and element zapper rules.")
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
                backupStatusMessage = "Export failed: \(error.localizedDescription)"
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
                Text("An existing wBlock configuration was found in iCloud (\(syncAdoptTimestamp)). Would you like to adopt it, or start fresh and upload your current setup?")
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

    private var syncEnabledBinding: Binding<Bool> {
        Binding(
            get: { syncManager.isEnabled },
            set: { newValue in
                if newValue { probeAndEnableSync() } else { syncManager.setEnabled(false) }
            }
        )
    }

    @ViewBuilder
    private var actionsSection: some View {
        NavigationLink {
            LogsView()
        } label: {
            Label("View Logs", systemImage: "doc.text.magnifyingglass")
        }

        NavigationLink {
            WhitelistManagerView(filterManager: filterManager)
        } label: {
            Label("Manage Whitelist", systemImage: "list.bullet")
        }

        NavigationLink {
            ZapperRuleManagerView()
        } label: {
            Label("Manage Element Zapper Rules", systemImage: "wand.and.stars")
        }
    }

    @ViewBuilder
    private var backupButtons: some View {
        #if os(macOS)
        LabeledContent {
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
            Toggle("Auto-Update Filters", isOn: autoUpdateToggleBinding)
                #if os(macOS)
                .toggleStyle(.switch)
                #endif

            #if os(macOS)
            if launchAgentNeedsApproval {
                Button("Open Login Items") {
                    AutoUpdateLaunchAgentManager.shared.openLoginItemsSettings()
                }
            }
            #endif

            if autoUpdateEnabled {
                Picker("Update Interval", selection: autoUpdateIntervalBinding) {
                    ForEach(Self.autoUpdateIntervalPresets, id: \.self) { hours in
                        Text(intervalDescription(hours: hours)).tag(hours)
                    }
                }

                #if os(iOS)
                iOSAutoUpdateDiagnosticsView
                #endif
            }
        } header: {
            Text("Filter Auto-Update")
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                if autoUpdateEnabled {
                    Text(compactStatusLine)
                    #if os(macOS)
                    Text(launchAgentStatusLine)
                    #endif
                }
            }
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var iOSAutoUpdateDiagnosticsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background Diagnostics")
                .font(.caption)
                .foregroundStyle(.secondary)

            backgroundTaskDiagnosticsView(
                title: "BGAppRefresh",
                diagnostics: autoUpdateDiagnostics.bgAppRefresh
            )
            backgroundTaskDiagnosticsView(
                title: "BGProcessing",
                diagnostics: autoUpdateDiagnostics.bgProcessing
            )
            diagnosticDetailView(title: "Silent Push", detail: silentPushDiagnosticsLine)
            diagnosticDetailView(title: "Foreground Catch-up", detail: foregroundCatchUpDiagnosticsLine)
        }
        .padding(.top, 4)
    }
    #endif

    @ViewBuilder
    private func backgroundTaskDiagnosticsView(
        title: String,
        diagnostics: BackgroundTaskDiagnosticsSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                "Registration: " + diagnosticEventLine(
                    timestamp: diagnostics.lastRegistrationTime,
                    result: diagnostics.lastRegistrationResult,
                    error: diagnostics.lastRegistrationError,
                    fallback: "Not recorded"
                )
            )
            Text(
                "Scheduling: " + diagnosticEventLine(
                    timestamp: diagnostics.lastScheduleAttemptTime,
                    result: diagnostics.lastScheduleResult,
                    error: diagnostics.lastScheduleError,
                    fallback: "No submit attempt yet"
                )
            )
            Text("Execution: \(backgroundTaskExecutionLine(diagnostics))")
        }
        .font(.footnote)
    }

    @ViewBuilder
    private func diagnosticDetailView(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.footnote)
        }
    }


    @ViewBuilder
    private var syncSection: some View {
        Section {
            HStack(spacing: 12) {
                Text("iCloud Sync")

                Spacer()

                Button {
                    Task { await syncManager.syncNow(trigger: "Manual") }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(
                            (!syncManager.isEnabled || syncManager.isSyncing)
                                ? .tertiary : .secondary
                        )
                }
                .buttonStyle(.plain)
                .disabled(!syncManager.isEnabled || syncManager.isSyncing)
                .accessibilityLabel("Sync Now")

                Toggle("", isOn: syncEnabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        } header: {
            Text("Sync")
        } footer: {
            if syncManager.isEnabled {
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
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("wBlock Version") {
                Text(
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                        as? String ?? "Unknown"
                )
            }
        }
    }

    @ViewBuilder
    private var dangerZoneSection: some View {
        Section("Danger Zone") {
            Button(role: .destructive) {
                showingRestartConfirmation = true
            } label: {
                HStack {
                    if isRestarting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .padding(.trailing, 8)
                    }
                    Text(isRestarting ? "Restarting…" : "Restart Onboarding")
                }
            }
            .disabled(isRestarting)
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        #if os(iOS)
        NavigationStack {
            List {
                Section("Actions") {
                    actionsSection
                    backupButtons
                }

                autoUpdateSection
                syncSection
                aboutSection
                dangerZoneSection
            }
            .unifiedTabListStyle()
            .navigationBarTitleDisplayMode(.inline)
        }
        #else
        NavigationStack {
            Form {
                Section("Actions") {
                    actionsSection
                    backupButtons
                }

                autoUpdateSection
                syncSection
                aboutSection
                dangerZoneSection
            }
            .formStyle(.grouped)
        }
        #endif
    }

    private func handleAutoUpdateConfigChange() async {
        await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
        await updateScheduleLine()
    }

    private func probeAndEnableSync() {
        Task {
            let probe = await CloudSyncManager.shared.probeRemoteConfig()
            guard probe.exists else {
                syncManager.setEnabled(true)
                return
            }

            if let updatedAt = probe.updatedAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
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
        let backup = BackupManager.createBackup(filterManager: filterManager)
        guard let data = try? BackupManager.exportData(backup: backup) else {
            backupStatusMessage = "Failed to create backup."
            showingBackupStatus = true
            return
        }

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = exportFilename()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                backupStatusMessage = "Export failed: \(error.localizedDescription)"
                showingBackupStatus = true
            }
        }
        #else
        backupDocument = BackupDocument(data: data)
        showingExportSheet = true
        #endif
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
                    backupStatusMessage = "Failed to read backup: \(error.localizedDescription)"
                    showingBackupStatus = true
                }
            }
        case .failure(let error):
            backupStatusMessage = "Import failed: \(error.localizedDescription)"
            showingBackupStatus = true
        }
    }

    private func performRestore() {
        guard let backup = pendingBackup else { return }
        pendingBackup = nil
        Task {
            await BackupManager.restoreBackup(backup, filterManager: filterManager)
            backupStatusMessage = "Settings restored. Tap Apply Changes to activate."
            showingBackupStatus = true
        }
    }

    // MARK: - User Defaults / Onboarding

    private func resetUserDefaults() {
        if let suiteDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) {
            suiteDefaults.removePersistentDomain(forName: GroupIdentifier.shared.value)
            suiteDefaults.synchronize()
        }
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        UserDefaults.standard.synchronize()
    }

    private func restartOnboarding() {
        guard !isRestarting else { return }
        isRestarting = true
        showingRestartConfirmation = false
        stopTimer()

        Task {
            defer {
                Task { @MainActor in isRestarting = false }
            }
            resetUserDefaults()
            await ProtobufDataManager.shared.resetToDefaultData()
            await ProtobufDataManager.shared.setHasCompletedOnboarding(false)
            await filterManager.resetForOnboarding()
            UserScriptManager.shared.simulateFreshInstall()
            await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
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
            return String.localizedStringWithFormat(
                NSLocalizedString("Every %dd %dh", comment: "Auto-update interval"),
                days,
                remainingHours
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

    private func formatSchedule(scheduledAt: Date?, remaining: TimeInterval?, isOverdue: Bool)
        -> String
    {
        guard let scheduledAt, let remaining else {
            return String(localized: "Waiting")
        }

        if isOverdue || remaining <= 0 {
            return overdueWaitLine
        }

        let componentsFormatter = DateComponentsFormatter()
        componentsFormatter.allowedUnits = [.day, .hour, .minute]
        componentsFormatter.unitsStyle = .short
        componentsFormatter.maximumUnitCount = 2
        let relative = componentsFormatter.string(from: remaining) ?? String(localized: "soon")

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timeString = timeFormatter.string(from: scheduledAt)

        return String.localizedStringWithFormat(
            NSLocalizedString("in %@ (%@)", comment: "Relative schedule"),
            relative,
            timeString
        )
    }

    private var silentPushDiagnosticsLine: String {
        let diagnostics = autoUpdateDiagnostics.silentPush
        guard diagnostics.lastReceivedTime > 0 else {
            return String(localized: "No silent push received yet")
        }

        if diagnostics.lastCompletionTime > 0 {
            return "Received \(formatDiagnosticTime(diagnostics.lastReceivedTime)), \(humanReadableDiagnosticResult(diagnostics.lastResult)) \(formatDiagnosticTime(diagnostics.lastCompletionTime))"
        }

        return "Received \(formatDiagnosticTime(diagnostics.lastReceivedTime)), waiting for completion"
    }

    private var foregroundCatchUpDiagnosticsLine: String {
        let timestamp = autoUpdateDiagnostics.lastForegroundCatchUpTime
        guard timestamp > 0 else {
            return String(localized: "No foreground catch-up recorded")
        }

        return "\(humanReadableDiagnosticResult(autoUpdateDiagnostics.lastForegroundCatchUpReason)) \(formatDiagnosticTime(timestamp))"
    }

    private func formatDiagnosticTime(_ timestamp: Int64) -> String {
        guard timestamp > 0 else { return String(localized: "never") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
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
            return "\(status) \(formatDiagnosticTime(timestamp))"
        }
        return "\(status) \(formatDiagnosticTime(timestamp)), \(error)"
    }

    private func backgroundTaskExecutionLine(_ diagnostics: BackgroundTaskDiagnosticsSnapshot) -> String {
        if diagnostics.lastExpirationTime >= diagnostics.lastCompletionTime,
           diagnostics.lastExpirationTime >= diagnostics.lastStartTime,
           diagnostics.lastExpirationTime > 0
        {
            return "Expired \(formatDiagnosticTime(diagnostics.lastExpirationTime))"
        }

        if diagnostics.lastCompletionTime > 0 {
            return "\(humanReadableDiagnosticResult(diagnostics.lastCompletionResult)) \(formatDiagnosticTime(diagnostics.lastCompletionTime))"
        }

        if diagnostics.lastStartTime > 0 {
            return "Started \(formatDiagnosticTime(diagnostics.lastStartTime))"
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
            return syncManager.lastSyncLine
        }

        switch syncManager.statusLine {
        case "Sync: Checking…", "Sync: Downloading…", "Sync: Uploading…", "Sync: Working…":
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
        #endif

        guard autoUpdateEnabled else {
            await MainActor.run {
                nextScheduleLine = String(localized: "Disabled")
                isOverdue = false
                #if os(macOS)
                launchAgentStatusLine = launchAgentStatus.detail
                launchAgentNeedsApproval = launchAgentStatus.needsApproval
                #endif
            }
            return
        }

        let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()

        let scheduleDescription = formatSchedule(
            scheduledAt: status.scheduledAt, remaining: status.remaining,
            isOverdue: status.isOverdue)
        await MainActor.run {
            nextScheduleLine = scheduleDescription
            isOverdue = status.isOverdue
            #if os(macOS)
            launchAgentStatusLine = launchAgentStatus.detail
            launchAgentNeedsApproval = launchAgentStatus.needsApproval
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
        stopTimer()
        guard autoUpdateEnabled else { return }
        // Update every 30 seconds to reduce main thread load
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { await updateScheduleLine() }
        }
    }

    @MainActor
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
