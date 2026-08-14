#if os(iOS)
import FamilyControls
import SwiftUI
import UIKit

struct ScreenTimeSettingsView: View {
    @StateObject private var manager = ScreenTimeManager.shared
    @State private var showingExplanation = false
    @State private var showingPicker = false

    private var isAuthorized: Bool {
        ScreenTimeManager.isAuthorized(manager.authorizationStatus)
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Enable Screen Time blocking",
                    isOn: Binding(
                        get: { manager.isEnabled },
                        set: { value in Task { await manager.setEnabled(value) } }
                    )
                )
                .disabled(!isAuthorized && !manager.isEnabled)

                Button("Choose websites and categories") {
                    showingPicker = true
                }
                .disabled(!isAuthorized)
            } footer: {
                Text("Screen Time blocks only the websites and categories selected here. Safari filters and userscripts are unchanged.")
            }

            Section("Authorization") {
                Text(statusText)
                    .foregroundStyle(.secondary)

                if manager.authorizationStatus == .denied {
                    Button("Open Settings") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                } else if !isAuthorized {
                    Button("Authorize Screen Time") {
                        showingExplanation = true
                    }
                }
            }
        }
        .navigationTitle("Screen Time")
        .familyActivityPicker(isPresented: $showingPicker, selection: $manager.selection)
        .onChange(of: manager.selection) { _ in
            Task { await manager.saveSelection() }
        }
        .task { await manager.reconcile() }
        .alert("Before authorization", isPresented: $showingExplanation) {
            Button("Continue") {
                Task { await manager.requestAuthorization() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("wBlock uses Apple’s Family Controls permission to shield the websites and categories you choose. Application selections are ignored. Safari blocking continues if permission is unavailable.")
        }
        .alert(
            "Screen Time",
            isPresented: Binding(
                get: { manager.errorMessage != nil },
                set: { if !$0 { manager.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { manager.errorMessage = nil }
        } message: {
            Text(manager.errorMessage ?? "")
        }
    }

    private var statusText: String {
        if isAuthorized { return String(localized: "Authorized") }
        if manager.authorizationStatus == .denied {
            return String(localized: "Authorization denied")
        }
        return String(localized: "Authorization not granted")
    }
}
#endif
