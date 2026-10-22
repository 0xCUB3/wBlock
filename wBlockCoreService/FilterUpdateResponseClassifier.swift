//
//  FilterUpdateResponseClassifier.swift
//  wBlockCoreService
//
//  Shared response classification for manual and background filter updates.
//

import Foundation

public enum FilterUpdateResponseStatus: Equatable {
    case notModified
    case updatedContent
    case unchangedContent
    case invalidContent
    case unexpectedStatus(Int)
}

public enum FilterUpdateResponseClassifier {
    public static func classify(
        statusCode: Int,
        responseData: Data?,
        localData: Data?
    ) -> FilterUpdateResponseStatus {
        switch statusCode {
        case 304:
            return .notModified
        case 200:
            guard let responseData, looksLikeFilterListData(responseData) else {
                return .invalidContent
            }
            return contentDiffers(remoteData: responseData, localData: localData)
                ? .updatedContent
                : .unchangedContent
        default:
            return .unexpectedStatus(statusCode)
        }
    }

    public static func looksLikeFilterListData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let prefix = data.prefix(2048)
        // A bounded sniff can end inside a UTF-8 scalar. Trim only the incomplete
        // tail; the downloader still validates the complete body before saving it.
        let maxTrim = data.count > prefix.count ? 3 : 0
        guard let text = (0...maxTrim).lazy.compactMap({ trim in
            String(data: prefix.dropLast(trim), encoding: .utf8)
        }).first else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed != "404: not found",
              !trimmed.hasPrefix("<!doctype html"), !trimmed.hasPrefix("<html") else { return false }
        return true
    }

    public static func isRetryable(statusCode: Int) -> Bool {
        statusCode == 403 || statusCode == 404 || statusCode == 408 || statusCode == 429 || statusCode >= 500
    }

    /// Saved lists are normalized (LF line endings, unsupported directives dropped),
    /// so the remote body is compared in that form. Comparing raw bytes reported
    /// every CRLF list as changed whenever the server sent a 200 instead of a 304.
    /// A fallback mirror can lag the primary by a few releases; its older copy
    /// is not an update, or applying it makes the next check offer the newer
    /// one again.
    public static func contentDiffers(remoteData: Data, localData: Data?) -> Bool {
        guard let localData else { return true }
        guard remoteData != localData else { return false }
        let remoteText = String(decoding: remoteData, as: UTF8.self)
        if let remoteVersion = numericVersion(remoteText),
           let localVersion = numericVersion(String(decoding: localData.prefix(16_384), as: UTF8.self)),
           UserScript.isVersionNewer(localVersion, than: remoteVersion) {
            return false
        }
        return Data(FilterListContentProcessing.normalizedContent(from: remoteText).utf8) != localData
    }

    /// Only dotted numbers order reliably; some lists stamp a date instead.
    private static func numericVersion(_ content: String) -> String? {
        guard let version = FilterListContentProcessing.parseMetadata(from: content).version,
              version.split(separator: ".", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        return version
    }
}
