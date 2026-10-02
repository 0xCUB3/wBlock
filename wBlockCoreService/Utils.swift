//
//  Utils.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 29/01/2025.
//

import Dispatch
import Foundation
import CryptoKit
import os.log

public enum FilterListMetadataParser {
    private static let titleRegex = headerRegex("Title")
    private static let descriptionRegex = headerRegex("Description")
    private static let versionRegex = headerRegex("(?:version|last modified|updated)")

    /// Adblock headers start with "!". Hosts-style lists use "#", where prose
    /// comments are common, so those need the colon to count as a field.
    private static func headerRegex(_ key: String) -> NSRegularExpression {
        try! NSRegularExpression(
            pattern: "^(?:!\\s*\(key)\\s*:?|#\\s*\(key)\\s*:)\\s*(.*)$",
            options: [.caseInsensitive]
        )
    }

    public static func parse(
        from content: String,
        maxLines: Int? = nil
    ) -> (title: String?, description: String?, version: String?) {
        var title: String?
        var description: String?
        var version: String?
        var scannedLines = 0

        for line in content.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if title == nil {
                title = firstCapturedGroup(in: trimmedLine, regex: titleRegex)
            }
            if description == nil {
                description = firstCapturedGroup(in: trimmedLine, regex: descriptionRegex)
            }
            if version == nil {
                version = firstCapturedGroup(in: trimmedLine, regex: versionRegex)
            }

            if title != nil, description != nil, version != nil {
                break
            }

            scannedLines += 1
            if let maxLines, scannedLines >= maxLines {
                break
            }
        }

        return (title: title, description: description, version: version)
    }

    private static func firstCapturedGroup(
        in line: String,
        regex: NSRegularExpression
    ) -> String? {
        let range = NSRange(location: 0, length: line.utf16.count)
        guard
            let match = regex.firstMatch(in: line, options: [], range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        let value = String(line[valueRange]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}

public enum NetworkRequestFactory {
    public static func makeConditionalRequest(
        url: URL,
        etag: String? = nil,
        lastModified: String? = nil,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
        timeout: TimeInterval = 30
    ) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeout)
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        return request
    }

}

public enum FilterDirectivePolicy {
    private static let directiveIntroducer = "!#"

    private static let preservedDirectiveNames: Set<String> = [
        "include",
        "if",
        "else",
        "endif",
        "safari_cb_affinity",
    ]

    public static func shouldPreserveDirective(_ trimmedLine: String) -> Bool {
        guard let directiveName = preprocessorDirectiveName(in: trimmedLine) else { return false }

        return preservedDirectiveNames.contains(directiveName)
    }

    public static func shouldStripUnsupportedDirective(_ trimmedLine: String) -> Bool {
        guard let directiveName = preprocessorDirectiveName(in: trimmedLine) else { return false }

        return !preservedDirectiveNames.contains(directiveName)
    }

    private static func preprocessorDirectiveName(in trimmedLine: String) -> String? {
        var index = trimmedLine.startIndex
        guard trimmedLine[index...].hasPrefix(directiveIntroducer) else { return nil }

        index = trimmedLine.index(index, offsetBy: directiveIntroducer.count)
        guard index < trimmedLine.endIndex, trimmedLine[index].isLetter else { return nil }

        let nameStart = index
        while index < trimmedLine.endIndex, isDirectiveNameCharacter(trimmedLine[index]) {
            index = trimmedLine.index(after: index)
        }

        return String(trimmedLine[nameStart..<index])
    }

    private static func isDirectiveNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }
}

public enum FilterListContentProcessing {
    public static func parseMetadata(
        from content: String,
        maxLines: Int = 120,
        sanitize: Bool = false
    ) -> (title: String?, description: String?, version: String?) {
        let rawMetadata = FilterListMetadataParser.parse(from: content, maxLines: maxLines)

        let title = rawMetadata.title.map { value in
            let rewritten = value.replacingOccurrences(of: "/", with: " & ")
            return sanitize ? Self.sanitizeMetadata(rewritten) : rewritten
        }
        let description = rawMetadata.description.map { value in
            let rewritten = value.replacingOccurrences(of: "/", with: " & ")
            return sanitize ? Self.sanitizeMetadata(rewritten) : rewritten
        }
        let normalizedVersion = sanitize
            ? rawMetadata.version.map { Self.sanitizeMetadata($0) }
            : rawMetadata.version

        let version: String?
        if let normalizedVersion,
            normalizedVersion.contains("%"),
            (normalizedVersion.lowercased().contains("timestamp")
                || normalizedVersion.lowercased().contains("date"))
        {
            version = nil
        } else {
            version = normalizedVersion
        }

        return (title: title, description: description, version: version)
    }

