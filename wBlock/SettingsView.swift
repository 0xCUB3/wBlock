import SwiftUI
import wBlockCoreService
import os.log
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

struct SettingsView: View {
@AppStorage("isBadgeCounterEnabled", store: UserDefaults(suiteName: GroupIdentifier.shared.value))
private var isBadgeCounterEnabled = true
    @State private var nextScheduleLine: String = "Loading…"
    @State private var timer: Timer?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        #if os(iOS)
        NavigationView {
            formContent
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task { 
            await updateScheduleLine()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        #else
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding([.top, .horizontal])
            
            formContent
                .formStyle(.grouped)
            
            Spacer()
        }
        .task { 
            await updateScheduleLine()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        #if os(macOS)
        .frame(minWidth: 350, minHeight: 200)
        #endif
        #endif
    }
    
    private var formContent: some View {
        Form {
            Section {
                Toggle("Show blocked item count in toolbar", isOn: $isBadgeCounterEnabled)
                .toggleStyle(.switch)
            }

            Section {
                HStack {
                    Text("Next Auto-Update Window")
                    Spacer()
                    Text(nextScheduleLine)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                Button("Refresh Status") { 
                    Task { 
                        await updateScheduleLine()
                    }
                }
            } header: {
                Text("Auto-Update")
            }
            .textCase(.none)

            #if DEBUG
            Section {
                #if os(iOS)
                Button("Run Auto-Update Now (iOS)") {
                    Task { await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "ManualButton_iOS") }
                }

                Button("Schedule BGProcessing (soon)") {
                    #if canImport(BackgroundTasks)
                    let id = "com.alexanderskula.wblock.filter-processing"
                    let req = BGProcessingTaskRequest(identifier: id)
                    req.requiresNetworkConnectivity = true
                    req.requiresExternalPower = true
                    req.earliestBeginDate = Date(timeIntervalSinceNow: 10) // ask system to run soon
                    do { try BGTaskScheduler.shared.submit(req) } catch { os_log("BGProcessing submit failed: %{public}@", error.localizedDescription) }
                    #endif
                }

                Button("Reset Auto-Update Throttle") {
                    let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
                    defaults.removeObject(forKey: "autoUpdateNextEligibleTime")
                }
                #else
                Button("Run Auto-Update Now (macOS, XPC if available)") {
                    Task {
                        let usedXPC = await FilterUpdateClient.shared.updateFilters()
                        if !usedXPC { await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "ManualButton_macOS") }
                    }
                }

                Button("Reset Auto-Update Throttle") {
                    let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
                    defaults.removeObject(forKey: "autoUpdateNextEligibleTime")
                }
                #endif
            } header: {
                Text("Developer (Debug)")
            }
            .textCase(.none)
            #endif

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
        }
    }
}

private extension SettingsView {
    func formatSchedule(scheduledAt: Date?, remaining: TimeInterval?, interval: Double) -> String {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f
        }()
        if let scheduledAt, let remaining {
            if remaining <= 0 {
                return "Due now (every \(Int(interval))h)"
            } else {
                let hrs = Int(remaining) / 3600
                let mins = (Int(remaining) % 3600) / 60
                return "in \(hrs)h \(mins)m (at \(formatter.string(from: scheduledAt)))"
            }
        } else {
            return "Not scheduled yet (every \(Int(interval))h)"
        }
    }

    func updateScheduleLine() async {
        let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
        nextScheduleLine = formatSchedule(scheduledAt: status.0, remaining: status.1, interval: status.2)
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                await updateScheduleLine()
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
