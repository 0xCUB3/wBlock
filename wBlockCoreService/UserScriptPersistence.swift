//
//  UserScriptPersistence.swift
//  wBlockCoreService
//
//  Userscript persistence helpers.
//

import Foundation

/// Merge used by ordinary userscript upserts. Persisted records that are not mentioned
/// by the caller survive, while an explicit enabled-state intent may rebase the matching
/// record's latest value. Concurrent inserts of the same remote URL retain the identity
/// that reached disk first.
enum UserScriptPersistence {
    static func canonicalRemoteURLIdentity(_ rawURL: String, isLocal: Bool) -> String? {
        guard !isLocal else { return nil }
        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              var components = URLComponents(string: trimmedURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty
        else { return nil }

        components.scheme = scheme
        components.host = host
        components.fragment = nil
        if (scheme == "http" && components.port == 80)
            || (scheme == "https" && components.port == 443)
        {
            components.port = nil
        }
        return components.string
    }

    private static func canonicalRemoteURLIdentity(
        _ record: Wblock_Data_UserScriptData
    ) -> String? {
        canonicalRemoteURLIdentity(record.url, isLocal: record.isLocal)
    }

    private static func indexByRemoteURL(
        in records: [Wblock_Data_UserScriptData]
    ) -> [String: Int] {
        var result: [String: Int] = [:]
        for (index, record) in records.enumerated() {
            guard let identity = canonicalRemoteURLIdentity(record), result[identity] == nil else {
                continue
            }
            result[identity] = index
        }
        return result
    }

    static func merge(
        persisted: [Wblock_Data_UserScriptData],
        incoming: [Wblock_Data_UserScriptData],
        explicitEnabledStates: [String: Bool] = [:],
        allowedInsertIDs: Set<String>? = nil
    ) -> [Wblock_Data_UserScriptData] {
        var merged = persisted
        var indexByID = Dictionary(
            merged.enumerated().compactMap { index, record in
                record.id.isEmpty ? nil : (record.id, index)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        var indexByRemoteURL = Self.indexByRemoteURL(in: merged)

        for incomingRecord in incoming where !incomingRecord.id.isEmpty {
            if let index = indexByID[incomingRecord.id] {
                var record = incomingRecord
                if let explicitEnabled = explicitEnabledStates[incomingRecord.id] {
                    record.isEnabled = explicitEnabled
                } else {
                    record.isEnabled = merged[index].isEnabled
                }
                let previousIdentity = canonicalRemoteURLIdentity(merged[index])
                merged[index] = record
                if previousIdentity != canonicalRemoteURLIdentity(record) {
                    // The URL identity moved; rebuild rather than track every alias.
                    indexByRemoteURL = Self.indexByRemoteURL(in: merged)
                }
            } else {
                // An ID omitted from allowedInsertIDs was deleted concurrently. Do not
                // let its URL update another record or resurrect the stale identity.
                guard allowedInsertIDs?.contains(incomingRecord.id) ?? true else { continue }

                if let identity = canonicalRemoteURLIdentity(incomingRecord),
                   let index = indexByRemoteURL[identity]
                {
                    let persistedID = merged[index].id
                    var record = incomingRecord
                    record.id = persistedID
                    if let explicitEnabled = explicitEnabledStates[incomingRecord.id]
                        ?? explicitEnabledStates[persistedID]
                    {
                        record.isEnabled = explicitEnabled
                    } else {
                        record.isEnabled = merged[index].isEnabled
                    }
                    merged[index] = record
                    indexByID[persistedID] = index
                    indexByRemoteURL[identity] = index
                    continue
                }

                var record = incomingRecord
                if let explicitEnabled = explicitEnabledStates[incomingRecord.id] {
                    record.isEnabled = explicitEnabled
                }
                indexByID[incomingRecord.id] = merged.count
                if let identity = canonicalRemoteURLIdentity(record) {
                    indexByRemoteURL[identity] = merged.count
                }
                merged.append(record)
            }
        }

        return merged
    }

    /// Explicit collection replacement used only by reset/restore/removal flows.
    static func replace(
        with incoming: [Wblock_Data_UserScriptData]
    ) -> [Wblock_Data_UserScriptData] {
        incoming
    }
}
