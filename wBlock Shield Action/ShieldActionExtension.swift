import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    private let activity = DeviceActivityName("skula.wBlock.screen-time-expirations")
    private let defaults = UserDefaults(suiteName: "group.skula.wBlock")!
    private let store = ManagedSettingsStore()

    private func allow<T: Codable>(
        _ token: T,
        kind: String,
        completion: @escaping (ShieldActionResponse) -> Void
    ) {
        guard let data = try? JSONEncoder().encode(token) else {
            completion(.close)
            return
        }

        let now = Date()
        let entry = ScreenTimeException(
            kind: kind,
            token: data,
            expires: now.addingTimeInterval(15 * 60)
        )
        var exceptions = loadExceptions().filter { $0.expires > now }
        exceptions.removeAll { $0.kind == kind && $0.token == data }
        exceptions.append(entry)
        saveExceptions(exceptions)
        applyPolicy(exceptions: exceptions)

        if schedule(exceptions: exceptions) {
            completion(.none)
            return
        }

        exceptions.removeAll { $0 == entry }
        if !schedule(exceptions: exceptions) {
            exceptions.removeAll()
        }
        saveExceptions(exceptions)
        applyPolicy(exceptions: exceptions)
        completion(.close)
    }

    private func applyPolicy(exceptions: [ScreenTimeException]) {
        guard defaults.bool(forKey: "screenTime.enabled"), isAuthorized else {
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            return
        }

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

    private func schedule(exceptions: [ScreenTimeException]) -> Bool {
        let center = DeviceActivityCenter()
        center.stopMonitoring([activity])
        guard let next = exceptions.map(\.expires).filter({ $0 > Date() }).min() else {
            return true
        }

        let calendar = Calendar.current
        let start = calendar.dateComponents([.hour, .minute, .second], from: Date().addingTimeInterval(-1))
        let end = calendar.dateComponents([.hour, .minute, .second], from: next)
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

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        if action == .secondaryButtonPressed {
            allow(webDomain, kind: "domain", completion: completionHandler)
        } else {
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        if action == .secondaryButtonPressed {
            allow(category, kind: "category", completion: completionHandler)
        } else {
            completionHandler(.close)
        }
    }
}

private struct ScreenTimeException: Codable, Equatable {
    let kind: String
    let token: Data
    let expires: Date
}
