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
