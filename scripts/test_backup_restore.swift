import Foundation
import wBlockCoreService

// Compile the production BackupManager with in-memory service doubles. Only
// the identity-derived inline files are real, and live inside a unique temp dir.
struct FilterListLoader {
    nonisolated(unsafe) static var directory: URL!
    func localFileURL(for filter: FilterList) -> URL? {
        Self.directory.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter))
    }
}
actor ConcurrentLogManager {
    static let shared = ConcurrentLogManager()
    func operation(_ event: String, fields: [String: String]) {}
}
@MainActor final class CloudSyncManager {
    static let shared = CloudSyncManager()
    func clearDeletedCustomListURL(_ url: String) {}
}
@MainActor final class ProtobufDataManager {
    static let shared = ProtobufDataManager()
    var disabledSites: [String] = []
    var filterDisabledSites: [String] = []
    var isNoAutoplayEnabled = false
    var noAutoplayAllowedSites: [String] = []
    var autoUpdateEnabled = true
    var autoUpdateIntervalHours = 6.0
    var disabledHosts: [String: [String]] = [:]
    var zapperDisabled: [String: Bool] = [:]
    var zapper: [String: [String]] = [:]
    func getUserScriptDisabledHosts() -> [String: [String]] { disabledHosts }
    func getUserScriptDisabledHosts(forScriptID id: String) -> [String] { disabledHosts[id] ?? [] }
    func setAllUserScriptDisabledHosts(_ map: [String: [String]]) async {
        disabledHosts = map.filter { !$0.value.isEmpty }
    }
    func getZapperDomains() -> [String] { Array(zapper.keys) }
    func getZapperRules(forHost host: String) -> [String] { zapper[host] ?? [] }
    func getDisabledZapperDomains() -> [String] { zapperDisabled.filter(\.value).map(\.key) }
    func setWhitelistedDomains(_ value: [String]) async { disabledSites = value }
    func setFilterDisabledDomains(_ value: [String]) async { filterDisabledSites = value }
    func setNoAutoplayEnabled(_ value: Bool) async { isNoAutoplayEnabled = value }
    func setNoAutoplayAllowedSites(_ value: [String]) async { noAutoplayAllowedSites = value }
    func setAutoUpdateEnabled(_ value: Bool) async { autoUpdateEnabled = value }
    func setAutoUpdateIntervalHours(_ value: Double) async { autoUpdateIntervalHours = value }
    func setHasCompletedOnboarding(_ value: Bool) async {}
    func applyZapperRulesBatch(rulesByHost: [String: [String]], disabledByHost: [String: Bool]?) async {
        for (host, rules) in rulesByHost { zapper[host] = rules }
        for (host, value) in disabledByHost ?? [:] { zapperDisabled[host] = value }
    }
}
@MainActor final class UserScriptManager {
    static let shared = UserScriptManager()
    var userScripts: [UserScript] = []
    func userScriptsForBackup() async -> [UserScript] { userScripts }
    func restoreUserScriptsFromBackup(_ scripts: [UserScript]) async { userScripts = scripts }
    func setTubeCleanerFeatures(_ value: TubeCleanerDeArrowPreference.Features) {}
    func setTubeCleanerDeArrow(_ value: TubeCleanerDeArrowPreference.Settings) {}
    func setPlayerCleanerFeatures(_ value: PlayerCleanerPreference.Features) {}
    func markInitialSetupComplete() {}
}
@MainActor final class AppFilterManager {
    var filterLists: [FilterList] = []
    var dataManager = ProtobufDataManager.shared
    func saveFilterLists() async {}
    func markNonSelectionChangesPending() {}
}
@MainActor final class ZapperRuleManager {
    static let shared = ZapperRuleManager()
    func refresh() {}
}
enum PortraitOrientationLock {
    static let storageKey = "unused-backup-test-portrait"
    static let isEnabled = false
}
enum AppAppearance: String {
    case system
    static let storageKey = "unused-backup-test-appearance"
}

