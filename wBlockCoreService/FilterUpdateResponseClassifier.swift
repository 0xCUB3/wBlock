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
        guard let text = String(data: prefix, encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !trimmed.hasPrefix("<!doctype html") && !trimmed.hasPrefix("<html")
    }

    public static func contentDiffers(remoteData: Data, localData: Data?) -> Bool {
        guard let localData else { return true }
        return remoteData != localData
    }
}
