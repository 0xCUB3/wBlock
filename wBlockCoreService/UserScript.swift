//
//  UserScript.swift
//  wBlock
//
//  Created by Alexander Skula on 6/7/25.
//

import CryptoKit
import Foundation
#if canImport(WBEngine)
internal import WBEngine
#endif

public enum UserScriptImportIdentity {
    public static func forFileURL(_ url: URL) -> String {
        "file:\(url.standardizedFileURL.path)"
    }

    public static func forContent(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return "content:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func normalized(_ identity: String?) -> String? {
        guard let identity else { return nil }
        let value = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

public enum UserScriptURLSupport {
    /// Collapses a wrapped script URL onto one line while preserving multiple
    /// complete http(s) URLs as separate lines for bulk import.
    public static func normalizePastedURL(_ rawValue: String) -> String {
        let lines = rawValue
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let hasMultipleURLs = lines.count > 1 && lines.dropFirst().allSatisfy {
            let value = $0.lowercased()
            return value.hasPrefix("http://") || value.hasPrefix("https://")
        }
        return lines.joined(separator: hasMultipleURLs ? "\n" : "")
    }

    /// Merges pasted text into an existing URL list (#642): keeps what was
    /// already typed, drops duplicates, and leaves one URL per line.
    public static func appendingPastedURLs(_ pasted: String, to existing: String) -> String {
        let incoming = normalizePastedURL(pasted)
        let current = existing
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !current.isEmpty else { return incoming }
        var seen = Set(current)
        var lines = current
        for line in incoming.components(separatedBy: .newlines) where !line.isEmpty && seen.insert(line).inserted {
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Reads a plain-text URL list for bulk import: one URL per line. Blank lines,
    /// `#` and `//` comment lines, and a leading BOM are ignored.
    public static func urlListText(fromFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: UserScriptImportLimits.maximumSourceFileBytes + 1) ?? Data()
        guard data.count <= UserScriptImportLimits.maximumSourceFileBytes else {
            throw NSError(domain: "wBlock.urlListImport", code: 1, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "The selected file is too large. Maximum size is 10 MB.", comment: "URL list import size error")
            ])
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Parses one wrapped URL or multiple complete URLs, one per line.
    public static func parseRemoteURLs(from rawValue: String) -> [URL] {
        let lines = rawValue.components(separatedBy: .newlines).compactMap { line -> String? in
            var candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { return nil }
            if let first = candidate.first, let last = candidate.last,
               (first == "<" && last == ">")
                || (first == "\"" && last == "\"")
                || (first == "'" && last == "'") {
                candidate = String(candidate.dropFirst().dropLast())
            }
            return candidate
        }

        if lines.count > 1 {
            let urls = lines.compactMap(validatedRemoteURL)
            if urls.count == lines.count {
                var seen = Set<URL>()
                return urls.filter { seen.insert($0).inserted }
            }
        }
        return validatedRemoteURL(from: rawValue).map { [$0] } ?? []
    }

    public static func validatedRemoteURL(from rawValue: String) -> URL? {
        let trimmed = normalizePastedURL(rawValue)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              hasSupportedExtension(in: components),
              let url = components.url else {
            return nil
        }

        return url
    }

    public static func displayName(forRemoteURL url: URL) -> String {
        let pathName = url.lastPathComponent
        if hasSupportedExtension(in: pathName) {
            return displayName(forFilename: pathName)
        }
        if let queryName = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .compactMap(\.value).first(where: { hasSupportedExtension(in: $0) })
        {
            return displayName(forFilename: queryName)
        }
        return displayName(forFilename: pathName)
    }

    public static func displayName(forFilename filename: String) -> String {
        let lowercased = filename.lowercased()

        if lowercased.hasSuffix(".user.js") {
            return String(filename.dropLast(".user.js".count))
        }

        if lowercased.hasSuffix(".js") {
            return String(filename.dropLast(".js".count))
        }

        if lowercased.hasSuffix(".user.css") {
            return String(filename.dropLast(".user.css".count))
        }

        if lowercased.hasSuffix(".css") {
            return String(filename.dropLast(".css".count))
        }

        return URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    }

    private static func hasSupportedExtension(in components: URLComponents) -> Bool {
        if hasSupportedExtension(in: components.path) {
            return true
        }
        // Some hosts (e.g. gitflic.ru raw endpoints) carry the script filename in
        // a query parameter rather than the path. Fall back to the query item value
        // so those legitimate URLs are not rejected as invalid.
        if let queryItems = components.queryItems {
            for item in queryItems {
                if let value = item.value, hasSupportedExtension(in: value) {
                    return true
                }
            }
        }
        return false
    }

    private static func hasSupportedExtension(in path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.hasSuffix(".js") || UserStyleSupport.isUserStylePath(lowercased)
    }
}

public enum UserScriptImportLimits {
    /// Maximum source size shared by local staging and remote script imports.
    public static let maximumSourceFileBytes = 10 * 1024 * 1024
}

public struct UserScriptResource: Codable, Hashable, Sendable {
    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

final class UserScriptPayloadDataCache: @unchecked Sendable {
    private final class Entry: NSObject {
        let source: String
        let data: Data

        init(source: String, data: Data) {
            self.source = source
            self.data = data
        }
    }

    private let cache = NSCache<NSString, Entry>()

    init(countLimit: Int = 2, totalCostLimit: Int = 8 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func data(for key: String, source: String, prepare: (String) -> String? = { $0 }) -> Data? {
        let cacheKey = key as NSString
        if let entry = cache.object(forKey: cacheKey), entry.source == source {
            return entry.data
        }
        guard let text = prepare(source), !text.isEmpty else { return nil }
        let data = Data(text.utf8)
        cache.setObject(Entry(source: source, data: data), forKey: cacheKey, cost: data.count)
        return data
    }
}

private struct UserScriptExecutableContent {
    let source: String
    let metadataRemovalRange: Range<String.Index>?
    let runtimePrefix: String?

    private var beforeMetadata: Substring {
        source[..<(metadataRemovalRange?.lowerBound ?? source.startIndex)]
    }

    private var afterMetadata: Substring {
        source[(metadataRemovalRange?.upperBound ?? source.startIndex)...]
    }

    func materialize(utf8ByteCount: Int? = nil) -> String {
        if runtimePrefix == nil {
            guard let metadataRemovalRange else { return source }
            if metadataRemovalRange.lowerBound == source.startIndex {
                return String(afterMetadata)
            }
        }

        let before = beforeMetadata
        let after = afterMetadata
        var result = String()
        result.reserveCapacity(utf8ByteCount ?? ((runtimePrefix?.utf8.count ?? 0) + before.utf8.count + after.utf8.count))
        if let runtimePrefix {
            result.append(runtimePrefix)
        }
        result.append(contentsOf: before)
        result.append(contentsOf: after)
        return result
    }

    func digest() -> String {
        if let runtimePrefix {
            return UserStylePreprocessorService.digest(segments: [runtimePrefix[...], beforeMetadata, afterMetadata])
        }
        return UserStylePreprocessorService.digest(segments: [beforeMetadata, afterMetadata])
    }
}

/// Stores offsets to avoid retaining the script source. Pass the original
/// source when materializing or hashing the payload.
@MainActor
final class UserScriptPreparedPayload {
    let runtimePrefix: String?
    let utf8ByteCount: Int
    private let metadataRemovalUTF8Range: Range<Int>?
    private(set) var cachedDigest: String?

    init(source: String, runtimePrefix: String?) {
        self.runtimePrefix = runtimePrefix
        let sourceUTF8 = source.utf8
        if let removal = UserScript.metadataRemovalRange(in: source) {
            let start = sourceUTF8.distance(from: sourceUTF8.startIndex, to: removal.lowerBound)
            let length = sourceUTF8.distance(from: removal.lowerBound, to: removal.upperBound)
            metadataRemovalUTF8Range = start..<(start + length)
        } else {
            metadataRemovalUTF8Range = nil
        }
        utf8ByteCount = sourceUTF8.count - (metadataRemovalUTF8Range?.count ?? 0) + (runtimePrefix?.utf8.count ?? 0)
    }

    func materializeContent(from source: String) -> String {
        executableContent(from: source).materialize(utf8ByteCount: utf8ByteCount)
    }

    func contentDigest(from source: String) -> String {
        if let cachedDigest { return cachedDigest }
        let digest = executableContent(from: source).digest()
        cachedDigest = digest
        return digest
    }

    private func executableContent(from source: String) -> UserScriptExecutableContent {
        let removal = metadataRemovalUTF8Range.map { offsets in
            let utf8 = source.utf8
            let lower = utf8.index(utf8.startIndex, offsetBy: offsets.lowerBound)
            let upper = utf8.index(lower, offsetBy: offsets.count)
            return lower..<upper
        }
        return UserScriptExecutableContent(source: source, metadataRemovalRange: removal, runtimePrefix: runtimePrefix)
    }
}

@MainActor
final class UserScriptPreparedPayloadCache {
    private struct CacheEntry {
        let payloadRevision: UInt64
        let payload: UserScriptPreparedPayload
        var hits: UInt64
        var lastUsed: UInt64
    }

    private static let maximumEntries = 128
    private var entries: [UUID: CacheEntry] = [:]
    private var clock: UInt64 = 0

    func payload(
        for script: UserScript,
        payloadRevision: UInt64,
        runtimePrefix: String?
    ) -> UserScriptPreparedPayload {
        clock &+= 1
        if var cached = entries[script.id],
           cached.payloadRevision == payloadRevision,
           cached.payload.runtimePrefix == runtimePrefix {
            cached.hits &+= 1
            cached.lastUsed = clock
            entries[script.id] = cached
            return cached.payload
        }
        let prepared = UserScriptPreparedPayload(source: script.content, runtimePrefix: runtimePrefix)

        if entries[script.id] == nil, entries.count >= Self.maximumEntries,
           let victim = entries.min(by: {
               $0.value.hits != $1.value.hits ? $0.value.hits < $1.value.hits : $0.value.lastUsed < $1.value.lastUsed
           })?.key {
            entries.removeValue(forKey: victim)
        }
        entries[script.id] = CacheEntry(
            payloadRevision: payloadRevision,
            payload: prepared,
            hits: 1,
            lastUsed: clock
        )
        return prepared
    }
}

public enum UserScriptRestoreMatcher {
    public static func matchingIndex(for restoredScript: UserScript, in existingScripts: [UserScript]) -> Int? {
        let restoredIsLocal = restoredScript.isLocal
            || restoredScript.url == nil
            || restoredScript.url?.isFileURL == true

        if restoredIsLocal {
            if let identity = UserScriptImportIdentity.normalized(restoredScript.localImportIdentity),
               let index = existingScripts.firstIndex(where: { script in
                   script.isLocal
                       && UserScriptImportIdentity.normalized(script.localImportIdentity) == identity
               }) {
                return index
            }

            // Identity-bearing backups may use the name fallback only to upgrade
            // one legacy record. A legacy backup has no identity, so it may use a
            // unique local name match regardless of the existing record's age.
            let candidates = existingScripts.indices.filter { index in
                let script = existingScripts[index]
                let existingIdentity = UserScriptImportIdentity.normalized(script.localImportIdentity)
                let restoredIdentity = UserScriptImportIdentity.normalized(restoredScript.localImportIdentity)
                return script.isLocal
                    && (restoredIdentity == nil || existingIdentity == nil)
                    && normalizedName(script.name) == normalizedName(restoredScript.name)
            }
            return candidates.count == 1 ? candidates[0] : nil
        }

        guard let restoredURL = restoredScript.url else { return nil }
        return existingScripts.firstIndex { script in
            !script.isLocal && script.url == restoredURL
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct UserScriptConnectPolicy: Sendable {
    public let entries: [String]
    public let pageURL: URL

    /// A script that declares any `@connect` may also reach the page's own
    /// site (`pageSite`, its registrable domain, and subdomains), so `self`
    /// covers the whole site. Paywall scripts fetch `apps.<site>` APIs they
    /// don't declare, and Stay allows them (#1114). An empty declaration still fails closed, and IP
    /// or public suffix pages (nil `pageSite`) keep the exact-host `self`.
    public init(entries: [String], pageURL: URL, pageSite: String?) {
        let declared = entries.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "self" }
        let host = pageURL.host ?? ""
        let isIP = host.contains(":") || host.allSatisfy { $0.isNumber || $0 == "." }
        let site = isIP ? nil : pageSite?.lowercased()
        self.entries = entries.isEmpty ? [] : declared + [site ?? "self"]
        self.pageURL = pageURL
    }

    public func allows(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let rawHost = url.host else { return false }
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let pageHost = pageURL.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return entries.contains { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value == "*" { return true }
            if value == "self" { return host == pageHost }
            guard !value.isEmpty,
                  !value.contains(where: { $0.isWhitespace || "/:@?#*\\%".contains($0) }),
                  let parsed = URL(string: "https://\(value)"), let domain = parsed.host?.lowercased(),
                  !domain.isEmpty else { return false }
            let normalized = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return !normalized.isEmpty && (host == normalized || host.hasSuffix(".\(normalized)"))
        }
    }
}

final class GMRedirectPolicyDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let policy: UserScriptConnectPolicy
    let redirect: String
    init(policy: UserScriptConnectPolicy, redirect: String) {
        self.policy = policy
        self.redirect = redirect
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, policy.allows(url), redirect == "follow" else {
            if redirect != "manual" { task.cancel() }
            completionHandler(nil)
            return
        }
        var authorizedRequest = request
        if response.url?.scheme != url.scheme || response.url?.host != url.host || response.url?.port != url.port {
            for name in ["Authorization", "Cookie", "Proxy-Authorization"] {
                authorizedRequest.setValue(nil, forHTTPHeaderField: name)
            }
        }
        completionHandler(authorizedRequest)
    }
}

public struct UserScript: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var url: URL?
    public var isEnabled: Bool = false
    public var description: String = ""
    public var author: String?
    public var homepage: String?
    public var metadataAuthorOverride: String?
    public var metadataHomepageOverride: String?
    public var version: String = ""
    public var matches: [String] = []
    public var excludeMatches: [String] = []
    public var includes: [String] = []
    public var excludes: [String] = []
    public var runAt: String = "document-end"
    public var injectInto: String = "auto"
    public var grant: [String] = []
    public var allowsGMXMLHttpRequest: Bool {
        let grants = Set(grant.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return !grants.contains("none") && (grants.contains("gm_xmlhttprequest") || grants.contains("gm.xmlhttprequest"))
    }
    private final class ConnectMetadata {
        let source: String
        let entries: [String]
        init(source: String, entries: [String]) { self.source = source; self.entries = entries }
    }
    private static let connectMetadataCache: NSCache<NSString, ConnectMetadata> = {
        let cache = NSCache<NSString, ConnectMetadata>()
        cache.countLimit = 128
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    public var connect: [String] {
        let key = id.uuidString as NSString
        if let cached = Self.connectMetadataCache.object(forKey: key), cached.source == content {
            return cached.entries
        }
        var values: [String] = []
        var inMetadata = false
        var declared = false
        content.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "// ==UserScript==" { inMetadata = true; return }
            if trimmed == "// ==/UserScript==" { stop = true; return }
            guard inMetadata else { return }
            let parts = trimmed.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2, parts[0] == "//", parts[1] == "@connect" else { return }
            declared = true
            if parts.count == 3 { values.append(String(parts[2])) }
        }
        let entries = declared ? values : ["self"]
        Self.connectMetadataCache.setObject(ConnectMetadata(source: content, entries: entries), forKey: key, cost: content.utf8.count)
        return entries
    }
    public var require: [String] = []
    public var resource: [UserScriptResource] = []
    public var resourceContents: [String: String] = [:] // Cached resource content
    public var noframes: Bool = false
    /// True when this entry is a UserCSS userstyle rather than a userscript.
    /// Styles reuse the userscript pipeline; `matches` then stores serialized
    /// `@-moz-document` conditions and `content` holds the full .user.css source.
    public var isUserStyle: Bool = false
    public var isLocal: Bool = true
    public var updateURL: String?
    public var downloadURL: String?
    public var content: String = ""
    /// Derived CSS is process-local and deliberately excluded from Codable/protobuf/cloud.
    /// Hydration populates it from a validated sidecar; runtime consumes it without compiling.
    public var compiledStyleBody: String? {
        get { Self.compiledStyleBodies.object(forKey: compiledStyleCacheKey)?.body }
        set {
            let key = compiledStyleCacheKey
            if let newValue {
                Self.compiledStyleBodies.setObject(CompiledStyleBodyBox(newValue), forKey: key)
            } else {
                Self.compiledStyleBodies.removeObject(forKey: key)
            }
        }
    }
    public var lastUpdated: Date?
    public var updatesAutomatically: Bool = true
    /// User-selected category for local organization. Existing scripts default to Scripts.
    public var category: FilterListCategory = .scripts
    /// Stable identity for local imports. Legacy entries may not have one.
    public var localImportIdentity: String?

    private final class CompiledStyleBodyBox: NSObject {
        let body: String
        init(_ body: String) { self.body = body }
    }
    private static let compiledStyleBodies = NSCache<NSString, CompiledStyleBodyBox>()

    /// A body is valid only for this script's current authoritative source.
    /// Source identity keeps an uncommitted replacement candidate isolated.
    private var compiledStyleCacheKey: NSString {
        "\(id.uuidString):\(UserStylePreprocessorService.digest(content))" as NSString
    }

    public static func localImportIdentityForUpdate(
        existing: UserScript?,
        requestedIdentity: String?,
        preserveExistingIdentity: Bool
    ) -> String? {
        if preserveExistingIdentity,
           let existingIdentity = UserScriptImportIdentity.normalized(existing?.localImportIdentity) {
            return existingIdentity
        }
        return UserScriptImportIdentity.normalized(requestedIdentity)
    }

    public static func matchesLocalImport(
        existing: UserScript,
        stableIdentity: String?,
        canonicalName: String
    ) -> Bool {
        guard existing.isLocal else { return false }
        let stableIdentity = UserScriptImportIdentity.normalized(stableIdentity)
        let existingIdentity = UserScriptImportIdentity.normalized(existing.localImportIdentity)
        if let stableIdentity, let existingIdentity {
            // A stable identity mismatch must not fall through to a display-name
            // match: two different local files may intentionally share a name.
            return existingIdentity == stableIdentity
        }
        // Preserve replacement behavior for entries written before stable
        // local-import identities were introduced, and for legacy sync payloads
        // that do not carry the additive identity field.
        return existing.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == canonicalName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Compares authoritative persisted/script metadata while deliberately
    /// excluding only process-local compiled CSS.
    func hasSameAuthoritativeState(as other: UserScript) -> Bool {
        id == other.id
            && name == other.name
            && url == other.url
            && isEnabled == other.isEnabled
            && description == other.description
            && author == other.author
            && homepage == other.homepage
            && metadataAuthorOverride == other.metadataAuthorOverride
            && metadataHomepageOverride == other.metadataHomepageOverride
            && version == other.version
            && matches == other.matches
            && excludeMatches == other.excludeMatches
            && includes == other.includes
            && excludes == other.excludes
            && runAt == other.runAt
            && injectInto == other.injectInto
            && grant == other.grant
            && require == other.require
            && resource == other.resource
            && resourceContents == other.resourceContents
            && noframes == other.noframes
            && isUserStyle == other.isUserStyle
            && isLocal == other.isLocal
            && updateURL == other.updateURL
            && downloadURL == other.downloadURL
            && content == other.content
            && lastUpdated == other.lastUpdated
            && updatesAutomatically == other.updatesAutomatically
            && category == other.category
            && localImportIdentity == other.localImportIdentity
    }

    /// Computed property to check if the userscript is downloaded and ready to use
    public var isDownloaded: Bool {
        !content.isEmpty
    }

    public var executableContent: String {
        Self.executableContent(from: content)
    }

    public var usesGMStorage: Bool {
        !grant.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "none" }
            && grant.contains { Self.storageGrants.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
    }

    private static let storageGrants: Set<String> = [
        "gm_getvalue", "gm_setvalue", "gm_deletevalue", "gm_listvalues",
        "gm_addvaluechangelistener", "gm_removevaluechangelistener",
        "gm.getvalue", "gm.setvalue", "gm.deletevalue", "gm.listvalues",
        "gm.addvaluechangelistener", "gm.removevaluechangelistener"
    ]

    public static func executableContent(from content: String) -> String {
        UserScriptExecutableContent(
            source: content,
            metadataRemovalRange: metadataRemovalRange(in: content),
            runtimePrefix: nil
        ).materialize()
    }

    fileprivate static func metadataRemovalRange(in content: String) -> Range<String.Index>? {
        guard let metadataStart = graphemeAlignedLiteralRange(
                "// ==UserScript==",
                in: content,
                range: content.startIndex..<content.endIndex
              )?.lowerBound,
              let metadataEndRange = graphemeAlignedLiteralRange(
                "// ==/UserScript==",
                in: content,
                range: metadataStart..<content.endIndex
              )
        else {
            return nil
        }

        var bodyStart = metadataEndRange.upperBound
        if bodyStart < content.endIndex, content[bodyStart] == "\r" {
            bodyStart = content.index(after: bodyStart)
        }
        if bodyStart < content.endIndex, content[bodyStart] == "\n" {
            bodyStart = content.index(after: bodyStart)
        }
        return metadataStart..<bodyStart
    }

    private static func isCharacterBoundary(_ index: String.Index, in content: String) -> Bool {
        index == content.endIndex
            || content.index(before: content.index(after: index)) == index
    }

    private static func graphemeAlignedLiteralRange(
        _ marker: String,
        in content: String,
        range searchRange: Range<String.Index>
    ) -> Range<String.Index>? {
        var cursor = searchRange.lowerBound
        while cursor < searchRange.upperBound,
              let match = content.range(of: marker, options: .literal, range: cursor..<searchRange.upperBound) {
            // A literal match can split a character, such as "=" followed by a combining accent.
            if isCharacterBoundary(match.lowerBound, in: content),
               isCharacterBoundary(match.upperBound, in: content) {
                return match
            }
            cursor = match.upperBound
        }
        return nil
    }
    
    public init(id: UUID = UUID(), name: String, url: URL? = nil, content: String = "") {
        self.id = id
        self.name = name
        self.url = url
        self.content = content
    }

    mutating func replaceContentAndParseMetadata(_ content: String, compiledBody: String? = nil) {
        self.content = content
        // Set the source first so the cache entry is installed under the new
        // authoritative identity. A plain source replacement invalidates output.
        self.compiledStyleBody = compiledBody
        parseMetadata()
    }

    /// Content refreshes preserve custom display edits, but built-ins use catalog metadata.
    mutating func restoreDisplayMetadata(from existing: UserScript) {
        if BuiltInUserScripts.definition(for: url) != nil {
            BuiltInUserScripts.applyDisplayMetadata(to: &self)
        } else {
            if !existing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = existing.name
            }
            description = existing.description
        }
    }

    /// Resolves metadata against the source URL, falling back to its .meta.js sibling.
    public var resolvedMetaURL: URL? {
        guard !isLocal else { return nil }
        if let updateURL, !updateURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return remoteUpdateURL(updateURL)
        }
        guard let scriptURL = remoteUpdateURL(url?.absoluteString) ?? resolvedDownloadURL else { return nil }
        let urlString = scriptURL.absoluteString
        if urlString.hasSuffix(".user.js") {
            return URL(string: String(urlString.dropLast(8)) + ".meta.js")
        }
        return scriptURL
    }

    public var resolvedDownloadURL: URL? {
        guard !isLocal else { return nil }
        if let downloadURL, !downloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return remoteUpdateURL(downloadURL)
        }
        return remoteUpdateURL(url?.absoluteString)
    }

    private func remoteUpdateURL(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.lowercased() != "none",
              let resolved = URL(string: value, relativeTo: url)?.absoluteURL,
              let scheme = resolved.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = resolved.host, !host.isEmpty else { return nil }
        return resolved
    }

    /// Missing downloads may be fetched, but local sources and metadata opt-outs never are.
    public var canUpdateAutomatically: Bool {
        !isLocal && updatesAutomatically && resolvedDownloadURL != nil
            && updateURL?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "none"
    }

    public var isEligibleForUpdateCheck: Bool {
        isDownloaded && canUpdateAutomatically
    }

    /// Compares two dot-separated version strings numerically.
    /// Returns true only if `remote` is strictly greater than `local`.
    /// Non-numeric segment prefixes (e.g. "0b") use leading digits only; no digits = 0.
    public static func isVersionNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".", omittingEmptySubsequences: false).map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
        let localParts = local.split(separator: ".", omittingEmptySubsequences: false).map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
        let maxLen = max(remoteParts.count, localParts.count)
        for i in 0..<maxLen {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    private final class MatchHostIndex {
        let patterns: [String]
        var exact: [String: [String]] = [:]
        var suffix: [String: [String]] = [:]
        var fallback: [String] = []

        init(_ patterns: [String], globs: Bool) {
            self.patterns = patterns
            for pattern in patterns {
                guard let separator = pattern.range(of: "://"),
                      let slash = pattern[separator.upperBound...].firstIndex(of: "/") else {
                    fallback.append(pattern)
                    continue
                }
                let host = String(pattern[separator.upperBound..<slash]).lowercased()
                // @include globs let wildcards cross URL separators, and `.tld`
                // magic keywords match any public suffix rather than literal "tld".
                if UserScript.isMagicTLDHostPattern(host) {
                    fallback.append(pattern)
                } else if globs && (!["http", "https", "ftp"].contains(String(pattern[..<separator.lowerBound]))
                    || host.contains(where: { "*?@%[".contains($0) }) || !host.utf8.allSatisfy({ $0 < 128 })) {
                    fallback.append(pattern)
                } else if host.hasPrefix("*.") && !host.dropFirst(2).contains("*") {
                    suffix[String(host.dropFirst(2)), default: []].append(pattern)
                } else if !host.contains("*") {
                    exact[host, default: []].append(pattern)
                } else {
                    fallback.append(pattern)
                }
            }
        }

        func candidates(for host: String) -> [String] {
            var result = exact[host] ?? []
            var tail = host[...]
            while !tail.isEmpty {
                result += suffix[String(tail)] ?? []
                guard let dot = tail.firstIndex(of: ".") else { break }
                tail = tail[tail.index(after: dot)...]
            }
            return result
        }
    }

    private static let matchHostIndexes: NSCache<NSString, MatchHostIndex> = {
        let cache = NSCache<NSString, MatchHostIndex>()
        cache.countLimit = 128
        cache.totalCostLimit = 200_000
        return cache
    }()

    private func indexedMatch(patterns: [String], kind: String, url: String,
                              parsedURL: ParsedMatchURL, urlRange: NSRange, globs: Bool = false) -> Bool {
        let asciiURL = globs && url.utf8.allSatisfy { $0 >= 32 && $0 < 127 }
        let matches: (String) -> Bool = { pattern in
            globs ? Self.matchesIncludePattern(pattern: pattern, url: url, urlRange: urlRange, asciiURL: asciiURL)
                : Self.matchesPattern(pattern: pattern, url: url, parsedURL: parsedURL, urlRange: urlRange)
        }
        // Small lists avoid index construction. Large lists share their immutable
        // array storage across frames; mutations invalidate the cached host index.
        guard patterns.count > 64, !globs || parsedURL.host.utf8.allSatisfy({ $0 < 128 }) else {
            return patterns.contains(where: matches)
        }
        let key = "\(id.uuidString):\(kind)" as NSString
        let index: MatchHostIndex
        if let cached = Self.matchHostIndexes.object(forKey: key), cached.patterns == patterns {
            index = cached
        } else {
            index = MatchHostIndex(patterns, globs: globs)
            Self.matchHostIndexes.setObject(index, forKey: key, cost: patterns.count)
        }
        var candidates = index.candidates(for: parsedURL.host)
        if parsedURL.hostWithPort != parsedURL.host {
            candidates += index.candidates(for: parsedURL.hostWithPort)
        }
        return (candidates + index.fallback).contains(where: matches)
    }

    private static let matchRegexCache: NSCache<NSString, NSRegularExpression> = {
        let cache = NSCache<NSString, NSRegularExpression>()
        cache.countLimit = 512
        return cache
    }()

    private static let includeRegexCache: NSCache<NSString, NSRegularExpression> = {
        let cache = NSCache<NSString, NSRegularExpression>()
        cache.countLimit = 512
        return cache
    }()

    private static func cachedRegex(
        for originalPattern: String,
        cache: NSCache<NSString, NSRegularExpression>,
        buildRegexPattern: (String) -> String
    ) -> NSRegularExpression? {
        let key = originalPattern as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let regexPattern = buildRegexPattern(originalPattern)
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else {
            return nil
        }
        cache.setObject(regex, forKey: key)
        return regex
    }
    
    /// True when the content carries a line-anchored userscript metadata block.
    public static func containsUserScriptMetadataBlock(_ content: String) -> Bool {
        var sawStart = false
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !sawStart {
                if trimmed.hasPrefix("// ==UserScript==") { sawStart = true }
            } else if trimmed.hasPrefix("// ==/UserScript==") {
                return true
            }
        }
        return false
    }

    /// True when the content should be treated as a UserCSS userstyle. A userscript
    /// metadata block wins, so scripts embedding usercss text in string literals
    /// never get reclassified.
    public static func detectsUserStyle(in content: String) -> Bool {
        UserStyleSupport.isUserStyleContent(content) && !containsUserScriptMetadataBlock(content)
    }

    /// Extract metadata from userscript or userstyle content
    public mutating func parseMetadata() {
        defer { BuiltInUserScripts.applyDisplayMetadata(to: &self) }
        // Reset metadata-backed fields so repeated parsing stays idempotent.
        description = ""
        author = nil
        homepage = nil
        version = ""
        matches.removeAll(keepingCapacity: true)
        excludeMatches.removeAll(keepingCapacity: true)
        includes.removeAll(keepingCapacity: true)
        excludes.removeAll(keepingCapacity: true)
        runAt = "document-end"
        injectInto = "auto"
        grant.removeAll(keepingCapacity: true)
        require.removeAll(keepingCapacity: true)
        resource.removeAll(keepingCapacity: true)
        noframes = false
        updateURL = nil
        downloadURL = nil
        isUserStyle = false

        if Self.detectsUserStyle(in: content),
           let style = UserStyleSupport.parsed(
               from: content,
               compiledBody: compiledStyleBody,
               compileSource: false
           )
        {
            applyUserStyleMetadata(style)
            return
        }

        // Resolve the user's preferred language code for locale-aware metadata.
        let preferredLang: String
        if #available(macOS 13.0, iOS 16.0, *) {
            preferredLang = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        } else {
            preferredLang = Locale.current.languageCode?.lowercased() ?? "en"
        }

        var nameByLocale: [String: String] = [:]    // locale → name
        var descByLocale: [String: String] = [:]    // locale → description
        var bareName: String?
        var bareDescription: String?

        var inMetadataBlock = false

        for line in content.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("// ==UserScript==") {
                inMetadataBlock = true
                continue
            }

            if trimmedLine.hasPrefix("// ==/UserScript==") {
                break
            }

            if inMetadataBlock && trimmedLine.hasPrefix("// @") {
                let metadataLine = trimmedLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
                guard !metadataLine.isEmpty else { continue }

                let components = metadataLine.split(
                    maxSplits: 1,
                    omittingEmptySubsequences: true,
                    whereSeparator: { $0.isWhitespace }
                )
                guard let keyComponent = components.first else { continue }

                let key = String(keyComponent)
                let normalizedKey = key.lowercased()
                let directive = normalizedKey.split(
                    separator: ":",
                    maxSplits: 1,
                    omittingEmptySubsequences: true
                ).first.map(String.init) ?? normalizedKey
                // Extract locale suffix (e.g. "en" from "@name:en")
                let localeSuffix: String? = {
                    let parts = normalizedKey.split(separator: ":", maxSplits: 1)
                    return parts.count > 1 ? String(parts[1]) : nil
                }()
                let value =
                    components.count > 1
                    ? String(components[1]).trimmingCharacters(in: .whitespaces) : ""

                switch directive {
                case "@name":
                    if !value.isEmpty {
                        let cleaned = value.removingEmoji
                        if let locale = localeSuffix {
                            nameByLocale[locale] = cleaned
                        } else {
                            bareName = cleaned
                        }
                    }
                case "@description":
                    let cleaned = value.removingEmoji
                    if let locale = localeSuffix {
                        descByLocale[locale] = cleaned
                    } else {
                        bareDescription = cleaned
                    }
                case "@author":
                    if !value.isEmpty { self.author = value }
                case "@homepage", "@homepageurl", "@website", "@source":
                    if !value.isEmpty { self.homepage = value }
                case "@version":
                    self.version = value
                case "@match":
                    self.matches.append(value)
                case "@exclude-match":
                    self.excludeMatches.append(value)
                case "@include":
                    self.includes.append(value)
                case "@exclude":
                    self.excludes.append(value)
                case "@run-at":
                    self.runAt = value
                case "@inject-into":
                    self.injectInto = value
                case "@grant":
                    if !self.grant.contains(value) {
                        self.grant.append(value)
                    }
                case "@require":
                    if !self.require.contains(value) {
                        self.require.append(value)
                    }
                case "@resource":
                    // Format: @resource name URL
                    let resourceComponents = value.components(separatedBy: " ")
                    if resourceComponents.count >= 2 {
                        let resourceName = resourceComponents[0]
                        let resourceURL = resourceComponents.dropFirst().joined(separator: " ")
                        self.resource.append(UserScriptResource(name: resourceName, url: resourceURL))
                    }
                case "@noframes":
                    self.noframes = true
                case "@updateurl":
                    self.updateURL = value.isEmpty ? nil : value
                case "@downloadurl":
                    self.downloadURL = value.isEmpty ? nil : value
                default:
                    break
                }
            }
        }

        // Resolve locale-aware @name: prefer user locale, then "en", then bare.
        self.name = nameByLocale[preferredLang]
            ?? nameByLocale["en"]
            ?? bareName
            ?? self.name

        // Resolve locale-aware @description: prefer user locale, then "en", then bare.
        self.description = descByLocale[preferredLang]
            ?? descByLocale["en"]
            ?? bareDescription
            ?? self.description
        if let metadataAuthorOverride { author = metadataAuthorOverride }
        if let metadataHomepageOverride { homepage = metadataHomepageOverride }
    }

    /// Populates metadata-backed fields from a parsed UserCSS style. The remaining
    /// fields were already reset by `parseMetadata()`.
    private mutating func applyUserStyleMetadata(_ style: UserStyleSupport.ParsedStyle) {
        isUserStyle = true
        if let styleName = style.name {
            let cleaned = styleName.removingEmoji
            if !cleaned.isEmpty { name = cleaned }
        }
        if let styleDescription = style.description {
            description = styleDescription.removingEmoji
        }
        version = style.version ?? ""
        matches = style.serializedConditions
        excludeMatches = style.excludeMatches
        excludes = style.excludes
        // Styles must be present before first paint; the injector inserts them as
        // <style> elements, so script-context concepts do not apply.
        runAt = "document-start"
        injectInto = "content"
        updateURL = style.updateURL
    }
    
    /// Check if userscript or userstyle matches a given URL
    public func matches(url: String) -> Bool {
        let comparableURL = Self.urlWithoutFragment(url)
        guard let parsedURL = Self.parsedMatchURL(from: comparableURL) else { return false }
        let comparableRange = NSRange(location: 0, length: comparableURL.utf16.count)
        let rawURLRange = NSRange(location: 0, length: url.utf16.count)

        let isIncluded: Bool
        if isUserStyle {
            isIncluded = UserStyleSupport.matches(serializedConditions: matches, url: url)
        } else {
            isIncluded = indexedMatch(patterns: matches, kind: "include", url: comparableURL, parsedURL: parsedURL, urlRange: comparableRange) || indexedMatch(patterns: includes, kind: "include-glob", url: url,
                              parsedURL: parsedURL, urlRange: rawURLRange, globs: true)
        }

        guard isIncluded else { return false }

        if indexedMatch(patterns: excludeMatches, kind: "exclude", url: comparableURL, parsedURL: parsedURL, urlRange: comparableRange) {
            return false
        }

        if indexedMatch(patterns: excludes, kind: "exclude-glob", url: url,
                        parsedURL: parsedURL, urlRange: rawURLRange, globs: true) {
            return false
        }

        return true
    }

    /// Greasemonkey-style `@match` evaluation for a single pattern.
    static func matchesMatchPattern(_ pattern: String, url: String) -> Bool {
        let comparableURL = urlWithoutFragment(url)
        guard let parsedURL = parsedMatchURL(from: comparableURL) else { return false }
        return matchesPattern(
            pattern: pattern, url: comparableURL, parsedURL: parsedURL,
            urlRange: NSRange(location: 0, length: comparableURL.utf16.count))
    }

    /// Greasemonkey-style `@include` glob evaluation for a single pattern.
    static func matchesIncludePattern(_ pattern: String, url: String) -> Bool {
        matchesIncludePattern(pattern: pattern, url: url, urlRange: NSRange(location: 0, length: url.utf16.count),
                              asciiURL: url.utf8.allSatisfy { $0 >= 32 && $0 < 127 })
    }

    private static func urlWithoutFragment(_ url: String) -> String {
        guard var components = URLComponents(string: url), components.fragment != nil else { return url }
        components.fragment = nil
        return components.string ?? url
    }

    private struct ParsedMatchURL {
        let scheme: String
        let host: String
        let port: Int?
        let hostWithPort: String
        let pathAndSuffix: String
    }

    private static func parsedMatchURL(from url: String) -> ParsedMatchURL? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased()
        else {
            return nil
        }

        let hostWithPort: String
        if let port = components.port {
            hostWithPort = "\(host):\(port)"
        } else {
            hostWithPort = host
        }

        var pathAndSuffix = components.percentEncodedPath
        if pathAndSuffix.isEmpty {
            pathAndSuffix = "/"
        }
        if let query = components.percentEncodedQuery {
            pathAndSuffix += "?\(query)"
        }
        return ParsedMatchURL(
            scheme: scheme,
            host: host,
            port: components.port,
            hostWithPort: hostWithPort,
            pathAndSuffix: pathAndSuffix
        )
    }

