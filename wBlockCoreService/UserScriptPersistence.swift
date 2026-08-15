//
//  UserScriptPersistence.swift
//  wBlockCoreService
//
//  Pure ID-based userscript persistence helpers.
//

import Foundation

/// Pure ID-based merge used by ordinary userscript upserts. Persisted records that are
/// not mentioned by the caller survive, while an explicit enabled-state intent may
/// rebase the matching record's latest value.
enum UserScriptPersistence {
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

        for incomingRecord in incoming where !incomingRecord.id.isEmpty {
            if let index = indexByID[incomingRecord.id] {
                var record = incomingRecord
                if let explicitEnabled = explicitEnabledStates[incomingRecord.id] {
                    record.isEnabled = explicitEnabled
                } else {
                    record.isEnabled = merged[index].isEnabled
                }
                merged[index] = record
            } else {
                guard allowedInsertIDs?.contains(incomingRecord.id) ?? true else { continue }
                var record = incomingRecord
                if let explicitEnabled = explicitEnabledStates[incomingRecord.id] {
                    record.isEnabled = explicitEnabled
                }
                indexByID[incomingRecord.id] = merged.count
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