    /// Drops unsupported `!#` directives and rewrites hosts-file entries
    /// (`0.0.0.0 ads.example`) as `||ads.example^` rules.
    public static func normalizedContent(
        from content: String,
        onStrip: ((String) -> Void)? = nil
    ) -> String {
        var result: [String] = []
        for line in content.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let hosts = hostsEntryHosts(trimmed) {
                result += hosts.map { "||\($0)^" }
            } else if FilterDirectivePolicy.shouldStripUnsupportedDirective(trimmed) {
                onStrip?(String(trimmed.prefix(60)))
            } else {
                result.append(String(line))
            }
        }
        return result.joined(separator: "\n")
    }

    private static let hostsAddress = try! NSRegularExpression(
        pattern: "^(?:\\d{1,3}(?:\\.\\d{1,3}){3}|[0-9A-Fa-f]*:[0-9A-Fa-f]*:[0-9A-Fa-f:.]*(?:%\\w+)?)$"
    )
    private static let hostsHostname = try! NSRegularExpression(
        pattern: "^(?:[A-Za-z0-9_](?:[A-Za-z0-9_-]*[A-Za-z0-9_])?\\.)+[A-Za-z][A-Za-z0-9-]*$"
    )
    private static let loopbackHostnames: Set<String> = ["localhost.localdomain", "ip6-localhost", "ip6-loopback"]

    /// The hostnames of a hosts-file line, or nil when the line is not one.
    /// Loopback names such as `localhost` map to an empty list.
    public static func hostsEntryHosts(_ trimmedLine: String) -> [String]? {
        let entry = trimmedLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let fields = entry.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 2, matches(hostsAddress, fields[0]) else { return nil }
        let names = fields.dropFirst()
        guard names.allSatisfy({ !$0.contains("/") && !$0.contains("$") }) else { return nil }
        return names
            .map { $0.lowercased() }
            .filter { matches(hostsHostname, $0) && !loopbackHostnames.contains($0) }
    }

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    public static func localDataForComparison(filter: FilterList, containerURL: URL) -> Data? {
        guard let localURL = ContentBlockerIncrementalCache.existingLocalFileURL(
            for: filter,
            containerURL: containerURL
        ) else {
            return nil
        }
        return try? Data(contentsOf: localURL)
    }

    public static func sanitizeMetadata(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var sanitized = text
        for (regex, replacement) in sanitizationRegexes {
            let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: replacement
            )
        }
        return sanitized
    }

    private static let sanitizationRegexes: [(regex: NSRegularExpression, replacement: String)] = {
        let patterns: [(pattern: String, replacement: String)] = [
            ("malicious", "suspicious"),
            ("malware", "unwanted software"),
            ("spyware", "tracking software"),
            ("harmful", "unwanted"),
            ("dangerous", "risky"),
        ]
        return patterns.compactMap { pattern, replacement in
            guard
                let regex = try? NSRegularExpression(
                    pattern: "\\b\(pattern)\\b",
                    options: [.caseInsensitive]
                )
            else { return nil }
            return (regex, replacement)
        }
    }()
}

public enum ContentBlockerIncrementalCache {
    // Bump when signature inputs/schema change so stale per-target signatures
    // do not suppress needed rebuilds.
    private static let inputSignatureSchemaVersion = "9"

    private struct State: Codable {
        var inputSignature: String
        var updatedAt: Int64
    }