@main struct BackupRestoreTests {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        FilterListLoader.directory = directory
        let id = UUID()
        let url = "wblock://userlist/\(id.uuidString)"
        let manager = AppFilterManager()
        let original = FilterList(id: id, name: "Edited", url: URL(string: url)!, category: .ads,
                                  isCustom: true, description: "Edited description", uniqueRuleCount: 99)
        manager.filterLists = [original]
        let file = FilterListLoader().localFileURL(for: original)!
        try "||edited.example^".write(to: file, atomically: true, encoding: .utf8)
        var script = UserScript(id: UUID(), name: "Local", url: nil, content: "// ==UserScript==\n// @name Local\n// ==/UserScript==\n")
        script.isLocal = true
        let scriptEntry = WBlockBackup.UserScriptEntry(userScript: script, disabledHosts: [])
        let backup = WBlockBackup(version: 1, createdAt: Date(), appVersion: "test",
            filterSelections: [],
            customFilterLists: [.init(name: "Backup title", url: url, category: FilterListCategory.privacy.rawValue,
                                     isSelected: true, description: "Backup description", content: "||backup.example^\n")],
            whitelistedDomains: [], zapperRules: ["example.com": [".ad"]], disabledZapperDomains: [],
            userScripts: [scriptEntry])
        let decoded = try BackupManager.importData(from: BackupManager.exportData(backup: backup))
        precondition(decoded.userScripts[0].disabledHosts == [], "explicit empty state must round-trip")
        ProtobufDataManager.shared.disabledHosts = [script.id.uuidString: ["example.com"], "unrelated": ["keep.example"]]
        ProtobufDataManager.shared.zapperDisabled = ["example.com": true, "unrelated.example": true]
        try await BackupManager.restoreBackup(decoded, filterManager: manager)
        precondition(manager.filterLists.count == 1 && manager.filterLists[0].id == id)
        precondition(manager.filterLists[0].name == "Backup title")
        precondition(manager.filterLists[0].description == "Backup description")
        precondition(manager.filterLists[0].category == .privacy && manager.filterLists[0].isSelected)
        precondition(manager.filterLists[0].sourceRuleCount == 1 && manager.filterLists[0].uniqueRuleCount == nil)
        let restoredContent = try String(contentsOf: file, encoding: .utf8)
        precondition(restoredContent == "||backup.example^\n")
        precondition(ProtobufDataManager.shared.disabledHosts[script.id.uuidString] == nil)
        precondition(ProtobufDataManager.shared.disabledHosts["unrelated"] == ["keep.example"])
        precondition(ProtobufDataManager.shared.zapperDisabled["example.com"] == false)
        precondition(ProtobufDataManager.shared.zapperDisabled["unrelated.example"] == true)
        let fresh = AppFilterManager()
        try await BackupManager.restoreBackup(decoded, filterManager: fresh)
        try await BackupManager.restoreBackup(decoded, filterManager: fresh)
        precondition(fresh.filterLists.count == 1 && fresh.filterLists[0].id == id, "restore must be idempotent")

        var legacy = decoded
        legacy.userScripts[0].disabledHosts = nil
        ProtobufDataManager.shared.disabledHosts[script.id.uuidString] = ["preserve.example"]
        try await BackupManager.restoreBackup(legacy, filterManager: manager)
        precondition(ProtobufDataManager.shared.disabledHosts[script.id.uuidString] == ["preserve.example"])

        var invalid = decoded
        invalid.customFilterLists[0].content = "||must-not-write.example^"
        var badEntry = invalid.customFilterLists[0]
        badEntry.url = "wblock://userlist/not-a-uuid"
        invalid.customFilterLists.append(badEntry)
        do {
            try await BackupManager.restoreBackup(invalid, filterManager: manager)
            fatalError("malformed inline identities must be rejected before any writes")
        } catch is CocoaError {}
        let afterInvalidRestore = try String(contentsOf: file, encoding: .utf8)
        precondition(afterInvalidRestore == "||backup.example^\n")

