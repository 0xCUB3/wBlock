import Foundation

/// A download owns metadata, never the user's configuration or the collection's membership.
enum FilterMetadataPersistence {
    static func merge(_ downloads: [FilterList], into records: inout [Wblock_Data_FilterListData]) {
        let byID = Dictionary(downloads.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { _, last in last })
        for index in records.indices {
            var record = records[index]
            guard let download = byID[record.id], record.url == download.url.absoluteString else { continue }
            // Missing ownership flags belong to legacy records. Keep their titles
            // until the ordinary migration/save path has resolved those flags.
            if record.isCustom, record.hasUserProvidedName, !record.userProvidedName,
               !download.hasUserProvidedName {
                record.name = download.name
            }
            if record.isCustom, record.hasUserProvidedDescription, !record.userProvidedDescription,
               !download.hasUserProvidedDescription {
                record.description_p = download.description
            }
            record.version = download.version
            if let count = download.sourceRuleCount { record.sourceRuleCount = Int32(count) }
            else { record.clearSourceRuleCount() }
            if let count = download.uniqueRuleCount { record.admittedSourceRuleCount = Int32(count) }
            else { record.clearAdmittedSourceRuleCount() }
            record.lastUpdated = Int64(Date().timeIntervalSince1970)
            records[index] = record
        }
    }
}
