//
//  Utils.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 29/01/2025.
//

import Dispatch
import Foundation
import CryptoKit

public enum FilterListMetadataParser {
    private static let titleRegex = try! NSRegularExpression(
        pattern: "^!\\s*Title\\s*:?\\s*(.*)$",
        options: [.caseInsensitive]
    )
    private static let descriptionRegex = try! NSRegularExpression(
        pattern: "^!\\s*Description\\s*:?\\s*(.*)$",
        options: [.caseInsensitive]
    )
    private static let versionRegex = try! NSRegularExpression(
        pattern: "^!\\s*(?:version|last modified|updated)\\s*:?\\s*(.*)$",
        options: [.caseInsensitive]
    )
    private static let metadataKeyRegex = try! NSRegularExpression(
        pattern: "^!\\s*(?:title|description|version|last modified|updated|expires|homepage|license|licence|diff-path|diff-expires|checksum|support|github issues|github pull requests)\\s*:",
        options: [.caseInsensitive]
    )

    public static func parse(
        from content: String,
        maxLines: Int? = nil
    ) -> (title: String?, description: String?, version: String?) {
        var title: String?
        var descriptionParts: [String] = []
        var version: String?
        var scannedLines = 0
        var isCollectingDescription = false

        for line in content.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if title == nil {
                title = firstCapturedGroup(in: trimmedLine, regex: titleRegex)
            }
            if version == nil {
                version = firstCapturedGroup(in: trimmedLine, regex: versionRegex)
            }

            if let firstDescriptionLine = firstCapturedGroup(in: trimmedLine, regex: descriptionRegex) {
                let marker = firstDescriptionLine.trimmingCharacters(in: .whitespaces)
                descriptionParts = (marker == "|" || marker == ">") ? [] : [firstDescriptionLine]
                isCollectingDescription = true
            } else if isCollectingDescription,
                      let continuation = descriptionContinuation(from: trimmedLine) {
                descriptionParts.append(continuation)
            } else if isCollectingDescription {
                isCollectingDescription = false
            }

            if title != nil, !descriptionParts.isEmpty, version != nil, !isCollectingDescription {
                break
            }

            scannedLines += 1
            if let maxLines, scannedLines >= maxLines {
                break
            }
        }

