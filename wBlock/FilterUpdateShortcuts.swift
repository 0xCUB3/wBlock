#if canImport(AppIntents) && !os(visionOS)
import AppIntents
import Foundation

extension Notification.Name {
    static let shortcutFilterUpdateRequested = Notification.Name("shortcutFilterUpdateRequested")
}

@MainActor
final class ShortcutFilterUpdateRequest {
    static let shared = ShortcutFilterUpdateRequest()

    private var isPending = false

    private init() {}

    func requestUpdate() {
        isPending = true
        NotificationCenter.default.post(name: .shortcutFilterUpdateRequested, object: nil)
    }

    func consumePendingRequest() -> Bool {
        guard isPending else { return false }
        isPending = false
        return true
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct UpdateWBlockFiltersIntent: AppIntent {
    static var title: LocalizedStringResource = "Update wBlock Filters"
    static var description = IntentDescription("Checks for wBlock filter updates and applies them when available.")
    static var openAppWhenRun: Bool { true }

    init() {}

    func perform() async throws -> some ProvidesDialog {
        await ShortcutFilterUpdateRequest.shared.requestUpdate()
        return .result(dialog: "wBlock filter update started.")
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
