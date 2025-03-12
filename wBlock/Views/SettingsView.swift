import SwiftUI

struct SettingsView: View {
    @AppStorage("updateInterval", store: UserDefaults(suiteName: "group.com.0xcube.wBlock")) private var updateInterval: TimeInterval = 86400
    @Environment(\.dismiss) var dismiss // Use standard dismiss
    @EnvironmentObject var filterListManager: FilterListManager


    let intervalOptions: [(name: String, value: TimeInterval)] = [
        ("1 Hour", 3600),
        ("24 Hours", 86400),
        ("7 Days", 604800),
        ("14 Days", 1209600),
        ("30 Days", 2592000)
    ]

    var body: some View {
        NavigationView { // Wrap in NavigationView
            Form { // Use Form for settings layout
                Section(header: Text("Update Interval")) {
                    Picker("Check for updates every:", selection: $updateInterval) {
                        ForEach(intervalOptions, id: \.value) { option in
                            Text(option.name).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu) // Use .menu for iOS style

                    Text("Note: Automatic updates currently only work while the app is running. It is recommended to update filter lists manually when needed rather than keeping the app running constantly.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            }
            .navigationTitle("Settings") // Set navigation title
            .toolbar { // Add toolbar for close button
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: updateInterval) { oldValue, newValue in
            Task {
                //await updateController.scheduleBackgroundUpdates(filterListManager: filterListManager)
                filterListManager.appendLog("Update interval changed to \(newValue) seconds") // This won't cause a crash
            }
        }
    }
}
