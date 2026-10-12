#if canImport(AppIntents) && !os(visionOS)
import AppIntents
import Foundation
import wBlockCoreService

@available(iOS 16.0, macOS 13.0, *)
struct UpdateWBlockFiltersIntent: AppIntent {
    static var title: LocalizedStringResource = "Update wBlock Filters"
    static var description = IntentDescription("Checks for wBlock filter updates and applies them when available.")
    /// iOS cuts an intent off after about 30 seconds, in the background or not, which
    /// stopped full applies between content-blocker reloads. There the shortcut opens
    /// wBlock and hands the apply to the visible app. macOS has no such limit.
    #if os(iOS)
    static var openAppWhenRun: Bool { true }
    #else
    static var openAppWhenRun: Bool { false }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        #if os(iOS)
        Task { await Self.runUpdate() }
        return .result(dialog: IntentDialog("wBlock filter update started."))
        #else
        guard let manager = await Self.runUpdate() else {
            return .result(dialog: IntentDialog("A wBlock filter update is already in progress."))
        }
        if manager.lastApplySucceeded && !manager.hasError {
            return .result(dialog: IntentDialog("wBlock filter update completed."))
        }
        return .result(dialog: IntentDialog("wBlock filter update completed with errors."))
        #endif
    }

    /// Returns the manager that ran the update, or nil when another apply was in flight.
    @MainActor
    @discardableResult
    private static func runUpdate() async -> AppFilterManager? {
        await WBlockLaunchSetup.run()
        let manager = await appFilterManager() ?? AppFilterManager()
        await manager.waitUntilReady()
        await UserScriptManager.shared.waitUntilReady()
        manager.setUserScriptManager(UserScriptManager.shared)
        return await manager.performFilterUpdate(showProgress: openAppWhenRun) ? manager : nil
    }

    /// The app's own manager, so its progress sheet and apply guard see this update.
    @MainActor
    private static func appFilterManager() async -> AppFilterManager? {
        #if os(iOS)
        // A cold launch attaches the manager when the first scene appears.
        for _ in 0..<50 {
            if let manager = AppDelegate.current?.filterManager { return manager }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #endif
        return AppDelegate.current?.filterManager
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct WBlockShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UpdateWBlockFiltersIntent(),
            phrases: [
                "Update \(.applicationName) filters",
                "Check \(.applicationName) filters",
                "Update filters in \(.applicationName)",
            ],
            shortTitle: "Update Filters",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
#endif
