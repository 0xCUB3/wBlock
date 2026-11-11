import Foundation
import CryptoKit

/// A list too big to convert. The engine needs about 1.4 GB per million
/// rules, so a 40-million-rule list got the app killed, and Safari holds
/// 150,000 rules per blocker anyway. Refused before decoding when the body
/// alone is too big, so the download can't exhaust memory either.
public struct FilterListTooLargeError: Error, Equatable {
    public static let maxBytes = 64 << 20
    public static let maxRules = 1_000_000
    /// Rules all selected lists may add up to before Apply refuses, well
    /// past real setups and short of what the device's memory can't hold.
    #if os(iOS)
    public static let maxApplyRules = 2_000_000
    #else
    public static let maxApplyRules = 4_000_000
    #endif
    /// Nil when the body was refused by size before its rules were counted.
    public let ruleCount: Int?
}

public enum FilterDownloadProcessor {
    private actor IncludeFailureTracker {
        private(set) var failed = false

        func markFailed() {
            failed = true
        }
    }

    private enum ProcessingError: Error {
        case invalidContent
        case decodingFailed
        case publicationFailed
    }

    public static func processAndPublish(
        data: Data,
        sourceURL: URL,
        filter: FilterList,
        containerURL: URL,
        etag: String?,
        lastModified: String?,
        urlSession: URLSession,
        onIncludeFetchError: IncludeResolver.FetchErrorHandler? = nil
    ) async throws -> (filter: FilterList, strippedDirectives: [String]) {
        guard data.count <= FilterListTooLargeError.maxBytes else {
            throw FilterListTooLargeError(ruleCount: nil)
        }
        guard FilterUpdateResponseClassifier.looksLikeFilterListData(data),
              let rawContent = String(data: data, encoding: .utf8) else {
            throw ProcessingError.decodingFailed
        }

        var strippedDirectives: [String] = []
        let processedContent = FilterListContentProcessing.normalizedContent(from: rawContent) {
            if !strippedDirectives.contains($0) { strippedDirectives.append($0) }
        }
        let rawCount = FilterList.countRules(in: processedContent)
        guard rawCount <= FilterListTooLargeError.maxRules else {
            throw FilterListTooLargeError(ruleCount: rawCount)
        }

        let finalContent: String
        if filter.isOptimizedBuiltin {
            finalContent = processedContent
        } else {
            let includeFailureTracker = IncludeFailureTracker()
            let preprocessor = FilterPreprocessor(
                urlSession: urlSession,
                onFetchError: { url, statusCode in
                    await includeFailureTracker.markFailed()
                    await onIncludeFetchError?(url, statusCode)
                }
            )
            finalContent = await preprocessor.preprocess(
                content: processedContent,
                listURL: sourceURL
            )
            try Task.checkCancellation()
            guard !(await includeFailureTracker.failed) else {
                throw ProcessingError.invalidContent
            }
        }

        try Task.checkCancellation()
        guard FilterListContentValidator.appearsToBeFilterList(finalContent),
              let finalData = finalContent.data(using: .utf8) else {
            throw ProcessingError.invalidContent
        }

        let metadata = FilterListContentProcessing.parseMetadata(
            from: finalContent,
            sanitize: true
        )
        var updatedFilter = FilterListRemoteMetadataPolicy.applying(
            title: metadata.title,
            description: metadata.description,
            version: metadata.version,
            to: filter
        )
        updatedFilter.sourceRuleCount = FilterList.countRules(in: finalContent)
        updatedFilter.sourceSizeBytes = finalData.count
        updatedFilter.rawSourceRuleCount = rawCount
        updatedFilter.lastUpdated = Date()
        updatedFilter.etag = etag
        updatedFilter.serverLastModified = lastModified

        let uuid = filter.id.uuidString
        let filename = ContentBlockerIncrementalCache.localFilename(for: filter)
        let fileURL = containerURL.appendingPathComponent(filename)
        let baselineURL = FilterListFetchChain.diffBaselineURL(for: filter, containerURL: containerURL)
        let stagedFileURL = containerURL.appendingPathComponent(
            ".pending-filter-\(uuid)-\(UUID().uuidString).txt",
            isDirectory: false
        )
        if filter.isCustom {
            try finalData.write(to: stagedFileURL, options: .atomic)
        } else {
            try FilterArtifactStorage.write(finalData, to: stagedFileURL)
        }
        let sourceSHA256 = SHA256.hash(data: finalData).map { String(format: "%02x", $0) }.joined()

        let revisionStoreURL = containerURL.appendingPathComponent(
            PendingFilterUpdateRevisions.filename,
            isDirectory: false
        )
        let rawBaselineData = FilterDiffUpdater.parseMetadata(from: rawContent) == nil
            ? nil
            : Data(rawContent.utf8)
        guard PendingFilterUpdateRevisions.markDownloaded(
            filterID: uuid,
            etag: etag,
            lastModified: lastModified,
            version: updatedFilter.version.isEmpty ? nil : updatedFilter.version,
            sourceSHA256: sourceSHA256,
            sourceFilename: filename,
            stagedFilename: stagedFileURL.lastPathComponent,
            storeURL: revisionStoreURL,
            publish: {
                // Clear stale delta state before exposing a new source. If writing
                // the new baseline later fails, future updates safely use a full fetch.
                if FileManager.default.fileExists(atPath: baselineURL.path) {
                    do {
                        try FileManager.default.removeItem(at: baselineURL)
                    } catch {
                        try FilterArtifactStorage.write(Data(), to: baselineURL)
                    }
                }
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: stagedFileURL)
                } else {
                    try FileManager.default.moveItem(at: stagedFileURL, to: fileURL)
                }
                if !filter.isCustom { FilterArtifactStorage.excludeFromBackup(fileURL) }
                if let rawBaselineData {
                    do {
                        try FilterArtifactStorage.write(rawBaselineData, to: baselineURL, sharingBlocksWith: fileURL)
                    } catch {
                        try? FileManager.default.removeItem(at: baselineURL)
                    }
                }
            }
        ) != nil else {
            try? FileManager.default.removeItem(at: stagedFileURL)
            throw ProcessingError.publicationFailed
        }

        return (filter: updatedFilter, strippedDirectives: strippedDirectives)
    }
}