    private static func matchesPattern(
        pattern: String,
        url: String,
        parsedURL: ParsedMatchURL,
        urlRange: NSRange
    ) -> Bool {
        // Fast path for normal @match patterns. Large userscripts such as tinyShield
        // carry tens of thousands of matches, and compiling regexes for each candidate
        // adds enough document-start latency to lose races against page scripts.
        if let result = matchesStructuredPattern(pattern: pattern, parsedURL: parsedURL) {
            return result
        }

        guard let regex = cachedRegex(
            for: pattern,
            cache: matchRegexCache,
            buildRegexPattern: { sourcePattern in
                var regexPattern = NSRegularExpression.escapedPattern(for: sourcePattern)
                // Greasemonkey and Tampermonkey expand "*://" to http and https only
                // (#751); ftp needs an explicit scheme.
                regexPattern = regexPattern.replacingOccurrences(of: "\\*:\\/\\/", with: "https?://")
                regexPattern = regexPattern.replacingOccurrences(of: "\\*\\.", with: "([^/]*\\.)?")
                regexPattern = regexPattern.replacingOccurrences(of: "\\/\\*", with: "/.*")
                regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
                return "^\(regexPattern)$"
            }
        ) else {
            return false
        }
        return regex.firstMatch(in: url, options: [], range: urlRange) != nil
    }

