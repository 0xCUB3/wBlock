import Foundation
import SwiftUI
import UniformTypeIdentifiers
import wBlockCoreService

// MARK: - Backup Data Model

struct WBlockBackup: Codable, Sendable {
    var version: Int
    var createdAt: Date
    var appVersion: String
    var filterSelections: [FilterSelection]
    var customFilterLists: [CustomFilterEntry]
    var whitelistedDomains: [String]
    var filterDisabledDomains: [String]
    var noAutoplayEnabled: Bool = false
    var noAutoplayAllowedSites: [String] = []
    var zapperRules: [String: [String]]
    var disabledZapperDomains: [String]

    var userScripts: [UserScriptEntry]

    /// App preferences (#629). Optional so backups from older builds still decode.
    var autoUpdateEnabled: Bool?
    var autoUpdateIntervalHours: Double?
    var lockPortraitOrientation: Bool?
    var appearance: String?
    var cosmeticFilteringEnabled: Bool?
    var tubeCleanerFeatures: TubeCleanerDeArrowPreference.Features?
    var tubeCleanerDeArrow: TubeCleanerDeArrowPreference.Settings?
    var playerCleanerFeatures: PlayerCleanerPreference.Features?
    struct FilterSelection: Codable, Sendable {
        var url: String
        var isSelected: Bool
    }

    struct CustomFilterEntry: Codable, Sendable {
        var name: String
        var url: String
        var category: String
        var isSelected: Bool
        var description: String
        var userProvidedName: Bool?
        var userProvidedDescription: Bool?
        var admittedSourceRuleCount: Int?
        var content: String?
    }

    struct UserScriptEntry: Codable, Sendable {
        var id: UUID
        var name: String
        var url: String?
        var isEnabled: Bool
        var description: String
        var version: String
        var matches: [String]
        var excludeMatches: [String]
        var includes: [String]
        var excludes: [String]
        var runAt: String
        var injectInto: String
        var grant: [String]
        var require: [String]
        var resource: [UserScriptResource]
        var resourceContents: [String: String]
        var noframes: Bool
        var isLocal: Bool
        var updateURL: String?
        var downloadURL: String?
        var content: String
        var lastUpdated: Date?
        var updatesAutomatically: Bool
        /// Optional for compatibility with backups created before categories were exported.
        var category: String?
        /// Optional for backups created before stable local-import identities.
        var localImportIdentity: String?

