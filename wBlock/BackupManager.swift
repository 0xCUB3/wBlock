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

    static func createBackup(filterManager: AppFilterManager) -> WBlockBackup {
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
                let isInlineUserList = filter.url.scheme?.lowercased() == "wblock"
                    && filter.url.host?.lowercased() == "userlist"
                var content: String? = nil
                if isInlineUserList, let fileURL = loader.localFileURL(for: filter) {
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

        // Whitelist
        let whitelistedDomains = defaults?.stringArray(forKey: "disabledSites") ?? []

        // Zapper rules
        var zapperRules: [String: [String]] = [:]
        if let allKeys = defaults?.dictionaryRepresentation().keys {
            let prefix = "zapperRules_"
            for key in allKeys where key.hasPrefix(prefix) {
                let hostname = String(key.dropFirst(prefix.count))
                if let rules = defaults?.stringArray(forKey: key), !rules.isEmpty {
                    zapperRules[hostname] = rules
                }
            }
        }

        return WBlockBackup(
            version: 1,
            createdAt: Date(),
            appVersion: appVersion,
            filterSelections: filterSelections,
            customFilterLists: customEntries,
            whitelistedDomains: whitelistedDomains,
            zapperRules: zapperRules
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

            let isInlineUserList = entry.url.hasPrefix("wblock://userlist/")
            if isInlineUserList, let content = entry.content {
                filterManager.addUserList(
                    name: entry.name,
                    description: entry.description.isEmpty ? nil : entry.description,
                    content: content,
                    isSelected: entry.isSelected
                )
            } else if !isInlineUserList {
                let category = FilterListCategory(rawValue: entry.category) ?? .custom
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

        // 4. Restore zapper rules
        let prefix = "zapperRules_"
        for (hostname, rules) in backup.zapperRules {
            defaults?.set(rules, forKey: prefix + hostname)
        }
        defaults?.synchronize()

        // 5. Mark unapplied changes so user can apply
        filterManager.hasUnappliedChanges = true

        // 6. Refresh ZapperRuleManager
        ZapperRuleManager.shared.refresh()
    }
}
