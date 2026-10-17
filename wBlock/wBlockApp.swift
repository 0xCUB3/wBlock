//
//  wBlockApp.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
import wBlockCoreService

@MainActor
enum WBlockLaunchSetup {
    static func run() async {
        await ProtobufDataManager.shared.waitUntilLoaded()
        await UserScriptManager.shared.waitUntilReady()
    }
}

@main
struct wBlockApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var filterManager = AppFilterManager()

    @Environment(\.scenePhase) private var scenePhase
    @State private var hasStartedLaunchSetup = false
    @State private var hasCompletedLaunchSetup = false

    #if os(macOS)
    @State private var showingRestartConfirmation = false
    #endif

    private func startLaunchSetupIfNeeded() {
        guard !hasStartedLaunchSetup else { return }
        hasStartedLaunchSetup = true

        Task {
            await WBlockLaunchSetup.run()
            await MainActor.run {
                hasCompletedLaunchSetup = true
                CloudSyncManager.shared.activateAfterLaunchSetup()
            }
        }
    }

    #if os(iOS)
    @State private var pendingFilterUpdateRequest = false

    private func runPendingFilterUpdate() {
        guard pendingFilterUpdateRequest, hasCompletedLaunchSetup,
              !filterManager.isLoading, !filterManager.showingApplyProgressSheet else { return }
        pendingFilterUpdateRequest = false
        Task { await filterManager.checkForUpdates(scope: .filters, presentation: .blocking) }
    }
    #endif

    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    var body: some Scene {
        WindowGroup {
            ContentView(filterManager: filterManager)
                .modifier(AppAppearanceModifier(appearance: appearance))
                .onAppear {
                    #if os(macOS)
                    if HeadlessLaunch.isHeadlessProcess {
                        for window in NSApp.windows { window.orderOut(nil) }
                        return
                    }
                    #endif
                    appDelegate.filterManager = filterManager
                    CloudSyncManager.shared.attach(filterManager: filterManager)
                    if appDelegate.hasPendingApplyNotification {
                        appDelegate.hasPendingApplyNotification = false
                        NotificationCenter.default.post(name: .applyWBlockChangesNotification, object: nil)
                    }

                    startLaunchSetupIfNeeded()
                }
                .onChangeCompat(of: scenePhase) { _, newPhase in
                    guard newPhase == .active, hasCompletedLaunchSetup else { return }
                    Task { await CloudSyncManager.shared.syncNow(trigger: "AppActive") }
                }
                #if os(iOS)
                .onOpenURL { url in
                    guard url.scheme == "wblockapp", url.host == "update-filters" else { return }
                    pendingFilterUpdateRequest = true
                    runPendingFilterUpdate()
                }
                .onChangeCompat(of: hasCompletedLaunchSetup) { _, _ in runPendingFilterUpdate() }
                .onChangeCompat(of: filterManager.isLoading) { _, _ in runPendingFilterUpdate() }
                .onChangeCompat(of: filterManager.showingApplyProgressSheet) { _, _ in runPendingFilterUpdate() }
                #endif
                #if os(macOS)
                .handlesExternalEvents(preferring: Set(["open"]), allowing: Set(["*"]))
                .confirmationDialog(
                    "Restart Onboarding?",
                    isPresented: $showingRestartConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Restart", role: .destructive) {
                        Task { @MainActor in
                            await filterManager.completeResetForOnboarding()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will reset all filters, userscripts, and preferences.")
                }
                #endif
        }
        #if os(macOS)
        .handlesExternalEvents(matching: Set(["open"]))
        #endif
        // The macOS and iPadOS menu bars, and hardware-keyboard shortcuts.
        .commands {
            // The Settings tab is wBlock's settings window; ⌘, goes there
            // rather than opening a second copy of it (#999).
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { post(.wBlockSelectTabRequest, 2) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            #if os(macOS)
            CommandGroup(after: .appInfo) {
                Button("Restart Onboarding") {
                    showingRestartConfirmation = true
                }
            }
            #endif
            // ⌘N used to open a second copy of the main window, which looked
            // like nothing happened. Repurpose it for the Add sheets.
            CommandGroup(replacing: .newItem) {
                Button("Add Filter List…") {
                    NotificationCenter.default.post(name: .wBlockAddFilterListRequest, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Add Userscript or Userstyle…") {
                    NotificationCenter.default.post(name: .wBlockAddUserScriptRequest, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Search") {
                    NotificationCenter.default.post(name: .wBlockSearchRequest, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
            CommandGroup(before: .toolbar) {
                Button("Filters") { post(.wBlockSelectTabRequest, 0) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Userscripts") { post(.wBlockSelectTabRequest, 1) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Settings") { post(.wBlockSelectTabRequest, 2) }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Show Enabled Only") { post(.wBlockToggleEnabledOnlyRequest) }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                Button("Logs") { post(.wBlockShowLogsRequest) }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
            }
            CommandGroup(replacing: .help) {
                Link("FAQ", destination: SettingsView.faqURL)
                Link("Report Issues", destination: SettingsView.reportIssueURL)
                Link("Contact Us", destination: SettingsView.contactURL)
                Link("Source Code", destination: SettingsView.sourceCodeURL)
            }
            CommandMenu("Updates") {
                Button("Update") { post(.wBlockUpdateRequest) }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Check for Filter Updates") {
                    NotificationCenter.default.post(name: .wBlockCheckFilterUpdatesRequest, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                Button("Check for Userscript Updates") {
                    NotificationCenter.default.post(name: .wBlockCheckScriptUpdatesRequest, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                Divider()
                Button("Apply Without Checking for Updates") { filterManager.forceApplyChanges() }
                Divider()
                Menu("Pause Blocking") { PauseBlockingControls(filterManager: filterManager) }
            }
        }
    }

    private func post(_ name: Notification.Name, _ object: Int? = nil) {
        NotificationCenter.default.post(name: name, object: object)
    }
}