        var disabledHosts: [String]?
        var siteAccess: UserScriptSiteAccess?
        init(userScript: UserScript, disabledHosts: [String] = [], siteAccess: UserScriptSiteAccess = .init()) {
            id = userScript.id
            name = userScript.name
            url = userScript.url?.absoluteString
            isEnabled = userScript.isEnabled
            description = userScript.description
            version = userScript.version
            matches = userScript.matches
            excludeMatches = userScript.excludeMatches
            includes = userScript.includes
            excludes = userScript.excludes
            runAt = userScript.runAt
            injectInto = userScript.injectInto
            grant = userScript.grant
            require = userScript.require
            resource = userScript.resource
            resourceContents = userScript.resourceContents
            noframes = userScript.noframes
            isLocal = userScript.isLocal
            updateURL = userScript.isLocal ? nil : userScript.updateURL
            downloadURL = userScript.isLocal ? nil : userScript.downloadURL
            content = userScript.content
            lastUpdated = userScript.lastUpdated
            updatesAutomatically = userScript.updatesAutomatically
            category = userScript.category.rawValue
            localImportIdentity = userScript.localImportIdentity
            // An empty collection is authoritative; nil belongs only to legacy backups.
            self.disabledHosts = disabledHosts
            self.siteAccess = siteAccess
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, url, isEnabled, description, version, matches, excludeMatches
            case includes, excludes, runAt, injectInto, grant, require, resource, resourceContents
            case noframes, isLocal, updateURL, downloadURL, content, lastUpdated, updatesAutomatically
            case category, localImportIdentity, disabledHosts, siteAccess
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
            description = try container.decode(String.self, forKey: .description)
            version = try container.decode(String.self, forKey: .version)
            matches = try container.decode([String].self, forKey: .matches)
            excludeMatches = try container.decode([String].self, forKey: .excludeMatches)
            includes = try container.decode([String].self, forKey: .includes)
            excludes = try container.decode([String].self, forKey: .excludes)
            runAt = try container.decode(String.self, forKey: .runAt)
            injectInto = try container.decode(String.self, forKey: .injectInto)
            grant = try container.decode([String].self, forKey: .grant)
            require = try container.decode([String].self, forKey: .require)
            resource = try container.decode([UserScriptResource].self, forKey: .resource)
            resourceContents = try container.decode([String: String].self, forKey: .resourceContents)
            noframes = try container.decode(Bool.self, forKey: .noframes)
            isLocal = try container.decode(Bool.self, forKey: .isLocal)
            updateURL = try container.decodeIfPresent(String.self, forKey: .updateURL)
            downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL)
            content = try container.decode(String.self, forKey: .content)
            lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
            updatesAutomatically = try container.decode(Bool.self, forKey: .updatesAutomatically)
            category = try container.decodeIfPresent(String.self, forKey: .category)
            localImportIdentity = try container.decodeIfPresent(String.self, forKey: .localImportIdentity)
            disabledHosts = try container.decodeIfPresent([String].self, forKey: .disabledHosts)
            siteAccess = try container.decodeIfPresent(UserScriptSiteAccess.self, forKey: .siteAccess)
        }