        let remoteID = UUID()
        let remote = FilterList(id: remoteID, name: "Old", url: URL(string: "https://example.com/list.txt")!,
                                category: .ads, isCustom: true, uniqueRuleCount: 500)
        let remoteEntry = WBlockBackup.CustomFilterEntry(name: "Restored", url: remote.url.absoluteString,
            category: FilterListCategory.privacy.rawValue, isSelected: true, description: "Restored description")
        let restored = try BackupCustomFilterRestorer.restore([remoteEntry], into: [remote], localFileURL: { _ in nil })
        precondition(restored.count == 1 && restored[0].id == remoteID && restored[0].name == "Restored")
        precondition(restored[0].category == .privacy && restored[0].uniqueRuleCount == nil)

        // A failure after the first inline publish must roll back every file and
        // leave the caller's metadata untouched because restore never returned.
        let id2 = UUID()
        let url2 = "wblock://userlist/\(id2.uuidString)"
        let original2 = FilterList(id: id2, name: "Second", url: URL(string: url2)!, category: .ads,
                                   isCustom: true, description: "Second original")
        let file2 = FilterListLoader().localFileURL(for: original2)!
        try "||second-original.example^".write(to: file2, atomically: true, encoding: .utf8)
        let originals = [original, original2]
        let entries = [
            WBlockBackup.CustomFilterEntry(name: "First restored", url: url, category: FilterListCategory.privacy.rawValue,
                                           isSelected: true, description: "First restored", content: "||first-new.example^\n"),
            WBlockBackup.CustomFilterEntry(name: "Second restored", url: url2, category: FilterListCategory.privacy.rawValue,
                                           isSelected: true, description: "Second restored", content: "||second-new.example^\n"),
        ]
        var writes = 0
        do {
            _ = try BackupCustomFilterRestorer.restore(
                entries,
                into: originals,
                localFileURL: FilterListLoader().localFileURL(for:),
                writeData: { data, destination in
                    writes += 1
                    if writes == 2 { throw CocoaError(.fileWriteUnknown) }
                    try data.write(to: destination, options: .atomic)
                }
            )
            fatalError("second inline write failure must abort restore")
        } catch {}
        let firstAfterFailure = try String(contentsOf: file, encoding: .utf8)
        let secondAfterFailure = try String(contentsOf: file2, encoding: .utf8)
        precondition(firstAfterFailure == "||backup.example^\n")
        precondition(secondAfterFailure == "||second-original.example^")
        precondition(originals[0].name == "Edited" && originals[1].name == "Second",
                     "failed file transaction must not publish restored metadata")

        // Rollback must not clobber bytes published by a newer writer after our
        // first write. The second injected write fails after replacing the first
        // transaction-owned file with concurrent content.
        var concurrentWriteCount = 0
        var firstPublishedURL: URL?
        do {
            _ = try BackupCustomFilterRestorer.restore(
                entries,
                into: originals,
                localFileURL: FilterListLoader().localFileURL(for:),
                writeData: { data, destination in
                    concurrentWriteCount += 1
                    if concurrentWriteCount == 1 {
                        firstPublishedURL = destination
                        try data.write(to: destination, options: .atomic)
                        return
                    }
                    if let firstPublishedURL {
                        try Data("||concurrent-newer.example^".utf8).write(to: firstPublishedURL, options: .atomic)
                    }
                    throw CocoaError(.fileWriteUnknown)
                }
            )
            fatalError("injected concurrent failure must abort restore")
        } catch {}
        guard let firstPublishedURL else { fatalError("first transaction write must occur") }
        let concurrentContent = try String(contentsOf: firstPublishedURL, encoding: .utf8)
        precondition(concurrentContent == "||concurrent-newer.example^",
                     "rollback must not overwrite a concurrent newer file")
        print("PASS backup restore: metadata, source, identities, empty/legacy states, validation")
    }
}
