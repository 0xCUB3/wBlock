import Foundation

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

    /// A list after normalization and include expansion, ready to stage.
    private struct ExpandedSource {
        var data: Data
        var filter: FilterList
        let strippedDirectives: [String]
        /// The raw body for uBO-style delta updates. Nil for lists without `! Diff-Path:`.
        let baselineData: Data?
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
        var expanded = try await expandSource(
            data: data, sourceURL: sourceURL, filter: filter,
            urlSession: urlSession, onIncludeFetchError: onIncludeFetchError)
        expanded.filter.etag = etag
        expanded.filter.serverLastModified = lastModified

        let uuid = filter.id.uuidString
        let filename = ContentBlockerIncrementalCache.localFilename(for: filter)
        let fileURL = containerURL.appendingPathComponent(filename)
        let baselineURL = FilterListFetchChain.diffBaselineURL(for: filter, containerURL: containerURL)
        let stagedFileURL = containerURL.appendingPathComponent(
            ".pending-filter-\(uuid)-\(UUID().uuidString).txt",
            isDirectory: false
        )
        // Runs on every exit that does not publish. After a successful publish the
        // staged file has been moved into place, so this is a no-op.
        defer { try? FileManager.default.removeItem(at: stagedFileURL) }
        if filter.isCustom {
            try expanded.data.write(to: stagedFileURL, options: .atomic)
        } else {
            try FilterArtifactStorage.write(expanded.data, to: stagedFileURL)
        }
        let sourceSHA256 = FilterUpdateResponseClassifier.sha256Hex(expanded.data)
        // The staged copy is on disk, so drop the in-memory body before publishing.
        expanded.data = Data()

        let updatedFilter = expanded.filter
        let baselineData = expanded.baselineData
        let strippedDirectives = expanded.strippedDirectives
        let revisionStoreURL = containerURL.appendingPathComponent(
            PendingFilterUpdateRevisions.filename,
            isDirectory: false
        )
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
                    // mmap'd by wbe; replace only by atomic rename
                    _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: stagedFileURL)
                } else {
                    try FileManager.default.moveItem(at: stagedFileURL, to: fileURL)
                }
                if !filter.isCustom { FilterArtifactStorage.excludeFromBackup(fileURL) }
                if let baselineData {
                    do {
                        try FilterArtifactStorage.write(baselineData, to: baselineURL, sharingBlocksWith: fileURL)
                    } catch {
                        try? FileManager.default.removeItem(at: baselineURL)
                    }
                }
            }
        ) != nil else {
            throw ProcessingError.publicationFailed
        }

        return (filter: updatedFilter, strippedDirectives: strippedDirectives)
    }

    /// Decodes, normalizes, and expands includes. The raw and normalized copies
    /// are released as soon as the expanded body exists.
    private static func expandSource(
        data: Data,
        sourceURL: URL,
        filter: FilterList,
        urlSession: URLSession,
        onIncludeFetchError: IncludeResolver.FetchErrorHandler?
    ) async throws -> ExpandedSource {
        guard data.count <= FilterListTooLargeError.maxBytes else {
            throw FilterListTooLargeError(ruleCount: nil)
        }
        guard FilterUpdateResponseClassifier.looksLikeFilterListData(data) else {
            throw ProcessingError.decodingFailed
        }
        let normalized = try normalize(data)
        guard normalized.rawCount <= FilterListTooLargeError.maxRules else {
            throw FilterListTooLargeError(ruleCount: normalized.rawCount)
        }

        let finalContent: String
        if filter.isOptimizedBuiltin {
            finalContent = normalized.content
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
                content: normalized.content,
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
        updatedFilter.rawSourceRuleCount = normalized.rawCount
        updatedFilter.lastUpdated = Date()
        return ExpandedSource(
            data: finalData,
            filter: updatedFilter,
            strippedDirectives: normalized.strippedDirectives,
            // Stored as the raw body, so the delta baseline keeps the exact input bytes.
            baselineData: normalized.hasDiffMetadata ? data : nil
        )
    }

    private static func normalize(
        _ data: Data
    ) throws -> (content: String, rawCount: Int, strippedDirectives: [String], hasDiffMetadata: Bool) {
        guard let rawContent = String(data: data, encoding: .utf8) else {
            throw ProcessingError.decodingFailed
        }
        var strippedDirectives: [String] = []
        let content = FilterListContentProcessing.normalizedContent(from: rawContent) {
            if !strippedDirectives.contains($0) { strippedDirectives.append($0) }
        }
        return (
            content: content,
            rawCount: FilterList.countRules(in: content),
            strippedDirectives: strippedDirectives,
            hasDiffMetadata: FilterDiffUpdater.parseMetadata(from: rawContent) != nil
        )
    }
}
