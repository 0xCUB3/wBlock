import SafariServices
import SwiftUI
import UniformTypeIdentifiers
import wBlockCoreService

struct SettingsView: View {
    let filterManager: AppFilterManager
    @ObservedObject private var dataManager = ProtobufDataManager.shared
    @ObservedObject private var syncManager = CloudSyncManager.shared
    private let minimumAutoUpdateIntervalHours: Double = 1
    private let maximumAutoUpdateIntervalHours: Double = 24 * 7
    @State private var nextScheduleLine = String(localized: "Next: Loading…")
    @State private var lastUpdateLine = String(localized: "Last: Never")
    @State private var isOverdue = false
    @State private var timer: Timer?
    @State private var showingRestartConfirmation = false
    @State private var isRestarting = false
    @State private var showingImportDialog = false
    @State private var showingRestoreBackupConfirmation = false
    @State private var pendingBackup: WBlockBackup? = nil
    @State private var backupStatusMessage: String? = nil
    @State private var showingBackupStatus = false
    #if os(iOS)
        @State private var backupDocument: BackupDocument? = nil
        @State private var showingExportSheet = false
    #endif

    // Computed properties backed by protobuf
    private var isBadgeCounterEnabled: Bool {
        dataManager.isBadgeCounterEnabled
    }

    private var autoUpdateEnabled: Bool {
        dataManager.autoUpdateEnabled
    }

    private var autoUpdateIntervalHours: Double {
        dataManager.autoUpdateIntervalHours
    }

