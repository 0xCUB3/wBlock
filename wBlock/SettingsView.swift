import SwiftUI
import wBlockCoreService

struct SettingsView: View {
    let filterManager: AppFilterManager
    @AppStorage("isBadgeCounterEnabled", store: UserDefaults(suiteName: GroupIdentifier.shared.value))
    private var isBadgeCounterEnabled = true
    @AppStorage("autoUpdateEnabled", store: UserDefaults(suiteName: GroupIdentifier.shared.value))
    private var autoUpdateEnabled = true
    @AppStorage("autoUpdateIntervalHours", store: UserDefaults(suiteName: GroupIdentifier.shared.value))
    private var autoUpdateIntervalHours = 6.0
    private let minimumAutoUpdateIntervalHours: Double = 1
    private let maximumAutoUpdateIntervalHours: Double = 24 * 7
    @State private var nextScheduleLine = "Next: Loading…"
    @State private var lastUpdateLine = "Last: Never"
    @State private var isOverdue = false
    @State private var isUpdating = false
    @State private var timer: Timer?
    @State private var showingRestartConfirmation = false
    @State private var isRestarting = false

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
                                Toggle("", isOn: $isBadgeCounterEnabled)
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
                                HStack {
                                    Text("Enable Auto-Updates")
                                        .font(.body)
                                    Spacer()
                                    Toggle("", isOn: $autoUpdateEnabled)
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                }
                                .padding(16)

                                Divider()
                                    .padding(.leading, 16)

                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Update Frequency")
                                        .font(.body)
                                        .fontWeight(.medium)

                                    Slider(
                                        value: autoUpdateIntervalBinding,
                                        in: minimumAutoUpdateIntervalHours...maximumAutoUpdateIntervalHours,
                                        step: 1
                                    ) {
                                        Text("Frequency")
                                    } minimumValueLabel: {
                                        Text("1h")
                                            .font(.caption2)
                                    } maximumValueLabel: {
                                        Text("7d")
                                            .font(.caption2)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(intervalDescription(hours: autoUpdateIntervalHours))
                                            Spacer()
                                            if isUpdating {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                    .padding(.trailing, 4)
                                                Text("Updating...")
                                                    .foregroundColor(.blue)
                                            } else {
                                                Text(nextScheduleLine)
                                                    .foregroundColor(isOverdue ? .orange : .secondary)
                                            }
                                        }
                                        .font(.caption)
                                        .lineLimit(1)

                                        Text(lastUpdateLine)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }

                                    Button {
                                        Task { await performManualUpdate() }
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                            Text("Update Now")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isUpdating || !autoUpdateEnabled)
                                    .padding(.top, 4)
                                }
                                .disabled(!autoUpdateEnabled)
                                .padding(16)
                            }
                        }

                        settingsSectionView(title: "About") {
                            HStack {
                                Text("wBlock Version")
                                    .font(.body)
                                Spacer()
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
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
            Text("This will remove all filters, userscripts, and preferences, then relaunch the onboarding flow.")
        }
        .onChange(of: autoUpdateEnabled) { isEnabled in
            Task {
                await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
                await updateScheduleLine()
                await MainActor.run {
                    if isEnabled {
                        startTimer()
                    } else {
                        stopTimer()
                    }
                }
            }
        }
    }

    private func settingsSectionView<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
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
}
private extension SettingsView {
    private var autoUpdateIntervalBinding: Binding<Double> {
        Binding(
            get: { autoUpdateIntervalHours },
            set: { newValue in
                let clamped: Double
                if newValue <= 24 {
                    clamped = max(min(round(newValue), 24), minimumAutoUpdateIntervalHours)
                } else {
                    let days = max(1, round(newValue / 24))
                    clamped = min(days * 24, maximumAutoUpdateIntervalHours)
                }

                guard abs(autoUpdateIntervalHours - clamped) > .ulpOfOne else { return }
                autoUpdateIntervalHours = clamped
                Task {
                    await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
                    await updateScheduleLine()
                }
            }
        )
    }

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
                isBadgeCounterEnabled = true
                autoUpdateEnabled = true
                autoUpdateIntervalHours = 6.0
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

    private func formatSchedule(scheduledAt: Date?, remaining: TimeInterval?, isOverdue: Bool) -> String {
        guard let scheduledAt, let remaining else {
            return "Next: Waiting"
        }

        if isOverdue {
            return "Next: Overdue"
        }

        if remaining <= 0 {
            return "Next: Checking..."
        }

        let componentsFormatter = DateComponentsFormatter()
        componentsFormatter.allowedUnits = [.day, .hour, .minute]
        componentsFormatter.unitsStyle = .short
        componentsFormatter.maximumUnitCount = 2
        let relative = componentsFormatter.string(from: remaining) ?? "soon"

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = Calendar.current.isDate(scheduledAt, inSameDayAs: Date()) ? .none : .short
        timeFormatter.timeStyle = .short
        let timeString = timeFormatter.string(from: scheduledAt)

        if timeString.isEmpty {
            return "Next: in \(relative)"
        }

        return "Next: in \(relative) · \(timeString)"
    }

    private func formatLastUpdate(date: Date?) -> String {
        guard let date else {
            return "Last: Never"
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Last: Just now"
        }

        let componentsFormatter = DateComponentsFormatter()
        componentsFormatter.allowedUnits = [.day, .hour, .minute]
        componentsFormatter.unitsStyle = .short
        componentsFormatter.maximumUnitCount = 1
        if let relative = componentsFormatter.string(from: interval) {
            return "Last: \(relative) ago"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        return "Last: \(dateFormatter.string(from: date))"
    }

    private func updateScheduleLine(shouldTriggerOverdue: Bool = true) async {
        guard autoUpdateEnabled else {
            await MainActor.run {
                nextScheduleLine = "Next: Disabled"
                lastUpdateLine = "Last: N/A"
                isOverdue = false
            }
            return
        }

        let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()

        let scheduleDescription = formatSchedule(scheduledAt: status.scheduledAt, remaining: status.remaining, isOverdue: status.isOverdue)
        let lastDescription = formatLastUpdate(date: status.lastSuccessful)

        await MainActor.run {
            nextScheduleLine = scheduleDescription
            lastUpdateLine = lastDescription
            isUpdating = status.isRunning
            isOverdue = status.isOverdue
        }

        // Trigger overdue updates ONLY on first call (not recursive)
        if shouldTriggerOverdue && status.isOverdue && !status.isRunning {
            await SharedAutoUpdateManager.shared.forceNextUpdate()
            await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "SettingsOverdueDetection", force: true)
            // Refresh display WITHOUT retriggering overdue check
            await updateScheduleLine(shouldTriggerOverdue: false)
        }
    }

    private func performManualUpdate() async {
        await MainActor.run { isUpdating = true }
        await SharedAutoUpdateManager.shared.forceNextUpdate()
        await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "ManualUpdateButton", force: true)
        await updateScheduleLine()
    }

    @MainActor
    private func startTimer() {
        stopTimer()
        guard autoUpdateEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { await updateScheduleLine() }
        }
    }

    @MainActor
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
