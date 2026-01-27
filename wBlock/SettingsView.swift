import SafariServices
import SwiftUI
import wBlockCoreService

struct SettingsView: View {
    let filterManager: AppFilterManager
    @ObservedObject private var dataManager = ProtobufDataManager.shared
    @ObservedObject private var syncManager = CloudSyncManager.shared
    private let minimumAutoUpdateIntervalHours: Double = 1
    private let maximumAutoUpdateIntervalHours: Double = 24 * 7
    @State private var nextScheduleLine = "Next: Loading…"
    @State private var lastUpdateLine = "Last: Never"
    @State private var isOverdue = false
    @State private var timer: Timer?
    @State private var showingRestartConfirmation = false
    @State private var isRestarting = false

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
            return "Waiting for activity"
        }
        return nextScheduleLine
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    LazyVStack(spacing: 16) {
                        #if os(macOS)
                            settingsSectionView(title: "Display") {
                                HStack {
                                    Text("Show blocked item count in toolbar")
                                        .font(.body)
                                    Spacer()
                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: { isBadgeCounterEnabled },
                                            set: { newValue in
                                                Task {
                                                    await dataManager.setIsBadgeCounterEnabled(
                                                        newValue)
                                                    // Wait for save to complete before notifying Safari
                                                    await dataManager.saveDataImmediately()
                                                    // Force Safari to refresh the toolbar badge
                                                    SFSafariApplication.setToolbarItemsNeedUpdate()
                                                }
                                            }
                                        )
                                    )
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                }
                                .padding(16)
                            }
                        #endif

                        settingsSectionView(title: "Actions") {
                            NavigationLink {
                                LogsView()
                            } label: {
                                HStack {
                                    Text("View Logs")
                                        .font(.body)
                                    Spacer()
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(16)

                            #if os(macOS)
                                Divider()
                                    .padding(.leading, 16)

                                NavigationLink {
                                    WhitelistManagerView(filterManager: filterManager)
                                } label: {
                                    HStack {
                                        Text("Manage Whitelist")
                                            .font(.body)
                                        Spacer()
                                        Image(systemName: "list.bullet.indent")
                                            .foregroundColor(.secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(16)
                            #endif
                        }

                        settingsSectionView(title: "Filter Auto-Update") {
                            VStack(spacing: 0) {
                                // Toggle row
                                HStack {
                                    Text("Auto-Update Filters")
                                        .font(.body)
                                    Spacer()
                                    Toggle(
                                        "",
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
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                }
                                .padding(16)

                                if autoUpdateEnabled {
                                    Divider()
                                        .padding(.leading, 16)

                                    // Frequency slider
                                    VStack(spacing: 10) {
                                        HStack(spacing: 8) {
                                            Text("1h")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            Slider(
                                                value: Binding(
                                                    get: { autoUpdateIntervalHours },
                                                    set: { newValue in
                                                        Task {
                                                            await dataManager
                                                                .setAutoUpdateIntervalHours(
                                                                    newValue)
                                                            await handleAutoUpdateConfigChange()
                                                        }
                                                    }
                                                ),
                                                in:
                                                    minimumAutoUpdateIntervalHours...maximumAutoUpdateIntervalHours,
                                                step: 1
                                            )
                                            Text("7d")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            Text(
                                                intervalDescription(hours: autoUpdateIntervalHours)
                                            )
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 90, alignment: .trailing)
                                            .contentTransition(.numericText())
                                        }
                                        HStack {
                                            Text("Next: \(compactStatusLine)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(lastUpdateLine)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(16)
                                }
                            }
                        }

                        settingsSectionView(title: "Sync") {
                            HStack(spacing: 12) {
                                Text("iCloud Sync")
                                    .font(.body)

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
                            .padding(16)
                        }

                        settingsSectionView(title: "About") {
                            HStack {
                                Text("wBlock Version")
                                    .font(.body)
                                Spacer()
                                Text(
                                    Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                                        as? String ?? "Unknown"
                                )
                                .foregroundColor(.secondary)
                            }
                            .padding(16)
                        }

                        settingsSectionView(title: "Danger Zone") {
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
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isRestarting)
                            .padding(16)
                        }

                    }
                    .padding(.horizontal)

                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            #if os(iOS)
                .padding(.horizontal, 16)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
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
    }

    private func settingsSectionView<Content: View>(
        title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func handleAutoUpdateConfigChange() async {
        await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
        await updateScheduleLine()
    }
}
extension SettingsView {
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
                nextScheduleLine = "Next: Loading…"
            }
            await updateScheduleLine()
        }
    }

    private func intervalDescription(hours: Double) -> String {
        if hours.truncatingRemainder(dividingBy: 24) == 0 {
            let days = Int(hours / 24)
            return days == 1 ? "Every 1 day" : "Every \(days) days"
        }

        if hours >= 24 {
            let days = Int(hours / 24)
            let remainingHours = Int(hours) % 24
            if remainingHours == 0 {
                return days == 1 ? "Every 1 day" : "Every \(days) days"
            }
            return "Every \(days)d \(remainingHours)h"
        }

        return Int(hours) == 1 ? "Every 1 hour" : "Every \(Int(hours)) hours"
    }

    private func formatSchedule(scheduledAt: Date?, remaining: TimeInterval?, isOverdue: Bool)
        -> String
    {
        guard let scheduledAt, let remaining else {
            return "Waiting"
        }

        if isOverdue || remaining <= 0 {
            return "Waiting for activity"
        }

        let componentsFormatter = DateComponentsFormatter()
        componentsFormatter.allowedUnits = [.day, .hour, .minute]
        componentsFormatter.unitsStyle = .short
        componentsFormatter.maximumUnitCount = 2
        let relative = componentsFormatter.string(from: remaining) ?? "soon"

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timeString = timeFormatter.string(from: scheduledAt)

        return "in \(relative) (\(timeString))"
    }

    private func formatLastUpdate(date: Date?) -> String {
        guard let date else {
            return "Never checked"
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Checked just now"
        }

        let componentsFormatter = DateComponentsFormatter()
        componentsFormatter.allowedUnits = [.day, .hour, .minute]
        componentsFormatter.unitsStyle = .short
        componentsFormatter.maximumUnitCount = 1
        if let relative = componentsFormatter.string(from: interval) {
            return "Checked \(relative) ago"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        return "Checked \(dateFormatter.string(from: date))"
    }

    private func updateScheduleLine(shouldTriggerOverdue: Bool = true) async {
        guard autoUpdateEnabled else {
            await MainActor.run {
                nextScheduleLine = "Disabled"
                lastUpdateLine = "N/A"
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
