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

    /// Removes a single CSS selector for the hostname and refreshes local state.
    func deleteRule(_ rule: String, forDomain hostname: String) {
        Task {
            await ProtobufDataManager.shared.deleteZapperRule(rule, forHost: hostname)
            refresh()
            if selectedDomain == hostname {
                rulesForSelectedDomain = rules(for: hostname)
            }
        }
    }

    /// Removes all rules for the hostname and refreshes local state.
    func deleteAllRules(forDomain hostname: String) {
        Task {
            await ProtobufDataManager.shared.deleteAllZapperRules(forHost: hostname)
            refresh()
            if selectedDomain == hostname {
                rulesForSelectedDomain = []
            }
        }
    }

    /// Returns the number of rules stored for the given hostname.
    func ruleCount(forDomain hostname: String) -> Int {
        return rules(for: hostname).count
    }

    /// Re-inserts a previously deleted rule and refreshes local state.
    func restoreRule(_ rule: String, forDomain hostname: String, at index: Int) {
        Task {
            await ProtobufDataManager.shared.restoreZapperRule(rule, forHost: hostname, at: index)
            refresh()
            if selectedDomain == hostname {
                rulesForSelectedDomain = rules(for: hostname)
            }
        }
    }
}
