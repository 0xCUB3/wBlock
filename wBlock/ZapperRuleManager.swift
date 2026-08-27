import Foundation
import os.log
import Darwin
import wBlockCoreService
#if os(macOS)
import SafariServices
#endif

/// ZapperRuleManager is the unified data layer for element zapper rules stored in protobuf.
///
/// It enumerates all hostnames that have saved rules, reads rules per hostname, and deletes
/// rules individually or in bulk. Phase 9 Settings UI binds to this ObservableObject.
@MainActor
final class ZapperRuleManager: ObservableObject {
    static let shared = ZapperRuleManager()

    /// Sorted list of hostnames that have at least one zapper rule.
    @Published private(set) var domains: [String] = []

    /// Hostnames whose zapper rules are kept but currently not applied.
    @Published private(set) var disabledDomains: Set<String> = []

    /// Convenience binding target: rules for the currently selected domain.
    @Published private(set) var rulesForSelectedDomain: [String] = []
    @Published private(set) var isMutationInFlight = false
    private var mutationTail: Task<Void, Never>?
    private var mutationGeneration = 0

    /// Serializes app-level zapper mutations so delete, undo, and clear cannot
    /// overlap with a disk refresh or with one another.
    func performMutation(_ operation: @escaping @MainActor () async -> Void) async {
        mutationGeneration += 1
        let generation = mutationGeneration
        let previous = mutationTail
        let task = Task { @MainActor in
            await previous?.value
            isMutationInFlight = true
            defer { isMutationInFlight = false }
            await operation()
        }
        mutationTail = task
        await task.value
        Self.notifySafariRulesChanged()
        if mutationGeneration == generation {
            mutationTail = nil
        }
    }

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
    static func notifySafariRulesChanged() {
        #if os(macOS)
        guard SafariProcessAvailability.isSafariOrTechnologyPreviewRunning else {
            Logger(subsystem: "skula.wBlock", category: "ZapperRuleManager").info("Skipped Safari zapper rules refresh: Safari is not running")
            return
        }
        SFSafariApplication.dispatchMessage(
            withName: "wblock:zapperRulesChanged",
            toExtensionWithIdentifier: "skula.wBlock.wBlock-Scripts",
            userInfo: ["action": "wblock:zapperRulesChanged"]
        ) { error in
            if let error {
                os_log("Failed to refresh Safari zapper rules: %{public}@", type: .error, error.localizedDescription)
            }
        }
        #endif
    }
    private let dataDirectoryMonitor = ProtobufDataDirectoryMonitor(
        queue: DispatchQueue(label: "skula.wBlock.zapper-rules-monitor", qos: .utility)
    )

    private init() {
        Task { @MainActor in
            setupDataDirectoryMonitor()
            await refreshFromDisk()
        }
    }

    // MARK: - Public API

    /// Reads all hostnames with zapper rules from protobuf and updates the published domains array.
    func refresh() {
        Task { @MainActor in
            await refreshFromDisk()
        }
    }

    /// Async variant for call sites that need to await completion.
    func refreshNow() async {
        await refreshFromDisk()
    }

    /// Returns the stored CSS selector strings for the given hostname, filtered for non-empty entries.
    func rules(for hostname: String) -> [String] {
        ProtobufDataManager.shared.getZapperRules(forHost: hostname)
    }

    /// Removes a single CSS selector for the hostname and refreshes local state.
    func deleteRule(_ rule: String, forDomain hostname: String) {
        Task { @MainActor in
            await ProtobufDataManager.shared.deleteZapperRule(rule, forHost: hostname)
            await refreshFromDisk()
            if selectedDomain == hostname {
                rulesForSelectedDomain = rules(for: hostname)
            }
        }
    }

    /// Removes all rules for the hostname and refreshes local state.
    func deleteAllRules(forDomain hostname: String) {
        Task { @MainActor in
            await ProtobufDataManager.shared.deleteAllZapperRules(forHost: hostname)
            await refreshFromDisk()
            if selectedDomain == hostname {
                rulesForSelectedDomain = []
            }
        }
    }

    /// Removes every stored rule for every hostname and refreshes local state.
    func deleteAllRules() {
        Task { @MainActor in
            for domain in ProtobufDataManager.shared.getZapperDomains() {
                await ProtobufDataManager.shared.deleteAllZapperRules(forHost: domain)
            }
            await refreshFromDisk()
            selectedDomain = nil
            rulesForSelectedDomain = []
        }
    }

    /// Returns the number of rules stored for the given hostname.
    func ruleCount(forDomain hostname: String) -> Int {
        return rules(for: hostname).count
    }

    /// True when the hostname's rules are kept but not applied.
    func isDisabled(_ hostname: String) -> Bool {
        disabledDomains.contains(hostname)
    }

    /// Flips the per-host kill switch and refreshes local state.
    func setDisabled(_ disabled: Bool, forDomain hostname: String) {
        Task { @MainActor in
            await ProtobufDataManager.shared.setZapperRulesDisabled(disabled, forHost: hostname)
            await refreshFromDisk()
        }
    }

    /// Re-inserts a previously deleted rule and refreshes local state.
    func restoreRule(_ rule: String, forDomain hostname: String, at index: Int) {
        Task { @MainActor in
            await ProtobufDataManager.shared.restoreZapperRule(rule, forHost: hostname, at: index)
            await refreshFromDisk()
            if selectedDomain == hostname {
                rulesForSelectedDomain = rules(for: hostname)
            }
        }
    }

    private func refreshFromDisk() async {
        await ProtobufDataManager.shared.waitUntilLoaded()
        _ = await ProtobufDataManager.shared.refreshFromDiskIfModified(forceRead: true)
        publishStateFromDataManager()
    }

    private func publishStateFromDataManager() {
        let discovered = ProtobufDataManager.shared.getZapperDomains()
        let discoveredDisabledDomains = Set(ProtobufDataManager.shared.getDisabledZapperDomains())
        var didChange = false

        if domains != discovered {
            domains = discovered
            didChange = true
        }
        if disabledDomains != discoveredDisabledDomains {
            disabledDomains = discoveredDisabledDomains
            didChange = true
        }
        if let selectedDomain {
            let discoveredRules = rules(for: selectedDomain)
            if rulesForSelectedDomain != discoveredRules {
                rulesForSelectedDomain = discoveredRules
                didChange = true
            }
        }

        if didChange {
            logger.info("ZapperRuleManager: Refreshed — found \(discovered.count) domain(s) with rules")
        }
    }

    private func setupDataDirectoryMonitor() {
        guard let directoryURL = ProtobufDataManager.shared.protobufDataDirectoryURL() else {
            logger.error("ZapperRuleManager: Failed to locate protobuf data directory")
            return
        }

        guard dataDirectoryMonitor.start(directoryURL: directoryURL, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshFromDisk()
            }
        }) else {
            logger.error("ZapperRuleManager: Failed to open protobuf data directory")
            return
        }
    }
}
