//
//  SetupChecklistView.swift
//  wBlock
//
//  Created by Alexander Skula on 10/26/25.
//

import SwiftUI
import wBlockCoreService

#if os(macOS)
import AppKit
#endif

struct SetupChecklistView: View {
    @ObservedObject var dataManager = ProtobufDataManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var hasEnabledContentBlockers = false
    @State private var hasEnabledAdvanced = false

    private var allChecklistItemsCompleted: Bool {
        hasEnabledContentBlockers && hasEnabledAdvanced
    }

    var body: some View {
        SheetContainer {
            VStack(spacing: 0) {
                // Header
                headerView

                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        warningBanner

                        checklistItems

                        Text("Already done this? Just check the boxes above.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }

                // Bottom toolbar
                SheetBottomToolbar {
                    Spacer()

                    Button("Continue") {
                        Task {
                            await saveAndDismiss()
                        }
                    }
                    .primaryActionButtonStyle()
                    .disabled(!allChecklistItemsCompleted)
                }
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            loadCurrentState()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.exclamationmark.fill")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)
                .symbolRenderingMode(.multicolor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Critical Setup Required")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("For complete ad blocking")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, SheetDesign.headerHorizontalPadding)
        .padding(.top, SheetDesign.headerTopPadding)
        .padding(.bottom, 12)
    }

    // MARK: - Warning Banner

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .symbolRenderingMode(.multicolor)

            VStack(alignment: .leading, spacing: 4) {
                #if os(macOS)
                Text("wBlock Advanced must be enabled and set to 'All Websites' to block YouTube ads.")
                    .font(.subheadline)
                #else
                Text("wBlock Scripts must be enabled and set to 'All Websites' to block YouTube ads.")
                    .font(.subheadline)
                #endif
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Checklist Items

    private var checklistItems: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Setup Instructions")
                    .font(.headline)
                Spacer()
                Button {
                    openSafariExtensionsSettings()
                } label: {
                    Label("Open Safari Settings", systemImage: "gear")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text("1.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: 20, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        #if os(macOS)
                        Text("Safari → Settings → Extensions")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Enable all 5 Content Blocker extensions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        #else
                        Text("Settings → Apps → Safari → Extensions")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Enable all 5 Content Blocker extensions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        #endif
                    }

                    Spacer()

                    Toggle("", isOn: $hasEnabledContentBlockers)
                        .labelsHidden()
                }

                Divider()
                    .padding(.leading, 30)

                HStack(alignment: .top, spacing: 10) {
                    Text("2.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: 20, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        #if os(macOS)
                        Text("Enable 'wBlock Advanced' → Always Allow on Every Website")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Required for YouTube ad blocking and much more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        #else
                        Text("Enable 'wBlock Scripts' → Always Allow on Every Website")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Required for YouTube ad blocking and much more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        #endif
                    }

                    Spacer()

                    Toggle("", isOn: $hasEnabledAdvanced)
                        .labelsHidden()
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func loadCurrentState() {
        hasEnabledContentBlockers = dataManager.hasEnabledContentBlockers
        hasEnabledAdvanced = dataManager.hasEnabledPlatformExtension && dataManager.hasSetAllWebsitesPermission
    }

    private func saveAndDismiss() async {
        // Save the state
        await dataManager.setHasEnabledContentBlockers(hasEnabledContentBlockers)
        await dataManager.setHasEnabledPlatformExtension(hasEnabledAdvanced)
        await dataManager.setHasSetAllWebsitesPermission(hasEnabledAdvanced)

        // Force UI update
        await MainActor.run {
            dataManager.objectWillChange.send()
        }

        // Give SwiftUI time to process the change
        try? await Task.sleep(for: .milliseconds(50))

        // The sheet will auto-dismiss because hasCompletedCriticalSetup is now true
    }

    private func openSafariExtensionsSettings() {
        #if os(macOS)
        // macOS: Open Safari's Settings/Preferences window
        // First, try to activate Safari if it's running
        let runningApps = NSWorkspace.shared.runningApplications
        if let safariApp = runningApps.first(where: { $0.bundleIdentifier == "com.apple.Safari" }) {
            safariApp.activate()

            // Use AppleScript to open Safari's preferences
            let script = """
            tell application "Safari"
                activate
            end tell
            tell application "System Events"
                tell process "Safari"
                    click menu item "Settings…" of menu "Safari" of menu bar 1
                end tell
            end tell
            """

            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if error != nil {
                    // If AppleScript fails, just activate Safari
                    safariApp.activate()
                }
            }
        } else {
            // Safari is not running, just open it
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Safari.app"))
        }
        #else
        // iOS: Try to open Settings > Safari > Extensions
        if let url = URL(string: "App-prefs:SAFARI&path=EXTENSIONS") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "App-prefs:") {
            // Fallback: Just open Settings app
            UIApplication.shared.open(url)
        }
        #endif
    }
}

#Preview("Setup Checklist") {
    SetupChecklistView()
}