    /// Keep rule order within each list intact. Target assignment and file
    /// fingerprints are stable, while callers pass the explicit compile order
    /// when output order matters.
    public static func canonicalFilterOrder(_ filters: [FilterList]) -> [FilterList] {
        filters.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// - Parameters:
    ///   - filters: Lists assigned to this target.
    ///   - affinityContributors: Lists assigned elsewhere whose
    ///     `!#safari_cb_affinity` blocks are replicated into this target. They
    ///     are part of the input, so they are part of the signature (#679).
    public static func computeInputSignature(
        filters: [FilterList],
        affinityContributors: [FilterList] = [],
        groupIdentifier: String,
        extraRulesText: String? = nil,
        cosmeticSites: CosmeticFilteringPreference.Sites = .all,
        compileOrder: [FilterList] = [],
        containerURL explicitContainerURL: URL? = nil
    ) -> String? {
        guard let containerURL = explicitContainerURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }

        var canonical = "schema=\(inputSignatureSchemaVersion)\ncount=\(filters.count)\n"
        canonical.reserveCapacity((filters.count + affinityContributors.count) * 64)

        for filter in canonicalFilterOrder(filters) {
            let fileMarker = localFileFingerprint(for: filter, containerURL: containerURL)
            canonical.append("\(filter.id.uuidString)|\(fileMarker)|\(siteScopeMarker(for: filter))\n")
        }
        if !affinityContributors.isEmpty {
            canonical.append("affinity=\(affinityContributors.count)\n")
            for filter in canonicalFilterOrder(affinityContributors) {
                let fileMarker = localFileFingerprint(for: filter, containerURL: containerURL)
                canonical.append("a|\(filter.id.uuidString)|\(fileMarker)|\(siteScopeMarker(for: filter))\n")
            }
        }

        if let extraRulesText, !extraRulesText.isEmpty {
            let extraDigest = SHA256.hash(data: Data(extraRulesText.utf8))
            let extraFingerprint = extraDigest.map { String(format: "%02x", $0) }.joined()
            canonical.append("extra=\(extraFingerprint)\n")
        } else {
            canonical.append("extra=\n")
        }
        for filter in canonicalFilterOrder(filters + affinityContributors) {
            canonical.append("distribution=\(filter.id.uuidString)|\(filter.sourceRuleCount ?? 0)\n")
        }
        if !compileOrder.isEmpty {
            canonical.append("compileOrder=\(compileOrder.map(\.id.uuidString).joined(separator: ","))\n")
        }
        if let marker = cosmeticSites.cacheMarker {
            canonical.append("cosmetic=\(marker)\n")
        }

        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func loadInputSignature(
        targetRulesFilename: String,
        groupIdentifier: String,
        containerURL: URL? = nil
    ) -> String? {
        guard
            let url = stateFileURL(
                targetRulesFilename: targetRulesFilename,
                groupIdentifier: groupIdentifier,
                containerURL: containerURL
            ),
            let data = try? Data(contentsOf: url),
            let state = try? JSONDecoder().decode(State.self, from: data)
        else {
            return nil
        }
        return state.inputSignature
    }

    public static func saveInputSignature(
        _ signature: String,
        targetRulesFilename: String,
        groupIdentifier: String,
        containerURL: URL? = nil
    ) {
        guard let url = stateFileURL(
            targetRulesFilename: targetRulesFilename,
            groupIdentifier: groupIdentifier,
            containerURL: containerURL
        ) else {
            return
        }

        let state = State(
            inputSignature: signature,
            updatedAt: Int64(Date().timeIntervalSince1970)
        )

        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func invalidateInputSignature(
        targetRulesFilename: String,
        groupIdentifier: String,
        containerURL: URL? = nil
    ) {
        guard let url = stateFileURL(
            targetRulesFilename: targetRulesFilename,
            groupIdentifier: groupIdentifier,
            containerURL: containerURL
        ) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    /// A cache hit is valid only when every artifact needed to reproduce the
    /// target exists. In particular, a missing advanced sidecar must force a
    /// conversion rather than silently dropping advanced rules.
    public static func hasCoherentBaseRulesCache(
        targetRulesFilename: String,
        groupIdentifier: String,
        containerURL explicitContainerURL: URL? = nil
    ) -> Bool {
        guard let containerURL = explicitContainerURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else { return false }

        let baseURL = containerURL.appendingPathComponent(baseRulesFilename(for: targetRulesFilename))
        let countURL = containerURL.appendingPathComponent("\(baseURL.lastPathComponent).count")
        let advancedURL = containerURL.appendingPathComponent(baseAdvancedRulesFilename(for: targetRulesFilename))
        // The base JSON is parsed once at the call site, which also compares
        // the parsed rule count against the .count sidecar. Here we only check
        // the sidecars and the outer array shape so a multi-megabyte file is
        // not deserialized twice.
        guard let countText = try? String(contentsOf: countURL, encoding: .utf8),
              let count = Int(countText.trimmingCharacters(in: .whitespacesAndNewlines)),
              count >= 0,
              looksLikeJSONArrayFile(at: baseURL),
              FileManager.default.fileExists(atPath: advancedURL.path),
              (try? String(contentsOf: advancedURL, encoding: .utf8)) != nil
        else { return false }
        return true
    }

    /// Cheap structural check: a non-empty file whose first non-whitespace byte is
    /// "[" and last non-whitespace byte is "]". Catches truncated or empty caches
    /// without parsing the whole array.
    private static func looksLikeJSONArrayFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return false }
        let window: UInt64 = 64
        try? handle.seek(toOffset: 0)
        guard let head = try? handle.read(upToCount: Int(min(window, size))),
              let first = head.first(where: { !isJSONWhitespace($0) }),
              first == UInt8(ascii: "[")
        else { return false }
        let tailStart = size > window ? size - window : 0
        try? handle.seek(toOffset: tailStart)
        guard let tail = try? handle.readToEnd(),
              let last = tail.last(where: { !isJSONWhitespace($0) })
        else { return false }
        return last == UInt8(ascii: "]")
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }

    public static func loadCachedAdvancedRules(
        targetRulesFilename: String,
        groupIdentifier: String,
        containerURL explicitContainerURL: URL? = nil
    ) -> String? {
        guard let containerURL = explicitContainerURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }
        let advancedURL = containerURL.appendingPathComponent(baseAdvancedRulesFilename(for: targetRulesFilename))
        guard FileManager.default.fileExists(atPath: advancedURL.path) else { return nil }
        return try? String(contentsOf: advancedURL, encoding: .utf8)
    }