        let description = descriptionParts.isEmpty ? nil : descriptionParts.joined(separator: " ")
        return (title: title, description: description, version: version)
    }

    private static func descriptionContinuation(from line: String) -> String? {
        guard line.hasPrefix("!") else { return nil }
        guard firstMatch(in: line, regex: metadataKeyRegex) == nil else { return nil }

        let payload = line.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }
        guard !payload.hasPrefix("[") else { return nil }
        guard !payload.hasPrefix("***") else { return nil }
        guard !payload.hasPrefix("---") else { return nil }

        let lowercased = payload.lowercased()
        guard !lowercased.hasPrefix("http://"), !lowercased.hasPrefix("https://") else { return nil }
        guard !lowercased.hasPrefix("github ") else { return nil }

        return payload
    }

    private static func firstCapturedGroup(
        in line: String,
        regex: NSRegularExpression
    ) -> String? {
        guard
            let match = firstMatch(in: line, regex: regex),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        let value = String(line[valueRange]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func firstMatch(in line: String, regex: NSRegularExpression) -> NSTextCheckingResult? {
        let range = NSRange(location: 0, length: line.utf16.count)
        return regex.firstMatch(in: line, options: [], range: range)
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

public enum ContentBlockerIncrementalCache {
    // Bump when signature inputs/schema change so stale per-target signatures
    // do not suppress needed rebuilds.
    private static let inputSignatureSchemaVersion = "4"

    private struct State: Codable {
        var inputSignature: String
        var updatedAt: Int64
    }

    public static func computeInputSignature(
        filters: [FilterList],
        groupIdentifier: String,
        extraRulesText: String? = nil
    ) -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }

        var canonical = "schema=\(inputSignatureSchemaVersion)\ncount=\(filters.count)\n"
        canonical.reserveCapacity(filters.count * 64)

        for filter in filters {
            let fileMarker = localFileFingerprint(for: filter, containerURL: containerURL)
            canonical.append("\(filter.id.uuidString)|\(fileMarker)\n")
        }

        if let extraRulesText, !extraRulesText.isEmpty {
            let extraDigest = SHA256.hash(data: Data(extraRulesText.utf8))
            let extraFingerprint = extraDigest.map { String(format: "%02x", $0) }.joined()
            canonical.append("extra=\(extraFingerprint)\n")
        } else {
            canonical.append("extra=\n")
        }

        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func loadInputSignature(
        targetRulesFilename: String,
        groupIdentifier: String
    ) -> String? {
        guard
            let url = stateFileURL(targetRulesFilename: targetRulesFilename, groupIdentifier: groupIdentifier),
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
        groupIdentifier: String
    ) {
        guard let url = stateFileURL(
            targetRulesFilename: targetRulesFilename,
            groupIdentifier: groupIdentifier
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
        groupIdentifier: String
    ) {
        guard let url = stateFileURL(
            targetRulesFilename: targetRulesFilename,
            groupIdentifier: groupIdentifier
        ) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    public static func hasBaseRulesCache(
        targetRulesFilename: String,
        groupIdentifier: String
    ) -> Bool {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return false
        }
        let baseURL = containerURL.appendingPathComponent(baseRulesFilename(for: targetRulesFilename))
        return FileManager.default.fileExists(atPath: baseURL.path)
    }

    public static func loadCachedAdvancedRules(
        targetRulesFilename: String,
        groupIdentifier: String
    ) -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }
        let advancedURL = containerURL.appendingPathComponent(baseAdvancedRulesFilename(for: targetRulesFilename))
        guard FileManager.default.fileExists(atPath: advancedURL.path) else { return nil }
        return try? String(contentsOf: advancedURL, encoding: .utf8)
    }

    private static func localFileFingerprint(for filter: FilterList, containerURL: URL) -> String {
        let primaryURL = containerURL.appendingPathComponent(localFilename(for: filter))
        if let fingerprint = fileFingerprint(at: primaryURL) {
            return "p|\(fingerprint)"
        }

        let legacyURL = containerURL.appendingPathComponent(legacyLocalFilename(for: filter))
        if let fingerprint = fileFingerprint(at: legacyURL) {
            return "l|\(fingerprint)"
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
        groupIdentifier: String
    ) -> URL? {
        guard let containerURL = FileManager.default.containerURL(
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

        let digest = SHA256.hash(data: Data(filter.url.absoluteString.utf8))
        let urlFingerprint = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        let prefix = sanitizedFilenameStem(filter.name)
        return "\(prefix)-\(urlFingerprint).txt"
    }

    public static func legacyLocalFilename(for filter: FilterList) -> String {
        "\(filter.name).txt"
    }

    private static func sanitizedFilenameStem(_ name: String) -> String {
        let safeName = name
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" || character == "_" || character == " " {
                    return character
                }
                return "_"
            }
        let prefix = String(String(safeName).prefix(80))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? "filter" : prefix
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
}

public enum UserScriptMetadataParser {
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

/// Runs an async operation on each item with bounded concurrency, calling `onResult`
/// for each completed result in completion order. Platform-aware default concurrency.
public func boundedConcurrentForEach<Item: Sendable, Result: Sendable>(
    _ items: [Item],
    maxConcurrent: Int? = nil,
    operation: @Sendable @escaping (Item) async -> Result,
    onResult: (Result) async -> Void
) async {
    guard !items.isEmpty else { return }

    let limit: Int
    if let maxConcurrent {
        limit = maxConcurrent
    } else {
        #if os(macOS)
        limit = 3
        #else
        limit = 2
        #endif
    }

    var iterator = items.makeIterator()

    await withTaskGroup(of: Result.self) { group in
        func enqueueNext() {
            guard let item = iterator.next() else { return }
            group.addTask { await operation(item) }
        }

        for _ in 0..<min(limit, items.count) {
            enqueueNext()
        }

        while let result = await group.next() {
            await onResult(result)
            enqueueNext()
        }
    }
}

func measure<T>(label: String, block: () throws -> T) rethrows -> T {
    let start = DispatchTime.now()
    let result = try block()
    let end = DispatchTime.now()
    let elapsedNanoseconds = end.uptimeNanoseconds - start.uptimeNanoseconds
    let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000
    let formattedTime = String(format: "%.3f", elapsedMilliseconds)
    NSLog("[\(label)] Elapsed Time: \(formattedTime) ms")

    return result
}
