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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let content: AnyView = {
            #if os(iOS)
            return AnyView(
                NavigationView {
                    formContent
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { dismiss() }
                        }
                    }
                }
            )
            #else
            return AnyView(
                VStack(spacing: 0) {
                    SheetHeader(title: "Settings") {
                        dismiss()
                    }

                    formContent
                        .formStyle(.grouped)

                    Spacer()
                }
                #if os(macOS)
                .frame(minWidth: 350, minHeight: 200)
                #endif
            )
            #endif
        }()

        return content
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
    }
    
    @ViewBuilder
    private var formContent: some View {
        Form {
            #if os(macOS)
            Section {
                Toggle("Show blocked item count in toolbar", isOn: $isBadgeCounterEnabled)
                    .toggleStyle(.switch)
            }
            #endif

            Section {
                Button {
                    Task { await filterManager.checkForUpdates() }
                } label: {
                    HStack {
                        Label("Check for Filterlist Updates", systemImage: "arrow.clockwise")
                        Spacer()
                    }
                }
                .disabled(filterManager.isLoading)

                NavigationLink {
                    LogsView()
                } label: {
                    Label("View Logs", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Actions")
            }
            .textCase(.none)

            Section {
                Toggle("Enable Auto-Updates", isOn: $autoUpdateEnabled)
                    .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 8) {
                    Slider(
                        value: autoUpdateIntervalBinding,
                        in: minimumAutoUpdateIntervalHours...maximumAutoUpdateIntervalHours,
                        step: 1
                    ) {
                        Text("Update Frequency")
                    } minimumValueLabel: {
                        Text("1h")
                    } maximumValueLabel: {
                        Text("7d")
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
            } header: {
                Text("Filterlist Auto-Update")
            }
            .textCase(.none)
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
            Section {
                HStack {
                    Text("wBlock Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("About")
            }
            .textCase(.none)

            Section {
                Button(role: .destructive) {
                    showingRestartConfirmation = true
                } label: {
                    HStack {
                        if isRestarting {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text(isRestarting ? "Restarting…" : "Restart Onboarding")
                    }
                }
                .disabled(isRestarting)
            }
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
            await MainActor.run {
                dismiss()
            }
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
