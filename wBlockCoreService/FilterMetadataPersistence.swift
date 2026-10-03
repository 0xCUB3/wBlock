import Foundation

extension Date {
    /// Whole epoch seconds, or 0 when a corrupt stored date is outside Int64.
    var epochSeconds: Int64 { Int64(exactly: timeIntervalSince1970.rounded(.towardZero)) ?? 0 }
}

/// An operation owns only its metadata delta, never configuration or membership.
enum FilterMetadataPersistence {
    static func merge(_ updates: [FilterList], baseline: [FilterList], into records: inout [Wblock_Data_FilterListData]) {
        let byID = Dictionary(updates.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { _, last in last })
        let baselineByID = Dictionary(baseline.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { _, last in last })
        for index in records.indices {
            var record = records[index]
            guard let update = byID[record.id], let original = baselineByID[record.id],
                  record.url == update.url.absoluteString, original.url == update.url else { continue }
            // Missing ownership flags have no opinion about remotely supplied text.
            if record.isCustom, record.hasUserProvidedName, !record.userProvidedName,
               !update.hasUserProvidedName, update.name != original.name {
                record.name = update.name
            }
            if record.isCustom, record.hasUserProvidedDescription, !record.userProvidedDescription,
               !update.hasUserProvidedDescription, update.description != original.description {
                record.description_p = update.description
            }
            if update.version != original.version { record.version = update.version }
            if update.sourceRuleCount != original.sourceRuleCount {
                if let count = update.sourceRuleCount { record.sourceRuleCount = Int32(count) }
                else { record.clearSourceRuleCount() }
            }
            if update.lastUpdated != original.lastUpdated, let date = update.lastUpdated {
                record.lastUpdated = date.epochSeconds
            }
            if update.uniqueRuleCount != original.uniqueRuleCount {
                if let count = update.uniqueRuleCount { record.admittedSourceRuleCount = Int32(count) }
                else { record.clearAdmittedSourceRuleCount() }
            }
            records[index] = record
        }
    }
}
