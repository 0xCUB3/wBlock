import Foundation

/// Only these playback preferences may cross from an external backup into Safari.
/// Never retain the source dictionary: SponsorBlock exports can contain credentials.
public enum SponsorBlockSettingsTransfer {
    public static let storageKey = "wblock.tubeCleaner.sponsorBlock"
    public static let maximumBytes = 1024 * 1024
    public static let categories = ["sponsor", "selfpromo", "interaction", "intro", "outro", "preview", "filler", "music_offtopic"]

    public enum TransferError: Error { case invalidSettings, storageFailure }

    public struct Settings: Codable, Equatable, Sendable {
        public var enabled = true
        public var showNotice = true
        public var minimumDuration: Double = 0
        public var modes: [String: String] = Dictionary(uniqueKeysWithValues: categories.map { ($0, $0 == "sponsor" ? "auto" : "off") })
        public var excludedChannels: [String] = []
        public init() {}
    }

    private struct Export: Codable {
        var format = "wblock-sponsorblock-settings"
        var version = 1
        var settings: Settings
    }

    private struct ExtensionSettings: Decodable {
        struct Selection: Decodable { let name: String; let option: Int }
        let categorySelections: [Selection]
        let disableSkipping: Bool?
        let dontShowNotice: Bool?
        let minDuration: Double?
        let whitelistedChannels: [String]?
    }

    public static func validated(_ settings: Settings) throws -> Settings {
        guard settings.minimumDuration.isFinite, settings.minimumDuration >= 0,
              settings.excludedChannels.count <= 200,
              settings.excludedChannels.allSatisfy({ !$0.isEmpty && $0.utf8.count < 200 }) else {
            throw TransferError.invalidSettings
        }
        var clean = settings
        clean.modes = [:]
        for category in categories {
            guard let mode = settings.modes[category], ["auto", "ask", "off"].contains(mode) else {
                throw TransferError.invalidSettings
            }
            clean.modes[category] = mode
        }
        clean.excludedChannels = Array(Set(settings.excludedChannels)).sorted()
        return clean
    }

    public static func parse(_ data: Data, current: Settings = Settings()) throws -> Settings {
        guard data.count <= maximumBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TransferError.invalidSettings
        }
        let decoder = JSONDecoder()
        if object["format"] != nil {
            let backup = try decoder.decode(Export.self, from: data)
            guard backup.format == "wblock-sponsorblock-settings", backup.version == 1 else {
                throw TransferError.invalidSettings
            }
            return try validated(backup.settings)
        }
        // The extension's All Options export is flat. Other Data and debug
        // exports are deliberately not accepted as a playback configuration.
        let imported = try decoder.decode(ExtensionSettings.self, from: data)
        guard imported.categorySelections.count <= 200 else { throw TransferError.invalidSettings }
        var settings = try validated(current)
        for category in categories { settings.modes[category] = "off" }
        var seen = Set<String>()
        for selection in imported.categorySelections {
            guard (-2...2).contains(selection.option), seen.insert(selection.name).inserted else {
                throw TransferError.invalidSettings
            }
            guard categories.contains(selection.name) else { continue }
            settings.modes[selection.name] = selection.option == 2 ? "auto" : selection.option == 1 ? "ask" : "off"
        }
        if let disabled = imported.disableSkipping { settings.enabled = !disabled }
        if let hidden = imported.dontShowNotice { settings.showNotice = !hidden }
        if let duration = imported.minDuration { settings.minimumDuration = duration }
        // New extension versions moved channel rules into unsupported profiles.
        // Absence of the legacy list must not erase existing Tube Cleaner exclusions.
        if let channels = imported.whitelistedChannels { settings.excludedChannels = channels }
        return try validated(settings)
    }

    public static func exportData(_ settings: Settings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Export(settings: validated(settings)))
    }

    public static func settings(scriptID: UUID) async throws -> Settings? {
        try await settings(scriptID: scriptID, storage: .shared)
    }

    static func settings(scriptID: UUID, storage: UserScriptStorageManager) async throws -> Settings? {
        let snapshot = await storage.snapshot(for: scriptID.uuidString)
        guard let raw = snapshot[storageKey] else { return nil }
        guard raw.utf8.count <= maximumBytes else { throw TransferError.invalidSettings }
        return try validated(JSONDecoder().decode(Settings.self, from: Data(raw.utf8)))
    }

    @MainActor
    public static func save(_ settings: Settings, scriptID: UUID) async throws {
        try await persist(settings, scriptID: scriptID, storage: .shared)
        UserScriptManager.invalidateDocumentStartExecutionCache()
    }

    static func persist(_ settings: Settings, scriptID: UUID, storage: UserScriptStorageManager) async throws {
        let data = try JSONEncoder().encode(validated(settings))
        let result = await storage.setSerializedValue(
            String(decoding: data, as: UTF8.self), forKey: storageKey, scriptID: scriptID.uuidString
        )
        guard result.ok else { throw TransferError.storageFailure }
    }
}
