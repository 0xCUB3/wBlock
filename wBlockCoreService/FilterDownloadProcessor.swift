import Foundation

public enum FilterDownloadProcessor {
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
        guard FilterUpdateResponseClassifier.looksLikeFilterListData(data),
              let rawContent = String(data: data, encoding: .utf8) else {
            throw ProcessingError.decodingFailed
        }

        var strippedDirectives: [String] = []
        let processedContent = FilterListContentProcessing.stripUnknownDirectives(from: rawContent) {
            strippedDirectives.append($0)
        }
        let rawCount = FilterList.countRules(in: processedContent)

        let finalContent: String
        if filter.isOptimizedBuiltin {
            finalContent = processedContent
        } else {
            let preprocessor = FilterPreprocessor(
                urlSession: urlSession,
                onFetchError: onIncludeFetchError
            )
            finalContent = await preprocessor.preprocess(
                content: processedContent,
                listURL: sourceURL
            )
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
        updatedFilter.rawSourceRuleCount = rawCount
        updatedFilter.lastUpdated = Date()
        updatedFilter.etag = etag
        updatedFilter.serverLastModified = lastModified

        let uuid = filter.id.uuidString
        let filename = ContentBlockerIncrementalCache.localFilename(for: filter)
        let fileURL = containerURL.appendingPathComponent(filename)
        let baselineURL = containerURL.appendingPathComponent("diff-baseline-\(filename)")
        let stagedFileURL = containerURL.appendingPathComponent(
            ".pending-filter-\(uuid)-\(UUID().uuidString).txt",
            isDirectory: false
        )
        try finalData.write(to: stagedFileURL, options: .atomic)

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
            storeURL: revisionStoreURL,
            publish: {
                // Clear stale delta state before exposing a new source. If writing
                // the new baseline later fails, future updates safely use a full fetch.
                if FileManager.default.fileExists(atPath: baselineURL.path) {
                    do {
                        try FileManager.default.removeItem(at: baselineURL)
                    } catch {
                        try Data().write(to: baselineURL, options: .atomic)
                    }
                }
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: stagedFileURL)
                } else {
                    try FileManager.default.moveItem(at: stagedFileURL, to: fileURL)
                }
                if let rawBaselineData {
                    do {
                        try rawBaselineData.write(to: baselineURL, options: .atomic)
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