    /// Per-list site scope changes the compiled output without touching
    /// the list file, so they must be part of the signature.
    private static func siteScopeMarker(for filter: FilterList) -> String {
        FilterListSiteExclusion.scopeMarker(excluding: filter.excludedSites, including: filter.selectedSites)
    }

    private static func localFileFingerprint(for filter: FilterList, containerURL: URL) -> String {
        let primaryURL = containerURL.appendingPathComponent(localFilename(for: filter))
        if let fingerprint = fileFingerprint(at: primaryURL) {
            return "p|\(fingerprint)"
        }
        return "missing"
    }

    private static func fileFingerprint(at url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let modMicros = Int64(modDate * 1_000_000)
        return "\(size)|\(modMicros)"
    }

    private static func stateFileURL(
        targetRulesFilename: String,
        groupIdentifier: String,
        containerURL explicitContainerURL: URL? = nil
    ) -> URL? {
        guard let containerURL = explicitContainerURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent("\(targetRulesFilename).incremental-state.json")
    }

    public static func localFilename(for filter: FilterList) -> String {
        if filter.isCustom {
            return "custom-\(filter.id.uuidString).txt"
        }
        guard isSafeFilenameComponent(filter.name) else {
            // Restored/corrupt non-custom metadata must not turn into a path.
            return "filter-\(filter.id.uuidString).txt"
        }
        return "\(filter.name).txt"
    }

