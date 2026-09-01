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
        init(userScript: UserScript, disabledHosts: [String] = []) {
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
            self.disabledHosts = disabledHosts.isEmpty ? nil : disabledHosts
        }

        private enum CodingKeys: String, CodingKey {
            case id, name, url, isEnabled, description, version, matches, excludeMatches
            case includes, excludes, runAt, injectInto, grant, require, resource, resourceContents
            case noframes, isLocal, updateURL, downloadURL, content, lastUpdated, updatesAutomatically
            case category, localImportIdentity, disabledHosts
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
        userScripts: [UserScriptEntry]
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

    static func createBackup(filterManager: AppFilterManager) async -> WBlockBackup {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let loader = FilterListLoader()

        // Built-in filter selections (non-custom)
        let filterSelections = filterManager.filterLists
            .filter { !$0.isCustom }
            .map { WBlockBackup.FilterSelection(url: $0.url.absoluteString, isSelected: $0.isSelected) }

        // Custom filter lists
        let customEntries = filterManager.filterLists
            .filter { $0.isCustom }
            .map { filter -> WBlockBackup.CustomFilterEntry in
                var content: String? = nil
                if filter.isInlineUserList, let fileURL = loader.localFileURL(for: filter) {
                    content = try? String(contentsOf: fileURL, encoding: .utf8)
                }
                return WBlockBackup.CustomFilterEntry(
                    name: filter.name,
                    url: filter.url.absoluteString,
                    category: filter.category.rawValue,
                    isSelected: filter.isSelected,
                    description: filter.description,
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
                disabledHosts: userScriptDisabledHosts[script.id] ?? []
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
            userScripts: userScriptEntries
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

    static func restoreBackup(_ backup: WBlockBackup, filterManager: AppFilterManager) async {
        // 1. Restore built-in filter selections by URL
        var lists = filterManager.filterLists
        for selection in backup.filterSelections {
            if let index = lists.firstIndex(where: { $0.url.absoluteString == selection.url }) {
                lists[index].isSelected = selection.isSelected
            }
        }
        filterManager.filterLists = lists
        await filterManager.saveFilterLists()

        // 2. Restore custom filter lists. The backup selection is authoritative for
        // both an existing URL and a newly added remote definition.
        var existingCustomSelectionChanged = false
        for entry in backup.customFilterLists {
            let matchingIndices = filterManager.filterLists.indices.filter { index in
                filterManager.filterLists[index].isCustom
                    && filterManager.filterLists[index].url.absoluteString == entry.url
            }
            if !matchingIndices.isEmpty {
                for index in matchingIndices where filterManager.filterLists[index].isSelected != entry.isSelected {
                    filterManager.filterLists[index].isSelected = entry.isSelected
                    existingCustomSelectionChanged = true
                }
                continue
            }

            let category = FilterListCategory(rawValue: entry.category) ?? .custom
            let isInlineUserList = entry.url.hasPrefix("wblock://userlist/")
            if isInlineUserList, let content = entry.content {
                filterManager.addUserList(
                    name: entry.name,
                    description: entry.description.isEmpty ? nil : entry.description,
                    content: content,
                    category: category,
                    isSelected: entry.isSelected
                )
            } else if !isInlineUserList {
                filterManager.addFilterList(
                    name: entry.name,
                    urlString: entry.url,
                    category: category,
                    isSelected: entry.isSelected
                )
            }
        }
        if existingCustomSelectionChanged {
            await filterManager.saveFilterLists()
        }

        // 3. Restore whitelist
        await filterManager.dataManager.setWhitelistedDomains(backup.whitelistedDomains)
        await filterManager.dataManager.setFilterDisabledDomains(backup.filterDisabledDomains)
        await filterManager.dataManager.setNoAutoplayEnabled(backup.noAutoplayEnabled)
        await filterManager.dataManager.setNoAutoplayAllowedSites(backup.noAutoplayAllowedSites)

        // 4. Restore zapper rules (to protobuf)
        await ProtobufDataManager.shared.applyZapperRulesBatch(
            rulesByHost: backup.zapperRules,
            disabledByHost: Dictionary(
                backup.disabledZapperDomains.map { ($0, true) },
                uniquingKeysWith: { first, _ in first }
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
            guard let disabledHosts = entry.disabledHosts, !disabledHosts.isEmpty else { continue }
            let restoredScript = entry.userScript
            guard let matchingIndex = UserScriptRestoreMatcher.matchingIndex(
                for: restoredScript,
                in: restoredUserScripts
            ) else {
                continue
            }
            let matchedScript = restoredUserScripts[matchingIndex]
            disabledHostsByScriptID[matchedScript.id.uuidString] = disabledHosts
        }
        await ProtobufDataManager.shared.setAllUserScriptDisabledHosts(disabledHostsByScriptID)

        // 6. Mark unapplied changes so user can apply
        filterManager.markNonSelectionChangesPending()

        // 7. Refresh ZapperRuleManager
        ZapperRuleManager.shared.refresh()

        // 8. Restored backups represent an existing configuration — skip the setup wizard.
        await ProtobufDataManager.shared.setHasCompletedOnboarding(true)
        UserScriptManager.shared.markInitialSetupComplete()
    }
}
