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

                                    HStack {
                                        Text(intervalDescription(hours: autoUpdateIntervalHours))
                                        Spacer()
                                        Text(nextScheduleLine)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
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
            SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
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

    private func formatSchedule(scheduledAt: Date?, remaining: TimeInterval?) -> String {
        guard let scheduledAt, let remaining else {
            return "Next: Waiting"
        }

        if remaining <= 0 {
            return "Next: Now"
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

    private func updateScheduleLine() async {
        guard autoUpdateEnabled else {
            await MainActor.run { nextScheduleLine = "Next: Disabled" }
            return
        }

        let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
        let description = formatSchedule(scheduledAt: status.0, remaining: status.1)
        await MainActor.run { nextScheduleLine = description }
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
