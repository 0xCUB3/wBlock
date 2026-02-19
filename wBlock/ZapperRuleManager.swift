import Foundation
import os.log
import wBlockCoreService

/// ZapperRuleManager is the unified data layer for element zapper rules stored in shared UserDefaults.
///
/// It enumerates all hostnames that have saved rules, reads rules per hostname, and deletes
/// rules individually or in bulk. Phase 9 Settings UI binds to this ObservableObject.
@MainActor
final class ZapperRuleManager: ObservableObject {
    static let shared = ZapperRuleManager()

    /// Sorted list of hostnames that have at least one zapper rule.
    @Published private(set) var domains: [String] = []

    /// Convenience binding target: rules for the currently selected domain.
    @Published private(set) var rulesForSelectedDomain: [String] = []

    /// When set, automatically loads rulesForSelectedDomain. Cleared to nil when no domain is selected.
    @Published var selectedDomain: String? {
        didSet {
            if let hostname = selectedDomain {
                rulesForSelectedDomain = rules(for: hostname)
            } else {
                rulesForSelectedDomain = []
            }
        }
    }

    private let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
    private let keyPrefix = "zapperRules_"
    private let logger = Logger(subsystem: "skula.wBlock", category: "ZapperRuleManager")

    private init() {}

    // MARK: - Public API

    /// Scans all UserDefaults keys matching the zapperRules_* prefix, extracts hostnames,
    /// sorts alphabetically, and updates the published domains array.
    /// Domains with no non-empty rules are excluded.
    func refresh() {
        let allKeys = defaults?.dictionaryRepresentation().keys.map { $0 } ?? []
        let discovered = allKeys
            .filter { $0.hasPrefix(keyPrefix) }
            .map { String($0.dropFirst(keyPrefix.count)) }
            .filter { !rules(for: $0).isEmpty }
            .sorted()
        domains = discovered
        logger.info("ZapperRuleManager: Refreshed — found \(discovered.count) domain(s) with rules")
    }

    /// Returns the stored CSS selector strings for the given hostname, filtered for non-empty entries.
    func rules(for hostname: String) -> [String] {
        let key = keyPrefix + hostname
        let raw = defaults?.stringArray(forKey: key) ?? []
        return raw.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Removes a single CSS selector from the stored array for the hostname.
    /// If the array becomes empty after removal, the UserDefaults key is deleted entirely.
    /// Updates domains and rulesForSelectedDomain when the affected domain is selected.
    func deleteRule(_ rule: String, forDomain hostname: String) {
        let key = keyPrefix + hostname
        var current = defaults?.stringArray(forKey: key) ?? []
        current.removeAll { $0 == rule }

        if current.isEmpty {
            defaults?.removeObject(forKey: key)
            domains.removeAll { $0 == hostname }
            logger.info("ZapperRuleManager: Deleted last rule for '\(hostname)' — key removed")
        } else {
            defaults?.setValue(current, forKey: key)
            logger.info("ZapperRuleManager: Deleted rule for '\(hostname)' — \(current.count) remaining")
        }

        if selectedDomain == hostname {
            rulesForSelectedDomain = rules(for: hostname)
        }
    }

    /// Removes the UserDefaults key for the hostname entirely, deleting all its rules.
    /// Updates domains and clears rulesForSelectedDomain if the domain was selected.
    func deleteAllRules(forDomain hostname: String) {
        let key = keyPrefix + hostname
        defaults?.removeObject(forKey: key)
        domains.removeAll { $0 == hostname }
        logger.info("ZapperRuleManager: Deleted all rules for '\(hostname)'")

        if selectedDomain == hostname {
            rulesForSelectedDomain = []
        }
    }

    /// Returns the number of rules stored for the given hostname.
    func ruleCount(forDomain hostname: String) -> Int {
        return rules(for: hostname).count
    }

    /// Re-inserts a previously deleted rule back into UserDefaults for the given hostname.
    /// Used by the undo banner in ZapperRuleManagerView.
    /// - Parameters:
    ///   - rule: The CSS selector string to restore.
    ///   - hostname: The domain the rule belongs to.
    ///   - index: The original position in the array; clamped to array bounds.
    func restoreRule(_ rule: String, forDomain hostname: String, at index: Int) {
        let key = keyPrefix + hostname
        var current = defaults?.stringArray(forKey: key) ?? []
        let insertIndex = min(index, current.count)
        current.insert(rule, at: insertIndex)
        defaults?.setValue(current, forKey: key)

        if !domains.contains(hostname) {
            refresh()
        }

        if selectedDomain == hostname {
            rulesForSelectedDomain = rules(for: hostname)
        }

        logger.info("ZapperRuleManager: Restored rule for '\(hostname)' at index \(insertIndex)")
    }
}
