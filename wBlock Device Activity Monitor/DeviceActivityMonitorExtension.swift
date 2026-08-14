import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let expectedActivity = "skula.wBlock.screen-time-expirations"
    private let defaults = UserDefaults(suiteName: "group.skula.wBlock")!
    private let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        restoreExpiredExceptions(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        restoreExpiredExceptions(for: activity)
    }

    private func restoreExpiredExceptions(for activity: DeviceActivityName) {
        guard activity.rawValue == expectedActivity else { return }

        var exceptions = loadExceptions().filter { $0.expires > Date() }
        saveExceptions(exceptions)

        guard defaults.bool(forKey: "screenTime.enabled"), isAuthorized else {
            clearShields()
            DeviceActivityCenter().stopMonitoring([activity])
            return
        }

        applyPolicy(exceptions: exceptions)
        if !scheduleNext(activity: activity, exceptions: exceptions) {
            exceptions.removeAll()
            saveExceptions(exceptions)
            applyPolicy(exceptions: exceptions)
        }
    }

    private func applyPolicy(exceptions: [ScreenTimeException]) {
        let selection = loadSelection()
        let domainExceptions = Set(exceptions.compactMap { exception in
            exception.kind == "domain"
                ? try? JSONDecoder().decode(WebDomainToken.self, from: exception.token)
                : nil
        })
        let categoryExceptions = Set(exceptions.compactMap { exception in
            exception.kind == "category"
                ? try? JSONDecoder().decode(ActivityCategoryToken.self, from: exception.token)
                : nil
        })
        let domains = selection.webDomainTokens.subtracting(domainExceptions)
        let categories = selection.categoryTokens.subtracting(categoryExceptions)
        store.shield.webDomains = domains.isEmpty ? nil : domains
        store.shield.webDomainCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: domainExceptions)
    }

    private func clearShields() {
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }

    private var isAuthorized: Bool {
        let status = AuthorizationCenter.shared.authorizationStatus
        if status == .approved { return true }
        if #available(iOS 26.4, *), status == .approvedWithDataAccess { return true }
        return false
    }

    private func loadSelection() -> FamilyActivitySelection {
        guard let data = defaults.data(forKey: "screenTime.selection") else {
            return FamilyActivitySelection()
        }
        return (try? JSONDecoder().decode(FamilyActivitySelection.self, from: data))
            ?? FamilyActivitySelection()
    }

    private func loadExceptions() -> [ScreenTimeException] {
        guard let data = defaults.data(forKey: "screenTime.exceptions") else { return [] }
        return (try? JSONDecoder().decode([ScreenTimeException].self, from: data)) ?? []
    }

    private func saveExceptions(_ exceptions: [ScreenTimeException]) {
        guard let data = try? JSONEncoder().encode(exceptions) else { return }
        defaults.set(data, forKey: "screenTime.exceptions")
    }

    private func scheduleNext(
        activity: DeviceActivityName,
        exceptions: [ScreenTimeException]
    ) -> Bool {
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        guard let next = exceptions.map(\.expires).filter({ $0 > Date() }).min() else {
            return true
        }

        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute, .second], from: next)
        let end = calendar.dateComponents(
            [.hour, .minute, .second],
            from: next.addingTimeInterval(15 * 60)
        )
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

private struct ScreenTimeException: Codable {
    let kind: String
    let token: Data
    let expires: Date
}