        var userScript: UserScript {
            var script = UserScript(id: id, name: name, url: url.flatMap(URL.init(string:)), content: content)
            script.isEnabled = isEnabled
            script.description = description
            script.version = version
            script.matches = matches
            script.excludeMatches = excludeMatches
            script.includes = includes
            script.excludes = excludes
            script.runAt = runAt
            script.injectInto = injectInto
            script.grant = grant
            script.require = require
            script.resource = resource
            script.resourceContents = resourceContents
            script.noframes = noframes
            script.isLocal = isLocal || script.url == nil || script.url?.isFileURL == true
            script.updateURL = script.isLocal ? nil : updateURL
            script.downloadURL = script.isLocal ? nil : downloadURL
            script.lastUpdated = lastUpdated
            script.updatesAutomatically = updatesAutomatically
            script.category = category.flatMap(FilterListCategory.init(rawValue:)) ?? .scripts
            script.localImportIdentity = localImportIdentity
            // Old backups predate the flag; the content always travels with the
            // entry, so re-derive instead of persisting a new schema field.
            script.isUserStyle = UserScript.detectsUserStyle(in: content)
            return script
        }
    }

    init(
        version: Int,
        createdAt: Date,
        appVersion: String,
        filterSelections: [FilterSelection],
        customFilterLists: [CustomFilterEntry],
        whitelistedDomains: [String],
        filterDisabledDomains: [String] = [],
        noAutoplayEnabled: Bool = false,
        noAutoplayAllowedSites: [String] = [],
        zapperRules: [String: [String]],
        disabledZapperDomains: [String],
        userScripts: [UserScriptEntry],
        autoUpdateEnabled: Bool? = nil,
        autoUpdateIntervalHours: Double? = nil,
        lockPortraitOrientation: Bool? = nil,
        appearance: String? = nil,
        cosmeticFilteringEnabled: Bool? = nil,
        tubeCleanerFeatures: TubeCleanerDeArrowPreference.Features? = nil,
        tubeCleanerDeArrow: TubeCleanerDeArrowPreference.Settings? = nil,
        playerCleanerFeatures: PlayerCleanerPreference.Features? = nil
    ) {
        self.version = version
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.filterSelections = filterSelections
        self.customFilterLists = customFilterLists
        self.whitelistedDomains = whitelistedDomains
        self.filterDisabledDomains = filterDisabledDomains
        self.noAutoplayEnabled = noAutoplayEnabled
        self.noAutoplayAllowedSites = noAutoplayAllowedSites
        self.zapperRules = zapperRules
        self.disabledZapperDomains = disabledZapperDomains
        self.userScripts = userScripts
        self.autoUpdateEnabled = autoUpdateEnabled
        self.autoUpdateIntervalHours = autoUpdateIntervalHours
        self.lockPortraitOrientation = lockPortraitOrientation
        self.appearance = appearance
        self.cosmeticFilteringEnabled = cosmeticFilteringEnabled
        self.tubeCleanerFeatures = tubeCleanerFeatures
        self.tubeCleanerDeArrow = tubeCleanerDeArrow
        self.playerCleanerFeatures = playerCleanerFeatures
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case createdAt
        case appVersion
        case filterSelections
        case customFilterLists
        case whitelistedDomains
        case filterDisabledDomains
        case noAutoplayEnabled
        case noAutoplayAllowedSites
        case zapperRules
        case disabledZapperDomains
        case userScripts
        case autoUpdateEnabled
        case autoUpdateIntervalHours
        case lockPortraitOrientation
        case appearance
        case cosmeticFilteringEnabled, tubeCleanerFeatures, tubeCleanerDeArrow, playerCleanerFeatures
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        filterSelections = try container.decode([FilterSelection].self, forKey: .filterSelections)
        customFilterLists = try container.decode([CustomFilterEntry].self, forKey: .customFilterLists)
        whitelistedDomains = try container.decode([String].self, forKey: .whitelistedDomains)
        filterDisabledDomains = try container.decodeIfPresent([String].self, forKey: .filterDisabledDomains) ?? []
        noAutoplayEnabled = try container.decodeIfPresent(Bool.self, forKey: .noAutoplayEnabled) ?? false
        noAutoplayAllowedSites = try container.decodeIfPresent([String].self, forKey: .noAutoplayAllowedSites) ?? []
        zapperRules = try container.decode([String: [String]].self, forKey: .zapperRules)
        disabledZapperDomains = try container.decodeIfPresent([String].self, forKey: .disabledZapperDomains) ?? []
        userScripts = try container.decodeIfPresent([UserScriptEntry].self, forKey: .userScripts) ?? []
        autoUpdateEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoUpdateEnabled)
        autoUpdateIntervalHours = try container.decodeIfPresent(Double.self, forKey: .autoUpdateIntervalHours)
        lockPortraitOrientation = try container.decodeIfPresent(Bool.self, forKey: .lockPortraitOrientation)
        appearance = try container.decodeIfPresent(String.self, forKey: .appearance)
        cosmeticFilteringEnabled = try container.decodeIfPresent(Bool.self, forKey: .cosmeticFilteringEnabled)
        tubeCleanerFeatures = try container.decodeIfPresent(TubeCleanerDeArrowPreference.Features.self, forKey: .tubeCleanerFeatures)
        tubeCleanerDeArrow = try container.decodeIfPresent(TubeCleanerDeArrowPreference.Settings.self, forKey: .tubeCleanerDeArrow)
        playerCleanerFeatures = try container.decodeIfPresent(PlayerCleanerPreference.Features.self, forKey: .playerCleanerFeatures)
    }
}

enum BackupContentError: LocalizedError {
    case unavailableLocalFilter(String)

    var errorDescription: String? {
        switch self {
        case .unavailableLocalFilter(let name):
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "The contents of local filter list \"%@\" are unavailable. Recover the list on the original device and create a new backup.",
                    comment: "Backup cannot safely export or restore a local list without its source"
                ),
                name
            )
        }
    }
}

/// Plans identity-preserving upserts before writing any inline content. The URL
/// resolver is injected so restore behavior can be tested without app-group data.
@MainActor
enum BackupCustomFilterRestorer {
    struct RestoreWriteError: LocalizedError {
        let original: Error
        let rollbackFailures: [Error]

