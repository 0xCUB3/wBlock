import Foundation
internal import SwiftProtobuf

@main
struct Issue742ProvenanceMigrationTests {
    static func main() throws {
        try protobufLegacyUniqueDoesNotPopulateAdmittedCount()
        try protobufAdmittedCountRoundTripsOnNewField()
        try filterListCodableIgnoresLegacyUniqueCount()
        try filterListCodablePersistsAdmittedCountOnlyOnNewKey()
        try backupCustomFilterEntryTreatsMissingProvenanceAsNil()
        print("PASS: issue 742 provenance migration")
    }

    private static func protobufLegacyUniqueDoesNotPopulateAdmittedCount() throws {
        var legacy = Wblock_Data_FilterListData()
        legacy.id = UUID().uuidString
        legacy.name = "Legacy"
        legacy.url = "https://example.com/legacy.txt"
        legacy.category = .custom
        legacy.uniqueRuleCount = 123

        let decoded = try Wblock_Data_FilterListData(serializedBytes: legacy.serializedData())
        guard decoded.hasUniqueRuleCount, decoded.uniqueRuleCount == 123 else {
            fatalError("legacy unique count should remain readable only as the legacy protobuf field")
        }
        guard !decoded.hasAdmittedSourceRuleCount else {
            fatalError("legacy unique count must not populate admitted source provenance")
        }
    }

    private static func protobufAdmittedCountRoundTripsOnNewField() throws {
        var current = Wblock_Data_FilterListData()
        current.id = UUID().uuidString
        current.name = "Current"
        current.url = "https://example.com/current.txt"
        current.category = .privacy
        current.admittedSourceRuleCount = 77

        let decoded = try Wblock_Data_FilterListData(serializedBytes: current.serializedData())
        guard decoded.hasAdmittedSourceRuleCount, decoded.admittedSourceRuleCount == 77 else {
            fatalError("admitted source count should round trip through protobuf field 16")
        }
        guard !decoded.hasUniqueRuleCount else {
            fatalError("new admitted source count must not write legacy unique count field 13")
        }
    }

    private static func filterListCodableIgnoresLegacyUniqueCount() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy Codable",
          "url": "https://example.com/filter.txt",
          "category": "Privacy",
          "isCustom": false,
          "isSelected": true,
          "description": "",
          "version": "",
          "uniqueRuleCount": 456
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(FilterList.self, from: json)
        guard decoded.uniqueRuleCount == nil else {
            fatalError("legacy Codable uniqueRuleCount must decode as nil admitted provenance")
        }
    }

    private static func filterListCodablePersistsAdmittedCountOnlyOnNewKey() throws {
        let filter = FilterList(
            name: "Current Codable",
            url: URL(string: "https://example.com/filter.txt")!,
            category: .ads,
            uniqueRuleCount: 91
        )
        let data = try JSONEncoder().encode(filter)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard object?["admittedSourceRuleCount"] as? Int == 91 else {
            fatalError("FilterList should encode admitted provenance with the new Codable key")
        }
        guard object?["uniqueRuleCount"] == nil else {
            fatalError("FilterList should not encode the legacy uniqueRuleCount key")
        }

        let decoded = try JSONDecoder().decode(FilterList.self, from: data)
        guard decoded.uniqueRuleCount == 91 else {
            fatalError("FilterList should decode admitted provenance from the new Codable key")
        }
    }

    private static func backupCustomFilterEntryTreatsMissingProvenanceAsNil() throws {
        struct CustomFilterEntryProbe: Codable {
            var name: String
            var url: String
            var category: String
            var isSelected: Bool
            var description: String
            var userProvidedName: Bool?
            var userProvidedDescription: Bool?
            var admittedSourceRuleCount: Int?
            var content: String?
        }

        let oldBackupEntry = """
        {
          "name": "Old backup custom list",
          "url": "https://example.com/custom.txt",
          "category": "Custom",
          "isSelected": true,
          "description": "User-added filter list.",
          "userProvidedName": true,
          "userProvidedDescription": false
        }
        """.data(using: .utf8)!
        let decodedOld = try JSONDecoder().decode(CustomFilterEntryProbe.self, from: oldBackupEntry)
        guard decodedOld.admittedSourceRuleCount == nil else {
            fatalError("old backup entries without provenance should restore nil until apply")
        }

        let currentBackupEntry = CustomFilterEntryProbe(
            name: "Current backup custom list",
            url: "https://example.com/custom.txt",
            category: "Custom",
            isSelected: true,
            description: "User-added filter list.",
            userProvidedName: true,
            userProvidedDescription: false,
            admittedSourceRuleCount: 64,
            content: nil
        )
        let encoded = try JSONEncoder().encode(currentBackupEntry)
        let decodedCurrent = try JSONDecoder().decode(CustomFilterEntryProbe.self, from: encoded)
        guard decodedCurrent.admittedSourceRuleCount == 64 else {
            fatalError("backup entries should preserve admitted provenance when present")
        }
    }
}