    /// Removes every downloaded source artifact owned by a filter. Missing files
    /// are already a successful cleanup, including files removed concurrently.
    @discardableResult
    public static func removeFilterCacheFiles(
        for filter: FilterList,
        containerURL: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let filename = localFilename(for: filter)
        let urls = [
            containerURL.appendingPathComponent(filename),
            containerURL.appendingPathComponent("diff-baseline-\(filename)")
        ]

        var firstError: Error?
        for url in urls {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                if (error as NSError).code != NSFileNoSuchFileError && firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
        return urls
    }

    private static func isSafeFilenameComponent(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("\0")
    }

    public static func existingLocalFileURL(
        for filter: FilterList,
        containerURL: URL
    ) -> URL? {
        let url = containerURL.appendingPathComponent(localFilename(for: filter))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Returns a legacy name-based cache/baseline path only when the name is a
    /// single safe filename component inside the expected app-group directory.
    /// Current ID-based paths must continue to use `localFilename(for:)`.
    public static func safeLegacyFileURL(
        name: String,
        containerURL: URL,
        prefix: String = ""
    ) -> URL? {
        guard !name.isEmpty,
              !name.contains("/"),
              !name.contains("\\"),
              !name.contains("\0"),
              name != ".",
              name != ".."
        else { return nil }

        let expectedDirectory = containerURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = containerURL
            .appendingPathComponent("\(prefix)\(name).txt", isDirectory: false)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let expectedPath = expectedDirectory.path.hasSuffix("/")
            ? expectedDirectory.path
            : expectedDirectory.path + "/"
        guard candidate.path.hasPrefix(expectedPath) else { return nil }
        return candidate
    }

    public static func baseRulesFilename(for targetRulesFilename: String) -> String {
        if targetRulesFilename.lowercased().hasSuffix(".json") {
            let stem = targetRulesFilename.dropLast(5)
            return "\(stem).base.json"
        }
        return "\(targetRulesFilename).base"
    }

    public static func baseAdvancedRulesFilename(for targetRulesFilename: String) -> String {
        "\(baseRulesFilename(for: targetRulesFilename)).advanced.txt"
    }
}

/// User-selected scope is an additional restriction, never a replacement for script metadata.
public struct UserScriptSiteAccess: Codable, Equatable, Sendable {
    public var onlySelectedSites: Bool
    public var hosts: [String]

    public init(onlySelectedSites: Bool = false, hosts: [String] = []) {
        self.onlySelectedSites = onlySelectedSites
        self.hosts = DisabledSitesNormalizer.normalizedDomains(from: hosts).sorted()
    }

    public func allows(host: String, excludedHosts: [String] = []) -> Bool {
        if HostMatcher.isHostDisabled(host: host, disabledSites: excludedHosts) { return false }
        return !onlySelectedSites || HostMatcher.isHostDisabled(host: host, disabledSites: hosts)
    }

    /// Duplicate repair must never broaden either record's selected-site scope.
    public func intersecting(_ other: Self) -> Self {
        guard onlySelectedSites else { return other }
        guard other.onlySelectedSites else { return self }
        return Self(onlySelectedSites: true, hosts: (hosts + other.hosts).filter {
            allows(host: $0) && other.allows(host: $0)
        })
    }
}

public enum HostMatcher {
    public static func isHostDisabled(host: String, disabledSites: [String]) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedHost.isEmpty { return false }
        for site in disabledSites {
            let disabled = site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if disabled.isEmpty { continue }
            if normalizedHost == disabled { return true }
            if normalizedHost.hasSuffix("." + disabled) { return true }
        }
        return false
    }

    /// The per-site override for `host` from the closest matching entry. An entry
    /// covers its subdomains (#870); a more specific entry wins, and blocked wins
    /// when the same entry is in both lists.
    public static func override(host: String, allowedSites: [String], blockedSites: [String]) -> Bool? {
        guard let host = DisabledSitesNormalizer.normalizedDomain(host) else { return nil }
        let closest: ([String]) -> Int? = { sites in
            DisabledSitesNormalizer.normalizedDomains(from: sites)
                .compactMap { isHostDisabled(host: host, disabledSites: [$0]) ? $0.count : nil }.max()
        }
        switch (closest(allowedSites), closest(blockedSites)) {
        case (nil, nil): return nil
        case (let allowed?, let blocked?): return allowed > blocked
        case (_?, nil): return true
        case (nil, _?): return false
        }
    }
}

public enum UserScriptMetadataParser {
    public static func extractValue(for directive: String, from userScriptContent: String) -> String? {
        let normalizedDirective = directive.hasPrefix("@") ? directive : "@\(directive)"
        var inMetadata = false

        for line in userScriptContent.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "// ==UserScript==" {
                inMetadata = true
                continue
            }
            if trimmed == "// ==/UserScript==" { break }
            if !inMetadata { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 2, parts[0] == "//", parts[1] == normalizedDirective else { continue }
            if parts.count >= 3 {
                let value = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            return nil
        }

        return nil
    }

    public static func extractResourceNames(from userScriptContent: String) -> [String] {
        var names: [String] = []
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
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 3 {
                    let name = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { names.append(name) }
                }
            }
        }

        return Array(Set(names)).sorted()
    }
}

/// Serializes access to the shared WebExtension instance to prevent data races
/// between concurrent lookup() and buildFilterEngine() calls.
public final class WebExtensionGate: @unchecked Sendable {
    public static let shared = WebExtensionGate()
    private let lock = NSLock()

    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

func measure<T>(label: String, block: () throws -> T) rethrows -> T {
    let start = DispatchTime.now()
    let result = try block()
    let end = DispatchTime.now()
    let elapsedNanoseconds = end.uptimeNanoseconds - start.uptimeNanoseconds
    let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000
    let formattedTime = String(format: "%.3f", elapsedMilliseconds)
    os_log(.debug, "[%{public}@] Elapsed Time: %{public}@ ms", label, formattedTime)

    return result
}
