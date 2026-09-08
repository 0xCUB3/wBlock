//
//  UserScript.swift
//  wBlock
//
//  Created by Alexander Skula on 6/7/25.
//

import CryptoKit
import Foundation

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
        return lowercased.hasSuffix(".user.js") || lowercased.hasSuffix(".js")
            || lowercased.hasSuffix(".user.css") || lowercased.hasSuffix(".css")
            || lowercased.hasSuffix(".less") || lowercased.hasSuffix(".sass")
            || lowercased.hasSuffix(".scss") || lowercased.hasSuffix(".styl")
            || lowercased.hasSuffix(".pcss")
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

    public init(entries: [String], pageURL: URL) {
        self.entries = entries
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
        grant.contains { Self.storageGrants.contains($0.lowercased()) }
    }

    private static let storageGrants: Set<String> = [
        "gm_getvalue", "gm_setvalue", "gm_deletevalue", "gm_listvalues",
        "gm_addvaluechangelistener", "gm_removevaluechangelistener",
        "gm.getvalue", "gm.setvalue", "gm.deletevalue", "gm.listvalues",
        "gm.addvaluechangelistener", "gm.removevaluechangelistener"
    ]

    public static func executableContent(from content: String) -> String {
        guard let metadataStart = content.range(of: "// ==UserScript==")?.lowerBound,
              let metadataEndRange = content.range(
                of: "// ==/UserScript==",
                range: metadataStart..<content.endIndex
              )
        else {
            return content
        }

        var bodyStart = metadataEndRange.upperBound
        if bodyStart < content.endIndex, content[bodyStart] == "\r" {
            bodyStart = content.index(after: bodyStart)
        }
        if bodyStart < content.endIndex, content[bodyStart] == "\n" {
            bodyStart = content.index(after: bodyStart)
        }

        if metadataStart == content.startIndex {
            return String(content[bodyStart...])
        }

        var stripped = String()
        stripped.reserveCapacity(content.count - content[metadataStart..<bodyStart].count)
        stripped.append(contentsOf: content[..<metadataStart])
        stripped.append(contentsOf: content[bodyStart...])
        return stripped
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

    /// Resolves the metadata URL for checking updates.
    /// Priority: updateURL > .user.js -> .meta.js derivation from url > url.
    public var resolvedMetaURL: URL? {
        guard !isLocal else { return nil }
        if let updateURLString = updateURL, let url = URL(string: updateURLString) {
            return url
        }
        guard let scriptURL = url else { return nil }
        let urlString = scriptURL.absoluteString
        if urlString.hasSuffix(".user.js") {
            let metaString = String(urlString.dropLast(8)) + ".meta.js"
            if let metaURL = URL(string: metaString) {
                return metaURL
            }
        }
        return scriptURL
    }

    /// Resolves the full script download URL.
    /// Priority: downloadURL > url.
    public var resolvedDownloadURL: URL? {
        guard !isLocal else { return nil }
        if let downloadURLString = downloadURL, let url = URL(string: downloadURLString) {
            return url
        }
        return url
    }

    /// Returns true if this remote script has sufficient URL information and auto-update preference to check for updates.
    public var isEligibleForUpdateCheck: Bool {
        !isLocal && isDownloaded && updatesAutomatically && (resolvedMetaURL != nil || resolvedDownloadURL != nil)
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

        init(_ patterns: [String]) {
            self.patterns = patterns
            for pattern in patterns {
                guard let separator = pattern.range(of: "://"),
                      let slash = pattern[separator.upperBound...].firstIndex(of: "/") else {
                    fallback.append(pattern)
                    continue
                }
                let host = String(pattern[separator.upperBound..<slash]).lowercased()
                if host.hasPrefix("*.") && !host.dropFirst(2).contains("*") {
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
                              parsedURL: ParsedMatchURL, urlRange: NSRange) -> Bool {
        // Small lists avoid index construction. Large lists share their immutable
        // array storage across frames; mutations invalidate the cached host index.
        guard patterns.count > 64 else {
            return patterns.contains { Self.matchesPattern(pattern: $0, url: url, parsedURL: parsedURL, urlRange: urlRange) }
        }
        let key = "\(id.uuidString):\(kind)" as NSString
        let index: MatchHostIndex
        if let cached = Self.matchHostIndexes.object(forKey: key), cached.patterns == patterns {
            index = cached
        } else {
            index = MatchHostIndex(patterns)
            Self.matchHostIndexes.setObject(index, forKey: key, cost: patterns.count)
        }
        var candidates = index.candidates(for: parsedURL.host)
        if parsedURL.hostWithPort != parsedURL.host {
            candidates += index.candidates(for: parsedURL.hostWithPort)
        }
        return (candidates + index.fallback).contains {
            Self.matchesPattern(pattern: $0, url: url, parsedURL: parsedURL, urlRange: urlRange)
        }
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
    
    /// Strip emoji glyphs from userscript/userstyle display metadata.
    ///
    /// Unicode marks ASCII digits, `#`, and `*` as emoji-capable because they can
    /// form keycap sequences (e.g. `1️⃣`). Filtering on `isEmoji` alone therefore
    /// deletes ordinary numbers from `@name` / `@description` (issue #484).
    /// Keep all ASCII, drop non-ASCII emoji bases and presentation forms, and
    /// scrub the combining marks that only exist to finish an emoji sequence.
    private func removeEmojis(from string: String) -> String {
        var result = String.UnicodeScalarView()
        result.reserveCapacity(string.unicodeScalars.count)

        for scalar in string.unicodeScalars {
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
        // Reset metadata-backed fields so repeated parsing stays idempotent.
        description = ""
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
                        let cleaned = removeEmojis(from: value)
                        if let locale = localeSuffix {
                            nameByLocale[locale] = cleaned
                        } else {
                            bareName = cleaned
                        }
                    }
                case "@description":
                    let cleaned = removeEmojis(from: value)
                    if let locale = localeSuffix {
                        descByLocale[locale] = cleaned
                    } else {
                        bareDescription = cleaned
                    }
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
    }

    /// Populates metadata-backed fields from a parsed UserCSS style. The remaining
    /// fields were already reset by `parseMetadata()`.
    private mutating func applyUserStyleMetadata(_ style: UserStyleSupport.ParsedStyle) {
        isUserStyle = true
        if let styleName = style.name {
            let cleaned = removeEmojis(from: styleName)
            if !cleaned.isEmpty { name = cleaned }
        }
        if let styleDescription = style.description {
            description = removeEmojis(from: styleDescription)
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
            isIncluded = indexedMatch(patterns: matches, kind: "include", url: comparableURL, parsedURL: parsedURL, urlRange: comparableRange) || includes.contains {
                Self.matchesIncludePattern(pattern: $0, url: url, urlRange: rawURLRange)
            }
        }

        guard isIncluded else { return false }

        if indexedMatch(patterns: excludeMatches, kind: "exclude", url: comparableURL, parsedURL: parsedURL, urlRange: comparableRange) {
            return false
        }

        if excludes.contains(where: { Self.matchesIncludePattern(pattern: $0, url: url, urlRange: rawURLRange) }) {
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
        matchesIncludePattern(pattern: pattern, url: url, urlRange: NSRange(location: 0, length: url.utf16.count))
    }

    private static func urlWithoutFragment(_ url: String) -> String {
        guard var components = URLComponents(string: url), components.fragment != nil else { return url }
        components.fragment = nil
        return components.string ?? url
    }

    private struct ParsedMatchURL {
        let scheme: String
        let host: String
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

        let hostValue = hostPattern.contains(":") ? parsedURL.hostWithPort : parsedURL.host
        guard matchesHostPattern(hostPattern, host: hostValue) else { return false }
        return wildcardMatch(pattern: pathPattern, value: parsedURL.pathAndSuffix)
    }

    private static func matchesHostPattern(_ pattern: String, host: String) -> Bool {
        if pattern == "*" {
            return true
        }

        if pattern.hasPrefix("*.") {
            let base = pattern.dropFirst(2)
            return host == base || host.hasSuffix(".\(base)")
        }

        return wildcardMatch(pattern: pattern[...], value: host)
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
    
    private static func matchesIncludePattern(pattern: String, url: String, urlRange: NSRange) -> Bool {
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

        guard let regex = cachedRegex(
            for: pattern,
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
        return regex.firstMatch(in: url, options: [], range: urlRange) != nil
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