    private static func matchesStructuredPattern(pattern: String, parsedURL: ParsedMatchURL) -> Bool? {
        guard let schemeSeparator = pattern.range(of: "://") else { return nil }
        let schemePattern = pattern[..<schemeSeparator.lowerBound].lowercased()
        let remainder = pattern[schemeSeparator.upperBound...]
        guard let pathStart = remainder.firstIndex(of: "/") else { return nil }

        let hostPattern = String(remainder[..<pathStart]).lowercased()
        let pathPattern = remainder[pathStart...]

        switch schemePattern {
        case "*":
            guard parsedURL.scheme == "http" || parsedURL.scheme == "https" else {
                return false
            }
        case parsedURL.scheme:
            break
        default:
            return false
        }

        let (patternHost, patternPort) = splitHostAndPort(hostPattern)
        if let patternPort {
            guard let actualPort = parsedURL.port else { return false }
            guard wildcardMatch(pattern: patternPort[...], value: String(actualPort)) else { return false }
        }
        guard matchesHostPattern(patternHost, host: parsedURL.host) else { return false }
        return wildcardMatch(pattern: pathPattern, value: parsedURL.pathAndSuffix)
    }

    private static func splitHostAndPort(_ authority: String) -> (host: String, port: String?) {
        // Leave bracketed IPv6 literals intact unless followed by `:port`.
        if authority.hasPrefix("[") {
            guard let closingBracket = authority.firstIndex(of: "]") else {
                return (authority, nil)
            }
            let afterBracket = authority.index(after: closingBracket)
            if afterBracket < authority.endIndex, authority[afterBracket] == ":" {
                let portStart = authority.index(after: afterBracket)
                return (String(authority[...closingBracket]), String(authority[portStart...]))
            }
            return (authority, nil)
        }
        guard let colon = authority.lastIndex(of: ":") else {
            return (authority, nil)
        }
        return (String(authority[..<colon]), String(authority[authority.index(after: colon)...]))
    }

