import Foundation
import os.log
import wBlockCoreService

/// ZapperRuleManager is the unified data layer for element zapper rules stored in protobuf.
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

    private let logger = Logger(subsystem: "skula.wBlock", category: "ZapperRuleManager")

    private init() {}

    // MARK: - Public API

    /// Reads all hostnames with zapper rules from protobuf and updates the published domains array.
    func refresh() {
        let discovered = ProtobufDataManager.shared.getZapperDomains()
        domains = discovered
        logger.info("ZapperRuleManager: Refreshed — found \(discovered.count) domain(s) with rules")
    }

    /// Returns the stored CSS selector strings for the given hostname, filtered for non-empty entries.
    func rules(for hostname: String) -> [String] {
        ProtobufDataManager.shared.getZapperRules(forHost: hostname)
    }

    /// Removes a single CSS selector from the stored array for the hostname.
    /// If the array becomes empty after removal, the host is removed from domains.
    /// Updates domains and rulesForSelectedDomain when the affected domain is selected.
    func deleteRule(_ rule: String, forDomain hostname: String) {
        Task {
            await ProtobufDataManager.shared.deleteZapperRule(rule, forHost: hostname)
        }

        // Update local state optimistically
        if ProtobufDataManager.shared.getZapperRules(forHost: hostname).filter({ $0 != rule }).isEmpty {
            domains.removeAll { $0 == hostname }
            logger.info("ZapperRuleManager: Deleted last rule for '\(hostname)'")
        } else {
            logger.info("ZapperRuleManager: Deleted rule for '\(hostname)'")
        }

        if selectedDomain == hostname {
            rulesForSelectedDomain = rules(for: hostname).filter { $0 != rule }
        }
    }

    /// Removes all rules for the hostname entirely.
    /// Updates domains and clears rulesForSelectedDomain if the domain was selected.
    func deleteAllRules(forDomain hostname: String) {
        Task {
            await ProtobufDataManager.shared.deleteAllZapperRules(forHost: hostname)
        }

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

    /// Re-inserts a previously deleted rule back for the given hostname.
    /// Used by the undo banner in ZapperRuleManagerView.
    /// - Parameters:
    ///   - rule: The CSS selector string to restore.
    ///   - hostname: The domain the rule belongs to.
    ///   - index: The original position in the array; clamped to array bounds.
    func restoreRule(_ rule: String, forDomain hostname: String, at index: Int) {
        Task {
            await ProtobufDataManager.shared.restoreZapperRule(rule, forHost: hostname, at: index)
        }

        if !domains.contains(hostname) {
            refresh()
        }

        if selectedDomain == hostname {
            rulesForSelectedDomain = rules(for: hostname)
            // If the async hasn't committed yet, add it locally
            if !rulesForSelectedDomain.contains(rule) {
                let insertIndex = min(index, rulesForSelectedDomain.count)
                rulesForSelectedDomain.insert(rule, at: insertIndex)
            }
        }

        logger.info("ZapperRuleManager: Restored rule for '\(hostname)' at index \(index)")
    }
}
