#if canImport(AppIntents) && !os(visionOS)
import AppIntents
import Foundation
import wBlockCoreService
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@available(iOS 16.0, macOS 13.0, *)
struct UpdateWBlockFiltersIntent: AppIntent {
    static var title: LocalizedStringResource = "Update wBlock Filters"
    static var description = IntentDescription("Checks for wBlock filter updates and applies them when available.")
    static var openAppWhenRun: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let filterManager: AppFilterManager?
        #if os(macOS)
        filterManager = (NSApplication.shared.delegate as? AppDelegate)?.filterManager
        #elseif os(iOS)
        filterManager = (UIApplication.shared.delegate as? AppDelegate)?.filterManager
        #else
        filterManager = nil
        #endif

        await WBlockLaunchSetup.run()
        let manager = filterManager ?? AppFilterManager()
        await manager.waitUntilReady()
        await UserScriptManager.shared.waitUntilReady()
        manager.setUserScriptManager(UserScriptManager.shared)
        await manager.performFilterUpdate(showProgress: false)

        return .result(dialog: IntentDialog("wBlock filter update started."))
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
