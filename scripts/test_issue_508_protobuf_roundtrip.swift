import Foundation
internal import SwiftProtobuf

@main
struct Issue508ProtobufRoundTripTests {
    static func main() throws {
        var message = Wblock_Data_UserScriptData()
        message.id = UUID().uuidString
        message.name = "Display Override"
        message.isLocal = true
        message.category = .custom
        message.localImportIdentity = "file:/tmp/example.user.js"

        let encoded = try message.serializedData()
        let decoded = try Wblock_Data_UserScriptData(serializedBytes: encoded)

        guard decoded.id == message.id,
              decoded.name == message.name,
              decoded.isLocal,
              decoded.category == .custom,
              decoded.hasLocalImportIdentity,
              decoded.localImportIdentity == message.localImportIdentity
        else {
            fatalError("protobuf round trip did not preserve local import identity and category")
        }

        var filter = Wblock_Data_FilterListData()
        filter.id = UUID().uuidString
        filter.name = "Manual Filter"
        filter.url = "https://example.com/filter.txt"
        filter.category = .custom
        filter.userProvidedName = true
        filter.userProvidedDescription = true

        let decodedFilter = try Wblock_Data_FilterListData(serializedBytes: filter.serializedData())
        guard decodedFilter.userProvidedName,
              decodedFilter.userProvidedDescription,
              decodedFilter.hasUserProvidedName,
              decodedFilter.hasUserProvidedDescription
        else {
            fatalError("protobuf round trip did not preserve custom filter user metadata flags")
        }

        var legacyFilter = Wblock_Data_FilterListData()
        legacyFilter.id = UUID().uuidString
        legacyFilter.name = "Legacy Filter"
        legacyFilter.url = "https://example.com/legacy.txt"
        legacyFilter.category = .custom
        let decodedLegacyFilter = try Wblock_Data_FilterListData(serializedBytes: legacyFilter.serializedData())
        guard !decodedLegacyFilter.hasUserProvidedName,
              !decodedLegacyFilter.hasUserProvidedDescription
        else {
            fatalError("legacy filter protobuf payload unexpectedly gained additive user metadata flags")
        }

        var legacy = Wblock_Data_UserScriptData()
        legacy.id = UUID().uuidString
        legacy.name = "Legacy"
        legacy.isLocal = true
        legacy.category = .unspecified
        let legacyDecoded = try Wblock_Data_UserScriptData(serializedBytes: legacy.serializedData())
        guard !legacyDecoded.hasLocalImportIdentity,
              legacyDecoded.category == .unspecified
        else {
            fatalError("legacy protobuf payload unexpectedly gained additive identity/category state")
        }

        print("PASS: issue 508 protobuf round trip")
    }
}
