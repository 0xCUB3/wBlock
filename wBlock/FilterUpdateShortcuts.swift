#if canImport(AppIntents) && !os(visionOS)
import AppIntents
import Foundation
import wBlockCoreService

extension Notification.Name {
    static let shortcutFilterUpdatePresentationChanged = Notification.Name("shortcutFilterUpdatePresentationChanged")
}

enum ShortcutFilterUpdatePresentationResult {
    case updated
    case noUpdates
    case skipped
    case deferred
    case failed
    case cancelled
}

enum ShortcutFilterUpdatePresentationStyle: String {
    case running
    case success
    case warning
    case failure
}

struct ShortcutFilterUpdatePresentationState {
    var title: String
    var message: String
    var style: ShortcutFilterUpdatePresentationStyle
}

@MainActor
final class ShortcutFilterUpdatePresentation {
    static let shared = ShortcutFilterUpdatePresentation()

    private(set) var state: ShortcutFilterUpdatePresentationState?

    private init() {}

    func start() {
        state = ShortcutFilterUpdatePresentationState(
            title: String(localized: "Updating wBlock Filters"),
            message: String(localized: "Checking for filter updates..."),
            style: .running
        )
        postChange()
    }

    func finish(result: ShortcutFilterUpdatePresentationResult, message: String) {
        state = ShortcutFilterUpdatePresentationState(
            title: Self.title(for: result),
            message: message,
            style: Self.style(for: result)
        )
        postChange()
    }

    private func postChange() {
        NotificationCenter.default.post(name: .shortcutFilterUpdatePresentationChanged, object: nil)
    }

    private static func title(for result: ShortcutFilterUpdatePresentationResult) -> String {
        switch result {
        case .updated:
            return String(localized: "wBlock Filters Updated")
        case .noUpdates:
            return String(localized: "No Filter Updates")
        case .skipped:
            return String(localized: "Filter Update Skipped")
        case .deferred:
            return String(localized: "Filter Update Deferred")
        case .failed:
            return String(localized: "Filter Update Failed")
        case .cancelled:
            return String(localized: "Filter Update Cancelled")
        }
    }

    private static func style(for result: ShortcutFilterUpdatePresentationResult) -> ShortcutFilterUpdatePresentationStyle {
        switch result {
        case .updated, .noUpdates:
            return .success
        case .skipped, .deferred, .cancelled:
            return .warning
        case .failed:
            return .failure
        }
    }
}

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
private extension ShortcutFilterUpdatePresentationResult {
    init(_ result: FilterUpdateShortcutResult) {
        switch result {
        case .updated:
            self = .updated
        case .noUpdates:
            self = .noUpdates
        case .skipped:
            self = .skipped
        case .deferred:
            self = .deferred
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        }
    }
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
        await ShortcutFilterUpdatePresentation.shared.start()

        let trigger = "Shortcut"
        let outcome = await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(
            trigger: trigger,
            force: forceCheck,
            policy: .foreground(trigger: trigger)
        )
        let response = Self.response(for: outcome)
        await ShortcutFilterUpdatePresentation.shared.finish(
            result: ShortcutFilterUpdatePresentationResult(response.result),
            message: response.message
        )
        return .result(value: response.result, dialog: IntentDialog(stringLiteral: response.message))
    }

    private static func response(
        for outcome: SharedAutoUpdateManager.AutoUpdateRunOutcome
    ) -> (result: FilterUpdateShortcutResult, message: String) {
        switch outcome {
        case let .completed(completion):
            return completedResponse(for: completion)
        case let .skipped(reason):
            return (.skipped, skippedDialog(for: reason))
        case .cancelled:
            return (.cancelled, String(localized: "wBlock filter update was cancelled."))
        case .deferred(_):
            return (.deferred, String(localized: "wBlock filter update was deferred. Open wBlock to finish updating."))
        case .failed(_):
            return (.failed, String(localized: "wBlock filter update failed. Open wBlock for details."))
        }
    }

    private static func completedResponse(
        for completion: SharedAutoUpdateManager.AutoUpdateCompletion
    ) -> (result: FilterUpdateShortcutResult, message: String) {
        let didUpdate = completion.updatedFilters > 0 || completion.updatedScripts > 0

        switch completion.result {
        case .appliedUpdates:
            return (.updated, String(localized: "wBlock filters updated."))
        case .noFilterUpdates where completion.updatedScripts > 0:
            return (.updated, String(localized: "No filter updates found. Userscripts updated."))
        case .noFilterUpdates:
            return (.noUpdates, String(localized: "No filter updates found."))
        case .noSelectedFilters where didUpdate:
            return (.updated, String(localized: "No filters are selected. Userscripts updated."))
        case .noSelectedFilters:
            return (.noUpdates, String(localized: "No filters are selected."))
        }
    }

    private static func skippedDialog(for reason: String) -> String {
        switch reason {
        case "already_running":
            return String(localized: "wBlock filter update is already running.")
        case "auto_update_disabled":
            return String(localized: "wBlock filter auto-update is disabled.")
        case "throttled_not_eligible", "throttled_legacy_interval":
            return String(localized: "wBlock filter update skipped because it is not due yet.")
        case "extension_safe_mode":
            return String(localized: "Open wBlock to update filters.")
        default:
            return String(localized: "wBlock filter update skipped.")
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
