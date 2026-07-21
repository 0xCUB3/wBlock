//
//  UserScriptManager.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 6/7/25.
//

import Combine
import Foundation
import os.log

public enum UserScriptImportError: LocalizedError {
    case unsupportedType
    case unreadableFile
    case emptyContent
    case missingMetadata
    case unsupportedStylePreprocessor(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "Choose a .user.js, .js, or .user.css file."
        case .unreadableFile:
            return "Couldn't read the selected file."
        case .emptyContent:
            return "The file is empty."
        case .missingMetadata:
            return "Not a userscript or userstyle: missing metadata block."
        case .unsupportedStylePreprocessor(let preprocessor):
            return "This userstyle needs the \"\(preprocessor)\" preprocessor, which isn't supported yet."
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
}

public enum BuiltInUserScriptSection: String, Hashable, Sendable {
    case general
    case foreign
}

struct BuiltInUserScriptDefinition {
    let name: String
    let url: String
    let isEnabledByDefault: Bool
    let section: BuiltInUserScriptSection
    let description: String
    let languages: [String]
    /// Non-nil for userscripts that ship embedded in the framework instead of
    /// being downloaded from `url`. The `url` then acts only as a stable
    /// identity (for sync, per-site toggles, and protection); it is never
    /// fetched. Content refreshes automatically when the app ships a newer
    /// bundled version.
    let bundledContent: String?