        var errorDescription: String? {
            guard !rollbackFailures.isEmpty else { return original.localizedDescription }
            return ([original] + rollbackFailures).map(\.localizedDescription).joined(separator: "\n")
        }
    }

    struct RestoreResult {
        let lists: [FilterList]
        fileprivate let previous: [URL: Data?]
        fileprivate let published: [(url: URL, bytes: Data)]

        func rollback(
            readData: (URL) throws -> Data? = { url in
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return try Data(contentsOf: url)
            },
            writeData: (Data, URL) throws -> Void = { data, url in
                try data.write(to: url, options: .atomic)
            },
            removeFile: (URL) throws -> Void = { url in
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                try FileManager.default.removeItem(at: url)
            }
        ) -> [Error] {
            var failures: [Error] = []
            for item in published.reversed() {
                do {
                    guard try readData(item.url) == item.bytes else { continue }
                    if let old = previous[item.url] ?? nil {
                        try writeData(old, item.url)
                    } else {
                        try removeFile(item.url)
                    }
                } catch {
                    failures.append(error)
                }
            }
            return failures
        }
    }

    static func restoreWithReceipt(
        _ entries: [WBlockBackup.CustomFilterEntry],
        into existing: [FilterList],
        localFileURL: (FilterList) -> URL?,
        readData: (URL) throws -> Data? = { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        },
        writeData: (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        },
        removeFile: (URL) throws -> Void = { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        }
    ) throws -> RestoreResult {

        var lists = existing
        var writes: [URL: Data] = [:]
        for entry in entries {
            guard let components = URLComponents(string: entry.url),
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let inline = components.scheme?.lowercased() == "wblock"
            let url: URL
            let inlineID: UUID?
            if inline {
                let path = components.path.split(separator: "/")
                guard components.host?.lowercased() == "userlist", path.count == 1,
                      let id = UUID(uuidString: String(path[0])),
                      components.user == nil, components.password == nil, components.port == nil,
                      components.query == nil, components.fragment == nil else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                guard entry.content != nil else {
                    throw BackupContentError.unavailableLocalFilter(entry.name)
                }
                inlineID = id
                url = URL(string: "wblock://userlist/\(id.uuidString)")!
            } else {
                guard let remoteURL = FilterListURLSupport.validatedRemoteURL(from: entry.url) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                inlineID = nil
                url = remoteURL
            }
            func matches(_ filter: FilterList) -> Bool {
                guard filter.isCustom, filter.isInlineUserList == inline else { return false }
                if let inlineID {
                    return UUID(uuidString: filter.url.lastPathComponent) == inlineID
                }
                return FilterListURLSupport.isSameList(filter.url, url)
            }
            let old = lists.first(where: matches)
            let id = inlineID ?? old?.id ?? UUID()
            guard !lists.contains(where: { $0.id == id && !matches($0) }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var restored = FilterList(
                id: id, name: entry.name, url: url,
                category: FilterListCategory(rawValue: entry.category) ?? .custom,
                isCustom: true, isSelected: entry.isSelected, description: entry.description,
                version: inline ? "" : (old?.version ?? ""),
                sourceRuleCount: inline ? entry.content.map(FilterList.countRules) : old?.sourceRuleCount,
                lastUpdated: inline ? Date() : old?.lastUpdated,
                hasUserProvidedName: entry.userProvidedName ?? true,
                hasUserProvidedDescription: entry.userProvidedDescription ?? !entry.description.isEmpty,
                excludedSites: old?.excludedSites ?? []
            )
            // Admission belongs to a confirmed compilation, not to imported metadata.
            restored.uniqueRuleCount = nil
            if let content = entry.content, inline {
                guard let destination = localFileURL(restored) else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                writes[destination] = Data(content.utf8)
            }
            if let index = lists.firstIndex(where: matches) {
                lists[index] = restored
                lists = lists.enumerated().filter { $0.offset == index || !matches($0.element) }.map(\.element)
            } else {
                lists.append(restored)
            }
        }
        // This synchronous MainActor section does not interleave with app-side
        // edits. Rollback is best effort and leaves externally changed bytes
        // alone; any rollback I/O failures are returned with the original error.
        let orderedWrites = writes.sorted { $0.key.path < $1.key.path }
        var previous: [URL: Data?] = [:]
        var published: [(url: URL, bytes: Data)] = []
        do {
            for (url, _) in orderedWrites {
                previous[url] = try readData(url)
            }
            for (url, content) in orderedWrites {
                published.append((url, content))
                try writeData(content, url)
            }
        } catch {
            let original = error
            let rollbackFailures = RestoreResult(
                lists: lists,
                previous: previous,
                published: published
            ).rollback(readData: readData, writeData: writeData, removeFile: removeFile)
            throw RestoreWriteError(original: original, rollbackFailures: rollbackFailures)
        }
        return RestoreResult(lists: lists, previous: previous, published: published)
    }

    static func restore(
        _ entries: [WBlockBackup.CustomFilterEntry],
        into existing: [FilterList],
        localFileURL: (FilterList) -> URL?,
        readData: (URL) throws -> Data? = { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        },
        writeData: (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        },
        removeFile: (URL) throws -> Void = { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        }
    ) throws -> [FilterList] {
        try restoreWithReceipt(
            entries,
            into: existing,
            localFileURL: localFileURL,
            readData: readData,
            writeData: writeData,
            removeFile: removeFile
        ).lists
    }
}

// MARK: - BackupDocument (FileDocument for iOS fileExporter)

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - BackupManager

@MainActor
enum BackupManager {

