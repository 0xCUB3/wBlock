//
//  UserScriptManager.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 6/7/25.
//

import Combine
import Foundation
import os.log
#if os(macOS)
import SafariServices
#endif

public enum UserScriptImportError: LocalizedError {
    case unsupportedType
    case unreadableFile
    case emptyContent
    case fileTooLarge
    case missingMetadata
    case unsupportedStylePreprocessor(String)
    case stylePreprocessorMismatch(expected: String, declared: String)
    case styleCompilationFailed(String)

    static let fallbackCompilerError = String(localized: "Unknown compiler error.", comment: "Fallback userstyle compiler error")

    public var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return String(localized: "Choose a .user.js, .js, .user.css, .less, .sass, .scss, .styl, or .pcss file.", comment: "UserScript import file type error")
        case .unreadableFile:
            return String(localized: "Couldn't read the selected file.", comment: "UserScript import read error")
        case .emptyContent:
            return String(localized: "The file is empty.", comment: "UserScript import empty file error")
        case .fileTooLarge:
            return String(localized: "The selected file is too large. Maximum size is 10 MB.", comment: "Local userscript import size error")
        case .missingMetadata:
            return String(localized: "Not a userscript or userstyle: missing metadata block.", comment: "UserScript import metadata error")
        case .unsupportedStylePreprocessor(let preprocessor):
            return String(localized: "This userstyle needs the \"%@\" preprocessor, which isn't supported yet.", comment: "Unsupported userstyle preprocessor error").replacingOccurrences(of: "%@", with: preprocessor)
        case .stylePreprocessorMismatch(let expected, let declared):
            return String(
                format: String(
                    localized: "This style file requires the \"%@\" preprocessor, but declares \"%@\".",
                    comment: "Userstyle extension and preprocessor mismatch error"
                ),
                expected,
                declared
            )
        case .styleCompilationFailed(let message):
            return String(localized: "Couldn't compile this userstyle: %@", comment: "Userstyle compilation wrapper").replacingOccurrences(of: "%@", with: message)
        }
    }
}

public extension Notification.Name {
    static let userScriptManagerDidImportLocalUserScript = Notification.Name(
        "UserScriptManagerDidImportLocalUserScript")
    static let userScriptManagerDidRemoveLocalUserScript = Notification.Name(
        "UserScriptManagerDidRemoveLocalUserScript")
    static let userScriptManagerDidUpsertUserScript = Notification.Name(
        "UserScriptManagerDidUpsertUserScript")
    static let userScriptManagerDidRemoveUserScript = Notification.Name(
        "UserScriptManagerDidRemoveUserScript")
}

public enum UserScriptManagerNotificationKey {
    public static let name = "name"
    public static let url = "url"
    public static let isLocal = "isLocal"
    public static let localImportIdentity = "localImportIdentity"
}

struct BuiltInUserScriptDefinition {
    let name: String
    let url: String
    let isEnabledByDefault: Bool
    let description: String
    let languages: [String]
    let displayRole: BuiltInUserScriptDisplayRole?
    let isBeta: Bool

    init(
        name: String,
        url: String,
        isEnabledByDefault: Bool,
        description: String = "Default userscript",
        languages: [String] = [],
        displayRole: BuiltInUserScriptDisplayRole? = nil,
        isBeta: Bool = false
    ) {
        self.name = name
        self.url = url
        self.isEnabledByDefault = isEnabledByDefault
        self.description = description
        self.languages = languages.map { $0.lowercased() }
        self.displayRole = displayRole
        self.isBeta = isBeta
    }
}

enum BuiltInUserScripts {
    static let popupBlockerName = "AdGuard Popup Blocker"
    static let popupBlockerStableURL =
        "https://userscripts.adtidy.org/release/popup-blocker/2.5/popupblocker.user.js"
    static let legacyPopupBlockerBetaURL =
        "https://userscripts.adtidy.org/beta/popup-blocker/2.5/popupblocker.user.js"
    static let tinyShieldURL =
        "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/tinyShield.user.js"
    static let legacyTinyShieldGroupedURLPrefix =
        "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/grouped/"
    static let tinyShieldDescription =
        "tinyShield helps block ads reinserted by Ad-Shield on matching sites."
    static let retiredYouTubeAdBlockURL =
        "https://raw.githubusercontent.com/SysAdminDoc/YoutubeAdblock/main/YoutubeAdblock.user.js"

    static let tubeCleanerURL = "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/tube-cleaner/dist/tube-cleaner.user.js"
    static let playerCleanerURL = "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/player-cleaner/dist/player-cleaner.user.js"
    static let darkReaderURL = DarkReaderAppearancePreference.scriptURL
    static let darkReaderDescription =
        "Dark Reader's MIT-licensed API engine for wBlock (beta; without the full site-fix database)."
    static let legacyBundledURLsByCanonical: [String: String] = [
        "https://bundled.wblock.invalid/tube-cleaner.user.js": tubeCleanerURL,
        "https://bundled.wblock.invalid/player-cleaner.user.js": playerCleanerURL,
        "https://bundled.wblock.invalid/dark-reader.user.js": darkReaderURL,
    ]
    static let tubeCleanerDescription =
        "Gives YouTube Safari-native controls, chapters, SponsorBlock skipping, picture-in-picture, background playback, quality selection, and audio-only mode."
    static let playerCleanerDescription =
        "Gives custom web players native controls, auto PiP, background playback, restored subtitle and chapter tracks, Now Playing metadata, and remembered playback preferences."

    static let definitions: [BuiltInUserScriptDefinition] = [
        BuiltInUserScriptDefinition(
            name: "Tube Cleaner",
            url: tubeCleanerURL,
            isEnabledByDefault: false,
            description: tubeCleanerDescription,
            displayRole: .functionality,
            isBeta: true
        ),
        BuiltInUserScriptDefinition(
            name: "Player Cleaner",
            url: playerCleanerURL,
            isEnabledByDefault: false,
            description: playerCleanerDescription,
            displayRole: .functionality,
            isBeta: true
        ),
        BuiltInUserScriptDefinition(
            name: "Dark Reader",
            url: darkReaderURL,
            isEnabledByDefault: false,
            description: darkReaderDescription,
            displayRole: .functionality,
            isBeta: true
        ),
        BuiltInUserScriptDefinition(
            name: "Return YouTube Dislike",
            url: "https://raw.githubusercontent.com/Anarios/return-youtube-dislike/main/Extensions/UserScript/Return%20Youtube%20Dislike.user.js",
            isEnabledByDefault: false,
            displayRole: .functionality
        ),
        BuiltInUserScriptDefinition(
            name: "Bypass Paywalls Clean",
            url: "https://greasyfork.org/scripts/542351-bypass-paywalls-clean-en/code/Bypass%20Paywalls%20Clean%20(EN).user.js",
            isEnabledByDefault: false,
            languages: ["en"],
            displayRole: .functionality
        ),
        BuiltInUserScriptDefinition(
            name: "AdGuard Extra",
            url: "https://userscripts.adtidy.org/release/adguard-extra/1.0/adguard-extra.user.js",
            isEnabledByDefault: false,
            description: "AdGuard Extra blocks Twitch ads and handles complicated anti-adblock cases.",
            displayRole: .blocking
        ),
        BuiltInUserScriptDefinition(
            name: "tinyShield",
            url: tinyShieldURL,
            isEnabledByDefault: true,
            description: tinyShieldDescription,
            displayRole: .blocking
        ),
        BuiltInUserScriptDefinition(
            name: popupBlockerName,
            url: popupBlockerStableURL,
            isEnabledByDefault: false,
            displayRole: .blocking
        ),
    ]

    static let protectedURLs = Set(definitions.map(\.url))
    static let legacyProtectedURLs = Set([legacyPopupBlockerBetaURL]).union(legacyBundledURLsByCanonical.keys)
    static let allProtectedURLs = protectedURLs.union(legacyProtectedURLs)
    static let displayRoleByURL = Dictionary(uniqueKeysWithValues: definitions.compactMap { definition in
        definition.displayRole.map { (definition.url, $0) }
    })
    static let isBetaByURL = Dictionary(
        uniqueKeysWithValues: definitions.filter(\.isBeta).map { ($0.url, true) }
    )
    static let languagesByURL = Dictionary(
        uniqueKeysWithValues: definitions.map { ($0.url, $0.languages) }
    )

}

public enum UserScriptMutationOrigin: Sendable, Equatable {
    case local
    case remoteSync
}

public struct UserScriptToggleState: Sendable {
    public let isEnabled: Bool
    public let desired: Bool
    public let isInFlight: Bool

    public init(isEnabled: Bool, desired: Bool, isInFlight: Bool) {
        self.isEnabled = isEnabled
        self.desired = desired
        self.isInFlight = isInFlight
    }
}

@MainActor
public class UserScriptManager: ObservableObject {
    public static func invalidateDocumentStartExecutionCache() {
        // Safari exposes the unsolicited app -> extension message channel only on
        // macOS. Keep this single mutation hook in the manager so every supported
        // native path shares the same invalidation contract when connected.
        #if os(macOS)
        SFSafariApplication.dispatchMessage(
            withName: "wblock:userscriptsChanged",
            toExtensionWithIdentifier: "skula.wBlock.wBlock-Scripts",
            userInfo: ["action": "wblock:userscriptsChanged"]
        ) { error in
            if let error {
                os_log("Failed to invalidate Safari userscript cache: %{public}@", type: .error, error.localizedDescription)
            }
        }
        #endif
    }

    @Published public var userScripts: [UserScript] = [] {
        didSet {
            rebuildUserScriptIndex()
            payloadMutationRevision &+= 1
        }
    }
    @Published public var isLoading: Bool = false
    @Published public var statusDescription: String = "Ready."
    @Published public var hasError: Bool = false
    @Published public var errorMessage: String = ""
    @Published public var showingUpdateSuccessAlert = false
    @Published public var showingUpdateErrorAlert = false
    @Published public var updateAlertMessage = ""
    @Published public var showingDuplicatesAlert = false
    @Published public var duplicatesMessage = ""
    @Published public var pendingDuplicatesToRemove: [UserScript] = []
    @Published public private(set) var isReady = false
    @Published public private(set) var userScriptToggleStates: [UUID: UserScriptToggleState] = [:]
    @Published public private(set) var isPrefetchingDefaultMetadata = false
    @Published public private(set) var darkReaderFollowsSystemAppearance =
        DarkReaderAppearancePreference.followsSystemAppearance()

    private let userScriptSiteDisabledDefaultsKey = "userScriptDisabledHostsByID"
    private let sharedContainerIdentifier = GroupIdentifier.shared.value
    private let dataManager = ProtobufDataManager.shared
    private let sharedDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
    private let logger = Logger(subsystem: "com.skula.wBlock", category: "UserScriptManager")
    private var cancellables = Set<AnyCancellable>()
    private var initialLoadTask: Task<Void, Never>?
    private var userScriptIndexByID: [UUID: Int] = [:]
    private var dataManagerSyncGeneration: UInt64 = 0
    private var nextUserScriptIntentRevision: UInt64 = 0
    private var userScriptIntentRevisions: [UUID: UInt64] = [:]
    private var latestUserScriptIntentValues: [UUID: Bool] = [:]
    private var pendingUserScriptIntents: [UUID: Bool] = [:]
    /// Monotonic revision of local-only userscript mutations. CloudSync can persist this
    /// value to coalesce work; remote-origin changes deliberately do not advance it.
    public private(set) var localMutationRevision: UInt64 = 0
    public private(set) var payloadMutationRevision: UInt64 = 0
    private var contentMutationRevisions: [UUID: UInt64] = [:]

    public func currentLocalSyncMutationRevision() -> UInt64 { localMutationRevision }

    private func recordLocalMutation() {
        localMutationRevision &+= 1
    }

    private func recordScriptMutation(_ id: UUID) {
        contentMutationRevisions[id, default: 0] &+= 1
        recordLocalMutation()
    }

    private func scriptMutationRevision(_ id: UUID) -> UInt64 {
        contentMutationRevisions[id, default: 0]
    }
    private var metadataPrefetchTask: Task<Void, Never>?
    nonisolated private static let maximumResourceBytes = 10 * 1024 * 1024
    nonisolated private static let maximumEncodedResourceBytes = ((maximumResourceBytes + 2) / 3) * 4 + 256
    nonisolated private static let maximumResourcesPerScript = 64
    nonisolated private static let maximumStoredResourceBytesPerScript = 25 * 1024 * 1024
    private static let maximumRequireBytes = 5 * 1024 * 1024
    private static let maximumRequireBytesPerScript = 20 * 1024 * 1024
    private static let maximumRequiresPerScript = 32
    private static let maximumUserScriptBytes = UserScriptImportLimits.maximumSourceFileBytes

    nonisolated private static func resourceCacheFitsLimits(_ resources: [String: String]) -> Bool {
        guard resources.count <= maximumResourcesPerScript else { return false }
        var totalBytes = 0
        for payload in resources.values {
            let payloadBytes = payload.utf8.count
            guard payloadBytes <= maximumEncodedResourceBytes else { return false }
            totalBytes += payloadBytes
            guard totalBytes <= maximumStoredResourceBytesPerScript else { return false }
        }
        return true
    }