    private static func isMagicTLDHostPattern(_ authority: String) -> Bool {
        let host = splitHostAndPort(authority.lowercased()).host
        return host.hasSuffix(".tld")
    }

    private static func matchesHostPattern(_ pattern: String, host: String) -> Bool {
        if pattern == "*" {
            return true
        }

        if pattern.hasSuffix(".tld") {
            return matchesMagicTLDHostPattern(pattern, host: host)
        }

        if pattern.hasPrefix("*.") {
            let base = pattern.dropFirst(2)
            return host == base || host.hasSuffix(".\(base)")
        }

        return wildcardMatch(pattern: pattern[...], value: host)
    }

    /// Matches Greasemonkey / Tampermonkey / Violentmonkey `.tld` magic keyword
    /// patterns against `host` using the Public Suffix List so `example.tld`
    /// matches `example.com` and `example.co.uk` without matching `example.evil.com`.
    private static func matchesMagicTLDHostPattern(_ pattern: String, host: String) -> Bool {
        let entityPattern = String(pattern.dropLast(4))
        guard !entityPattern.isEmpty, entityPattern != "*" else { return false }
        guard let entityHost = hostEntityWithoutPublicSuffix(for: host) else { return false }

        if entityPattern.hasPrefix("*.") {
            let base = entityPattern.dropFirst(2)
            guard !base.isEmpty else { return false }
            if !base.contains("*") {
                return entityHost == base || entityHost.hasSuffix(".\(base)")
            }
            return wildcardMatch(pattern: base, value: entityHost)
                || (entityHost.contains(".") && wildcardMatch(pattern: entityPattern[...], value: entityHost))
        }

        return wildcardMatch(pattern: entityPattern[...], value: entityHost)
    }