    // MARK: - Create

    static func createBackup(filterManager: AppFilterManager) async throws -> WBlockBackup {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let loader = FilterListLoader()

        // Built-in filter selections (non-custom)
        let filterSelections = filterManager.filterLists
            .filter { !$0.isCustom }
            .map { WBlockBackup.FilterSelection(url: $0.url.absoluteString, isSelected: $0.isSelected) }

        // Custom filter lists
        let customEntries = try filterManager.filterLists
            .filter { $0.isCustom }
            .map { filter -> WBlockBackup.CustomFilterEntry in
                var content: String? = nil
                if filter.isInlineUserList {
                    guard let fileURL = loader.localFileURL(for: filter) else {
                        throw BackupContentError.unavailableLocalFilter(filter.name)
                    }
                    do {
                        content = try String(contentsOf: fileURL, encoding: .utf8)
                    } catch {
                        throw BackupContentError.unavailableLocalFilter(filter.name)
                    }
                }
                return WBlockBackup.CustomFilterEntry(
                    name: filter.name,
                    url: filter.url.absoluteString,
                    category: filter.category.rawValue,
                    isSelected: filter.isSelected,
                    description: filter.description,
                    userProvidedName: filter.hasUserProvidedName,
                    userProvidedDescription: filter.hasUserProvidedDescription,
                    admittedSourceRuleCount: filter.uniqueRuleCount,
                    content: content
                )
            }

        let backedUpUserScripts = await UserScriptManager.shared.userScriptsForBackup()
        let userScriptDisabledHosts = await MainActor.run {
            Dictionary(
                uniqueKeysWithValues: backedUpUserScripts.map { script in
                    (script.id, ProtobufDataManager.shared.getUserScriptDisabledHosts(forScriptID: script.id.uuidString))
                }
            )
        }
        let userScriptEntries = backedUpUserScripts.map { script in
            WBlockBackup.UserScriptEntry(
                userScript: script,
                disabledHosts: userScriptDisabledHosts[script.id] ?? [],
                siteAccess: ProtobufDataManager.shared.userScriptSiteAccess(forScriptID: script.id.uuidString)
            )
        }

        // Whitelist (live source is the protobuf store, not the legacy UserDefaults migration key)
        let whitelistedDomains = filterManager.dataManager.disabledSites
        let filterDisabledDomains = filterManager.dataManager.filterDisabledSites
        let noAutoplayEnabled = filterManager.dataManager.isNoAutoplayEnabled
        let noAutoplayAllowedSites = filterManager.dataManager.noAutoplayAllowedSites
        let (zapperRules, disabledZapperDomains) = await MainActor.run {
            var zapperRules: [String: [String]] = [:]
            let zapperDomains = ProtobufDataManager.shared.getZapperDomains()
            for domain in zapperDomains {
                let rules = ProtobufDataManager.shared.getZapperRules(forHost: domain)
                if !rules.isEmpty {
                    zapperRules[domain] = rules
                }
            }
            return (zapperRules, ProtobufDataManager.shared.getDisabledZapperDomains())
        }

        await ConcurrentLogManager.shared.operation("backup-created", fields: ["filters": String(filterSelections.count + customEntries.count), "scripts": String(userScriptEntries.count), "zapperHosts": String(zapperRules.count)])
        return WBlockBackup(
            version: 1,
            createdAt: Date(),
            appVersion: appVersion,
            filterSelections: filterSelections,
            customFilterLists: customEntries,
            whitelistedDomains: whitelistedDomains,
            filterDisabledDomains: filterDisabledDomains,
            noAutoplayEnabled: noAutoplayEnabled,
            noAutoplayAllowedSites: noAutoplayAllowedSites,
            zapperRules: zapperRules,
            disabledZapperDomains: disabledZapperDomains,
            userScripts: userScriptEntries,
            autoUpdateEnabled: filterManager.dataManager.autoUpdateEnabled,
            autoUpdateIntervalHours: filterManager.dataManager.autoUpdateIntervalHours,
            lockPortraitOrientation: PortraitOrientationLock.isEnabled,
            appearance: UserDefaults.standard.string(forKey: AppAppearance.storageKey),
            cosmeticFilteringEnabled: CosmeticFilteringPreference.isEnabled(),
            tubeCleanerFeatures: TubeCleanerDeArrowPreference.features(),
            tubeCleanerDeArrow: TubeCleanerDeArrowPreference.settings(),
            playerCleanerFeatures: PlayerCleanerPreference.features()
        )
    }

