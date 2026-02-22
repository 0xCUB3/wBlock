import Foundation
import os.log
import Darwin
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
    private let monitorQueue = DispatchQueue(label: "skula.wBlock.zapper-rules-monitor", qos: .utility)
    private var dataDirectoryMonitor: DispatchSourceFileSystemObject?
    private var dataDirectoryFileDescriptor: CInt = -1
    private var pendingRefreshTask: Task<Void, Never>?

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

    /// Returns the number of rules stored for the given hostname.
    func ruleCount(forDomain hostname: String) -> Int {
        return rules(for: hostname).count
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
        domains = discovered
        if let selectedDomain {
            rulesForSelectedDomain = rules(for: selectedDomain)
        }
        logger.info("ZapperRuleManager: Refreshed — found \(discovered.count) domain(s) with rules")
    }

    private func setupDataDirectoryMonitor() {
        dataDirectoryMonitor?.cancel()
        dataDirectoryMonitor = nil
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil

        guard let directoryURL = ProtobufDataManager.shared.protobufDataDirectoryURL() else {
            logger.error("ZapperRuleManager: Failed to locate protobuf data directory")
            return
        }

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            logger.error("ZapperRuleManager: Failed to open protobuf data directory")
            return
        }

        dataDirectoryFileDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: monitorQueue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pendingRefreshTask?.cancel()
            self.pendingRefreshTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                await self?.refreshFromDisk()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.dataDirectoryFileDescriptor >= 0 {
                close(self.dataDirectoryFileDescriptor)
                self.dataDirectoryFileDescriptor = -1
            }
        }

        dataDirectoryMonitor = source
        source.resume()
    }

    deinit {
        pendingRefreshTask?.cancel()
        dataDirectoryMonitor?.cancel()
        dataDirectoryMonitor = nil
        if dataDirectoryFileDescriptor >= 0 {
            close(dataDirectoryFileDescriptor)
            dataDirectoryFileDescriptor = -1
        }
    }
}