    // Configured URLSession for better resource management
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 0, diskPath: nil)  // 2MB memory, no disk cache
        return URLSession(configuration: config)
    }()

    private func rebuildUserScriptIndex() {
        var newIndex: [UUID: Int] = [:]
        newIndex.reserveCapacity(userScripts.count)
        for (index, script) in userScripts.enumerated() {
            newIndex[script.id] = index
        }
        userScriptIndexByID = newIndex
    }

    private func indexOfUserScript(withId id: UUID) -> Int? {
        if let cachedIndex = userScriptIndexByID[id],
            userScripts.indices.contains(cachedIndex),
            userScripts[cachedIndex].id == id
        {
            return cachedIndex
        }

        guard let scannedIndex = userScripts.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        userScriptIndexByID[id] = scannedIndex
        return scannedIndex
    }

    public func userScript(withId id: UUID) -> UserScript? {
        guard let index = indexOfUserScript(withId: id) else { return nil }
        return userScripts[index]
    }

    /// Returns the latest actual state plus any immediate desired state for a pending toggle.
    public func userScriptToggleState(for id: UUID) -> UserScriptToggleState? {
        guard let script = userScript(withId: id) else { return nil }
        let desired = pendingUserScriptIntents[id] ?? script.isEnabled
        return UserScriptToggleState(
            isEnabled: script.isEnabled,
            desired: desired,
            isInFlight: pendingUserScriptIntents[id] != nil
        )
    }

    private func beginUserScriptIntent(
        for id: UUID,
        desired: Bool,
        origin: UserScriptMutationOrigin
    ) -> UInt64 {
        nextUserScriptIntentRevision &+= 1
        let revision = nextUserScriptIntentRevision
        userScriptIntentRevisions[id] = revision
        latestUserScriptIntentValues[id] = desired
        pendingUserScriptIntents[id] = desired
        if origin == .local {
            recordScriptMutation(id)
        }
        if let script = userScript(withId: id) {
            userScriptToggleStates[id] = UserScriptToggleState(
                isEnabled: script.isEnabled,
                desired: desired,
                isInFlight: true
            )
        }
        return revision
    }

    private func isCurrentUserScriptIntent(_ id: UUID, revision: UInt64) -> Bool {
        userScriptIntentRevisions[id] == revision
    }

    private func finishUserScriptIntent(_ id: UUID, revision: UInt64) {
        guard isCurrentUserScriptIntent(id, revision: revision) else { return }
        pendingUserScriptIntents.removeValue(forKey: id)
        userScriptToggleStates.removeValue(forKey: id)
    }

    private func applyLatestUserScriptIntents(to scripts: inout [UserScript]) {
        for index in scripts.indices {
            if let desired = latestUserScriptIntentValues[scripts[index].id] {
                scripts[index].isEnabled = desired
            }
        }
    }

    public func userScriptEditorSnapshot(withId id: UUID) async -> UserScript? {
        guard let script = userScript(withId: id) else { return nil }
        guard script.content.isEmpty else { return script }

        return await Task.detached { [script] in
            Self.hydrateUserScriptFromDisk(script)
        }.value
    }

    /// Returns local scripts with source hydrated for cloud serialization and reconciliation.
    /// The hydrated copies are deliberately not assigned to `userScripts`, preserving the
    /// disk-backed idle representation for disabled scripts.
    public func cloudSyncLocalUserScripts() async -> [UserScript] {
        await hydrateUserScriptsFromDisk(
            userScripts.filter(\.isLocal),
            includeResources: false,
            hydrateDisabled: true
        )
    }

    private func resolveMetadataURL(_ rawValue: String, relativeTo userScript: UserScript) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let baseURL = userScript.url,
           let resolvedURL = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
           resolvedURL.scheme != nil {
            return resolvedURL
        }

        guard let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return url
    }

    private func extractResourceURL(forResourceName name: String, from userScriptContent: String) -> String? {
        var inMetadata = false
        for line in userScriptContent.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "// ==UserScript==" {
                inMetadata = true
                continue
            }
            if trimmed == "// ==/UserScript==" { break }
            if !inMetadata { continue }

            if trimmed.hasPrefix("// @resource") {
                // Format: // @resource <name> <url>
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 4 {
                    let resourceName = String(parts[2])
                    if resourceName == name {
                        return parts.dropFirst(3).joined(separator: " ")
                    }
                }
            }
        }
        return nil
    }

    private func resourceMIMEType(from response: URLResponse?, sourceURL: URL) -> String {
        if let mimeType = response?.mimeType, !mimeType.isEmpty {
            return mimeType
        }

        switch sourceURL.pathExtension.lowercased() {
        case "css":
            return "text/css"
        case "js", "mjs":
            return "text/javascript"
        case "json":
            return "application/json"
        case "xml":
            return "application/xml"
        case "svg":
            return "image/svg+xml"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "mp3":
            return "audio/mpeg"
        case "ogg":
            return "audio/ogg"
        case "wav":
            return "audio/wav"
        case "woff2":
            return "font/woff2"
        case "woff":
            return "font/woff"
        case "ttf":
            return "font/ttf"
        default:
            return "application/octet-stream"
        }
    }

    private func isTextResource(response: URLResponse?, sourceURL: URL) -> Bool {
        let mimeType = resourceMIMEType(from: response, sourceURL: sourceURL).lowercased()
        if mimeType.hasPrefix("text/") {
            return true
        }

        switch mimeType {
        case "application/json", "application/javascript", "application/x-javascript",
            "application/xml", "image/svg+xml":
            return true
        default:
            break
        }

        switch sourceURL.pathExtension.lowercased() {
        case "css", "js", "mjs", "json", "txt", "html", "xml", "svg":
            return true
        default:
            return false
        }
    }

    private func decodedTextResource(from data: Data, response: URLResponse?, sourceURL: URL) -> String? {
        guard isTextResource(response: response, sourceURL: sourceURL) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func encodedResourcePayload(from data: Data, response: URLResponse?, sourceURL: URL) -> String {
        let mimeType = resourceMIMEType(from: response, sourceURL: sourceURL)
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private func downloadData(from url: URL, maximumBytes: Int) async throws -> (Data, URLResponse) {
        let (downloadURL, response) = try await urlSession.download(from: url)
        defer { try? FileManager.default.removeItem(at: downloadURL) }

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        let expectedBytes = response.expectedContentLength
        guard expectedBytes <= 0 || expectedBytes <= maximumBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }

        let fileSize = try downloadURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= maximumBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        return (try Data(contentsOf: downloadURL), response)
    }

    public func ensureResourceContent(forScriptId scriptId: UUID, resourceName: String) async -> String? {
        guard let index = indexOfUserScript(withId: scriptId) else {
            return nil
        }

        // 1) In-memory cache
        if let cached = self.userScripts[index].resourceContents[resourceName], !cached.isEmpty {
            return cached
        }

        // 2) Disk cache
        if let diskResources = readUserScriptResources(self.userScripts[index]) {
            guard Self.resourceCacheFitsLimits(diskResources) else {
                logger.error("Ignoring oversized @resource cache for script \(self.userScripts[index].name)")
                removeUserScriptResourcesFile(self.userScripts[index])
                return nil
            }
            if let diskValue = diskResources[resourceName], !diskValue.isEmpty {
                self.userScripts[index].resourceContents = diskResources
                return diskValue
            }
        }

        // 3) Download on-demand by parsing metadata
        let content = self.userScripts[index].content
        let script = self.userScripts[index]
        guard let resourceURLString = self.extractResourceURL(forResourceName: resourceName, from: content),
            let url = self.resolveMetadataURL(resourceURLString, relativeTo: script)
        else {
            self.logger.error(
                "❌ Missing @resource URL for '\(resourceName)' in script \(self.userScripts[index].name)"
            )
            return nil
        }

        let existingResources = self.userScripts[index].resourceContents
        guard existingResources.count < Self.maximumResourcesPerScript else {
            logger.error("Refusing @resource '\(resourceName)': per-script resource count limit reached")
            return nil
        }

        do {
            self.logger.info(
                "📥 Downloading on-demand @resource '\(resourceName)' from \(resourceURLString)"
            )

            let (responseData, response) = try await self.downloadData(
                from: url,
                maximumBytes: Self.maximumResourceBytes
            )

            if let resourceText = self.decodedTextResource(
                from: responseData,
                response: response,
                sourceURL: url
            ), self.isDDoSProtectionPage(resourceText) {
                self.logger.error(
                    "❌ Received DDoS protection page for on-demand @resource: \(resourceURLString)"
                )
                return nil
            }

            let resourceContent = self.encodedResourcePayload(
                from: responseData,
                response: response,
                sourceURL: url
            )

            guard let currentIndex = self.indexOfUserScript(withId: scriptId) else {
                return nil
            }
            var updatedResources = self.userScripts[currentIndex].resourceContents
            updatedResources[resourceName] = resourceContent
            guard Self.resourceCacheFitsLimits(updatedResources) else {
                self.logger.error(
                    "Refusing @resource '\(resourceName)': per-script storage limit reached"
                )
                return nil
            }

            self.userScripts[currentIndex].resourceContents = updatedResources
            _ = self.writeUserScriptResources(self.userScripts[currentIndex])
            return resourceContent
        } catch {
            self.logger.error(
                "❌ Failed to download on-demand @resource '\(resourceName)' from \(resourceURLString): \(error)"
            )
            return nil
        }
    }

    private func userScriptResourcesFileName(for userScript: UserScript) -> String {
        "\(userScript.id.uuidString).resources.json"
    }

    private func readUserScriptResources(_ userScript: UserScript) -> [String: String]? {
        Self.readUserScriptResourcesOffMain(userScript)
    }

    private func removeUserScriptResourcesFile(_ userScript: UserScript) {
        let fileName = userScriptResourcesFileName(for: userScript)
        [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.forEach { dirURL in
            let fileURL = dirURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    @discardableResult
    private func writeUserScriptResources(_ userScript: UserScript) -> Bool {
        if userScript.resourceContents.isEmpty {
            removeUserScriptResourcesFile(userScript)
            return true
        }

        do {
            let data = try JSONEncoder().encode(userScript.resourceContents)
            var success = false
            let fileName = userScriptResourcesFileName(for: userScript)
            [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.forEach { dirURL in
                let fileURL = dirURL.appendingPathComponent(fileName)
                do {
                    try data.write(to: fileURL, options: .atomic)
                    success = true
                    logger.info("💾 Wrote userscript resources to: \(fileURL.path)")
                } catch {
                    logger.error("❌ Failed to write userscript resources to \(fileURL.path): \(error)")
                }
            }
            return success
        } catch {
            logger.error("❌ Failed to encode userscript resources for \(userScript.name): \(error)")
            return false
        }
    }

    /// Checks if content is a DDoS protection page instead of actual content
    private func isDDoSProtectionPage(_ content: String) -> Bool {
        let lowerContent = content.lowercased()
        return lowerContent.contains("ddos-guard") || lowerContent.contains("ddos protection")
            || lowerContent.contains("checking your browser")
            || (lowerContent.hasPrefix("<!doctype html") && lowerContent.contains("challenge"))
    }

    private func downloadUserScriptContent(from url: URL) async throws -> String {
        let (data, _) = try await downloadData(from: url, maximumBytes: Self.maximumUserScriptBytes)
        guard let content = String(data: data, encoding: .utf8),
              !content.isEmpty,
              !isDDoSProtectionPage(content)
        else {
            throw URLError(.cannotParseResponse)
        }
        return content
    }

    // MARK: - Singleton
    public static let shared = UserScriptManager()

    private let defaultUserScripts = BuiltInUserScripts.definitions

    public func isDefaultUserScript(_ userScript: UserScript) -> Bool {
        guard let urlString = userScript.url?.absoluteString else { return false }
        return BuiltInUserScripts.allProtectedURLs.contains(urlString)
    }

    public func builtInDisplayRole(for userScript: UserScript) -> BuiltInUserScriptDisplayRole? {
        guard let urlString = userScript.url?.absoluteString else { return nil }
        return BuiltInUserScripts.displayRoleByURL[urlString]
    }

    public func builtInLanguages(for userScript: UserScript) -> [String] {
        guard let urlString = userScript.url?.absoluteString else { return [] }
        return BuiltInUserScripts.languagesByURL[urlString] ?? []
    }

    public func isBeta(for userScript: UserScript) -> Bool {
        guard let urlString = userScript.url?.absoluteString else { return false }
        return BuiltInUserScripts.isBetaByURL[urlString] ?? false
    }

    public func isDarkReader(_ userScript: UserScript) -> Bool {
        DarkReaderAppearancePreference.matches(scriptURL: userScript.url)
    }

    public func setDarkReaderFollowsSystemAppearance(_ followsSystemAppearance: Bool) {
        guard darkReaderFollowsSystemAppearance != followsSystemAppearance else { return }
        DarkReaderAppearancePreference.setFollowsSystemAppearance(followsSystemAppearance)
        darkReaderFollowsSystemAppearance = followsSystemAppearance
        Self.invalidateDocumentStartExecutionCache()
        Task { await refreshOutdatedDarkReaderContentIfNeeded() }
    }

    /// Installs made before the appearance preference shipped persist a Dark Reader
    /// adapter that never reads the prepended preference constant: the first build
    /// called DarkReader.enable() unconditionally, so pages stayed dark-themed even
    /// with the system in light mode, and later pre-preference builds always followed
    /// the system. Legacy migration intentionally keeps persisted content, and
    /// auto-update is throttled (and effectively manual on iOS), so refresh such
    /// content directly whenever we notice it.
    private func refreshOutdatedDarkReaderContentIfNeeded() async {
        guard let script = userScripts.first(where: {
            DarkReaderAppearancePreference.matches(scriptURL: $0.url)
        }),
            !script.content.isEmpty,
            !script.content.contains(DarkReaderAppearancePreference.appearanceFlagName)
        else { return }

        logger.info("🔄 Dark Reader content predates the appearance preference; refreshing")
        do {
            if try await updateSingleScript(script) {
                await persistUserScriptsNow()
                Self.invalidateDocumentStartExecutionCache()
                logger.info("✅ Refreshed Dark Reader to an appearance-aware adapter")
            }
        } catch {
            logger.error("❌ Dark Reader appearance refresh failed: \(error.localizedDescription)")
        }
    }

    private init() {
        logger.info("🔧 UserScriptManager initializing...")

        // Using ProtobufDataManager for data persistence
        logger.info("✅ Using ProtobufDataManager for userscript persistence")

        // Initialize userscripts after data manager finishes loading saved data
        var task: Task<Void, Never>?
        task = Task { @MainActor [weak self] in
            defer {
                if let self, let task, self.initialLoadTask == task {
                    self.initialLoadTask = nil
                }
            }
            guard let self else { return }
            await dataManager.waitUntilLoaded()
            // Load existing scripts
            self.userScripts = dataManager.getUserScripts(includePersistedContent: true)
            logger.info("🔧 Loaded \(self.userScripts.count) userscripts from ProtobufDataManager")

            // Initial setup (folders, defaults, downloads)
            await self.setup()

            // Observe dataManager for userscript changes only (not all appData changes)
            dataManager.$appData
                .map { $0.userScripts }
                .removeDuplicates()
                .sink { [weak self] _ in
                    Task { [weak self] in
                        await self?.syncFromDataManager()
                    }
                }
            .store(in: &cancellables)
            logger.info("✅ UserScriptManager data sync observer setup complete")
            self.isReady = true
            self.startDeferredStartupMaintenance()
        }
        initialLoadTask = task
    }

    /// Waits until the manager has finished loading and initial setup has run.
    public func waitUntilReady() async {
        if let initialLoadTask {
            await initialLoadTask.value
            return
        }

        while !isReady {
            await Task.yield()
        }
    }

    /// Reloads the authoritative userscript records after another process may have
    /// changed the shared container. Execution authorization must use this boundary,
    /// rather than relying on this process's cached array or revision counter.
    public func refreshFromDiskForExecution() async {
        await waitUntilReady()
        _ = await dataManager.refreshFromDiskIfModified(forceRead: true)
        let diskScripts = dataManager.getUserScripts(includePersistedContent: true)
        let hydratedScripts = await hydrateUserScriptsFromDisk(
            diskScripts,
            includeResources: false,
            hydrateDisabled: false
        )
        guard areUserScriptsEqual(userScripts, hydratedScripts) == false else { return }
        userScripts = hydratedScripts
    }

    private func syncFromDataManager() async {
        dataManagerSyncGeneration &+= 1
        let generation = dataManagerSyncGeneration
        let newUserScripts = dataManager.getUserScripts()
        logger.info("🔄 Syncing userscripts from data manager: \(newUserScripts.count) scripts")

        // If data manager has no scripts but we have defaults, don't sync from empty data manager
        if newUserScripts.isEmpty && !userScripts.isEmpty {
            logger.info(
                "🔄 Data manager is empty but we have userscripts - skipping sync to preserve defaults"
            )
            return
        }

        // Update content from stored files (do file I/O off main thread)
        var updatedScripts = await hydrateUserScriptsFromDisk(
            newUserScripts,
            includeResources: false,
            hydrateDisabled: false
        )
        guard generation == dataManagerSyncGeneration else {
            logger.info("🔄 Ignoring stale userscript sync generation \(generation)")
            return
        }
        applyLatestUserScriptIntents(to: &updatedScripts)

        // Only update if the scripts have actually changed to avoid unnecessary UI updates
        if !areUserScriptsEqual(userScripts, updatedScripts) {
            userScripts = updatedScripts
            logger.info("✅ Updated userscripts from data manager")
        }
    }

    private func hydrateUserScriptsFromDisk(
        _ userScripts: [UserScript],
        includeResources: Bool,
        hydrateDisabled: Bool = true
    ) async -> [UserScript] {
        await Task.detached {
            Self.hydrateUserScriptsFromDiskOffMain(
                userScripts,
                includeResources: includeResources,
                hydrateDisabled: hydrateDisabled
            )
        }.value
    }

    nonisolated private static func hydrateUserScriptsFromDiskOffMain(
        _ userScripts: [UserScript],
        includeResources: Bool,
        hydrateDisabled: Bool
    ) -> [UserScript] {
        var scripts = userScripts
        for i in scripts.indices {
            if !hydrateDisabled && !scripts[i].isEnabled {
                scripts[i].content = ""
                scripts[i].resourceContents = [:]
                continue
            }

            scripts[i] = hydrateUserScriptFromDisk(scripts[i])

            guard includeResources else { continue }
            if let resources = readUserScriptResourcesOffMain(scripts[i]) {
                scripts[i].resourceContents = resources
            }
        }
        return scripts
    }

    /// Hydrates source content without discarding display metadata chosen for a local import.
    nonisolated private static func hydrateUserScriptFromDisk(_ script: UserScript) -> UserScript {
        var hydratedScript = script
        guard let content = readUserScriptContentOffMain(script) else { return hydratedScript }

        // Source is authoritative. The derived artifact is loaded or rebuilt off-main;
        // neither protobuf hydration nor runtime injection ever compiles on @MainActor.
        if UserScript.detectsUserStyle(in: content),
           let metadata = UserStyleSupport.parsed(from: content, compiledBody: nil, compileSource: false) {
            let artifact = validatedCompiledStyleArtifact(for: content, metadata: metadata, scriptID: script.id)
            hydratedScript.replaceContentAndParseMetadata(content, compiledBody: artifact?.body)
            if artifact == nil, UserStylePreprocessorService.requiresCompilation(metadata.preprocessor) {
                let request = UserStyleSupport.compilationRequest(
                    for: content, preprocessor: metadata.preprocessor,
                    variables: metadata.variables)
                if let rebuilt = try? UserStylePreprocessorService.compile(request) {
                    hydratedScript.replaceContentAndParseMetadata(content, compiledBody: rebuilt.body)
                    writeCompiledStyleArtifact(rebuilt, scriptID: script.id)
                } else {
                    removeCompiledStyleArtifact(scriptID: script.id)
                }
            }
        } else {
            hydratedScript.replaceContentAndParseMetadata(content)
            removeCompiledStyleArtifact(scriptID: script.id)
        }

        let persistedName = script.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedDescription = script.description

        // Parsing large scripts can allocate tens of thousands of metadata strings
        // that are identical to the persisted protobuf values. Reuse the persisted
        // array storage after validating it against the source-derived metadata.
        let persistedArrayFields: [WritableKeyPath<UserScript, [String]>] = [
            \.matches, \.excludeMatches, \.includes, \.excludes, \.grant,
        ]
        for keyPath in persistedArrayFields
        where hydratedScript[keyPath: keyPath] == script[keyPath: keyPath] {
            hydratedScript[keyPath: keyPath] = script[keyPath: keyPath]
        }

        if script.isLocal {
            if !persistedName.isEmpty {
                hydratedScript.name = script.name
            }
            hydratedScript.description = persistedDescription
        }
        return hydratedScript
    }

    nonisolated private static let compiledStyleSidecarSuffix = ".user.css.compiled.v1.json"

    nonisolated private static func scriptsDirectoryURLs() -> [URL] {
        var urls: [URL] = []
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value)?.appendingPathComponent("userscripts") {
            urls.append(group)
        }
        if let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("wBlock").appendingPathComponent("userscripts") {
            urls.append(fallback)
        }
        return urls
    }

    nonisolated private static func compiledStyleURL(scriptID: UUID, directory: URL) -> URL {
        directory.appendingPathComponent("\(scriptID.uuidString)\(compiledStyleSidecarSuffix)")
    }

    nonisolated private static func validatedCompiledStyleArtifact(
        for source: String, metadata: UserStyleSupport.ParsedStyle, scriptID: UUID
    ) -> UserStyleCompiledArtifact? {
        guard UserStylePreprocessorService.requiresCompilation(metadata.preprocessor) else { return nil }
        let request = UserStyleSupport.compilationRequest(
            for: source, preprocessor: metadata.preprocessor, variables: metadata.variables)
        for directory in scriptsDirectoryURLs() {
            let url = compiledStyleURL(scriptID: scriptID, directory: directory)
            guard let data = try? Data(contentsOf: url), let artifact = try? JSONDecoder().decode(UserStyleCompiledArtifact.self, from: data) else { continue }
            if UserStylePreprocessorService.validate(artifact, for: request) {
                writeCompiledStyleArtifact(artifact, scriptID: scriptID)
                return artifact
            }
        }
        return nil
    }

    @discardableResult
    nonisolated private static func writeCompiledStyleArtifact(_ artifact: UserStyleCompiledArtifact, scriptID: UUID) -> Bool {
        guard let data = try? JSONEncoder().encode(artifact) else { return false }
        let directories = scriptsDirectoryURLs()
        guard !directories.isEmpty else { return false }
        var success = true
        for directory in directories {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var url = compiledStyleURL(scriptID: scriptID, directory: directory)
                try data.write(to: url, options: .atomic)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try url.setResourceValues(values)
            } catch {
                success = false
            }
        }
        return success
    }

    nonisolated private static func removeCompiledStyleArtifact(scriptID: UUID) {
        for directory in scriptsDirectoryURLs() { try? FileManager.default.removeItem(at: compiledStyleURL(scriptID: scriptID, directory: directory)) }
    }

    /// Read userscript content off the main thread
    nonisolated private static func readUserScriptContentOffMain(_ userScript: UserScript) -> String? {
        // Try fallback directory first
        if let fallbackURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("wBlock").appendingPathComponent("userscripts")
        {
            let fileURL = fallbackURL.appendingPathComponent("\(userScript.id.uuidString).user.js")
            if FileManager.default.fileExists(atPath: fileURL.path),
                let content = try? String(contentsOf: fileURL, encoding: .utf8)
            {
                if let groupURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
                )?.appendingPathComponent("userscripts") {
                    let destURL = groupURL.appendingPathComponent(fileURL.lastPathComponent)
                    try? FileManager.default.copyItem(at: fileURL, to: destURL)
                }
                return content
            }
        }

        // Then try group directory
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
        )?.appendingPathComponent("userscripts") {
            let fileURL = groupURL.appendingPathComponent("\(userScript.id.uuidString).user.js")
            if FileManager.default.fileExists(atPath: fileURL.path),
                let content = try? String(contentsOf: fileURL, encoding: .utf8)
            {
                return content
            }
        }
        return nil
    }

    /// Read cached userscript resources off the main thread
    nonisolated private static func readUserScriptResourcesOffMain(
        _ userScript: UserScript
    ) -> [String: String]? {
        let fileName = "\(userScript.id.uuidString).resources.json"

        // Try fallback directory first (files may exist here initially)
        if let fallbackURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("wBlock").appendingPathComponent("userscripts")
        {
            let fileURL = fallbackURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path),
                let data = try? Data(contentsOf: fileURL),
                let decoded = try? JSONDecoder().decode([String: String].self, from: data)
            {
                if let groupURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
                )?.appendingPathComponent("userscripts") {
                    let destURL = groupURL.appendingPathComponent(fileURL.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: destURL.path) {
                        try? FileManager.default.copyItem(at: fileURL, to: destURL)
                    }
                }
                return decoded
            }
        }

        // Then try group directory
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
        )?.appendingPathComponent("userscripts") {
            let fileURL = groupURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path),
                let data = try? Data(contentsOf: fileURL),
                let decoded = try? JSONDecoder().decode([String: String].self, from: data)
            {
                return decoded
            }
        }

        return nil
    }

    private func areUserScriptsEqual(_ scripts1: [UserScript], _ scripts2: [UserScript]) -> Bool {
        guard scripts1.count == scripts2.count else { return false }

        for i in 0..<scripts1.count {
            let script1 = scripts1[i]
            let script2 = scripts2[i]

            if script1.id != script2.id || script1.isEnabled != script2.isEnabled
                || script1.name != script2.name || script1.version != script2.version
                || script1.content != script2.content
            {
                return false
            }
        }

        return true
    }

    /// Simple and reliable duplicate detection - only finds truly duplicate scripts
    private func detectDuplicateUserScripts() -> [(older: UserScript, newer: UserScript)] {
        guard userScripts.count > 1 else { return [] }

        var duplicates: [(older: UserScript, newer: UserScript)] = []

        for i in 0..<userScripts.count {
            for j in (i + 1)..<userScripts.count {
                let a = userScripts[i]
                let b = userScripts[j]

                if let urlA = a.url?.absoluteString, let urlB = b.url?.absoluteString,
                   !urlA.isEmpty, urlA == urlB {
                    let (older, newer) = b.isEnabled && !a.isEnabled ? (a, b) : (b, a)
                    duplicates.append((older, newer))
                    continue
                }

                let nameA = a.name.lowercased().trimmingCharacters(in: .whitespaces)
                let nameB = b.name.lowercased().trimmingCharacters(in: .whitespaces)

                guard nameA == nameB else { continue }

                if UserScript.isVersionNewer(b.version, than: a.version) {
                    duplicates.append((a, b))
                } else if UserScript.isVersionNewer(a.version, than: b.version) {
                    duplicates.append((b, a))
                } else {
                    duplicates.append(b.isEnabled && !a.isEnabled ? (a, b) : (b, a))
                }
            }
        }

        if !duplicates.isEmpty {
            logger.info("🔍 Found \(duplicates.count) duplicate userscript pair(s)")
        }
        return duplicates
    }

    /// Simple removal of duplicate userscripts
    private func removeDuplicateUserScripts(_ duplicatesToRemove: [UserScript]) async {
        guard !duplicatesToRemove.isEmpty else { return }

        logger.info("🗑️ Removing \(duplicatesToRemove.count) duplicate userscripts...")

        // Get IDs of scripts to remove
        let idsToRemove = Set(duplicatesToRemove.map { $0.id })

        // Remove files first
        for script in duplicatesToRemove {
            removeUserScriptFile(script)
        }

        // Filter out the scripts to remove from the array
        let originalCount = userScripts.count
        userScripts = userScripts.filter { [idsToRemove] in !idsToRemove.contains($0.id) }

        logger.info("🗑️ Removed \(originalCount - self.userScripts.count) duplicate, \(self.userScripts.count) remaining")

        await persistUserScriptsNow(authoritative: true)
    }

    /// Checks for duplicates and presents confirmation dialog to user
    private func checkForDuplicatesAndAskForConfirmation() {
        let duplicatePairs = detectDuplicateUserScripts()

        if !duplicatePairs.isEmpty {
            let duplicatesToRemove = duplicatePairs.map { $0.older }
            let pendingDuplicateIDs = Set(pendingDuplicatesToRemove.map(\.id))
            let duplicateIDs = Set(duplicatesToRemove.map(\.id))

            if showingDuplicatesAlert && pendingDuplicateIDs == duplicateIDs {
                logger.info("📋 Duplicate removal dialog already showing for current duplicates")
                return
            }

            pendingDuplicatesToRemove = duplicatesToRemove

            let duplicateNames = duplicatePairs.map { pair in
                "• '\(pair.older.name)' (keeping '\(pair.newer.name)')"
            }.joined(separator: "\n")

            duplicatesMessage =
                "Found \(duplicatePairs.count) duplicate userscript(s):\n\n\(duplicateNames)\n\nWould you like to remove the older versions?"

            // Use a small delay to ensure UI is ready to show the alert
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                self.showingDuplicatesAlert = true
                self.logger.info("📋 Showing duplicate removal confirmation dialog")
            }

            logger.info(
                "📋 Asking user to confirm removal of \(duplicatesToRemove.count) duplicate userscripts"
            )
        } else {
            logger.info("✅ No duplicate userscripts found")
        }
    }

    /// Remove the file associated with a userscript from ALL possible locations to prevent resurrection
    private func removeUserScriptFile(_ userScript: UserScript) {
        let fileName = "\(userScript.id.uuidString).user.js"
        var totalRemoved = 0

        // Remove from ALL possible directory locations to prevent resurrection
        [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.forEach {
            dirURL in
            let fileURL = dirURL.appendingPathComponent(fileName)
            let locationName =
                dirURL.path.contains("Group Containers") ? "group container" : "application support"

            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    totalRemoved += 1
                    logger.info("🗑️ Successfully removed file from \(locationName): \(fileURL.path)")
                } catch {
                    logger.error(
                        "❌ Failed to remove file from \(locationName) \(fileURL.path): \(error)")
                }
            } else {
                logger.info("ℹ️ File not found in \(locationName): \(fileURL.path)")
            }
        }

        if totalRemoved == 0 {
            logger.warning(
                "⚠️ No files were found to remove for userscript: \(userScript.name) (ID: \(userScript.id))"
            )
        } else {
            logger.info(
                "✅ Completely removed \(totalRemoved) file(s) for userscript: \(userScript.name) - no resurrection possible"
            )
        }

        removeUserScriptResourcesFile(userScript)
        Self.removeCompiledStyleArtifact(scriptID: userScript.id)
    }

    private func userScriptNotificationInfo(for userScript: UserScript) -> [String: Any] {
        var info: [String: Any] = [
            UserScriptManagerNotificationKey.name: userScript.name,
            UserScriptManagerNotificationKey.isLocal: userScript.isLocal,
        ]

        if let identity = UserScriptImportIdentity.normalized(userScript.localImportIdentity) {
            info[UserScriptManagerNotificationKey.localImportIdentity] = identity
        }
        if let url = userScript.url?.absoluteString {
            info[UserScriptManagerNotificationKey.url] = url
        }

        return info
    }

    private func setup() async {
        logger.info("🔧 Setting up UserScriptManager...")
        checkAndCreateUserScriptsFolder()
        await loadUserScripts()
        await migrateUserScriptSiteExceptionsIfNeeded()
        prefetchDefaultUserScriptMetadataIfNeeded()
        logger.info("✅ UserScriptManager initialized with \(self.userScripts.count) userscript(s)")
        statusDescription = "Initialized with \(userScripts.count) userscript(s)."
    }

    // MARK: - Scripts Directory Locations
    /// URL for group container scripts directory, if available
    private var groupScriptsDirectoryURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: sharedContainerIdentifier)?
            .appendingPathComponent("userscripts")
    }
    /// URL for fallback scripts directory in Application Support
    private var fallbackScriptsDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("wBlock").appendingPathComponent("userscripts")
    }
    private func checkAndCreateUserScriptsFolder() {
        // Ensure both group and fallback directories exist
        [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.forEach {
            dirURL in
            logger.info("📁 Ensuring userscripts folder at: \(dirURL.path)")
            if !FileManager.default.fileExists(atPath: dirURL.path) {
                do {
                    try FileManager.default.createDirectory(
                        at: dirURL, withIntermediateDirectories: true, attributes: nil)
                    logger.info("✅ Created userscripts directory at: \(dirURL.path)")
                } catch {
                    logger.error(
                        "❌ Error creating userscripts directory at \(dirURL.path): \(error)")
                }
            } else {
                logger.info("✅ Userscripts directory already exists at: \(dirURL.path)")
            }
        }
    }

    private func loadUserScripts() async {
        logger.info("📖 Loading userscripts from ProtobufDataManager...")
        _ = await dataManager.refreshFromDiskIfModified(forceRead: true)
        userScripts = dataManager.getUserScripts(includePersistedContent: true)
        logger.info("📖 Loaded \(self.userScripts.count) userscripts from ProtobufDataManager")

        let embeddedMigration = migrateEmbeddedProtobufContentToFilesIfNeeded()
        if embeddedMigration.embeddedCount > 0 {
            if embeddedMigration.failedCount == 0 {
                let cleared = await dataManager.clearEmbeddedUserScriptContentIfPresent()
                if cleared {
                    logger.info(
                        "🧹 Cleared embedded userscript content from protobuf after file migration (\(embeddedMigration.embeddedCount) scripts)")
                }
            } else {
                logger.error(
                    "⚠️ Kept embedded userscript content in protobuf for safety. Failed to migrate \(embeddedMigration.failedCount) scripts to file storage.")
            }
        }

        await removeRetiredYouTubeAdBlockIfNeeded()
        await migrateLegacyBundledUserScriptsIfNeeded()
        await migrateLegacyPopupBlockerIfNeeded()
        await migrateLegacyTinyShieldVariantsIfNeeded()

        // Always check for missing default scripts first
        await checkAndAddMissingDefaultScripts()
        await refreshDefaultUserScriptDescriptionsIfNeeded()

        // Always check for duplicates - simplified approach
        checkForDuplicatesAndAskForConfirmation()

        if userScripts.isEmpty {
            logger.info("📖 No userscripts found after default check, loading defaults")
            await loadDefaultUserScripts()
        } else {
            let hydratedScripts = await hydrateUserScriptsFromDisk(
                userScripts,
                includeResources: true,
                hydrateDisabled: false
            )

            for script in hydratedScripts {
                logger.info("📖 Loading content for script: \(script.name) (ID: \(script.id))")
                logger.info("📖 Script enabled: \(script.isEnabled), matches: \(script.matches.count)")

                if script.content.isEmpty {
                    if script.isEnabled {
                        logger.warning("⚠️ Failed to load content for \(script.name)")
                    } else {
                        logger.info("📖 Skipped content for disabled script \(script.name)")
                    }
                } else {
                    logger.info(
                        "✅ Loaded content for \(script.name) (\(script.content.count) characters)")
                }

                if !script.resourceContents.isEmpty {
                    logger.info(
                        "✅ Loaded \(script.resourceContents.count) cached resources for \(script.name)")
                }
            }

            userScripts = hydratedScripts
        }

    }

    /// Startup maintenance that needs the network. It must not gate
    /// `waitUntilReady()`: extension processes call `getUserScripts` while a page
    /// is loading, and a slow or unreachable download server here used to stall
    /// every userscript injection behind the injector's retry ladder until the
    /// native request timed out (the "Dark Reader applies after ~15 seconds"
    /// reports). Run it after readiness so cold starts answer from disk.
    private func startDeferredStartupMaintenance() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Only download scripts that are enabled but missing content (e.g., from migration).
            await self.downloadMissingDefaultScripts()
            // Heal Dark Reader installs whose persisted adapter cannot honor the
            // appearance preference (pre-preference builds themed pages unconditionally).
            await self.refreshOutdatedDarkReaderContentIfNeeded()
        }
    }

    private func migrateEmbeddedProtobufContentToFilesIfNeeded() -> (
        embeddedCount: Int, failedCount: Int
    ) {
        var embeddedCount = 0
        var failedCount = 0

        for script in userScripts {
            guard !script.content.isEmpty else { continue }
            embeddedCount += 1

            if userScriptFileExists(script) {
                continue
            }

            if !writeUserScriptContent(script) {
                failedCount += 1
                logger.error(
                    "❌ Failed migrating embedded userscript content to file for \(script.name)")
            }
        }

        if embeddedCount > 0 {
            logger.info(
                "📦 Detected \(embeddedCount) userscripts with embedded protobuf content; migrated \(embeddedCount - failedCount) to file-backed storage.")
        }

        return (embeddedCount: embeddedCount, failedCount: failedCount)
    }

    private func checkAndAddMissingDefaultScripts() async {
        logger.info("🔍 Checking for missing default userscripts...")
        logger.info("🔍 Current userscripts count: \(self.userScripts.count)")

        var hasAddedNew = false

        for defaultScript in defaultUserScripts {
            logger.info("🔍 Checking default script: '\(defaultScript.name)'")

            // Simple check - does this URL already exist?
            let existsByURL = userScripts.contains { script in
                script.url?.absoluteString == defaultScript.url
            }

            if !existsByURL {
                logger.info("➕ Adding missing default script: \(defaultScript.name)")
                guard let url = URL(string: defaultScript.url) else {
                    logger.error("❌ Invalid URL for default script: \(defaultScript.url)")
                    continue
                }

                var newUserScript = UserScript(name: defaultScript.name, url: url, content: "")
                newUserScript.isEnabled = defaultScript.isEnabledByDefault
                newUserScript.isLocal = false
                newUserScript.description = defaultScript.description
                newUserScript.version = ""

                userScripts.append(newUserScript)
                hasAddedNew = true
                logger.info("✅ Added default script: \(defaultScript.name)")
            } else {
                logger.info("✅ Default script already exists: \(defaultScript.name)")
            }
        }

        if hasAddedNew {
            logger.info("💾 Saving \(self.userScripts.count) userscripts after adding defaults")
            await persistUserScriptsNow()
        } else {
            logger.info("ℹ️ No missing default scripts to add")
        }
    }

    private func refreshDefaultUserScriptDescriptionsIfNeeded() async {
        var didUpdate = false

        for defaultScript in defaultUserScripts {
            guard let index = userScripts.firstIndex(where: { $0.url?.absoluteString == defaultScript.url }) else {
                continue
            }
            guard shouldReplaceDefaultUserScriptDescription(userScripts[index].description) else {
                continue
            }
            guard userScripts[index].description != defaultScript.description else {
                continue
            }

            userScripts[index].description = defaultScript.description
            didUpdate = true
        }

        if didUpdate {
            await persistUserScriptsNow()
        }
    }

    private func shouldReplaceDefaultUserScriptDescription(_ description: String) -> Bool {
        let normalizedDescription = description
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedDescription.isEmpty
            || normalizedDescription == "default userscript"
            || normalizedDescription == "default userscript - downloading..."
            || normalizedDescription == "ready to enable"
    }

    private func downloadMissingDefaultScripts() async {
        logger.info("📥 Checking and downloading enabled userscripts that are missing content...")

        // Keep stable IDs across awaits. The array can be replaced while a download is
        // suspended (for example by a sync or restore), so an index captured before an
        // await must never be reused afterward.
        let candidateIDs = userScripts.map(\.id)
        for scriptID in candidateIDs {
            guard let index = indexOfUserScript(withId: scriptID) else { continue }
            let script = userScripts[index]

            // Check if this is a default script that needs downloading
            let isDefaultScript = script.url.map { BuiltInUserScripts.allProtectedURLs.contains($0.absoluteString) } ?? false

            guard isDefaultScript else { continue }
            guard script.isEnabled else { continue }
            guard !script.isLocal else { continue }

            // Prefer local disk content if available (avoid unnecessary network requests on launch).
            if script.content.isEmpty, let diskContent = readUserScriptContent(script), !diskContent.isEmpty {
                userScripts[index].replaceContentAndParseMetadata(diskContent)
                if let resources = readUserScriptResources(script) {
                    userScripts[index].resourceContents = resources
                }
                continue
            }

            if script.content.isEmpty, let url = script.url {
                await downloadUserScriptInBackground(for: scriptID, from: url)
            }
        }

        await MainActor.run {
            logger.info("✅ Finished checking enabled userscripts")
        }
    }

    private func loadDefaultUserScripts() async {
        logger.info("🎯 Loading default userscripts for first-time setup...")

        for defaultScript in defaultUserScripts {
            guard let url = URL(string: defaultScript.url) else {
                logger.error("❌ Invalid URL for default userscript: \(defaultScript.url)")
                continue
            }

            var newUserScript = UserScript(name: defaultScript.name, url: url, content: "")
            newUserScript.isEnabled = defaultScript.isEnabledByDefault
            newUserScript.isLocal = false  // Mark as remote

            // Add placeholder metadata so they show up in the list
            newUserScript.description = defaultScript.description
            newUserScript.version = ""

            userScripts.append(newUserScript)
            logger.info("✅ Added default userscript placeholder: \(defaultScript.name)")
        }

        if !userScripts.isEmpty {
            logger.info("💾 About to save \(self.userScripts.count) default userscript placeholders")
            await persistUserScriptsNow()
            logger.info("💾 Saved \(self.userScripts.count) default userscript placeholders")
        }
    }

    private func migrateLegacyBundledUserScriptsIfNeeded() async {
        var didChange = false

        for (legacyURL, canonicalURLString) in BuiltInUserScripts.legacyBundledURLsByCanonical {
            guard let canonicalURL = URL(string: canonicalURLString),
                  let legacy = userScripts.first(where: { $0.url?.absoluteString == legacyURL })
            else { continue }

            // Prefer an already-canonical record when one survives. Its enabled state
            // is an explicit configured choice and must not be promoted by migration.
            // If it does not exist, retain the legacy UUID so per-site state survives.
            let canonicalWasConfigured = userScripts.contains {
                $0.url?.absoluteString == canonicalURLString
            }
            let retainedID = userScripts.first(where: {
                $0.url?.absoluteString == canonicalURLString
            })?.id ?? legacy.id
            guard let retainedIndex = userScripts.firstIndex(where: { $0.id == retainedID }) else {
                continue
            }
            if !canonicalWasConfigured {
                userScripts[retainedIndex].isEnabled = userScripts.contains {
                    $0.url?.absoluteString == legacyURL && $0.isEnabled
                }
            }

            if userScripts[retainedIndex].content.isEmpty,
               let diskContent = readUserScriptContent(userScripts[retainedIndex]),
               !diskContent.isEmpty {
                userScripts[retainedIndex].replaceContentAndParseMetadata(diskContent)
                userScripts[retainedIndex].resourceContents =
                    readUserScriptResources(userScripts[retainedIndex]) ?? [:]
            }

            let duplicateIDs = userScripts.compactMap { script -> UUID? in
                guard script.id != retainedID,
                      script.url?.absoluteString == legacyURL
                        || script.url?.absoluteString == canonicalURLString
                else { return nil }
                return script.id
            }
            var mergedDisabledHosts = Set(
                dataManager.getUserScriptDisabledHosts(forScriptID: retainedID.uuidString)
            )

            for duplicateID in duplicateIDs {
                guard let duplicateIndex = userScripts.firstIndex(where: {
                    $0.id == duplicateID
                }), let currentRetainedIndex = userScripts.firstIndex(where: {
                    $0.id == retainedID
                }) else { continue }
                let duplicate = userScripts[duplicateIndex]
                mergedDisabledHosts.formUnion(
                    dataManager.getUserScriptDisabledHosts(forScriptID: duplicateID.uuidString)
                )
                if userScripts[currentRetainedIndex].content.isEmpty {
                    let duplicateContent = duplicate.content.isEmpty
                        ? readUserScriptContent(duplicate)
                        : duplicate.content
                    if let duplicateContent, !duplicateContent.isEmpty {
                        userScripts[currentRetainedIndex].replaceContentAndParseMetadata(duplicateContent)
                        userScripts[currentRetainedIndex].resourceContents = duplicate.resourceContents.isEmpty
                            ? (readUserScriptResources(duplicate) ?? [:])
                            : duplicate.resourceContents
                    }
                }

                removeUserScriptFile(duplicate)
                userScripts.remove(at: duplicateIndex)
                await dataManager.setUserScriptDisabledHosts(
                    [], forScriptID: duplicateID.uuidString
                )
                didChange = true
            }

            guard let currentIndex = userScripts.firstIndex(where: {
                $0.id == retainedID
            }) else { continue }
            userScripts[currentIndex].url = canonicalURL
            userScripts[currentIndex].updatesAutomatically = true
            if !userScripts[currentIndex].content.isEmpty {
                _ = writeUserScriptFiles(userScripts[currentIndex])
            }
            await dataManager.setUserScriptDisabledHosts(
                mergedDisabledHosts.sorted(), forScriptID: retainedID.uuidString
            )
            didChange = true
        }

        if didChange {
            await persistUserScriptsNow(authoritative: true)
        }
    }

    private func removeRetiredYouTubeAdBlockIfNeeded() async {
        let retiredScripts = userScripts.filter {
            $0.url?.absoluteString == BuiltInUserScripts.retiredYouTubeAdBlockURL
        }
        guard !retiredScripts.isEmpty else { return }

        for script in retiredScripts {
            removeUserScriptFile(script)
        }
        userScripts.removeAll {
            $0.url?.absoluteString == BuiltInUserScripts.retiredYouTubeAdBlockURL
        }
        await persistUserScriptsNow(authoritative: true)
    }

    @MainActor
    private func migrateLegacyPopupBlockerIfNeeded() async {
        guard let stableURL = URL(string: BuiltInUserScripts.popupBlockerStableURL) else {
            logger.error("❌ Invalid stable popup blocker URL: \(BuiltInUserScripts.popupBlockerStableURL)")
            return
        }

        let legacyIndices = userScripts.indices.filter {
            userScripts[$0].url?.absoluteString == BuiltInUserScripts.legacyPopupBlockerBetaURL
        }

        guard !legacyIndices.isEmpty else { return }

        logger.info("🔁 Migrating \(legacyIndices.count) legacy popup blocker userscript(s) to stable")

        var didChange = false
        var needsStableDownload = false
        var scriptsToDeleteFromDisk: [UserScript] = []
        let legacyWasEnabled = legacyIndices.contains { userScripts[$0].isEnabled }

        for legacyIndex in legacyIndices.sorted(by: >) {
            guard userScripts.indices.contains(legacyIndex) else { continue }

            let legacyScript = userScripts[legacyIndex]

            if let stableIndex = userScripts.firstIndex(where: {
                $0.id != legacyScript.id
                    && $0.url?.absoluteString == BuiltInUserScripts.popupBlockerStableURL
            }) {
                // A surviving stable record is already configured. Do not let a legacy
                // migration override its explicit disabled choice.
                needsStableDownload = needsStableDownload || userScripts[stableIndex].isEnabled
                scriptsToDeleteFromDisk.append(legacyScript)
                userScripts.remove(at: legacyIndex)
                didChange = true
                continue
            }

            userScripts[legacyIndex].name = BuiltInUserScripts.popupBlockerName
            userScripts[legacyIndex].url = stableURL
            userScripts[legacyIndex].isEnabled = legacyWasEnabled
            userScripts[legacyIndex].description = "Default userscript"
            userScripts[legacyIndex].version = ""
            userScripts[legacyIndex].updateURL = nil
            userScripts[legacyIndex].downloadURL = nil
            userScripts[legacyIndex].content = ""
            userScripts[legacyIndex].resourceContents = [:]

            scriptsToDeleteFromDisk.append(legacyScript)
            needsStableDownload = needsStableDownload || legacyScript.isEnabled
            didChange = true
        }

        guard didChange else { return }

        for script in scriptsToDeleteFromDisk {
            removeUserScriptFile(script)
        }

        await persistUserScriptsNow(authoritative: true)

        if needsStableDownload {
            await downloadMissingDefaultScripts()
        }
    }

    private func migrateLegacyTinyShieldVariantsIfNeeded() async {
        let legacyIndices = userScripts.indices.filter {
            userScripts[$0].url?.absoluteString.hasPrefix(BuiltInUserScripts.legacyTinyShieldGroupedURLPrefix) == true
        }
        guard !legacyIndices.isEmpty else { return }

        let fullIndex = userScripts.firstIndex {
            $0.url?.absoluteString == BuiltInUserScripts.tinyShieldURL
        }
        var retainedIndex = fullIndex ?? legacyIndices[0]
        if fullIndex == nil {
            // No canonical record survived: migrate one legacy record in place so the
            // consolidated legacy choice becomes the configured canonical choice.
            userScripts[retainedIndex].isEnabled = legacyIndices.contains { userScripts[$0].isEnabled }
            userScripts[retainedIndex].url = URL(string: BuiltInUserScripts.tinyShieldURL)
            userScripts[retainedIndex].name = "tinyShield"
            userScripts[retainedIndex].description = BuiltInUserScripts.tinyShieldDescription
        }

        let duplicateIDs = legacyIndices.compactMap { index -> UUID? in
            guard userScripts.indices.contains(index), index != retainedIndex else { return nil }
            return userScripts[index].id
        }
        for id in duplicateIDs {
            guard let index = indexOfUserScript(withId: id) else { continue }
            removeUserScriptFile(userScripts[index])
            userScripts.remove(at: index)
            if index < retainedIndex { retainedIndex -= 1 }
        }
        await persistUserScriptsNow(authoritative: true)
    }

    private func shouldPrefetchMetadata(for userScript: UserScript) -> Bool {
        guard !userScript.isLocal else { return false }
        guard isDefaultUserScript(userScript) else { return false }
        let normalizedVersion = userScript.version.trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedVersion.isEmpty || shouldReplaceDefaultUserScriptDescription(userScript.description)
    }

    public func prefetchDefaultUserScriptMetadataIfNeeded() {
        guard metadataPrefetchTask == nil else { return }

        let candidateIDs = userScripts
            .filter { shouldPrefetchMetadata(for: $0) }
            .map(\.id)

        guard !candidateIDs.isEmpty else { return }

        metadataPrefetchTask = Task { @MainActor [weak self] in
            guard let self else { return }

            self.isPrefetchingDefaultMetadata = true
            defer {
                self.isPrefetchingDefaultMetadata = false
                self.metadataPrefetchTask = nil
            }

            var hasMetadataUpdates = false

            for scriptID in candidateIDs {
                guard let index = self.indexOfUserScript(withId: scriptID) else { continue }
                guard self.userScripts.indices.contains(index) else { continue }

                let currentScript = self.userScripts[index]
                guard self.shouldPrefetchMetadata(for: currentScript) else { continue }
                guard let scriptURL = currentScript.url else { continue }

                do {
                    let content = try await self.downloadUserScriptContent(from: scriptURL)

                    var parsed = UserScript(name: currentScript.name, url: scriptURL, content: content)
                    parsed.parseMetadata()

                    let parsedDescription = parsed.description.trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    let parsedVersion = parsed.version.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard let updateIndex = self.indexOfUserScript(withId: scriptID),
                          self.userScripts.indices.contains(updateIndex)
                    else { continue }

                    if !parsedDescription.isEmpty
                        && self.userScripts[updateIndex].description != parsedDescription
                    {
                        self.userScripts[updateIndex].description = parsedDescription
                        hasMetadataUpdates = true
                    }

                    if !parsedVersion.isEmpty && self.userScripts[updateIndex].version != parsedVersion {
                        self.userScripts[updateIndex].version = parsedVersion
                        hasMetadataUpdates = true
                    }
                } catch {
                    self.logger.error(
                        "❌ Failed prefetching metadata for default userscript \(currentScript.name): \(error)"
                    )
                }
            }

            if hasMetadataUpdates {
                await self.persistUserScriptsNow()
            }
        }
    }


    /// UserCSS source is compiled as authored. Userscript-only dependency directives
    /// must never change the source identity associated with a compiled artifact.
    private func processedDependencies(
        for userScript: UserScript
    ) async -> (content: String, resources: [String: String]) {
        guard !userScript.isUserStyle else { return (userScript.content, [:]) }
        let content = await processRequireDirectives(userScript)
        let resources = await processResourceDirectives(userScript)
        return (content, resources)
    }

    /// Downloads and processes @require dependencies for a userscript
    private func processRequireDirectives(_ userScript: UserScript) async -> String {
        guard !userScript.require.isEmpty else {
            return userScript.content
        }

        logger.info(
            "📦 Processing \(userScript.require.count) @require directive(s) for \(userScript.name)")

        var requiredSections: [String] = []
        requiredSections.reserveCapacity(min(userScript.require.count, Self.maximumRequiresPerScript))
        var requiredBytes = 0

        // Download and prepend each required script
        for requireURL in userScript.require.prefix(Self.maximumRequiresPerScript) {
            guard let url = resolveMetadataURL(requireURL, relativeTo: userScript) else {
                logger.error("❌ Invalid @require URL: \(requireURL)")
                continue
            }

            do {
                logger.info("📥 Downloading required script: \(url.absoluteString)")

                let (responseData, _) = try await downloadData(
                    from: url,
                    maximumBytes: Self.maximumRequireBytes
                )

                if let requiredContent = String(data: responseData, encoding: .utf8) {
                    // Check for DDoS protection page
                    if isDDoSProtectionPage(requiredContent) {
                        logger.error("❌ Received DDoS protection page for @require: \(requireURL)")
                        continue
                    }
                    let section = "// @require \(url.absoluteString)\n\(requiredContent)\n\n"
                    let sectionBytes = section.utf8.count
                    guard requiredBytes + sectionBytes <= Self.maximumRequireBytesPerScript else {
                        logger.error("❌ Skipping @require: per-script dependency limit reached")
                        break
                    }
                    requiredSections.append(section)
                    requiredBytes += sectionBytes
                    logger.info("✅ Downloaded required script from: \(url.absoluteString)")
                } else {
                    logger.error("❌ Failed to decode required script from: \(requireURL)")
                }
            } catch {
                logger.error("❌ Failed to download @require from \(requireURL): \(error)")
            }
        }

        requiredSections.append(userScript.content)
        let combinedContent = requiredSections.joined()
        logger.info(
            "✅ Combined script size: \(combinedContent.count) characters (original: \(userScript.content.count))"
        )
        return combinedContent
    }

    /// Downloads and caches @resource dependencies for a userscript
    private func processResourceDirectives(_ userScript: UserScript) async -> [String: String] {
        guard !userScript.resource.isEmpty else {
            return [:]
        }

        logger.info(
            "📦 Processing \(userScript.resource.count) @resource directive(s) for \(userScript.name)"
        )

        var resources: [String: String] = [:]

        // Download and cache each resource
        for resource in userScript.resource {
            let resourceName = resource.name
            let resourceURL = resource.url
            guard let url = resolveMetadataURL(resourceURL, relativeTo: userScript) else {
                logger.error("❌ Invalid @resource URL: \(resourceURL)")
                continue
            }

            do {
                logger.info("📥 Downloading resource: \(resourceName) from \(url.absoluteString)")

                let (responseData, response) = try await downloadData(
                    from: url,
                    maximumBytes: Self.maximumResourceBytes
                )

                if let resourceText = decodedTextResource(
                    from: responseData,
                    response: response,
                    sourceURL: url
                ), isDDoSProtectionPage(resourceText) {
                    logger.error(
                        "❌ Received DDoS protection page for @resource: \(resourceURL)")
                    continue
                }

                let resourceContent = encodedResourcePayload(
                    from: responseData,
                    response: response,
                    sourceURL: url
                )
                var updatedResources = resources
                updatedResources[resourceName] = resourceContent
                guard Self.resourceCacheFitsLimits(updatedResources) else {
                    logger.error(
                        "❌ Skipping @resource '\(resourceName)': per-script resource limit reached"
                    )
                    continue
                }
                resources = updatedResources
                logger.info(
                    "✅ Downloaded resource '\(resourceName)' (\(responseData.count) bytes)")
            } catch {
                logger.error(
                    "❌ Failed to download @resource '\(resourceName)' from \(resourceURL): \(error)"
                )
            }
        }

        logger.info(
            "✅ Downloaded \(resources.count)/\(userScript.resource.count) resources for \(userScript.name)"
        )
        return resources
    }

    private func downloadUserScriptInBackground(
        for scriptID: UUID,
        from url: URL,
        origin: UserScriptMutationOrigin = .local
    ) async {
        guard let index = indexOfUserScript(withId: scriptID),
              userScripts.indices.contains(index)
        else { return }
        let scriptName = userScripts[index].name
        let mutationRevision = scriptMutationRevision(scriptID)

        logger.info("📥 Downloading userscript from: \(url)")

        do {
            let content = try await downloadUserScriptContent(from: url)

            guard mutationRevision == scriptMutationRevision(scriptID),
                  let currentIndex = indexOfUserScript(withId: scriptID),
                  userScripts.indices.contains(currentIndex)
            else { return }

            let downloaded = try await validatedDownloadedUserScriptContent(
                content,
                replacing: userScripts[currentIndex]
            )
            userScripts[currentIndex] = downloaded
            userScripts[currentIndex].lastUpdated = Date()

            // Update description and version from metadata, but keep disabled
            if userScripts[currentIndex].description.isEmpty
                || userScripts[currentIndex].description == "Default userscript - downloading..."
            {
                userScripts[currentIndex].description =
                    userScripts[currentIndex].description.isEmpty
                    ? "Ready to enable" : userScripts[currentIndex].description
            }

            if userScripts[currentIndex].version == "Downloading..." {
                userScripts[currentIndex].version =
                    userScripts[currentIndex].version.isEmpty
                    ? "Downloaded" : userScripts[currentIndex].version
            }

            // Process @require directives after metadata is parsed
            let scriptForDirectives = userScripts[currentIndex]
            let dependencies = await processedDependencies(for: scriptForDirectives)
            let processedContent = dependencies.content
            let resourceContents = dependencies.resources

            guard mutationRevision == scriptMutationRevision(scriptID),
                  let finalIndex = indexOfUserScript(withId: scriptID),
                  userScripts.indices.contains(finalIndex)
            else { return }

            userScripts[finalIndex].content = processedContent
            userScripts[finalIndex].resourceContents = resourceContents
            _ = writeUserScriptFiles(userScripts[finalIndex])
            if origin == .local { recordScriptMutation(scriptID) }
            await persistUserScriptsNow()
            logger.info("✅ Downloaded and saved: \(self.userScripts[finalIndex].name)")
        } catch {
            if mutationRevision == scriptMutationRevision(scriptID),
               let failedIndex = indexOfUserScript(withId: scriptID),
               userScripts.indices.contains(failedIndex) {
                userScripts[failedIndex].description = "Download failed - tap to retry"
                userScripts[failedIndex].version = "Error"
                await persistUserScriptsNow()
            }
            logger.error("❌ Failed to download \(scriptName): \(error)")
        }
    }

    private func saveUserScripts() {
        Task { @MainActor in
            await persistUserScriptsNow()
        }
    }

    /// Persists the current in-memory userscripts and waits for completion. Use this in async flows
    /// where the caller needs stronger ordering guarantees.
    @MainActor
    private func persistUserScriptsNow(
        invalidateExecutionCache: Bool = true,
        explicitEnabledStates: [UUID: Bool] = [:],
        authoritative: Bool = false
    ) async {
        logger.info("💾 Saving \(self.userScripts.count) userscripts to ProtobufDataManager")
        if authoritative {
            await dataManager.replaceUserScripts(userScripts)
        } else {
            await dataManager.updateUserScripts(
                userScripts,
                explicitEnabledStates: explicitEnabledStates
            )
        }
        if invalidateExecutionCache {
            Self.invalidateDocumentStartExecutionCache()
        }
        logger.info(
            "💾 Successfully saved \(self.userScripts.count) userscripts to ProtobufDataManager")
    }

    private func readUserScriptContent(_ userScript: UserScript) -> String? {
        Self.readUserScriptContentOffMain(userScript)
    }

    private func writeUserScriptContent(_ userScript: UserScript) -> Bool {
        var success = false
        let fileName = "\(userScript.id.uuidString).user.js"
        [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.forEach {
            dirURL in
            let fileURL = dirURL.appendingPathComponent(fileName)
            do {
                try userScript.content.write(to: fileURL, atomically: true, encoding: .utf8)
                success = true
                logger.info("💾 Wrote userscript to: \(fileURL.path)")
            } catch {
                logger.error("❌ Failed to write script to \(fileURL.path): \(error)")
            }
        }
        return success
    }

    private func writeUserScriptFiles(_ userScript: UserScript) -> Bool {
        let metadata = userScript.isUserStyle
            ? UserStyleSupport.parsed(
                from: userScript.content, compiledBody: nil, compileSource: false
            )
            : nil
        let needsArtifact = metadata.map {
            UserStylePreprocessorService.requiresCompilation($0.preprocessor)
        } ?? false

        // Write derived output first. If the later source write fails, its digest no
        // longer matches and hydration safely rejects the sidecar. The reverse order
        // could expose new source without the artifact runtime requires.
        if needsArtifact {
            guard let metadata, let body = userScript.compiledStyleBody,
                  let revision = UserStylePreprocessorService.compilerRevision(
                      for: metadata.preprocessor
                  )
            else { return false }
            let request = UserStyleSupport.compilationRequest(
                for: userScript.content, preprocessor: metadata.preprocessor,
                variables: metadata.variables
            )
            let artifact = UserStyleCompiledArtifact(
                request: request, compilerRevision: revision, body: body
            )
            guard UserStylePreprocessorService.validate(artifact, for: request),
                  Self.writeCompiledStyleArtifact(artifact, scriptID: userScript.id)
            else { return false }
        }

        let contentSaved = writeUserScriptContent(userScript)
        let resourcesSaved = writeUserScriptResources(userScript)
        guard contentSaved && resourcesSaved else { return false }
        if !needsArtifact {
            Self.removeCompiledStyleArtifact(scriptID: userScript.id)
        }
        return true
    }

    private func validatedDownloadedUserScriptContent(
        _ content: String,
        replacing existing: UserScript
    ) async throws -> UserScript {
        var downloaded = existing
        downloaded.replaceContentAndParseMetadata(content)

        if existing.isUserStyle {
            guard UserStyleSupport.isUserStyleContent(content), downloaded.isUserStyle else {
                throw UserScriptImportError.missingMetadata
            }
        }

        if let sourceURL = existing.url,
           UserStyleSupport.expectedPreprocessor(for: sourceURL) != nil,
           !UserStyleSupport.isUserStyleContent(content) {
            throw UserScriptImportError.missingMetadata
        }

        if downloaded.isUserStyle {
            let style = await Task.detached(priority: .userInitiated) {
                UserStyleSupport.parsed(from: content)
            }.value
            guard let style else {
                throw UserScriptImportError.missingMetadata
            }
            if let expected = existing.url.flatMap(UserStyleSupport.expectedPreprocessor(for:)),
               UserStylePreprocessorService.normalize(style.preprocessor) != expected {
                throw UserScriptImportError.stylePreprocessorMismatch(expected: expected, declared: style.preprocessor)
            }
            if !style.isPreprocessorSupported {
                throw UserScriptImportError.unsupportedStylePreprocessor(style.preprocessor)
            }
            guard style.isCompiled else {
                throw UserScriptImportError.styleCompilationFailed(
                    style.compilationError ?? UserScriptImportError.fallbackCompilerError)
            }
            downloaded.compiledStyleBody = style.compiledArtifact?.body
        }

        return downloaded
    }

    private func updatedUserScript(
        _ existing: UserScript,
        from parsed: UserScript,
        content: String,
        resources: [String: String]
    ) -> UserScript {
        var updated = parsed
        updated.name = existing.name
        updated.url = existing.url
        updated.isEnabled = existing.isEnabled
        updated.isLocal = existing.isLocal
        updated.updatesAutomatically = existing.updatesAutomatically
        updated.category = existing.category
        updated.content = content
        updated.resourceContents = resources
        updated.lastUpdated = Date()
        return updated
    }

    public func hasDownloadedContent(for userScript: UserScript) -> Bool {
        userScript.isDownloaded || userScriptFileExists(userScript)
    }

    private func userScriptFileExists(_ userScript: UserScript) -> Bool {
        let fileName = "\(userScript.id.uuidString).user.js"
        return [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.contains {
            dirURL in
            let filePath = dirURL.appendingPathComponent(fileName).path
            return FileManager.default.fileExists(atPath: filePath)
        }
    }

    nonisolated private static func hasMetadataBlock(in content: String) -> Bool {
        if UserScript.detectsUserStyle(in: content) { return true }

        let lines = content.split(whereSeparator: \.isNewline)
        var sawStart = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !sawStart {
                if trimmed == "// ==UserScript==" { sawStart = true }
            } else {
                if trimmed == "// ==/UserScript==" { return true }
            }
        }

        return false
    }

    nonisolated private static func baseName(for fileURL: URL) -> String {
        UserScriptURLSupport.displayName(forFilename: fileURL.lastPathComponent)
    }

    private func backupCopy(of script: UserScript, id: UUID) -> UserScript {
        var copy = UserScript(id: id, name: script.name, url: script.url, content: script.content)
        copy.isEnabled = script.isEnabled
        copy.description = script.description
        copy.version = script.version
        copy.matches = script.matches
        copy.excludeMatches = script.excludeMatches
        copy.includes = script.includes
        copy.excludes = script.excludes
        copy.runAt = script.runAt
        copy.injectInto = script.injectInto
        copy.grant = script.grant
        copy.require = script.require
        copy.resource = script.resource
        copy.resourceContents = script.resourceContents
        copy.noframes = script.noframes
        copy.isLocal = script.isLocal || script.url == nil || script.url?.isFileURL == true
        copy.updateURL = copy.isLocal ? nil : script.updateURL
        copy.downloadURL = copy.isLocal ? nil : script.downloadURL
        copy.lastUpdated = script.lastUpdated
        copy.isUserStyle = script.isUserStyle
        copy.updatesAutomatically = script.updatesAutomatically
        copy.category = script.category
        copy.localImportIdentity = UserScriptImportIdentity.normalized(script.localImportIdentity)
        return copy
    }

    public func userScriptsForBackup() async -> [UserScript] {
        await waitUntilReady()
        return await hydrateUserScriptsFromDisk(userScripts, includeResources: true)
    }

    public func restoreUserScriptsFromBackup(_ restoredScripts: [UserScript]) async {
        await waitUntilReady()
        guard !restoredScripts.isEmpty else { return }

        var mergedScripts = userScripts

        for restoredScript in restoredScripts {
            let existingIndex = UserScriptRestoreMatcher.matchingIndex(
                for: restoredScript,
                in: mergedScripts
            )
            let targetID = existingIndex.map { mergedScripts[$0].id } ?? restoredScript.id
            let scriptToRestore = backupCopy(of: restoredScript, id: targetID)

            if let existingIndex {
                mergedScripts[existingIndex] = scriptToRestore
            } else {
                mergedScripts.append(scriptToRestore)
            }

            _ = writeUserScriptFiles(scriptToRestore)
            NotificationCenter.default.post(
                name: .userScriptManagerDidUpsertUserScript,
                object: self,
                userInfo: userScriptNotificationInfo(for: scriptToRestore)
            )
        }

        userScripts = mergedScripts
        await persistUserScriptsNow(authoritative: true)
        // Flush the restored scripts to disk right away instead of relying on the
        // debounced save. The steps that run next (setUserScriptDisabledHosts) and
        // cross-process reloads use atomic read-modify-writes that read from disk; if
        // the restored scripts are still only in memory when those run, they observe
        // the stale pre-restore state and clobber the restore, leaving the userscript
        // section empty. (#485)
        _ = await dataManager.saveDataImmediately()
    }

    // MARK: - Public Methods

    @discardableResult
    public func addUserScript(
        from url: URL,
        origin: UserScriptMutationOrigin = .local
    ) async -> Error? {
        isLoading = true
        statusDescription = UserStyleSupport.isUserStyleURL(url)
            ? "Downloading userstyle..." : "Downloading userscript..."
        hasError = false

        do {
            let content = try await downloadUserScriptContent(from: url)

            var newUserScript = UserScript(
                name: UserScriptURLSupport.displayName(forRemoteURL: url),
                url: url, content: content)
            newUserScript.parseMetadata()

            // A .css URL must actually carry a UserStyle metadata block; otherwise the
            // content would be misclassified as a userscript and injected as JS.
            if UserStyleSupport.isUserStyleURL(url), !newUserScript.isUserStyle {
                hasError = true
                errorMessage = UserScriptImportError.missingMetadata.errorDescription ?? ""
                statusDescription = "Download failed"
                isLoading = false
                return UserScriptImportError.missingMetadata
            }
            let downloadedStyle = await Task.detached(priority: .userInitiated) {
                UserStyleSupport.parsed(from: newUserScript.content)
            }.value
            if newUserScript.isUserStyle,
               let style = downloadedStyle {
                if let expected = UserStyleSupport.expectedPreprocessor(for: url),
                   UserStylePreprocessorService.normalize(style.preprocessor) != expected {
                    let mismatch = UserScriptImportError.stylePreprocessorMismatch(expected: expected, declared: style.preprocessor)
                    hasError = true
                    errorMessage = mismatch.errorDescription ?? ""
                    statusDescription = "Download failed"
                    isLoading = false
                    return mismatch
                }
                newUserScript.compiledStyleBody = style.compiledArtifact?.body
                if !style.isPreprocessorSupported {
                    hasError = true
                    errorMessage = UserScriptImportError.unsupportedStylePreprocessor(style.preprocessor).errorDescription ?? ""
                    statusDescription = "Download failed"
                    isLoading = false
                    return UserScriptImportError.unsupportedStylePreprocessor(style.preprocessor)
                }
                if !style.isCompiled {
                    hasError = true
                    errorMessage = UserScriptImportError.styleCompilationFailed(style.compilationError ?? UserScriptImportError.fallbackCompilerError).errorDescription ?? ""
                    statusDescription = "Download failed"
                    isLoading = false
                    return UserScriptImportError.styleCompilationFailed(style.compilationError ?? UserScriptImportError.fallbackCompilerError)
                }
            }
            newUserScript.isEnabled = true
            newUserScript.isLocal = false
            newUserScript.lastUpdated = Date()

            // Process @require directives and @resource directives
            let dependencies = await processedDependencies(for: newUserScript)
            let processedContent = dependencies.content
            let resourceContents = dependencies.resources
            newUserScript.content = processedContent
            newUserScript.resourceContents = resourceContents

            // Check if script already exists
            if let existingIndex = userScripts.firstIndex(where: { $0.url == url }) {
                newUserScript.updatesAutomatically = userScripts[existingIndex].updatesAutomatically
                userScripts[existingIndex] = newUserScript
                if origin == .local { recordScriptMutation(newUserScript.id) }
                statusDescription = "Updated \(newUserScript.isUserStyle ? "userstyle" : "userscript"): \(newUserScript.name)"
            } else {
                userScripts.append(newUserScript)
                if origin == .local { recordLocalMutation() }
                statusDescription = "Added \(newUserScript.isUserStyle ? "userstyle" : "userscript"): \(newUserScript.name)"
            }

            _ = writeUserScriptFiles(newUserScript)

            NotificationCenter.default.post(
                name: .userScriptManagerDidUpsertUserScript,
                object: self,
                userInfo: userScriptNotificationInfo(for: newUserScript)
            )

            // Check for duplicates after adding a script
            checkForDuplicatesAndAskForConfirmation()

            await persistUserScriptsNow()
            isLoading = false
            return nil
        } catch {
            hasError = true
            errorMessage = "Failed to download userscript: \(error.localizedDescription)"
            statusDescription = "Download failed"
            isLoading = false
            return error
        }
    }

    nonisolated public static func stageUserScriptImport(fromLocalFile fileURL: URL) throws -> UserScript {
        let filename = fileURL.lastPathComponent
        let lowercased = filename.lowercased()
        let isSupportedType = lowercased.hasSuffix(".user.js") || lowercased.hasSuffix(".js")
            || lowercased.hasSuffix(".user.css") || lowercased.hasSuffix(".css")
            || lowercased.hasSuffix(".less") || lowercased.hasSuffix(".sass")
            || lowercased.hasSuffix(".scss") || lowercased.hasSuffix(".styl")
            || lowercased.hasSuffix(".pcss")
        guard isSupportedType else { throw UserScriptImportError.unsupportedType }

        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= UserScriptImportLimits.maximumSourceFileBytes else {
            throw UserScriptImportError.fileTooLarge
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw UserScriptImportError.unreadableFile
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw UserScriptImportError.unreadableFile
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { throw UserScriptImportError.emptyContent }
        guard Self.hasMetadataBlock(in: content) else { throw UserScriptImportError.missingMetadata }

        var staged = UserScript(name: Self.baseName(for: fileURL), content: content)
        staged.parseMetadata()
        let expectedPreprocessor = UserStyleSupport.expectedPreprocessor(forPath: filename)
        guard !UserStyleSupport.isUserStylePath(filename)
                || UserStyleSupport.isUserStyleContent(content)
        else {
            throw UserScriptImportError.missingMetadata
        }
        if let expectedPreprocessor {
            guard let classifiedStyle = UserStyleSupport.parsed(from: content) else {
                throw UserScriptImportError.missingMetadata
            }
            if UserStylePreprocessorService.normalize(classifiedStyle.preprocessor) != expectedPreprocessor {
                throw UserScriptImportError.stylePreprocessorMismatch(expected: expectedPreprocessor, declared: classifiedStyle.preprocessor)
            }
        }
        if staged.isUserStyle,
           let style = UserStyleSupport.parsed(from: content) {
            guard style.isPreprocessorSupported else {
                throw UserScriptImportError.unsupportedStylePreprocessor(style.preprocessor)
            }
            guard style.isCompiled else {
                throw UserScriptImportError.styleCompilationFailed(style.compilationError ?? UserScriptImportError.fallbackCompilerError)
            }
            staged.compiledStyleBody = style.compiledArtifact?.body
        }
        if staged.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            staged.name = Self.baseName(for: fileURL)
        }
        // Metadata is retained in the source for display, but local imports can
        // never use its remote update endpoints.
        staged.updateURL = nil
        staged.downloadURL = nil
        staged.isEnabled = true
        staged.isLocal = true
        staged.localImportIdentity = UserScriptImportIdentity.forFileURL(fileURL)
        return staged
    }

    public func stageUserScriptImport(fromLocalFile fileURL: URL) async throws -> UserScript {
        try await Task.detached(priority: .userInitiated) {
            try Self.stageUserScriptImport(fromLocalFile: fileURL)
        }.value
    }

    public func addUserScript(
        fromStagedImport staged: UserScript,
        nameOverride: String,
        descriptionOverride: String,
        category: FilterListCategory,
        origin: UserScriptMutationOrigin = .local
    ) async -> Error? {
        isLoading = true
        statusDescription = staged.isUserStyle ? "Importing userstyle..." : "Importing userscript..."
        hasError = false

        do {
            _ = try await importLocalUserScript(
                content: staged.content,
                fallbackName: staged.name,
                importedStatusVerb: "Imported",
                replacedStatusVerb: "Replaced",
                nameOverride: nameOverride,
                descriptionOverride: descriptionOverride,
                categoryOverride: category,
                localImportIdentity: staged.localImportIdentity,
                origin: origin
            )
            isLoading = false
            return nil
        } catch {
            hasError = true
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusDescription = "Import failed"
            isLoading = false
            return error
        }
    }

    public func addUserScript(
        fromLocalFile fileURL: URL,
        nameOverride: String? = nil,
        descriptionOverride: String? = nil,
        category: FilterListCategory? = nil,
        origin: UserScriptMutationOrigin = .local
    ) async -> Error? {
        isLoading = true
        statusDescription = UserStyleSupport.isUserStylePath(fileURL.lastPathComponent)
            ? "Importing userstyle..." : "Importing userscript..."
        hasError = false

        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let staged = try await stageUserScriptImport(fromLocalFile: fileURL)

            _ = try await importLocalUserScript(
                content: staged.content,
                fallbackName: staged.name,
                importedStatusVerb: "Imported",
                replacedStatusVerb: "Replaced",
                nameOverride: nameOverride,
                descriptionOverride: descriptionOverride,
                categoryOverride: category,
                localImportIdentity: staged.localImportIdentity,
                origin: origin
            )

            isLoading = false
            return nil
        } catch {
            hasError = true
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusDescription = "Import failed"
            isLoading = false
            return error
        }
    }

    public func addUserScript(
        fromSourceContent content: String,
        nameOverride: String? = nil,
        descriptionOverride: String? = nil,
        category: FilterListCategory? = nil,
        localImportIdentity: String? = nil,
        legacyLocalImportMatching: Bool = false,
        origin: UserScriptMutationOrigin = .local
    ) async -> Error? {
        isLoading = true
        statusDescription = "Adding userscript..."
        hasError = false

        do {
            _ = try await importLocalUserScript(
                content: content,
                fallbackName: "Pasted Userscript",
                importedStatusVerb: "Added",
                replacedStatusVerb: "Updated",
                nameOverride: nameOverride,
                descriptionOverride: descriptionOverride,
                categoryOverride: category,
                localImportIdentity: localImportIdentity ?? UserScriptImportIdentity.forContent(content),
                legacyLocalImportMatching: legacyLocalImportMatching,
                origin: origin
            )

            isLoading = false
            return nil
        } catch {
            hasError = true
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusDescription = "Import failed"
            isLoading = false
            return error
        }
    }

    @discardableResult
    private func importLocalUserScript(
        content rawContent: String,
        fallbackName: String,
        importedStatusVerb: String,
        replacedStatusVerb: String,
        nameOverride: String? = nil,
        descriptionOverride: String? = nil,
        categoryOverride: FilterListCategory? = nil,
        localImportIdentity: String? = nil,
        legacyLocalImportMatching: Bool = false,
        origin: UserScriptMutationOrigin = .local
    ) async throws -> UserScript {
        let trimmedContent = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedContent.isEmpty else {
            throw UserScriptImportError.emptyContent
        }

        guard Self.hasMetadataBlock(in: rawContent) else {
            throw UserScriptImportError.missingMetadata
        }

        var tempScript = UserScript(name: "", content: rawContent)
        tempScript.parseMetadata()

        let importedStyle = await Task.detached(priority: .userInitiated) {
            UserStyleSupport.parsed(from: rawContent)
        }.value
        if tempScript.isUserStyle, let style = importedStyle {
            guard style.isPreprocessorSupported else {
                throw UserScriptImportError.unsupportedStylePreprocessor(style.preprocessor)
            }
            guard style.isCompiled else {
                throw UserScriptImportError.styleCompilationFailed(style.compilationError ?? UserScriptImportError.fallbackCompilerError)
            }
            tempScript.compiledStyleBody = style.compiledArtifact?.body
        }

        let metadataName = tempScript.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let overrideName = nameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let canonicalName = !overrideName.isEmpty
            ? overrideName
            : (!metadataName.isEmpty ? metadataName : (fallbackName.isEmpty ? "Pasted Userscript" : fallbackName))

        let stableIdentity = UserScriptImportIdentity.normalized(localImportIdentity)
            ?? UserScriptImportIdentity.forContent(rawContent)
        let existingIndex = userScripts.firstIndex {
            UserScript.matchesLocalImport(
                existing: $0,
                // A legacy CloudSync entry deliberately has no identity, so it
                // retains the old name-based replacement behavior. Normal local
                // imports pass an explicit file/content identity.
                stableIdentity: legacyLocalImportMatching ? nil : stableIdentity,
                canonicalName: canonicalName
            )
        }

        let scriptID = existingIndex.flatMap { userScripts[$0].id } ?? UUID()
        var newUserScript = UserScript(id: scriptID, name: canonicalName, url: nil, content: rawContent)
        newUserScript.isEnabled = existingIndex.map { userScripts[$0].isEnabled } ?? true
        newUserScript.updatesAutomatically = existingIndex.map { userScripts[$0].updatesAutomatically } ?? true
        newUserScript.isLocal = true
        // A legacy CloudSync update matched by display name must not replace the
        // stable file identity. Otherwise its next delete/backup can target the
        // wrong duplicate and lose the existing per-site state keyed by script ID.
        newUserScript.localImportIdentity = UserScript.localImportIdentityForUpdate(
            existing: existingIndex.map { userScripts[$0] },
            requestedIdentity: stableIdentity,
            preserveExistingIdentity: legacyLocalImportMatching
        ) ?? UserScriptImportIdentity.normalized(stableIdentity)
        newUserScript.lastUpdated = Date()

        newUserScript.description = descriptionOverride ?? tempScript.description
        newUserScript.version = tempScript.version
        newUserScript.matches = tempScript.matches
        newUserScript.excludeMatches = tempScript.excludeMatches
        newUserScript.includes = tempScript.includes
        newUserScript.excludes = tempScript.excludes
        newUserScript.runAt = tempScript.runAt
        newUserScript.injectInto = tempScript.injectInto
        newUserScript.grant = tempScript.grant
        newUserScript.require = tempScript.require
        newUserScript.resource = tempScript.resource
        newUserScript.resourceContents = tempScript.resourceContents
        newUserScript.noframes = tempScript.noframes
        // Local imports retain the source metadata in content, but never retain
        // remote endpoints that an updater could fetch.
        newUserScript.updateURL = nil
        newUserScript.downloadURL = nil
        newUserScript.isUserStyle = tempScript.isUserStyle
        newUserScript.category = categoryOverride ?? existingIndex.map { userScripts[$0].category } ?? .scripts

        let dependencies = await processedDependencies(for: newUserScript)
        let processedContent = dependencies.content
        let resourceContents = dependencies.resources
        newUserScript.replaceContentAndParseMetadata(processedContent, compiledBody: tempScript.compiledStyleBody)
        newUserScript.resourceContents = resourceContents

        // Disk and sidecar writes must succeed before any observable mutation.
        guard writeUserScriptFiles(newUserScript) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if let existingIndex {
            userScripts[existingIndex] = newUserScript
            if origin == .local { recordScriptMutation(newUserScript.id) }
            statusDescription = "\(replacedStatusVerb) \(newUserScript.isUserStyle ? "userstyle" : "userscript"): \(newUserScript.name)"
        } else {
            userScripts.append(newUserScript)
            if origin == .local { recordLocalMutation() }
            statusDescription = "\(importedStatusVerb) \(newUserScript.isUserStyle ? "userstyle" : "userscript"): \(newUserScript.name)"
        }

        NotificationCenter.default.post(
            name: .userScriptManagerDidImportLocalUserScript,
            object: self,
            userInfo: [UserScriptManagerNotificationKey.name: newUserScript.name]
        )
        NotificationCenter.default.post(
            name: .userScriptManagerDidUpsertUserScript,
            object: self,
            userInfo: userScriptNotificationInfo(for: newUserScript)
        )

        checkForDuplicatesAndAskForConfirmation()
        await persistUserScriptsNow()
        return newUserScript
    }

    public func toggleUserScript(_ userScript: UserScript) async {
        guard let state = userScriptToggleState(for: userScript.id) else { return }
        await setUserScript(userScript, isEnabled: !state.desired)
    }

    /// Sets the enabled state for a userscript explicitly (idempotent).
    /// The intent is recorded before any download so a newer intent can cancel it.
    public func setUserScript(
        _ userScript: UserScript,
        isEnabled: Bool,
        origin: UserScriptMutationOrigin = .local
    ) async {
        guard self.userScript(withId: userScript.id) != nil else { return }
        let revision = beginUserScriptIntent(
            for: userScript.id,
            desired: isEnabled,
            origin: origin
        )

        guard let current = self.userScript(withId: userScript.id) else {
            finishUserScriptIntent(userScript.id, revision: revision)
            return
        }
        if current.isEnabled == isEnabled {
            // Even an idempotent request invalidates an older suspended enable.
            finishUserScriptIntent(userScript.id, revision: revision)
            return
        }

        if isEnabled {
            let isReady = await ensureScriptReadyForEnabling(scriptID: userScript.id, origin: origin)
            guard isCurrentUserScriptIntent(userScript.id, revision: revision) else { return }
            guard isReady else {
                finishUserScriptIntent(userScript.id, revision: revision)
                hasError = true
                errorMessage = "Failed to download \(userScript.name). Please try again."
                statusDescription = "Download failed"
                return
            }
        }

        guard isCurrentUserScriptIntent(userScript.id, revision: revision),
              let index = indexOfUserScript(withId: userScript.id),
              userScripts.indices.contains(index)
        else { return }

        userScripts[index].isEnabled = isEnabled
        statusDescription = isEnabled ? "Enabled \(userScript.name)" : "Disabled \(userScript.name)"
        logger.info("💾 Persisting userscript setEnabled for \(userScript.name): \(isEnabled)")
        await persistUserScriptsNow(
            explicitEnabledStates: [userScript.id: isEnabled]
        )
        guard isCurrentUserScriptIntent(userScript.id, revision: revision) else {
            // A newer toggle may have completed while persistence was reading shared state.
            // Rewrite the live array so the older completion cannot become the disk winner.
            await persistUserScriptsNow(
                explicitEnabledStates: pendingUserScriptIntents.reduce(into: [:]) { result, entry in
                    result[entry.key] = entry.value
                }
            )
            return
        }
        finishUserScriptIntent(userScript.id, revision: revision)
        logger.info("💾 Userscripts saved after setEnabled")
    }

    /// Sets the userscript category used for local organization and sync.
    public func setUserScript(
        _ userScript: UserScript,
        category: FilterListCategory,
        origin: UserScriptMutationOrigin = .local
    ) async {
        guard let index = userScripts.firstIndex(where: { $0.id == userScript.id }) else { return }
        guard userScripts[index].category != category else { return }

        userScripts[index].category = category
        if origin == .local { recordScriptMutation(userScript.id) }
        await persistUserScriptsNow(invalidateExecutionCache: false)
    }

    /// Sets whether bulk and scheduled updates should include this userscript.
    public func setUserScript(
        _ userScript: UserScript,
        updatesAutomatically: Bool,
        origin: UserScriptMutationOrigin = .local
    ) async {
        guard let index = userScripts.firstIndex(where: { $0.id == userScript.id }) else { return }
        guard userScripts[index].updatesAutomatically != updatesAutomatically else { return }

        userScripts[index].updatesAutomatically = updatesAutomatically
        if origin == .local { recordScriptMutation(userScript.id) }
        statusDescription = updatesAutomatically
            ? "Automatic updates enabled for \(userScript.name)"
            : "Automatic updates paused for \(userScript.name)"
        logger.info("💾 Persisting userscript update preference for \(userScript.name): \(updatesAutomatically)")
        await persistUserScriptsNow(invalidateExecutionCache: false)
        logger.info("💾 Userscripts saved after update preference change")
    }

    private func ensureScriptReadyForEnabling(
        scriptID: UUID,
        origin: UserScriptMutationOrigin = .local
    ) async -> Bool {
        guard let index = indexOfUserScript(withId: scriptID),
              userScripts.indices.contains(index)
        else { return false }
        let script = userScripts[index]
        guard !script.isLocal else { return !script.content.isEmpty }
        guard script.content.isEmpty else { return true }

        if let diskContent = readUserScriptContent(script), !diskContent.isEmpty {
            userScripts[index].replaceContentAndParseMetadata(diskContent)
            if let resources = readUserScriptResources(script) {
                userScripts[index].resourceContents = resources
            }
            return true
        }

        guard let url = script.url else { return false }
        await downloadUserScriptInBackground(for: scriptID, from: url, origin: origin)

        guard let currentIndex = indexOfUserScript(withId: scriptID),
              userScripts.indices.contains(currentIndex)
        else { return false }
        return userScripts[currentIndex].isDownloaded
    }

    /// Batch apply enabled state using a set of IDs (single persistence write).
    /// Each script gets its own revision so a newer explicit toggle wins.
    public func setEnabledScripts(withIDs enabledIDs: Set<UUID>) async {
        var failedRemoteEnables = Set<String>()
        var batchRevisions: [UUID: UInt64] = [:]
        for script in userScripts {
            batchRevisions[script.id] = beginUserScriptIntent(
                for: script.id,
                desired: enabledIDs.contains(script.id),
                origin: .local
            )
        }

        // Ensure any scripts being enabled have content available. Keep IDs rather than
        // indices because downloads suspend and the array may be synchronized meanwhile.
        let remoteScriptIDsToDownload = userScripts.compactMap { script -> (UUID, URL)? in
            guard enabledIDs.contains(script.id),
                  !script.isLocal,
                  script.content.isEmpty,
                  let url = script.url
            else { return nil }
            return (script.id, url)
        }

        for (scriptID, url) in remoteScriptIDsToDownload {
            guard let revision = batchRevisions[scriptID],
                  isCurrentUserScriptIntent(scriptID, revision: revision)
            else { continue }

            if let index = indexOfUserScript(withId: scriptID),
               userScripts.indices.contains(index),
               let diskContent = readUserScriptContent(userScripts[index]),
               !diskContent.isEmpty
            {
                userScripts[index].replaceContentAndParseMetadata(diskContent)
                if let resources = readUserScriptResources(userScripts[index]) {
                    userScripts[index].resourceContents = resources
                }
                continue
            }

            await downloadUserScriptInBackground(for: scriptID, from: url)

            guard isCurrentUserScriptIntent(scriptID, revision: revision),
                  let currentIndex = indexOfUserScript(withId: scriptID),
                  userScripts.indices.contains(currentIndex)
            else { continue }

            if !userScripts[currentIndex].isDownloaded {
                failedRemoteEnables.insert(userScripts[currentIndex].name)
            }
        }

        var changed = false
        for i in userScripts.indices {
            guard let revision = batchRevisions[userScripts[i].id],
                  isCurrentUserScriptIntent(userScripts[i].id, revision: revision)
            else { continue }

            let requestedEnable = enabledIDs.contains(userScripts[i].id)
            let canEnable = userScripts[i].isLocal || userScripts[i].isDownloaded
            let shouldEnable = requestedEnable && canEnable

            if requestedEnable && !canEnable && !userScripts[i].isLocal {
                failedRemoteEnables.insert(userScripts[i].name)
            }

            if userScripts[i].isEnabled != shouldEnable {
                userScripts[i].isEnabled = shouldEnable
                changed = true
            }
        }

        if changed {
            logger.info("💾 Persisting batch userscript enable states for \(enabledIDs.count) scripts")
            await persistUserScriptsNow(
                explicitEnabledStates: Dictionary(
                    uniqueKeysWithValues: batchRevisions.keys.compactMap { id in
                        enabledIDs.contains(id) ? (id, true) : (id, false)
                    }
                )
            )
            logger.info("💾 Userscripts saved after batch setEnabled")
        } else {
            logger.info("ℹ️ No userscript enable state changes to persist (batch)")
        }

        let batchWasSuperseded = batchRevisions.contains { scriptID, revision in
            !isCurrentUserScriptIntent(scriptID, revision: revision)
        }
        for (scriptID, revision) in batchRevisions {
            finishUserScriptIntent(scriptID, revision: revision)
        }
        if batchWasSuperseded {
            // A newer per-script toggle won while the batch save was suspended. Persist the
            // current array once more so the stale batch cannot win on disk.
            await persistUserScriptsNow(
                explicitEnabledStates: pendingUserScriptIntents.reduce(into: [:]) { result, entry in
                    result[entry.key] = entry.value
                }
            )
        }

        if !failedRemoteEnables.isEmpty {
            let names = failedRemoteEnables.sorted()
            let preview = names.prefix(3).joined(separator: ", ")
            let remainingCount = names.count - min(names.count, 3)
            let suffix = remainingCount > 0 ? " (+\(remainingCount) more)" : ""
            hasError = true
            errorMessage =
                "Could not enable some userscripts because they failed to download: \(preview)\(suffix)."
            statusDescription = "Some userscripts could not be enabled"
            logger.error(
                "❌ Failed to enable remote userscripts due to missing content: \(names.joined(separator: ", "))")
        }
    }

    public func removeUserScript(
        _ userScript: UserScript,
        origin: UserScriptMutationOrigin = .local
    ) async {
        if isDefaultUserScript(userScript) {
            statusDescription = "Default userscripts can't be removed"
            logger.info("🛑 Prevented removal of default userscript: '\(userScript.name)'")
            return
        }

        if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
            let removedScript = userScripts[index]

            // Remove from memory first so no later save snapshots include this ID.
            userScripts.remove(at: index)
            if origin == .local { recordScriptMutation(removedScript.id) }

            // Persist the exact deletion before touching sidecar files or returning. Any
            // stale in-flight upsert is ignored by its ID-based merge, and suspension
            // cannot leave an executable record on disk.
            await dataManager.removeUserScript(withId: removedScript.id)
            removeUserScriptFile(removedScript)

            if removedScript.isLocal {
                NotificationCenter.default.post(
                    name: .userScriptManagerDidRemoveLocalUserScript,
                    object: self,
                    userInfo: [UserScriptManagerNotificationKey.name: removedScript.name]
                )
            }
            NotificationCenter.default.post(
                name: .userScriptManagerDidRemoveUserScript,
                object: self,
                userInfo: userScriptNotificationInfo(for: removedScript)
            )

            statusDescription = "Removed \(removedScript.name)"

            logger.info("🗑️ Removed userscript: '\(removedScript.name)'")
        }
    }

    /// Downloads a userscript (and its dependencies) without changing the enabled state.
    @discardableResult
    public func downloadUserScript(_ userScript: UserScript) async -> Bool {
        guard let index = userScripts.firstIndex(where: { $0.id == userScript.id }) else { return false }
        guard !userScripts[index].isLocal else { return true }
        guard userScripts[index].content.isEmpty else { return true }
        guard let url = userScripts[index].url else { return false }

        let scriptID = userScript.id
        let scriptName = userScripts[index].name
        isLoading = true
        statusDescription = "Downloading \(scriptName)..."
        await downloadUserScriptInBackground(for: scriptID, from: url)
        isLoading = false

        guard let currentIndex = indexOfUserScript(withId: scriptID),
              userScripts.indices.contains(currentIndex)
        else {
            statusDescription = "Download failed"
            return false
        }

        if userScripts[currentIndex].isDownloaded {
            statusDescription = "Downloaded \(userScripts[currentIndex].name)"
            return true
        }

        statusDescription = "Download failed"
        return false
    }

    public func updateUserScript(_ userScript: UserScript) async {
        guard let index = userScripts.firstIndex(where: { $0.id == userScript.id }),
              !userScripts[index].isLocal,
              let url = userScripts[index].url,
              url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"
        else { return }

        let mutationRevision = scriptMutationRevision(userScript.id)
        await MainActor.run {
            isLoading = true
            statusDescription = "Updating \(userScript.name)..."
        }

        do {
            let content = try await downloadUserScriptContent(from: url)

            guard mutationRevision == scriptMutationRevision(userScript.id),
                  let current = userScripts.first(where: { $0.id == userScript.id }) else {
                isLoading = false
                return
            }
            let tempUserScript = try await validatedDownloadedUserScriptContent(
                content,
                replacing: current
            )

            // Process @require directives and @resource directives
            let dependencies = await processedDependencies(for: tempUserScript)
            let processedContent = dependencies.content
            let resourceContents = dependencies.resources

            guard mutationRevision == scriptMutationRevision(userScript.id),
                  let index = userScripts.firstIndex(where: { $0.id == userScript.id }) else {
                isLoading = false
                return
            }
            let updated = updatedUserScript(
                userScripts[index],
                from: tempUserScript,
                content: processedContent,
                resources: resourceContents
            )
            guard writeUserScriptFiles(updated) else {
                throw CocoaError(.fileWriteUnknown)
            }
            userScripts[index] = updated
            recordScriptMutation(userScript.id)
            await persistUserScriptsNow()
            statusDescription = "Updated \(userScript.name)"
            updateAlertMessage = "\(userScript.name) has been successfully updated."
            showingUpdateSuccessAlert = true
            isLoading = false
        } catch {
            await MainActor.run {
                hasError = true
                errorMessage = "Failed to update userscript: \(error.localizedDescription)"
                statusDescription = "Update failed"
                updateAlertMessage =
                    "Failed to update \(userScript.name): \(error.localizedDescription)"
                showingUpdateErrorAlert = true
                isLoading = false
            }
        }
    }


    nonisolated private static func expectedPreprocessor(for userScript: UserScript) -> String? {
        if let url = userScript.url,
           let expected = UserStyleSupport.expectedPreprocessor(for: url)
        {
            return expected
        }
        guard let identity = userScript.localImportIdentity,
              identity.hasPrefix("file:")
        else { return nil }
        return UserStyleSupport.expectedPreprocessor(
            forPath: String(identity.dropFirst("file:".count))
        )
    }

    public func saveEditedContent(for scriptId: UUID, newContent: String) async -> String? {
        guard let index = indexOfUserScript(withId: scriptId) else { return nil }
        let existing = userScripts[index]
        var candidate = existing
        candidate.replaceContentAndParseMetadata(newContent)
        if existing.isUserStyle && !candidate.isUserStyle {
            return UserScriptImportError.missingMetadata.errorDescription
        }
        if candidate.isUserStyle,
           let metadata = UserStyleSupport.parsed(
               from: newContent, compiledBody: nil, compileSource: false
           ),
           let expected = Self.expectedPreprocessor(for: existing),
           UserStylePreprocessorService.normalize(metadata.preprocessor) != expected
        {
            return UserScriptImportError.stylePreprocessorMismatch(
                expected: expected, declared: metadata.preprocessor
            ).errorDescription
        }
        let editedStyle = await Task.detached(priority: .userInitiated) {
            UserStyleSupport.parsed(from: newContent)
        }.value
        if candidate.isUserStyle,
           let style = editedStyle
        {
            if !style.isPreprocessorSupported {
                return UserScriptImportError.unsupportedStylePreprocessor(style.preprocessor).errorDescription
            }
            if !style.isCompiled {
                return UserScriptImportError.styleCompilationFailed(style.compilationError ?? UserScriptImportError.fallbackCompilerError).errorDescription
            }
            candidate.compiledStyleBody = style.compiledArtifact?.body
        }
        candidate.lastUpdated = Date()
        guard writeUserScriptFiles(candidate) else {
            return String(localized: "Couldn't save the edited source.", comment: "Userstyle editor save error")
        }
        userScripts[index] = candidate
        recordScriptMutation(candidate.id)
        await persistUserScriptsNow()
        logger.info("Saved edited content for \(self.userScripts[index].name)")
        return nil
    }

    /// Persists display metadata overrides for an editable local import.
    @discardableResult
    public func setUserScriptMetadataOverrides(
        for scriptId: UUID,
        name: String,
        description: String,
        origin: UserScriptMutationOrigin = .local
    ) async -> Bool {
        guard let index = indexOfUserScript(withId: scriptId), userScripts[index].isLocal else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        userScripts[index].name = trimmedName
        userScripts[index].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if origin == .local { recordScriptMutation(userScripts[index].id) }
        await persistUserScriptsNow(invalidateExecutionCache: false)
        return true
    }

    public struct AutoUpdateResult: Sendable {
        public let updated: Int
        public let failed: Int

        public init(updated: Int, failed: Int) {
            self.updated = updated
            self.failed = failed
        }
    }

    /// Resolves the lightweight metadata URL for a userscript.
    /// Priority: @updateURL > .user.js -> .meta.js derivation > nil (skip meta check).
    private func resolveMetaURL(for script: UserScript) -> URL? {
        guard !script.isLocal else { return nil }
        if let updateURLString = script.updateURL, let url = URL(string: updateURLString) {
            return url
        }
        guard let scriptURL = script.url else { return nil }
        let urlString = scriptURL.absoluteString
        guard urlString.hasSuffix(".user.js") else { return nil }
        let metaString = String(urlString.dropLast(8)) + ".meta.js"
        return URL(string: metaString)
    }

    /// Resolves the full script download URL.
    /// Priority: @downloadURL > script.url.
    private func resolveDownloadURL(for script: UserScript) -> URL? {
        guard !script.isLocal else { return nil }
        if let downloadURLString = script.downloadURL, let url = URL(string: downloadURLString) {
            return url
        }
        return script.url
    }

    /// Fetches a URL and parses @version from the metadata block.
    /// Returns nil if fetch fails, content is empty, or no version found.
    private func fetchRemoteVersion(from url: URL) async -> String? {
        do {
            let content = try await downloadUserScriptContent(from: url)
            var temp = UserScript(name: "", content: content)
            temp.parseMetadata()
            return temp.version.isEmpty ? nil : temp.version
        } catch {
            return nil
        }
    }

    /// Auto-updates enabled remote userscripts using a two-phase flow:
    /// first check .meta.js for version changes, then download full script only if needed.
    public func autoUpdateEnabledUserScripts() async -> AutoUpdateResult {
        await waitUntilReady()

        let candidates = userScripts.filter { script in
            guard script.isEnabled && !script.isLocal && script.url != nil && script.updatesAutomatically else {
                return false
            }
            return true
        }

        guard !candidates.isEmpty else { return AutoUpdateResult(updated: 0, failed: 0) }

        var updatedCount = 0
        var failedCount = 0
        var didChange = false

        for candidate in candidates {
            do {
                let updated = try await updateSingleScript(candidate)
                if updated {
                    updatedCount += 1
                    didChange = true
                }
            } catch {
                failedCount += 1
                logger.error("❌ Auto-update userscript failed: \(candidate.name) – \(error.localizedDescription)")
            }
        }

        if didChange {
            await persistUserScriptsNow()
        }

        if updatedCount > 0 {
            logger.info("✅ Auto-updated \(updatedCount) userscripts (\(failedCount) failed)")
        }

        return AutoUpdateResult(updated: updatedCount, failed: failedCount)
    }

    /// Two-phase update for a single script.
    /// Phase 1: fetch meta URL, compare @version. If newer, proceed to phase 2.
    /// Phase 2: download full script, process directives, write if content changed.
    /// Falls back to full download + content comparison if meta check is inconclusive.
    private func updateSingleScript(_ candidate: UserScript) async throws -> Bool {
        guard !candidate.isLocal,
              userScripts.contains(where: { $0.id == candidate.id })
        else { return false }

        // Phase 1: Try meta check
        let metaURL = resolveMetaURL(for: candidate)
        if let metaURL = metaURL {
            let remoteVersion = await fetchRemoteVersion(from: metaURL)
            if let remoteVersion = remoteVersion, !candidate.version.isEmpty {
                // Both versions available: compare
                if !UserScript.isVersionNewer(remoteVersion, than: candidate.version) {
                    return false // Not newer, skip
                }
                // Newer version found, proceed to full download
            }
            // If remoteVersion is nil or local version is empty, fall through to full download
        }

        // Phase 2: Full download + content comparison
        guard let downloadURL = resolveDownloadURL(for: candidate) else { return false }

        let rawContent = try await downloadUserScriptContent(from: downloadURL)

        let tempUserScript = try await validatedDownloadedUserScriptContent(
            rawContent,
            replacing: candidate
        )

        let dependencies = await processedDependencies(for: tempUserScript)
        let processedContent = dependencies.content
        let resourceContents = dependencies.resources

        guard let index = userScripts.firstIndex(where: { $0.id == candidate.id }) else { return false }

        // Skip if nothing changed
        if userScripts[index].content == processedContent,
           userScripts[index].resourceContents == resourceContents {
            return false
        }

        let updated = updatedUserScript(
            userScripts[index],
            from: tempUserScript,
            content: processedContent,
            resources: resourceContents
        )
        guard writeUserScriptFiles(updated) else {
            throw CocoaError(.fileWriteUnknown)
        }
        userScripts[index] = updated
        return true
    }

    public func downloadAndEnableUserScript(_ userScript: UserScript) async {
        guard !userScript.isLocal, let url = userScript.url else { return }

        await MainActor.run {
            isLoading = true
            statusDescription = "Downloading \(userScript.name)..."
        }

        do {
            let content = try await downloadUserScriptContent(from: url)

            guard let index = userScripts.firstIndex(where: { $0.id == userScript.id }) else {
                isLoading = false
                return
            }
            let downloaded = try await validatedDownloadedUserScriptContent(
                content,
                replacing: userScripts[index]
            )
            userScripts[index] = downloaded

            // Process @require directives and @resource directives after metadata is parsed
            if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
                let dependencies = await processedDependencies(for: userScripts[index])
                let processedContent = dependencies.content
                let resourceContents = dependencies.resources

                userScripts[index].content = processedContent
                userScripts[index].resourceContents = resourceContents
                userScripts[index].isEnabled = true
                userScripts[index].isLocal = false
                userScripts[index].lastUpdated = Date()

                _ = writeUserScriptFiles(userScripts[index])
                await persistUserScriptsNow()
                statusDescription = "Downloaded and enabled \(userScript.name)"
                isLoading = false
            }
        } catch {
            await MainActor.run {
                hasError = true
                errorMessage = "Failed to download userscript: \(error.localizedDescription)"
                statusDescription = "Download failed"
                isLoading = false
            }
        }
    }

    public func getEnabledUserScriptsForURL(_ url: String) -> [UserScript] {
        guard !BlockingPauseStore.isPaused(.userScripts) else { return [] }
        let enabledScripts = userScripts.filter { $0.isEnabled }
        let matchingScripts = enabledScripts.filter { $0.matches(url: url) }
        let host = URL(string: url)?.host ?? ""
        let runnableScripts = matchingScripts.filter {
            !isUserScript($0, disabledOnHost: host)
        }

        #if DEBUG
        logger.debug(
            "🎯 Userscript match summary for URL \(url, privacy: .public): enabled=\(enabledScripts.count), matched=\(matchingScripts.count), runnable=\(runnableScripts.count)"
        )
        #endif

        return runnableScripts
    }

    public func pageUserScripts(for url: String) -> [(script: UserScript, disabledForSite: Bool)] {
        guard !BlockingPauseStore.isPaused(.userScripts) else { return [] }
        let host = URL(string: url)?.host ?? ""
        let pageScripts = userScripts
            .filter { $0.isEnabled && $0.matches(url: url) }
            .map { script in
                (script: script, disabledForSite: isUserScript(script, disabledOnHost: host))
            }

        return pageScripts
    }

    @discardableResult
    public func setUserScript(withId scriptID: UUID, disabledOnHost host: String, disabled: Bool) async -> Bool {
        guard indexOfUserScript(withId: scriptID) != nil else { return false }
        let normalizedHost = normalizedDisabledHost(host)
        guard !normalizedHost.isEmpty else { return false }

        var disabledHosts = dataManager.getUserScriptDisabledHosts(forScriptID: scriptID.uuidString)
        disabledHosts.removeAll { $0 == normalizedHost }
        if disabled {
            disabledHosts.append(normalizedHost)
        }
        await dataManager.setUserScriptDisabledHosts(disabledHosts.sorted(), forScriptID: scriptID.uuidString)
        return true
    }

    public func isUserScript(_ userScript: UserScript, disabledOnHost host: String) -> Bool {
        let disabledHosts = dataManager.getUserScriptDisabledHosts(forScriptID: userScript.id.uuidString)
        return HostMatcher.isHostDisabled(host: host, disabledSites: disabledHosts)
    }

    /// One-time move of the legacy UserDefaults exceptions map into protobuf,
    /// so backup/sync/UI all read one store. Idempotent: the key is removed after merge.
    private func migrateUserScriptSiteExceptionsIfNeeded() async {
        guard let legacy = sharedDefaults.dictionary(forKey: userScriptSiteDisabledDefaultsKey) as? [String: [String]] else {
            return
        }
        for (scriptID, hosts) in legacy {
            let normalized = hosts.map(normalizedDisabledHost).filter { !$0.isEmpty }
            guard !normalized.isEmpty else { continue }
            let merged = Set(normalized).union(dataManager.getUserScriptDisabledHosts(forScriptID: scriptID))
            await dataManager.setUserScriptDisabledHosts(merged.sorted(), forScriptID: scriptID)
        }
        sharedDefaults.removeObject(forKey: userScriptSiteDisabledDefaultsKey)
        logger.info("✅ Migrated per-site userscript exceptions to protobuf (\(legacy.count) script(s))")
    }

    private func normalizedDisabledHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Manually triggers duplicate userscript removal and cleanup
    public func cleanupDuplicateUserScripts() {
        logger.info("🧹 Manual cleanup of duplicate userscripts requested")
        // Force duplicate detection even during initial setup when manually requested
        checkForDuplicatesAndAskForConfirmation()
    }

    /// Confirms removal of pending duplicate userscripts
    public func confirmDuplicateRemoval() {
        let count = pendingDuplicatesToRemove.count
        let scriptNames = pendingDuplicatesToRemove.map { $0.name }.joined(separator: ", ")

        logger.info("✅ User confirmed removal of \(count) duplicate userscripts: \(scriptNames)")

        Task { @MainActor in
            await removeDuplicateUserScripts(pendingDuplicatesToRemove)

            // Clear pending state
            pendingDuplicatesToRemove = []
            showingDuplicatesAlert = false
            statusDescription = "Removed \(count) duplicate userscript\(count == 1 ? "" : "s")"

            logger.info("🎉 Duplicate removal completed successfully")
        }
    }

    /// Cancels removal of pending duplicate userscripts
    public func cancelDuplicateRemoval() {
        logger.info("❌ User cancelled removal of duplicate userscripts")
        pendingDuplicatesToRemove = []
        showingDuplicatesAlert = false
        statusDescription = "Duplicate removal cancelled"
    }

    /// Called when userscript initial setup finishes (onboarding completed or a backup
    /// restored). The script set is now settled, so run the duplicate check.
    public func markInitialSetupComplete() {
        logger.info("✅ Initial setup complete; checking for duplicate userscripts")
        checkForDuplicatesAndAskForConfirmation()
    }

    public func simulateFreshInstall() async {
        logger.info("🧪 Simulating fresh install for testing")

        isReady = false
        metadataPrefetchTask?.cancel()
        metadataPrefetchTask = nil

        // Clear all existing userscripts to simulate fresh install
        userScripts.removeAll()

        // Re-run setup as if it's the first time, and do not let onboarding continue
        // until default script placeholders have been recreated.
        await setup()
        isReady = true
        startDeferredStartupMaintenance()

        logger.info("🧪 Fresh install simulation complete")
    }

}