    private static let fallbackMultiLabelPublicSuffixes: Set<String> = [
        "ac.uk", "co.id", "co.il", "co.in", "co.jp", "co.kr", "co.nz", "co.th",
        "co.uk", "co.za", "com.ar", "com.au", "com.br", "com.cn", "com.hk",
        "com.mx", "com.my", "com.pl", "com.sg", "com.tr", "com.tw", "com.ua",
        "edu.au", "gov.au", "gov.uk", "ne.jp", "net.au", "net.br", "or.jp",
        "org.au", "org.br", "org.uk"
    ]

    /// Strips the host's public suffix (eTLD), returning `nil` for bare public
    /// suffixes, single-label hosts (`localhost`), or IP addresses.
    private static func hostEntityWithoutPublicSuffix(for host: String) -> String? {
        var normalized = host.lowercased()
        if normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        guard !normalized.isEmpty, !normalized.contains(":") else { return nil }
        let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              let lastLabel = labels.last, !lastLabel.isEmpty,
              !(lastLabel.allSatisfy { $0.isASCII && $0.isNumber })
        else { return nil }

        #if canImport(WBEngine)
        guard let root = WBEngine.registrableDomain(of: normalized),
              let dot = root.firstIndex(of: ".")
        else { return nil }
        let suffixLength = root[dot...].count
        guard normalized.count > suffixLength else { return nil }
        return String(normalized.dropLast(suffixLength))
        #else
        let lastTwo = "\(labels[labels.count - 2]).\(lastLabel)"
        if fallbackMultiLabelPublicSuffixes.contains(lastTwo) {
            guard labels.count >= 3 else { return nil }
            return labels.dropLast(2).joined(separator: ".")
        }
        return labels.dropLast(1).joined(separator: ".")
        #endif
    }

