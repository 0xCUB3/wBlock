#if os(iOS)
import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

@MainActor
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()
    static let appGroup = "group.skula.wBlock"
    nonisolated static let activityName = "skula.wBlock.screen-time-expirations"

    @Published var selection: FamilyActivitySelection = ScreenTimeManager.loadSelection()
    @Published var isEnabled = UserDefaults(suiteName: appGroup)?.bool(forKey: "screenTime.enabled") ?? false
    @Published private(set) var authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published var errorMessage: String?

    private let defaults = UserDefaults(suiteName: appGroup)!
    private let store = ManagedSettingsStore()

    static func isAuthorized(_ status: AuthorizationStatus) -> Bool {
        if status == .approved { return true }
        if #available(iOS 26.4, *), status == .approvedWithDataAccess { return true }
        return false
    }

    func reconcile() async {
        pruneExpiredExceptions()
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        guard isEnabled, Self.isAuthorized(authorizationStatus) else {
            clearShields()
            ScreenTimeMonitorScheduler.stop()
            return
        }

        applyPolicy()
        scheduleNextExpiration()
    }

    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        defaults.set(enabled, forKey: "screenTime.enabled")
        await reconcile()
    }

    func saveSelection() async {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: "screenTime.selection")
        }
        await reconcile()
    }

    func requestAuthorization() async {
        do {
            if #available(iOS 16.0, *) {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            } else {
                try await withCheckedThrowingContinuation { continuation in
                    AuthorizationCenter.shared.requestAuthorization { result in
                        continuation.resume(with: result)
                    }
                }
            }
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            await reconcile()
        } catch {
            if let familyError = error as? FamilyControlsError,
               familyError == .authorizationCanceled {
                errorMessage = String(localized: "Screen Time setup was cancelled.")
            } else {
                errorMessage = String(localized: "Screen Time is unavailable or was not approved.")
            }
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            clearShields()
            ScreenTimeMonitorScheduler.stop()
        }
    }

    func clearShields() {
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }

    func applyPolicy() {
        let exceptions = activeExceptions()
        let domains = selection.webDomainTokens.subtracting(exceptions.webDomains)
        let categories = selection.categoryTokens.subtracting(exceptions.categories)
        store.shield.webDomains = domains.isEmpty ? nil : domains
        store.shield.webDomainCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: exceptions.webDomains)
    }

    struct Exception: Codable, Equatable {
        let kind: String
        let token: Data
        let expires: Date
    }

    static func exceptions() -> [Exception] {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "screenTime.exceptions") else {
            return []
        }
        return (try? JSONDecoder().decode([Exception].self, from: data)) ?? []
    }

    static func saveExceptions(_ values: [Exception]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: "screenTime.exceptions")
    }

    private func pruneExpiredExceptions() {
        Self.saveExceptions(Self.exceptions().filter { $0.expires > Date() })
    }

    private func activeExceptions() -> (
        webDomains: Set<WebDomainToken>,
        categories: Set<ActivityCategoryToken>
    ) {
        var domains = Set<WebDomainToken>()
        var categories = Set<ActivityCategoryToken>()
        for exception in Self.exceptions() where exception.expires > Date() {
            if exception.kind == "domain",
               let token = try? JSONDecoder().decode(WebDomainToken.self, from: exception.token) {
                domains.insert(token)
            } else if exception.kind == "category",
                      let token = try? JSONDecoder().decode(ActivityCategoryToken.self, from: exception.token) {
                categories.insert(token)
            }
        }
        return (domains, categories)
    }

    private func scheduleNextExpiration() {
        let next = Self.exceptions().map(\.expires).filter { $0 > Date() }.min()
        if !ScreenTimeMonitorScheduler.schedule(at: next) {
            Self.saveExceptions([])
            applyPolicy()
        }
    }

    private static func loadSelection() -> FamilyActivitySelection {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "screenTime.selection"),
              let value = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return value
    }
}

private enum ScreenTimeMonitorScheduler {
    private static var activity: DeviceActivityName {
        DeviceActivityName(ScreenTimeManager.activityName)
    }

    static func stop() {
        DeviceActivityCenter().stopMonitoring([activity])
    }

    static func schedule(at date: Date?) -> Bool {
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        guard let date else { return true }

        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute, .second], from: Date().addingTimeInterval(-1))
        let end = calendar.dateComponents([.hour, .minute, .second], from: date)
        do {
            try center.startMonitoring(
                activity,
                during: DeviceActivitySchedule(
                    intervalStart: start,
                    intervalEnd: end,
                    repeats: false
                )
            )
            return true
        } catch {
            return false
        }
    }
}
#endif
