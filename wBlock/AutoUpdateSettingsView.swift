import SwiftUI
import wBlockCoreService

struct AutoUpdateSettingsView: View {
    @State private var enabled: Bool = true
    @State private var intervalHours: Double = 6
    @State private var scheduleText: String = ""
    @State private var startAtLogin: Bool = false
    @State private var statusLine: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable auto-update", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    enabled = newValue
                    Task { await AutoUpdateStore.shared.setEnabled(newValue) }
                }
            ))

            HStack {
                Text("Interval")
                Slider(value: Binding(
                    get: { intervalHours },
                    set: { val in
                        intervalHours = val
                        Task { await AutoUpdateStore.shared.setIntervalHours(val) }
                    }
                ), in: 1...24, step: 1)
                Text("\(Int(intervalHours))h")
                    .frame(width: 36, alignment: .trailing)
            }

            if !scheduleText.isEmpty {
                Text(scheduleText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            #if os(macOS)
            Divider().padding(.vertical, 4)
            Toggle("Start at login", isOn: Binding(
                get: { startAtLogin },
                set: { newValue in
                    startAtLogin = newValue
                    if MacLoginItemManager.isAvailable() {
                        MacLoginItemManager.setEnabled(newValue)
                        Task { await refreshStatus() }
                    }
                }
            ))
            .help("Requires embedded Login Item. Falls back to no-op if unavailable.")

            if !statusLine.isEmpty {
                Text(statusLine)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            #endif

            #if os(iOS)
            // Manual trigger (iOS only)
            Button {
                Task {
                    await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "ManualTest")
                    await updateScheduleText()
                }
            } label: {
                Label("Test Auto-Update Now", systemImage: "play.circle")
            }

            // iOS Background Update Status Banner
            iosBackgroundStatusBanner()
            #endif
        }
        .onAppear(perform: load)
    }

    private func load() {
        Task {
            let store = AutoUpdateStore.shared
            enabled = await store.isEnabled()
            intervalHours = await store.getIntervalHours()
            await updateScheduleText()
            #if os(macOS)
            startAtLogin = MacLoginItemManager.isEnabled()
            await refreshStatus()
            #endif
        }
    }

    private func updateScheduleText() async {
        let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f
        }()
        if let scheduledAt = status.0, let remaining = status.1 {
            if remaining == 0 {
                scheduleText = "Next run: due now (interval=\(Int(status.2))h), scheduled at \(formatter.string(from: scheduledAt))"
            } else {
                let hrs = Int(remaining) / 3600
                let mins = (Int(remaining) % 3600) / 60
                scheduleText = "Next run in \(hrs)h \(mins)m (scheduled \(formatter.string(from: scheduledAt)))"
            }
        } else {
            scheduleText = "No prior run; interval=\(Int(status.2))h"
        }
    }

    #if os(macOS)
    @MainActor
    private func refreshStatus(force: Bool = false) async {
        var parts: [String] = []
        if MacLoginItemManager.isAvailable() {
            parts.append("SMAppService: \(MacLoginItemManager.isEnabled() ? "Enabled" : "Disabled")")
            if let url = MacLoginItemManager.embeddedLoginItemURL() {
                parts.append("Embedded: OK (\(url.lastPathComponent))")
            } else {
                parts.append("Embedded: Not Found (check Copy Files: Wrapper → Contents/Library/LoginItems)")
            }
        } else {
            parts.append("SMAppService: Unavailable (macOS < 13)")
        }
        statusLine = parts.joined(separator: " • ") + " — Check System Settings → General → Login Items → Allow in the Background"
    }
    #endif

    #if os(iOS)
    @ViewBuilder
    private func iosBackgroundStatusBanner() -> some View {
        let status = UIApplication.shared.backgroundRefreshStatus
        let identifiers = (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]) ?? []
        let hasTaskID = identifiers.contains("com.alexanderskula.wblock.filter-update")
        let bgModes = (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]) ?? []
        let hasProcessing = bgModes.contains("background-processing")

        let (title, color): (String, Color) = {
            switch status {
            case .available: return ("Background App Refresh: Available", Color.green.opacity(0.15))
            case .denied: return ("Background App Refresh: Disabled in Settings", Color.red.opacity(0.15))
            case .restricted: return ("Background App Refresh: Restricted", Color.orange.opacity(0.15))
            @unknown default: return ("Background App Refresh: Unknown", Color.gray.opacity(0.15))
            }
        }()

        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline).bold()
            Text("BGTask ID registered: \(hasTaskID ? "Yes" : "No") • Background Processing mode: \(hasProcessing ? "Yes" : "No")")
                .font(.footnote)
                .foregroundColor(.secondary)
            if status != .available {
                Text("Tip: Enable Settings → General → Background App Refresh for best results.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(color))
    }
    #endif
}