    /// Rewrites an `@include`/`@exclude` glob whose host ends in `.tld` against
    /// a subject URL whose real public suffix is replaced by `.tld`.
    private static func magicTLDIncludeRewrite(
        pattern: String,
        url: String
    ) -> (pattern: String, url: String)? {
        guard let patternSchemeSep = pattern.range(of: "://") else { return nil }
        let patternAfterScheme = pattern[patternSchemeSep.upperBound...]
        let patternAuthorityEnd = patternAfterScheme.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" })
            ?? patternAfterScheme.endIndex
        let patternAuthority = String(patternAfterScheme[..<patternAuthorityEnd])
        let (patternHostRaw, _) = splitHostAndPort(patternAuthority)
        let patternHostLower = patternHostRaw.lowercased()
        guard patternHostLower.hasSuffix(".tld") else { return nil }

        // Require a non-empty host entity before `.tld` (reject `.tld` or `*.tld`).
        let entityPattern = patternHostLower.dropLast(4)
        guard !entityPattern.isEmpty, entityPattern != "*" else { return nil }

        guard let urlSchemeSep = url.range(of: "://") else { return nil }
        let urlAfterScheme = url[urlSchemeSep.upperBound...]
        let urlAuthorityEnd = urlAfterScheme.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" })
            ?? urlAfterScheme.endIndex
        let urlAuthority = urlAfterScheme[..<urlAuthorityEnd]
        let hostStart = urlAuthority.lastIndex(of: "@").map { urlAuthority.index(after: $0) }
            ?? urlAuthority.startIndex
        let hostAndPort = String(urlAuthority[hostStart..<urlAuthorityEnd])
        let (rawURLHost, _) = splitHostAndPort(hostAndPort)
        guard let entityHost = hostEntityWithoutPublicSuffix(for: rawURLHost) else { return nil }

        let strippedURLHost = rawURLHost.hasSuffix(".") ? String(rawURLHost.dropLast()) : rawURLHost
        let realSuffixLength = strippedURLHost.count - entityHost.count
        guard realSuffixLength > 0 else { return nil }

        let suffixEndInURL = url.index(hostStart, offsetBy: strippedURLHost.count)
        let suffixStartInURL = url.index(suffixEndInURL, offsetBy: -realSuffixLength)
        var rewrittenURL = url
        rewrittenURL.replaceSubrange(suffixStartInURL..<suffixEndInURL, with: ".tld")

        // Normalize `.TLD` casing in the pattern's host suffix so it matches `.tld`.
        let tldEndInPattern = pattern.index(patternSchemeSep.upperBound, offsetBy: patternHostRaw.count)
        let tldStartInPattern = pattern.index(tldEndInPattern, offsetBy: -4)
        var normalizedPattern = pattern
        if normalizedPattern[tldStartInPattern..<tldEndInPattern] != ".tld" {
            normalizedPattern.replaceSubrange(tldStartInPattern..<tldEndInPattern, with: ".tld")
        }

        return (normalizedPattern, rewrittenURL)
    }

