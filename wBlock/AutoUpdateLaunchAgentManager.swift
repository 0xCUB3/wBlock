#if os(macOS)
import Foundation
import ServiceManagement
import os.log

@MainActor
final class AutoUpdateLaunchAgentManager {
    static let shared = AutoUpdateLaunchAgentManager()
    static let plistName = "skula.wBlock.FilterUpdateAgent.plist"

    struct RegistrationStatus: Equatable {
        enum State: Equatable {
            case enabled
            case requiresApproval
            case notRegistered
            case notFound
            case unavailable
        }

        let state: State
        let detail: String

        var isRegistered: Bool {
            state == .enabled || state == .requiresApproval
        }

        var needsApproval: Bool {
            state == .requiresApproval
        }
    }

    private let logger = Logger(subsystem: "skula.wBlock", category: "AutoUpdateLaunchAgent")

    private init() {}

    private var service: SMAppService {
        SMAppService.agent(plistName: Self.plistName)
    }

    func currentStatus() -> RegistrationStatus {
        status(from: service.status)
    }

    @discardableResult
    func reconcileWithAutoUpdateSetting(_ enabled: Bool) -> RegistrationStatus {
        let current = service.status

        do {
            if enabled {
                if current != .enabled && current != .requiresApproval {
                    try service.register()
                }
            } else if current == .enabled || current == .requiresApproval {
                try service.unregister()
            }
        } catch {
            logger.error("Launch agent reconcile failed: \(error.localizedDescription, privacy: .public)")
            let refreshed = service.status
            if refreshed == .enabled || refreshed == .requiresApproval || refreshed == .notRegistered || refreshed == .notFound {
                return status(from: refreshed)
            }
            return RegistrationStatus(
                state: .unavailable,
                detail: "Background agent error: \(error.localizedDescription)"
            )
        }

        return currentStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func status(from serviceStatus: SMAppService.Status) -> RegistrationStatus {
        switch serviceStatus {
        case .enabled:
            return RegistrationStatus(state: .enabled, detail: "Background agent registered")
        case .requiresApproval:
            return RegistrationStatus(
                state: .requiresApproval,
                detail: "Background agent needs approval in Login Items"
            )
        case .notRegistered:
            return RegistrationStatus(state: .notRegistered, detail: "Background agent not registered")
        case .notFound:
            return RegistrationStatus(state: .notFound, detail: "Bundled background agent missing from app build")
        @unknown default:
            return RegistrationStatus(state: .unavailable, detail: "Background agent status unavailable")
        }
    }
}
#endif
