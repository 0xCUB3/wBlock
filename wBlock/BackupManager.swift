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
            updateURL = userScript.updateURL
            downloadURL = userScript.downloadURL
            content = userScript.content
            lastUpdated = userScript.lastUpdated
            updatesAutomatically = userScript.updatesAutomatically
            self.disabledHosts = disabledHosts.isEmpty ? nil : disabledHosts
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
            script.updateURL = updateURL
            script.downloadURL = downloadURL
            script.lastUpdated = lastUpdated
            script.updatesAutomatically = updatesAutomatically
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
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
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

        // Whitelist
        let whitelistedDomains = defaults?.stringArray(forKey: "disabledSites") ?? []

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

        // 2. Restore custom filter lists (skip if URL already exists)
        for entry in backup.customFilterLists {
            let alreadyExists = filterManager.filterLists.contains(where: { $0.url.absoluteString == entry.url })
            guard !alreadyExists else { continue }

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
                    category: category
                )
            }
        }

        // 3. Restore whitelist
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
        defaults?.set(backup.whitelistedDomains, forKey: "disabledSites")

        // 4. Restore zapper rules (to protobuf)
        for (hostname, rules) in backup.zapperRules {
            await ProtobufDataManager.shared.setZapperRules(forHost: hostname, rules: rules)
        }

        for domain in backup.disabledZapperDomains {
            await ProtobufDataManager.shared.setZapperRulesDisabled(true, forHost: domain)
        }

        // 5. Restore userscripts, including custom script content and enabled/update state
        let userScripts = backup.userScripts.map(\.userScript)
        await UserScriptManager.shared.restoreUserScriptsFromBackup(userScripts)
        let restoredUserScripts = await MainActor.run {
            UserScriptManager.shared.userScripts
        }
        for entry in backup.userScripts {
            guard let disabledHosts = entry.disabledHosts, !disabledHosts.isEmpty else { continue }
            guard let restoredScript = restoredUserScripts.first(where: { script in
                if let entryURL = entry.url.flatMap(URL.init(string:)) {
                    return script.url == entryURL
                }
                return script.isLocal
                    && script.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        == entry.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }) else {
                continue
            }
            await ProtobufDataManager.shared.setUserScriptDisabledHosts(disabledHosts, forScriptID: restoredScript.id.uuidString)
        }

        // 6. Mark unapplied changes so user can apply
        filterManager.markNonSelectionChangesPending()

        // 7. Refresh ZapperRuleManager
        ZapperRuleManager.shared.refresh()

        // 8. Restored backups represent an existing configuration — skip the setup wizard.
        await ProtobufDataManager.shared.setHasCompletedOnboarding(true)
        UserScriptManager.shared.markInitialSetupComplete()
    }
}