    private static func wildcardMatch(pattern: Substring, value: String) -> Bool {
        if pattern == "*" {
            return true
        }

        if pattern == "/*" {
            return value.hasPrefix("/")
        }

        guard pattern.contains("*") else {
            return value == pattern
        }

        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false)
        var searchStart = value.startIndex

        if let first = parts.first, !first.isEmpty {
            guard value[searchStart...].hasPrefix(first) else { return false }
            searchStart = value.index(searchStart, offsetBy: first.count)
        }

        for part in parts.dropFirst().dropLast() where !part.isEmpty {
            guard let range = value[searchStart...].range(of: part) else { return false }
            searchStart = range.upperBound
        }

        if let last = parts.last, !last.isEmpty {
            if pattern.last == "*" {
                return value[searchStart...].range(of: last) != nil
            }
            return value[searchStart...].hasSuffix(last)
        }

        return pattern.last == "*" || searchStart == value.endIndex
    }
    
    private static func matchesIncludePattern(pattern: String, url: String, urlRange: NSRange, asciiURL: Bool) -> Bool {
        // Regex-form @include/@exclude is supported by userscript managers. Keep
        // it bounded before handing the expression to ICU so hostile metadata
        // cannot feed arbitrarily large patterns or subjects into the matcher.
        if pattern.utf8.count <= 4_096,
           url.utf8.count <= 16_384,
           isRegexIncludePattern(pattern) {
            let body = String(pattern.dropFirst().dropLast())
                .replacingOccurrences(of: "\\/", with: "/")
            guard let regex = cachedRegex(
                for: "regex:\(body)",
                cache: includeRegexCache,
                buildRegexPattern: { _ in body }
            ) else {
                return false
            }
            return boundedRegexMatch(regex, in: url, range: urlRange)
        }

        var effectivePattern = pattern
        var effectiveURL = url
        var effectiveRange = urlRange
        var effectiveASCII = asciiURL

        if pattern.range(of: ".tld", options: .caseInsensitive) != nil,
           let schemeSep = pattern.range(of: "://") {
            let afterScheme = pattern[schemeSep.upperBound...]
            let authorityEnd = afterScheme.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" })
                ?? afterScheme.endIndex
            let authorityHost = splitHostAndPort(String(afterScheme[..<authorityEnd])).host
            if authorityHost.lowercased().hasSuffix(".tld") {
                guard let rewritten = magicTLDIncludeRewrite(pattern: pattern, url: url) else {
                    return false
                }
                effectivePattern = rewritten.pattern
                effectiveURL = rewritten.url
                effectiveRange = NSRange(location: 0, length: effectiveURL.utf16.count)
                effectiveASCII = effectiveURL.utf8.allSatisfy { $0 >= 32 && $0 < 127 }
            }
        }

        // Ordinary ASCII globs need no regex compilation or cache entry. Keep
        // ICU for question marks and Unicode/newlines, whose semantics differ.
        if effectiveASCII, !effectivePattern.contains("?"), effectivePattern.utf8.allSatisfy({ $0 < 128 }) {
            return wildcardMatch(pattern: effectivePattern[...], value: effectiveURL)
        }

        guard let regex = cachedRegex(
            for: effectivePattern,
            cache: includeRegexCache,
            buildRegexPattern: { sourcePattern in
                // Escape first, then restore wildcard semantics.
                var regexPattern = NSRegularExpression.escapedPattern(for: sourcePattern)
                regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
                regexPattern = regexPattern.replacingOccurrences(of: "\\?", with: ".")
                return "^\(regexPattern)$"
            }
        ) else {
            return false
        }
        return regex.firstMatch(in: effectiveURL, options: [], range: effectiveRange) != nil
    }

    private static func boundedRegexMatch(
        _ regex: NSRegularExpression,
        in value: String,
        range: NSRange,
        budget: TimeInterval = 0.025
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        var matched = false
        regex.enumerateMatches(
            in: value,
            options: [.reportProgress, .reportCompletion],
            range: range
        ) { result, flags, stop in
            if result != nil {
                matched = true
                stop.pointee = true
                return
            }
            if flags.contains(.progress), ProcessInfo.processInfo.systemUptime >= deadline {
                stop.pointee = true
            }
        }
        return matched
    }

    private static func isRegexIncludePattern(_ pattern: String) -> Bool {
        guard pattern.count >= 2, pattern.first == "/", pattern.last == "/" else { return false }
        let delimiter = pattern.index(before: pattern.endIndex)
        var cursor = delimiter
        var precedingBackslashes = 0
        while cursor > pattern.startIndex {
            let previous = pattern.index(before: cursor)
            guard pattern[previous] == "\\" else { break }
            precedingBackslashes += 1
            cursor = previous
        }
        return precedingBackslashes.isMultiple(of: 2)
    }
    
    // Shared formatters to avoid allocating new ones per row
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE 'at' h:mm a"
        return f
    }()
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Returns a formatted string for the last updated date
    public var lastUpdatedFormatted: String? {
        guard let lastUpdated = lastUpdated else { return nil }

        let now = Date()
        let calendar = Calendar.current

        if calendar.isDate(lastUpdated, inSameDayAs: now) {
            return "Today at \(Self.timeFormatter.string(from: lastUpdated))"
        } else if let daysDifference = calendar.dateComponents([.day], from: lastUpdated, to: now).day, daysDifference < 7 {
            return Self.weekdayFormatter.string(from: lastUpdated)
        } else {
            return Self.dateOnlyFormatter.string(from: lastUpdated)
        }
    }
}

public extension String {
    /// The string without emoji glyphs, for names and descriptions taken from
    /// userscript and filter list headers.
    ///
    /// Unicode marks ASCII digits, `#`, and `*` as emoji-capable because they can
    /// form keycap sequences (e.g. `1️⃣`). Filtering on `isEmoji` alone therefore
    /// deletes ordinary numbers from `@name` / `@description` (issue #484).
    /// Keep all ASCII, drop non-ASCII emoji bases and presentation forms, and
    /// scrub the combining marks that only exist to finish an emoji sequence.
    var removingEmoji: String {
        var result = String.UnicodeScalarView()
        result.reserveCapacity(unicodeScalars.count)

        for scalar in unicodeScalars {
            if scalar.isASCII {
                result.append(scalar)
                continue
            }

            if scalar.properties.isEmojiPresentation || scalar.properties.isEmoji {
                continue
            }

            if scalar.properties.isEmojiModifier {
                continue
            }

            // Variation Selector-16, Combining Enclosing Keycap, Zero Width Joiner
            let value = scalar.value
            if value == 0xFE0F || value == 0x20E3 || value == 0x200D {
                continue
            }

            result.append(scalar)
        }

        return String(result).trimmingCharacters(in: .whitespaces)
    }
}