    init(
        name: String,
        url: String,
        isEnabledByDefault: Bool,
        section: BuiltInUserScriptSection = .general,
        description: String = "Default userscript",
        languages: [String] = [],
        bundledContent: String? = nil
    ) {
        self.name = name
        self.url = url
        self.isEnabledByDefault = isEnabledByDefault
        self.section = section
        self.description = description
        self.languages = languages
        self.bundledContent = bundledContent
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
    static let tinyShieldGroupedURLPrefix =
        "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/grouped/"
    static let tinyShieldDescription =
        "tinyShield helps block ads reinserted by Ad-Shield on matching sites."

    // Bundled "cleaner" userscripts (Vinegar/Baking Soda style). These ship
    // embedded in the framework; the URLs below are stable identities only and
    // are never fetched over the network.
    static let tubeCleanerURL = "https://bundled.wblock.invalid/tube-cleaner.user.js"
    static let playerCleanerURL = "https://bundled.wblock.invalid/player-cleaner.user.js"
    static let tubeCleanerDescription =
        "Turns YouTube's own video element into a native Safari player: hides custom chrome, restores Picture-in-Picture, keeps videos playing in background tabs, and adds an audio-only mode. wBlock's content blocker handles ads separately."
    static let playerCleanerDescription =
        "Replaces custom video players on other websites with a clean HTML5 video element, restoring native controls and Picture-in-Picture. Disable it per site from the toolbar if a player misbehaves."

    private static func tinyShieldGroupedDefinition(
        _ domainGroup: String,
        displayDomain: String? = nil,
        languages: [String]
    ) -> BuiltInUserScriptDefinition {
        let initial = domainGroup.prefix(1).lowercased()
        return BuiltInUserScriptDefinition(
            name: "tinyShield (\(displayDomain ?? domainGroup))",
            url: "\(tinyShieldGroupedURLPrefix)\(initial)/tinyShield-\(domainGroup).user.js",
            isEnabledByDefault: false,
            section: .foreign,
            description: tinyShieldDescription,
            languages: languages
        )
    }

    static let definitions: [BuiltInUserScriptDefinition] = [
        BuiltInUserScriptDefinition(
            name: "Tube Cleaner",
            url: tubeCleanerURL,
            isEnabledByDefault: false,
            description: tubeCleanerDescription,
            bundledContent: BundledUserScriptSources.tubeCleaner
        ),
        BuiltInUserScriptDefinition(
            name: "Player Cleaner",
            url: playerCleanerURL,
            isEnabledByDefault: false,
            description: playerCleanerDescription,
            bundledContent: BundledUserScriptSources.playerCleaner
        ),
        BuiltInUserScriptDefinition(
            name: "Return YouTube Dislike",
            url: "https://raw.githubusercontent.com/Anarios/return-youtube-dislike/main/Extensions/UserScript/Return%20Youtube%20Dislike.user.js",
            isEnabledByDefault: false
        ),
        BuiltInUserScriptDefinition(
            name: "Bypass Paywalls Clean",
            url: "https://greasyfork.org/scripts/542351-bypass-paywalls-clean-en/code/Bypass%20Paywalls%20Clean%20(EN).user.js",
            isEnabledByDefault: false
        ),
        BuiltInUserScriptDefinition(
            name: "YouTube Classic",
            url: "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/greasemonkey/youtube-classic.user.js",
            isEnabledByDefault: false
        ),
        BuiltInUserScriptDefinition(
            name: "AdGuard Extra",
            url: "https://userscripts.adtidy.org/release/adguard-extra/1.0/adguard-extra.user.js",
            isEnabledByDefault: false
        ),
        BuiltInUserScriptDefinition(
            name: "tinyShield",
            url: tinyShieldURL,
            isEnabledByDefault: true,
            description: tinyShieldDescription
        ),
        BuiltInUserScriptDefinition(
            name: popupBlockerName,
            url: popupBlockerStableURL,
            isEnabledByDefault: false
        ),
        tinyShieldGroupedDefinition("autobild.de", languages: ["de"]),
        tinyShieldGroupedDefinition("bild.de", languages: ["de"]),
        tinyShieldGroupedDefinition("computerbild.de", languages: ["de"]),
        tinyShieldGroupedDefinition("gutefrage.net", languages: ["de"]),
        tinyShieldGroupedDefinition("welt.de", languages: ["de"]),
        tinyShieldGroupedDefinition("geo.fr", languages: ["fr"]),
        tinyShieldGroupedDefinition("lerobert.com", languages: ["fr"]),
        tinyShieldGroupedDefinition("programme-tv.net", languages: ["fr"]),
        tinyShieldGroupedDefinition("kuruma-news.jp", languages: ["ja"]),
        tinyShieldGroupedDefinition("oricon.co.jp", languages: ["ja"]),
        tinyShieldGroupedDefinition("toyokeizai.net", languages: ["ja"]),
        tinyShieldGroupedDefinition("dogdrip.net", languages: ["ko"]),
        tinyShieldGroupedDefinition("sportalkorea.com", languages: ["ko"]),
        tinyShieldGroupedDefinition("ygosu.com", languages: ["ko"]),
        tinyShieldGroupedDefinition("dziennik.pl", languages: ["pl"]),
        tinyShieldGroupedDefinition("doviz.com", languages: ["tr"]),
        tinyShieldGroupedDefinition("elnacional.cat", languages: ["ca"]),
        tinyShieldGroupedDefinition("pravda.com.ua", languages: ["uk"]),
        tinyShieldGroupedDefinition("slobodnadalmacija.hr", languages: ["hr"])
    ]

    static let protectedURLs = Set(definitions.map(\.url))
    static let legacyProtectedURLs = Set([legacyPopupBlockerBetaURL])
    static let allProtectedURLs = protectedURLs.union(legacyProtectedURLs)
    static let sectionByURL = Dictionary(uniqueKeysWithValues: definitions.map { ($0.url, $0.section) })
    static let languagesByURL = Dictionary(uniqueKeysWithValues: definitions.map { ($0.url, $0.languages) })
    /// Embedded source for bundled userscripts, keyed by their identity URL.
    static let bundledContentByURL: [String: String] = Dictionary(
        uniqueKeysWithValues: definitions.compactMap { definition in
            definition.bundledContent.map { (definition.url, $0) }
        }
    )

    /// Returns the embedded source for a bundled userscript URL, or nil when the
    /// URL refers to a normally-downloaded userscript.
    static func bundledContent(forURL url: String) -> String? {
        bundledContentByURL[url]
    }
}

@MainActor
public class UserScriptManager: ObservableObject {
    @Published public var userScripts: [UserScript] = [] {
        didSet {
            rebuildUserScriptIndex()
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
    @Published public private(set) var isPrefetchingDefaultMetadata = false

    private let userScriptSiteDisabledDefaultsKey = "userScriptDisabledHostsByID"
    private let sharedContainerIdentifier = GroupIdentifier.shared.value
    private let dataManager = ProtobufDataManager.shared
    private let sharedDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
    private let logger = Logger(subsystem: "com.skula.wBlock", category: "UserScriptManager")
    private var cancellables = Set<AnyCancellable>()
    private var initialLoadTask: Task<Void, Never>?
    private var userScriptIndexByID: [UUID: Int] = [:]
    private var metadataPrefetchTask: Task<Void, Never>?
    private static let maximumResourceBytes = 10 * 1024 * 1024
    private static let maximumEncodedResourceBytes = ((maximumResourceBytes + 2) / 3) * 4 + 256
    private static let maximumResourcesPerScript = 64
    private static let maximumStoredResourceBytesPerScript = 25 * 1024 * 1024
    private static let maximumRequireBytes = 5 * 1024 * 1024
    private static let maximumRequireBytesPerScript = 20 * 1024 * 1024
    private static let maximumRequiresPerScript = 32
    private static let maximumUserScriptBytes = 10 * 1024 * 1024

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

    public func userScriptEditorSnapshot(withId id: UUID) async -> UserScript? {
        guard let script = userScript(withId: id) else { return nil }
        guard script.content.isEmpty else { return script }

        return await Task.detached { [script] in
            var hydratedScript = script
            hydratedScript.content = Self.readUserScriptContentOffMain(script) ?? ""
            return hydratedScript
        }.value
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

    public func builtInSection(for userScript: UserScript) -> BuiltInUserScriptSection? {
        guard let urlString = userScript.url?.absoluteString else { return nil }
        return BuiltInUserScripts.sectionByURL[urlString]
    }

    public func builtInLanguages(for userScript: UserScript) -> [String] {
        guard let urlString = userScript.url?.absoluteString else { return [] }
        return BuiltInUserScripts.languagesByURL[urlString] ?? []
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

    private func syncFromDataManager() async {
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
        let updatedScripts = await hydrateUserScriptsFromDisk(
            newUserScripts,
            includeResources: false
        )

        // Only update if the scripts have actually changed to avoid unnecessary UI updates
        if !areUserScriptsEqual(userScripts, updatedScripts) {
            userScripts = updatedScripts
            logger.info("✅ Updated userscripts from data manager")
        }
    }

    private func hydrateUserScriptsFromDisk(
        _ userScripts: [UserScript],
        includeResources: Bool
    ) async -> [UserScript] {
        await Task.detached {
            Self.hydrateUserScriptsFromDiskOffMain(
                userScripts,
                includeResources: includeResources
            )
        }.value
    }

    nonisolated private static func hydrateUserScriptsFromDiskOffMain(
        _ userScripts: [UserScript],
        includeResources: Bool
    ) -> [UserScript] {
        var scripts = userScripts
        for i in scripts.indices {
            if let content = readUserScriptContentOffMain(scripts[i]) {
                scripts[i].content = content
            }

            guard includeResources else { continue }
            if let resources = readUserScriptResourcesOffMain(scripts[i]) {
                scripts[i].resourceContents = resources
            }
        }
        return scripts
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

        await dataManager.updateUserScripts(userScripts)
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
    }

    private func userScriptNotificationInfo(for userScript: UserScript) -> [String: Any] {
        var info: [String: Any] = [
            UserScriptManagerNotificationKey.name: userScript.name,
            UserScriptManagerNotificationKey.isLocal: userScript.isLocal,
        ]

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

        await migrateLegacyPopupBlockerIfNeeded()

        // Always check for missing default scripts first
        await checkAndAddMissingDefaultScripts()
        await refreshBundledUserScriptsIfNeeded()
        await refreshDefaultUserScriptDescriptionsIfNeeded()

        // Always check for duplicates - simplified approach
        checkForDuplicatesAndAskForConfirmation()

        if userScripts.isEmpty {
            logger.info("📖 No userscripts found after default check, loading defaults")
            await loadDefaultUserScripts()
        } else {
            let hydratedScripts = await hydrateUserScriptsFromDisk(
                userScripts,
                includeResources: true
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

        // Only download scripts that are enabled but missing content (e.g., from migration).
        await downloadMissingDefaultScripts()

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

                if let bundledContent = defaultScript.bundledContent {
                    applyBundledContent(to: &newUserScript, content: bundledContent)
                }

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

    /// Applies embedded bundled content to a userscript: parses metadata so the
    /// localized name/description, version, and match rules populate immediately,
    /// marks the script as not auto-updating from a URL (it updates with the app),
    /// and writes the content to disk so the injector can run it.
    private func applyBundledContent(to userScript: inout UserScript, content: String) {
        userScript.content = content
        userScript.parseMetadata()
        userScript.lastUpdated = Date()
        userScript.updatesAutomatically = false
        _ = writeUserScriptFiles(userScript)
    }

    /// Extracts the @version declared by a bundled userscript's metadata block.
    private func bundledContentVersion(_ content: String) -> String {
        var probe = UserScript(name: "probe", content: content)
        probe.parseMetadata()
        return probe.version
    }

    /// Installs or refreshes bundled userscripts. Runs on every load regardless
    /// of enabled state so an app update that ships newer embedded script content
    /// reaches users without a network fetch.
    private func refreshBundledUserScriptsIfNeeded() async {
        var didUpdate = false

        for definition in defaultUserScripts {
            guard let bundledContent = definition.bundledContent else { continue }
            guard let index = userScripts.firstIndex(where: {
                $0.url?.absoluteString == definition.url
            }) else { continue }

            let existing = userScripts[index]
            let bundledVersion = bundledContentVersion(bundledContent)
            let needsInstall = existing.content.isEmpty
            let needsRefresh = !bundledVersion.isEmpty
                && UserScript.isVersionNewer(bundledVersion, than: existing.version)

            guard needsInstall || needsRefresh else { continue }

            var updated = existing
            applyBundledContent(to: &updated, content: bundledContent)
            // Preserve the user's enablement choice across refreshes.
            updated.isEnabled = existing.isEnabled
            userScripts[index] = updated
            didUpdate = true
            logger.info(
                "📦 Bundled userscript \(needsInstall ? "installed" : "refreshed"): \(definition.name) (v\(bundledVersion))"
            )
        }

        if didUpdate {
            await persistUserScriptsNow()
        }
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

            // Bundled userscripts ship embedded in the app and are refreshed by
            // refreshBundledUserScriptsIfNeeded(); never fetch them from a URL.
            if let urlString = script.url?.absoluteString,
               BuiltInUserScripts.bundledContent(forURL: urlString) != nil {
                continue
            }

            // Prefer local disk content if available (avoid unnecessary network requests on launch).
            if script.content.isEmpty, let diskContent = readUserScriptContent(script), !diskContent.isEmpty {
                userScripts[index].content = diskContent
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

            if let bundledContent = defaultScript.bundledContent {
                applyBundledContent(to: &newUserScript, content: bundledContent)
            }

            userScripts.append(newUserScript)
            logger.info("✅ Added default userscript placeholder: \(defaultScript.name)")
        }

        if !userScripts.isEmpty {
            logger.info("💾 About to save \(self.userScripts.count) default userscript placeholders")
            await persistUserScriptsNow()
            logger.info("💾 Saved \(self.userScripts.count) default userscript placeholders")
        }
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

        for legacyIndex in legacyIndices.sorted(by: >) {
            guard userScripts.indices.contains(legacyIndex) else { continue }

            let legacyScript = userScripts[legacyIndex]

            if let stableIndex = userScripts.firstIndex(where: {
                $0.id != legacyScript.id
                    && $0.url?.absoluteString == BuiltInUserScripts.popupBlockerStableURL
            }) {
                if legacyScript.isEnabled && !userScripts[stableIndex].isEnabled {
                    userScripts[stableIndex].isEnabled = true
                    needsStableDownload = true
                    didChange = true
                }

                scriptsToDeleteFromDisk.append(legacyScript)
                userScripts.remove(at: legacyIndex)
                didChange = true
                continue
            }

            userScripts[legacyIndex].name = BuiltInUserScripts.popupBlockerName
            userScripts[legacyIndex].url = stableURL
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

        await persistUserScriptsNow()

        if needsStableDownload {
            await downloadMissingDefaultScripts()
        }
    }

    private func shouldPrefetchMetadata(for userScript: UserScript) -> Bool {
        guard !userScript.isLocal else { return false }
        guard isDefaultUserScript(userScript) else { return false }
        // Bundled userscripts carry their metadata in the app; never fetch it.
        if let urlString = userScript.url?.absoluteString,
           BuiltInUserScripts.bundledContent(forURL: urlString) != nil {
            return false
        }

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

    private func downloadUserScriptInBackground(for scriptID: UUID, from url: URL) async {
        guard let index = indexOfUserScript(withId: scriptID),
              userScripts.indices.contains(index)
        else { return }
        let scriptName = userScripts[index].name

        logger.info("📥 Downloading userscript from: \(url)")

        do {
            let content = try await downloadUserScriptContent(from: url)

            guard let currentIndex = indexOfUserScript(withId: scriptID),
                  userScripts.indices.contains(currentIndex)
            else { return }

            userScripts[currentIndex].content = content
            userScripts[currentIndex].parseMetadata()
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
            let processedContent = await processRequireDirectives(scriptForDirectives)
            let resourceContents = await processResourceDirectives(scriptForDirectives)

            guard let finalIndex = indexOfUserScript(withId: scriptID),
                  userScripts.indices.contains(finalIndex)
            else { return }

            userScripts[finalIndex].content = processedContent
            userScripts[finalIndex].resourceContents = resourceContents
            _ = writeUserScriptFiles(userScripts[finalIndex])
            await persistUserScriptsNow()
            logger.info("✅ Downloaded and saved: \(self.userScripts[finalIndex].name)")
        } catch {
            if let failedIndex = indexOfUserScript(withId: scriptID),
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
    private func persistUserScriptsNow() async {
        logger.info("💾 Saving \(self.userScripts.count) userscripts to ProtobufDataManager")
        await dataManager.updateUserScripts(userScripts)
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
        let contentSaved = writeUserScriptContent(userScript)
        let resourcesSaved = writeUserScriptResources(userScript)
        return contentSaved && resourcesSaved
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
        updated.content = content
        updated.resourceContents = resources
        updated.lastUpdated = Date()
        return updated
    }

    private func userScriptFileExists(_ userScript: UserScript) -> Bool {
        let fileName = "\(userScript.id.uuidString).user.js"
        return [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.contains {
            dirURL in
            let filePath = dirURL.appendingPathComponent(fileName).path
            return FileManager.default.fileExists(atPath: filePath)
        }
    }

    private func hasMetadataBlock(in content: String) -> Bool {
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

    private func baseName(for fileURL: URL) -> String {
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
        copy.updateURL = script.updateURL
        copy.downloadURL = script.downloadURL
        copy.lastUpdated = script.lastUpdated
        copy.isUserStyle = script.isUserStyle
        copy.updatesAutomatically = script.updatesAutomatically
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
            let restoredLocalName = restoredScript.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let existingIndex = mergedScripts.firstIndex { script in
                if let restoredURL = restoredScript.url {
                    return script.url == restoredURL
                }

                return script.isLocal
                    && script.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == restoredLocalName
            }

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
        await persistUserScriptsNow()
    }

    // MARK: - Public Methods

    @discardableResult
    public func addUserScript(from url: URL) async -> Error? {
        isLoading = true
        statusDescription = UserStyleSupport.isUserStylePath(url.path)
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
            if UserStyleSupport.isUserStylePath(url.path), !newUserScript.isUserStyle {
                hasError = true
                errorMessage = UserScriptImportError.missingMetadata.errorDescription ?? ""
                statusDescription = "Download failed"
                isLoading = false
                return UserScriptImportError.missingMetadata
            }
            if newUserScript.isUserStyle,
               let style = UserStyleSupport.parsed(from: newUserScript.content),
               !style.isPreprocessorSupported
            {
                hasError = true
                errorMessage = UserScriptImportError
                    .unsupportedStylePreprocessor(style.preprocessor).errorDescription ?? ""
                statusDescription = "Download failed"
                isLoading = false
                return UserScriptImportError.unsupportedStylePreprocessor(style.preprocessor)
            }
            newUserScript.isEnabled = true
            newUserScript.isLocal = false
            newUserScript.lastUpdated = Date()

            // Process @require directives and @resource directives
            let processedContent = await processRequireDirectives(newUserScript)
            let resourceContents = await processResourceDirectives(newUserScript)
            newUserScript.content = processedContent
            newUserScript.resourceContents = resourceContents

            // Check if script already exists
            if let existingIndex = userScripts.firstIndex(where: { $0.url == url }) {
                newUserScript.updatesAutomatically = userScripts[existingIndex].updatesAutomatically
                userScripts[existingIndex] = newUserScript
                statusDescription = "Updated \(newUserScript.isUserStyle ? "userstyle" : "userscript"): \(newUserScript.name)"
            } else {
                userScripts.append(newUserScript)
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

    public func addUserScript(fromLocalFile fileURL: URL) async -> Error? {
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
            let filename = fileURL.lastPathComponent
            let lowercased = filename.lowercased()
            let isSupportedType = lowercased.hasSuffix(".user.js") || lowercased.hasSuffix(".js")
                || lowercased.hasSuffix(".user.css") || lowercased.hasSuffix(".css")

            guard isSupportedType else { throw UserScriptImportError.unsupportedType }

            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                throw UserScriptImportError.unreadableFile
            }

            guard let content = String(data: data, encoding: .utf8) else {
                throw UserScriptImportError.unreadableFile
            }

            _ = try await importLocalUserScript(
                content: content,
                fallbackName: baseName(for: fileURL),
                importedStatusVerb: "Imported",
                replacedStatusVerb: "Replaced"
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

    public func addUserScript(fromSourceContent content: String) async -> Error? {
        isLoading = true
        statusDescription = "Adding userscript..."
        hasError = false

        do {
            _ = try await importLocalUserScript(
                content: content,
                fallbackName: "Pasted Userscript",
                importedStatusVerb: "Added",
                replacedStatusVerb: "Updated"
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
        replacedStatusVerb: String
    ) async throws -> UserScript {
        let trimmedContent = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedContent.isEmpty else {
            throw UserScriptImportError.emptyContent
        }

        guard hasMetadataBlock(in: rawContent) else {
            throw UserScriptImportError.missingMetadata
        }

        var tempScript = UserScript(name: "", content: rawContent)
        tempScript.parseMetadata()

        if tempScript.isUserStyle,
           let style = UserStyleSupport.parsed(from: rawContent),
           !style.isPreprocessorSupported
        {
            throw UserScriptImportError.unsupportedStylePreprocessor(style.preprocessor)
        }

        let metadataName = tempScript.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalName = !metadataName.isEmpty
            ? metadataName : (fallbackName.isEmpty ? "Pasted Userscript" : fallbackName)

        let existingIndex = userScripts.firstIndex { script in
            script.isLocal
                && script.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == canonicalName.lowercased()
        }

        let scriptID = existingIndex.flatMap { userScripts[$0].id } ?? UUID()
        var newUserScript = UserScript(id: scriptID, name: canonicalName, url: nil, content: rawContent)
        newUserScript.isEnabled = existingIndex.map { userScripts[$0].isEnabled } ?? true
        newUserScript.updatesAutomatically = existingIndex.map { userScripts[$0].updatesAutomatically } ?? true
        newUserScript.isLocal = true
        newUserScript.lastUpdated = Date()

        newUserScript.description = tempScript.description
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
        newUserScript.updateURL = tempScript.updateURL
        newUserScript.downloadURL = tempScript.downloadURL
        newUserScript.isUserStyle = tempScript.isUserStyle

        let processedContent = await processRequireDirectives(newUserScript)
        let resourceContents = await processResourceDirectives(newUserScript)
        newUserScript.content = processedContent
        newUserScript.resourceContents = resourceContents

        if let existingIndex {
            userScripts[existingIndex] = newUserScript
            statusDescription = "\(replacedStatusVerb) \(newUserScript.isUserStyle ? "userstyle" : "userscript"): \(newUserScript.name)"
        } else {
            userScripts.append(newUserScript)
            statusDescription = "\(importedStatusVerb) \(newUserScript.isUserStyle ? "userstyle" : "userscript"): \(newUserScript.name)"
        }

        _ = writeUserScriptFiles(newUserScript)

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
        guard let initialIndex = userScripts.firstIndex(where: { $0.id == userScript.id }) else { return }
        let shouldEnable = !userScripts[initialIndex].isEnabled

        if shouldEnable {
            let isReady = await ensureScriptReadyForEnabling(scriptID: userScript.id)
            guard isReady else {
                hasError = true
                errorMessage = "Failed to download \(userScript.name). Please try again."
                statusDescription = "Download failed"
                return
            }
        }

        guard let index = indexOfUserScript(withId: userScript.id),
              userScripts.indices.contains(index)
        else { return }

        userScripts[index].isEnabled = shouldEnable
        statusDescription =
            userScripts[index].isEnabled
            ? "Enabled \(userScript.name)" : "Disabled \(userScript.name)"
        // Persist the change synchronously
        logger.info(
            "💾 Persisting userscript toggle for \(userScript.name): \(self.userScripts[index].isEnabled)"
        )
        await dataManager.updateUserScripts(self.userScripts)
        logger.info("💾 Userscripts saved after toggle")
    }

    /// Sets the enabled state for a userscript explicitly (idempotent)
    public func setUserScript(_ userScript: UserScript, isEnabled: Bool) async {
        guard let initialIndex = userScripts.firstIndex(where: { $0.id == userScript.id }) else { return }
        guard userScripts[initialIndex].isEnabled != isEnabled else { return }

        if isEnabled {
            let isReady = await ensureScriptReadyForEnabling(scriptID: userScript.id)
            guard isReady else {
                hasError = true
                errorMessage = "Failed to download \(userScript.name). Please try again."
                statusDescription = "Download failed"
                return
            }
        }

        guard let index = indexOfUserScript(withId: userScript.id),
              userScripts.indices.contains(index)
        else { return }

        userScripts[index].isEnabled = isEnabled
        statusDescription =
            isEnabled ? "Enabled \(userScript.name)" : "Disabled \(userScript.name)"
        logger.info("💾 Persisting userscript setEnabled for \(userScript.name): \(isEnabled)")
        await dataManager.updateUserScripts(self.userScripts)
        logger.info("💾 Userscripts saved after setEnabled")
    }

    /// Sets whether bulk and scheduled updates should include this userscript.
    public func setUserScript(_ userScript: UserScript, updatesAutomatically: Bool) async {
        guard let index = userScripts.firstIndex(where: { $0.id == userScript.id }) else { return }
        guard userScripts[index].updatesAutomatically != updatesAutomatically else { return }

        userScripts[index].updatesAutomatically = updatesAutomatically
        statusDescription = updatesAutomatically
            ? "Automatic updates enabled for \(userScript.name)"
            : "Automatic updates paused for \(userScript.name)"
        logger.info("💾 Persisting userscript update preference for \(userScript.name): \(updatesAutomatically)")
        await dataManager.updateUserScripts(self.userScripts)
        logger.info("💾 Userscripts saved after update preference change")
    }

    private func ensureScriptReadyForEnabling(scriptID: UUID) async -> Bool {
        guard let index = indexOfUserScript(withId: scriptID),
              userScripts.indices.contains(index)
        else { return false }
        let script = userScripts[index]
        guard !script.isLocal else { return !script.content.isEmpty }
        guard script.content.isEmpty else { return true }

        if let diskContent = readUserScriptContent(script), !diskContent.isEmpty {
            userScripts[index].content = diskContent
            if let resources = readUserScriptResources(script) {
                userScripts[index].resourceContents = resources
            }
            return true
        }

        // Bundled userscripts are reinstalled from the app, never downloaded.
        if let urlString = script.url?.absoluteString,
           let bundledContent = BuiltInUserScripts.bundledContent(forURL: urlString) {
            var reinstalled = script
            applyBundledContent(to: &reinstalled, content: bundledContent)
            reinstalled.isEnabled = script.isEnabled
            userScripts[index] = reinstalled
            return true
        }

        guard let url = script.url else { return false }
        await downloadUserScriptInBackground(for: scriptID, from: url)

        guard let currentIndex = indexOfUserScript(withId: scriptID),
              userScripts.indices.contains(currentIndex)
        else { return false }
        return userScripts[currentIndex].isDownloaded
    }

    /// Batch apply enabled state using a set of IDs (single persistence write)
    public func setEnabledScripts(withIDs enabledIDs: Set<UUID>) async {
        var failedRemoteEnables = Set<String>()

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
            if let index = indexOfUserScript(withId: scriptID),
               userScripts.indices.contains(index),
               let diskContent = readUserScriptContent(userScripts[index]),
               !diskContent.isEmpty
            {
                userScripts[index].content = diskContent
                if let resources = readUserScriptResources(userScripts[index]) {
                    userScripts[index].resourceContents = resources
                }
                continue
            }

            await downloadUserScriptInBackground(for: scriptID, from: url)

            guard let currentIndex = indexOfUserScript(withId: scriptID),
                  userScripts.indices.contains(currentIndex)
            else { continue }

            if !userScripts[currentIndex].isDownloaded {
                failedRemoteEnables.insert(userScripts[currentIndex].name)
            }
        }

        var changed = false
        for i in userScripts.indices {
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
            await dataManager.updateUserScripts(self.userScripts)
            logger.info("💾 Userscripts saved after batch setEnabled")
        } else {
            logger.info("ℹ️ No userscript enable state changes to persist (batch)")
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

    public func removeUserScript(_ userScript: UserScript) {
        if isDefaultUserScript(userScript) {
            statusDescription = "Default userscripts can't be removed"
            logger.info("🛑 Prevented removal of default userscript: '\(userScript.name)'")
            return
        }

        if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
            let removedScript = userScripts[index]

            // Remove file
            removeUserScriptFile(removedScript)

            // Remove from memory
            userScripts.remove(at: index)
            saveUserScripts()

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
        guard let url = userScript.url else { return }

        await MainActor.run {
            isLoading = true
            statusDescription = "Updating \(userScript.name)..."
        }

        do {
            let content = try await downloadUserScriptContent(from: url)

            var tempUserScript = UserScript(
                id: userScript.id, name: userScript.name, url: url, content: content)
            tempUserScript.parseMetadata()

            // Process @require directives and @resource directives
            let processedContent = await processRequireDirectives(tempUserScript)
            let resourceContents = await processResourceDirectives(tempUserScript)

            guard let index = userScripts.firstIndex(where: { $0.id == userScript.id }) else {
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

    public func saveEditedContent(for scriptId: UUID, newContent: String) async {
        guard let index = indexOfUserScript(withId: scriptId) else { return }
        userScripts[index].content = newContent
        userScripts[index].parseMetadata()
        userScripts[index].lastUpdated = Date()
        _ = writeUserScriptFiles(userScripts[index])
        await persistUserScriptsNow()
        logger.info("Saved edited content for \(self.userScripts[index].name)")
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
            // Bundled userscripts update with the app, never from a URL.
            if let urlString = script.url?.absoluteString,
               BuiltInUserScripts.bundledContent(forURL: urlString) != nil {
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
        guard userScripts.contains(where: { $0.id == candidate.id }) else { return false }

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

        var tempUserScript = UserScript(
            id: candidate.id, name: candidate.name, url: downloadURL, content: rawContent)
        tempUserScript.parseMetadata()

        // Never swap a working userstyle for one we cannot compile natively.
        if tempUserScript.isUserStyle,
           let style = UserStyleSupport.parsed(from: rawContent),
           !style.isPreprocessorSupported
        {
            return false
        }

        let processedContent = await processRequireDirectives(tempUserScript)
        let resourceContents = await processResourceDirectives(tempUserScript)

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
        guard let url = userScript.url else { return }

        await MainActor.run {
            isLoading = true
            statusDescription = "Downloading \(userScript.name)..."
        }

        do {
            let content = try await downloadUserScriptContent(from: url)

            if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
                userScripts[index].content = content
                userScripts[index].parseMetadata()
            }

            // Process @require directives and @resource directives after metadata is parsed
            if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
                let processedContent = await processRequireDirectives(userScripts[index])
                let resourceContents = await processResourceDirectives(userScripts[index])

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
        let enabledScripts = userScripts.filter { $0.isEnabled }
        let matchingScripts = enabledScripts.filter { $0.matches(url: url) }
        let host = URL(string: url)?.host ?? ""
        let runnableScripts = Self.suppressingRedundantTinyShieldVariants(
            matchingScripts.filter {
                !isUserScript($0, disabledOnHost: host)
            }
        )

        #if DEBUG
        logger.debug(
            "🎯 Userscript match summary for URL \(url, privacy: .public): enabled=\(enabledScripts.count), matched=\(matchingScripts.count), runnable=\(runnableScripts.count)"
        )
        #endif

        return runnableScripts
    }

    /// The grouped regional tinyShield scripts are strict subsets of the full tinyShield
    /// script. When both would run on a page, the same code would execute twice, so the
    /// full script wins and the grouped variants are dropped.
    private static func suppressingRedundantTinyShieldVariants(_ scripts: [UserScript]) -> [UserScript] {
        guard scripts.contains(where: { $0.url?.absoluteString == BuiltInUserScripts.tinyShieldURL }) else {
            return scripts
        }
        return scripts.filter { script in
            guard let urlString = script.url?.absoluteString else { return true }
            return !urlString.hasPrefix(BuiltInUserScripts.tinyShieldGroupedURLPrefix)
        }
    }

    public func pageUserScripts(for url: String) -> [(script: UserScript, disabledForSite: Bool)] {
        let host = URL(string: url)?.host ?? ""
        let pageScripts = userScripts
            .filter { $0.isEnabled && $0.matches(url: url) }
            .map { script in
                (script: script, disabledForSite: isUserScript(script, disabledOnHost: host))
            }

        // Mirror the injection-time dedup: hide grouped tinyShield variants whenever the
        // full script actually runs on this page, so the popup reflects what is injected.
        let fullTinyShieldRuns = pageScripts.contains {
            !$0.disabledForSite && $0.script.url?.absoluteString == BuiltInUserScripts.tinyShieldURL
        }
        guard fullTinyShieldRuns else { return pageScripts }
        return pageScripts.filter { item in
            guard let urlString = item.script.url?.absoluteString else { return true }
            return !urlString.hasPrefix(BuiltInUserScripts.tinyShieldGroupedURLPrefix)
        }
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

        logger.info("🧪 Fresh install simulation complete")
    }

}