    private var compactStatusLine: String {
        if isOverdue {
            return String(localized: "Waiting for iOS background wake or app open")
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
    }

    @ViewBuilder
    private var settingsContent: some View {
        #if os(iOS)
        NavigationStack {
            List {
                Section("Actions") {
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("View Logs", systemImage: "doc.text.magnifyingglass")
                    }

                    NavigationLink {
                        WhitelistManagerView(filterManager: filterManager)
                    } label: {
                        Label("Manage Whitelist", systemImage: "list.bullet.indent")
                    }

                    NavigationLink {
                        ZapperRuleManagerView()
                    } label: {
                        Label("Manage Element Zapper Rules", systemImage: "wand.and.stars")
                    }

                    Button { exportBackup() } label: {
                        Label("Export Settings", systemImage: "square.and.arrow.up")
                    }

                    Button { showingImportDialog = true } label: {
                        Label("Import Settings", systemImage: "square.and.arrow.down")
                    }
                }

                Section {
                    Toggle(
                        "Auto-Update Filters",
                        isOn: Binding(
                            get: { autoUpdateEnabled },
                            set: { newValue in
                                Task {
                                    await dataManager.setAutoUpdateEnabled(newValue)
                                    await handleAutoUpdateConfigChange()
                                    await MainActor.run {
                                        if newValue {
                                            startTimer()
                                        } else {
                                            stopTimer()
                                        }
                                    }
                                }
                            }
                        )
                    )

                    if autoUpdateEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(intervalDescription(hours: autoUpdateIntervalHours))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())

                            Slider(
                                value: Binding(
                                    get: { autoUpdateIntervalHours },
                                    set: { newValue in
                                        Task {
                                            await dataManager
                                                .setAutoUpdateIntervalHours(newValue)
                                            await handleAutoUpdateConfigChange()
                                        }
                                    }
                                ),
                                in: minimumAutoUpdateIntervalHours...maximumAutoUpdateIntervalHours,
                                step: 1
                            )
                        }
                    }
                } header: {
                    Text("Filter Auto-Update")
                } footer: {
                    if autoUpdateEnabled {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(compactStatusLine) · \(lastUpdateLine)")
                            Text("iOS background refresh is best-effort; checks may run later than scheduled.")
                        }
                    }
                }

                Section("Sync") {
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

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { syncManager.isEnabled },
                                set: { newValue in
                                    syncManager.setEnabled(newValue)
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }

                Section("About") {
                    LabeledContent("wBlock Version") {
                        Text(
                            Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                                as? String ?? "Unknown"
                        )
                    }
                }

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
            .unifiedTabListStyle()
            .navigationBarTitleDisplayMode(.inline)
        }
        #else
        NavigationStack {
            List {
                Section("Display") {
                    Toggle(
                        "Show blocked item count in toolbar",
                        isOn: Binding(
                            get: { isBadgeCounterEnabled },
                            set: { newValue in
                                Task {
                                    await dataManager.setIsBadgeCounterEnabled(newValue)
                                    await dataManager.saveDataImmediately()
                                    SFSafariApplication.setToolbarItemsNeedUpdate()
                                }
                            }
                        )
                    )
                }

                Section("Actions") {
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("View Logs", systemImage: "doc.text.magnifyingglass")
                    }

                    NavigationLink {
                        WhitelistManagerView(filterManager: filterManager)
                    } label: {
                        Label("Manage Whitelist", systemImage: "list.bullet.indent")
                    }

                    NavigationLink {
                        ZapperRuleManagerView()
                    } label: {
                        Label("Manage Element Zapper Rules", systemImage: "wand.and.stars")
                    }

                    Button { exportBackup() } label: {
                        Label("Export Settings", systemImage: "square.and.arrow.up")
                    }

                    Button { showingImportDialog = true } label: {
                        Label("Import Settings", systemImage: "square.and.arrow.down")
                    }
                }

                Section {
                    Toggle(
                        "Auto-Update Filters",
                        isOn: Binding(
                            get: { autoUpdateEnabled },
                            set: { newValue in
                                Task {
                                    await dataManager.setAutoUpdateEnabled(newValue)
                                    await handleAutoUpdateConfigChange()
                                    await MainActor.run {
                                        if newValue {
                                            startTimer()
                                        } else {
                                            stopTimer()
                                        }
                                    }
                                }
                            }
                        )
                    )

                    if autoUpdateEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(intervalDescription(hours: autoUpdateIntervalHours))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())

                            Slider(
                                value: Binding(
                                    get: { autoUpdateIntervalHours },
                                    set: { newValue in
                                        Task {
                                            await dataManager
                                                .setAutoUpdateIntervalHours(newValue)
                                            await handleAutoUpdateConfigChange()
                                        }
                                    }
                                ),
                                in: minimumAutoUpdateIntervalHours...maximumAutoUpdateIntervalHours,
                                step: 1
                            )
                        }
                    }
                } header: {
                    Text("Filter Auto-Update")
                } footer: {
                    if autoUpdateEnabled {
                        Text("\(compactStatusLine) · \(lastUpdateLine)")
                    }
                }

                Section("Sync") {
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

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { syncManager.isEnabled },
                                set: { newValue in
                                    syncManager.setEnabled(newValue)
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }

                Section("About") {
                    LabeledContent("wBlock Version") {
                        Text(
                            Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                                as? String ?? "Unknown"
                        )
                    }
                }

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
            .unifiedTabListStyle()
        }
        #endif
    }

    private func handleAutoUpdateConfigChange() async {
        await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
        await updateScheduleLine()
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
                var didAccess = false
                #if os(iOS)
                    didAccess = url.startAccessingSecurityScopedResource()
                #endif
                defer {
                    #if os(iOS)
                        if didAccess { url.stopAccessingSecurityScopedResource() }
                    #endif
                }
                do {
                    let data = try Data(contentsOf: url)
                    let backup = try BackupManager.importData(from: data)
                    pendingBackup = backup
                    showingRestoreBackupConfirmation = true
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
            return String(localized: "Waiting for iOS background wake or app open")
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

    private func formatLastUpdate(date: Date?) -> String {
        guard let date else {
            return String(localized: "Never checked")
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return String(localized: "Checked just now")
        }

        let componentsFormatter = DateComponentsFormatter()
        componentsFormatter.allowedUnits = [.day, .hour, .minute]
        componentsFormatter.unitsStyle = .short
        componentsFormatter.maximumUnitCount = 1
        if let relative = componentsFormatter.string(from: interval) {
            return String.localizedStringWithFormat(
                NSLocalizedString("Checked %@ ago", comment: "Last update relative time"),
                relative
            )
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        return String.localizedStringWithFormat(
            NSLocalizedString("Checked %@", comment: "Last update date"),
            dateFormatter.string(from: date)
        )
    }

    private func updateScheduleLine(shouldTriggerOverdue: Bool = true) async {
        guard autoUpdateEnabled else {
            await MainActor.run {
                nextScheduleLine = String(localized: "Disabled")
                lastUpdateLine = String(localized: "N/A")
                isOverdue = false
            }
            return
        }

        let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()

        let scheduleDescription = formatSchedule(
            scheduledAt: status.scheduledAt, remaining: status.remaining,
            isOverdue: status.isOverdue)
        let lastDescription = formatLastUpdate(date: status.lastCheckTime)

        await MainActor.run {
            nextScheduleLine = scheduleDescription
            lastUpdateLine = lastDescription
            isOverdue = status.isOverdue
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
