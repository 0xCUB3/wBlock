//
//  Utils.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 29/01/2025.
//

import Dispatch
import Foundation

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