    // MARK: - Export

    static func exportData(backup: WBlockBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    // MARK: - Import

    static func importData(from data: Data) throws -> WBlockBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WBlockBackup.self, from: data)
    }

    // MARK: - Restore

    static func restoreBackup(_ backup: WBlockBackup, filterManager: AppFilterManager) async throws {
        let loader = FilterListLoader()
        let originalLists = filterManager.filterLists
        let restored = try BackupCustomFilterRestorer.restoreWithReceipt(
            backup.customFilterLists,
            into: originalLists,
            localFileURL: loader.localFileURL(for:)
        )
        var lists = restored.lists
        // 1. Restore built-in filter selections by URL
        for selection in backup.filterSelections {
            if let index = lists.firstIndex(where: { !$0.isCustom && $0.url.absoluteString == selection.url }) {
                lists[index].isSelected = selection.isSelected
                lists[index].uniqueRuleCount = nil
            }
        }
        filterManager.filterLists = lists
        let persisted = await filterManager.saveFilterLists()
        guard persisted else {
            let persistenceError = filterManager.dataManager.lastError ?? CocoaError(.fileWriteUnknown)
            let rollbackFailures = restored.rollback()
            if filterManager.filterLists == lists {
                filterManager.filterLists = originalLists
            }
            throw BackupCustomFilterRestorer.RestoreWriteError(
                original: persistenceError,
                rollbackFailures: rollbackFailures
            )
        }
        let currentLists = filterManager.filterLists
        for entry in backup.customFilterLists {
            if let url = URL(string: entry.url),
               let filter = currentLists.first(where: { $0.isCustom && FilterListURLSupport.isSameList($0.url, url) }) {
                CloudSyncManager.shared.clearDeletedCustomListURL(filter.url.absoluteString)
            }
        }

        // 3. Restore whitelist
        await filterManager.dataManager.setWhitelistedDomains(backup.whitelistedDomains)
        await filterManager.dataManager.setFilterDisabledDomains(backup.filterDisabledDomains)
        await filterManager.dataManager.setNoAutoplayEnabled(backup.noAutoplayEnabled)
        await filterManager.dataManager.setNoAutoplayAllowedSites(backup.noAutoplayAllowedSites)

        // 4. Restore zapper rules (to protobuf)
        let disabledZapperHosts = Set(backup.disabledZapperDomains)
        await ProtobufDataManager.shared.applyZapperRulesBatch(
            rulesByHost: backup.zapperRules,
            disabledByHost: Dictionary(uniqueKeysWithValues:
                Set(backup.zapperRules.keys).union(disabledZapperHosts)
                    .map { ($0, disabledZapperHosts.contains($0)) }
            )
        )

        // 5. Restore userscripts, including custom script content and enabled/update state
        let userScripts = backup.userScripts.map(\.userScript)
        await UserScriptManager.shared.restoreUserScriptsFromBackup(userScripts)
        let restoredUserScripts = await MainActor.run {
            UserScriptManager.shared.userScripts
        }
        var disabledHostsByScriptID = await MainActor.run {
            ProtobufDataManager.shared.getUserScriptDisabledHosts()
        }
        for entry in backup.userScripts {
            let disabledHosts = entry.disabledHosts
            let restoredScript = entry.userScript
            guard let matchingIndex = UserScriptRestoreMatcher.matchingIndex(
                for: restoredScript,
                in: restoredUserScripts
            ) else {
                continue
            }
            let matchedScript = restoredUserScripts[matchingIndex]
            if let disabledHosts { disabledHostsByScriptID[matchedScript.id.uuidString] = disabledHosts }
            if let siteAccess = entry.siteAccess {
                await ProtobufDataManager.shared.setUserScriptSiteAccess(siteAccess, forScriptID: matchedScript.id.uuidString)
            }
        }
        await ProtobufDataManager.shared.setAllUserScriptDisabledHosts(disabledHostsByScriptID)

        // 6. Restore app preferences when the backup carries them
        if let autoUpdateEnabled = backup.autoUpdateEnabled {
            await filterManager.dataManager.setAutoUpdateEnabled(autoUpdateEnabled)
        }
        if let hours = backup.autoUpdateIntervalHours {
            await filterManager.dataManager.setAutoUpdateIntervalHours(hours)
        }
        if let lockPortrait = backup.lockPortraitOrientation {
            UserDefaults.standard.set(lockPortrait, forKey: PortraitOrientationLock.storageKey)
        }
        if let appearance = backup.appearance, AppAppearance(rawValue: appearance) != nil {
            UserDefaults.standard.set(appearance, forKey: AppAppearance.storageKey)
        }
        if let cosmetic = backup.cosmeticFilteringEnabled {
            CosmeticFilteringPreference.setEnabled(cosmetic)
        }

        if let features = backup.tubeCleanerFeatures { UserScriptManager.shared.setTubeCleanerFeatures(features) }
        if let settings = backup.tubeCleanerDeArrow { UserScriptManager.shared.setTubeCleanerDeArrow(settings) }
        if let features = backup.playerCleanerFeatures { UserScriptManager.shared.setPlayerCleanerFeatures(features) }

        // 7. Mark unapplied changes so user can apply
        filterManager.markNonSelectionChangesPending()

        // 8. Refresh ZapperRuleManager
        ZapperRuleManager.shared.refresh()

        // 9. Restored backups represent an existing configuration — skip the setup wizard.
        await ProtobufDataManager.shared.setHasCompletedOnboarding(true)
        UserScriptManager.shared.markInitialSetupComplete()
    }
}
