#if canImport(AppIntents) && !os(visionOS)
import AppIntents
import Foundation
import wBlockCoreService

@available(iOS 16.0, macOS 13.0, *)
enum FilterUpdateShortcutResult: String, AppEnum {
    case updated
    case noUpdates
    case skipped
    case deferred
    case failed
    case cancelled

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Filter Update Result")

    static var caseDisplayRepresentations: [FilterUpdateShortcutResult: DisplayRepresentation] = [
        .updated: "Updated",
        .noUpdates: "No Updates",
        .skipped: "Skipped",
        .deferred: "Deferred",
        .failed: "Failed",
        .cancelled: "Cancelled",
    ]
}

@available(iOS 16.0, macOS 13.0, *)
struct UpdateWBlockFiltersIntent: AppIntent {
    static var title: LocalizedStringResource = "Update wBlock Filters"
    static var description = IntentDescription("Checks for wBlock filter updates and applies them when available.")
    static var openAppWhenRun: Bool { true }

    @Parameter(
        title: "Force Check",
        description: "Check now even if automatic updates are not due yet."
    )
    var forceCheck: Bool

    init() {
        self.forceCheck = false
    }

    init(forceCheck: Bool) {
        self.forceCheck = forceCheck
    }

    func perform() async throws -> some ReturnsValue<FilterUpdateShortcutResult> & ProvidesDialog {
        let trigger = "Shortcut"
        let outcome = await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(
            trigger: trigger,
            force: forceCheck,
            policy: .foreground(trigger: trigger)
        )
        let response = Self.response(for: outcome)
        return .result(value: response.result, dialog: response.dialog)
    }

    private static func response(
        for outcome: SharedAutoUpdateManager.AutoUpdateRunOutcome
    ) -> (result: FilterUpdateShortcutResult, dialog: IntentDialog) {
        switch outcome {
        case let .completed(completion):
            return completedResponse(for: completion)
        case let .skipped(reason):
            return (.skipped, skippedDialog(for: reason))
        case .cancelled:
            return (.cancelled, "wBlock filter update was cancelled.")
        case .deferred(_):
            return (.deferred, "wBlock filter update was deferred. Open wBlock to finish updating.")
        case .failed(_):
            return (.failed, "wBlock filter update failed. Open wBlock for details.")
        }
    }

    private static func completedResponse(
        for completion: SharedAutoUpdateManager.AutoUpdateCompletion
    ) -> (result: FilterUpdateShortcutResult, dialog: IntentDialog) {
        let didUpdate = completion.updatedFilters > 0 || completion.updatedScripts > 0

        switch completion.result {
        case .appliedUpdates:
            return (.updated, "wBlock filters updated.")
        case .noFilterUpdates where completion.updatedScripts > 0:
            return (.updated, "No filter updates found. Userscripts updated.")
        case .noFilterUpdates:
            return (.noUpdates, "No filter updates found.")
        case .noSelectedFilters where didUpdate:
            return (.updated, "No filters are selected. Userscripts updated.")
        case .noSelectedFilters:
            return (.noUpdates, "No filters are selected.")
        }
    }

    private static func skippedDialog(for reason: String) -> IntentDialog {
        switch reason {
        case "already_running":
            return "wBlock filter update is already running."
        case "auto_update_disabled":
            return "wBlock filter auto-update is disabled."
        case "throttled_not_eligible", "throttled_legacy_interval":
            return "wBlock filter update skipped because it is not due yet."
        case "extension_safe_mode":
            return "Open wBlock to update filters."
        default:
            return "wBlock filter update skipped."
        }
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
