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
        return String(line[valueRange]).trimmingCharacters(in: .whitespaces)
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

    public static func makeGitflicRequest(
        url: URL,
        etag: String? = nil,
        lastModified: String? = nil,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
        timeout: TimeInterval = 30
    ) -> URLRequest {
        var request = makeConditionalRequest(
            url: url,
            etag: etag,
            lastModified: lastModified,
            cachePolicy: cachePolicy,
            timeout: timeout
        )
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/plain,*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("gitflic.ru", forHTTPHeaderField: "Host")
        request.setValue("https://gitflic.ru", forHTTPHeaderField: "Referer")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("?1", forHTTPHeaderField: "Sec-Fetch-User")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue("max-age=0", forHTTPHeaderField: "Cache-Control")
        return request
    }
}

public enum ContentBlockerIncrementalCache {
    private struct State: Codable {
        var inputSignature: String
        var updatedAt: Int64
    }

    public static func computeInputSignature(
        filters: [FilterList],
        groupIdentifier: String
    ) -> String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }

        var canonical = "count=\(filters.count)\n"
        canonical.reserveCapacity(filters.count * 64)

        for filter in filters {
            let fileMarker = localFileFingerprint(for: filter, containerURL: containerURL)
            canonical.append("\(filter.id.uuidString)|\(fileMarker)\n")
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

        guard filter.isCustom else { return "missing" }
        let legacyURL = containerURL.appendingPathComponent("\(filter.name).txt")
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

    private static func localFilename(for filter: FilterList) -> String {
        if filter.isCustom {
            return "custom-\(filter.id.uuidString).txt"
        }
        return "\(filter.name).txt"
    }

    private static func baseRulesFilename(for targetRulesFilename: String) -> String {
        if targetRulesFilename.lowercased().hasSuffix(".json") {
            let stem = targetRulesFilename.dropLast(5)
            return "\(stem).base.json"
        }
        return "\(targetRulesFilename).base"
    }

    private static func baseAdvancedRulesFilename(for targetRulesFilename: String) -> String {
        "\(baseRulesFilename(for: targetRulesFilename)).advanced.txt"
    }
}

func measure<T>(label: String, block: () -> T) -> T {
    let start = DispatchTime.now()  // Start the timer

    let result = block()  // Execute the code block

    let end = DispatchTime.now()  // End the timer
    let elapsedNanoseconds = end.uptimeNanoseconds - start.uptimeNanoseconds
    let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000  // Convert to milliseconds

    // Pretty print elapsed time
    let formattedTime = String(format: "%.3f", elapsedMilliseconds)
    NSLog("[\(label)] Elapsed Time: \(formattedTime) ms")

    return result
}
