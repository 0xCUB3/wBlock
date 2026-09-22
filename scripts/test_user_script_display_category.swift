import Foundation
internal import SwiftProtobuf
import wBlockCoreService

@main
struct UserScriptDisplayCategoryTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func main() async throws {
        check(UserScriptDisplayCategory.allCases == [.blocking, .functionality, .experimental, .appearance, .other], "display order")
        check(UserScriptDisplayCategorySupport.category(isUserStyle: false, builtInRole: .functionality, persistedCategory: .scripts, isBeta: true) == .experimental, "beta default")
        check(UserScriptDisplayCategorySupport.category(isUserStyle: false, builtInRole: .functionality, persistedCategory: .scriptBlocking, isBeta: true) == .blocking, "explicit category overrides beta default")
        check(UserScriptDisplayCategorySupport.category(isUserStyle: false, builtInRole: .blocking, persistedCategory: .scriptExperimental) == .experimental, "explicit Experimental category")
        check(UserScriptDisplayCategorySupport.category(isUserStyle: true, builtInRole: nil, persistedCategory: .scripts, isBeta: true) == .appearance, "userstyle default remains Appearance")
        check(UserScriptDisplayCategorySupport.category(isUserStyle: false, builtInRole: nil, persistedCategory: .scripts) == .other, "custom default remains Other")
        check(FilterListCategory.scriptExperimental.isUserScriptOnly && !FilterListCategory.experimental.isUserScriptOnly, "script category must not leak into filter categories")
        let rawCases = FilterListCategory.allCases
        for category in rawCases {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(FilterListCategory.self, from: data)
            check(decoded == category, "JSON round trip for \(category)")
        }

        let protobufCases: [(FilterListCategory, Wblock_Data_FilterListCategory, String)] = [
            (.scripts, .scripts, "FILTER_LIST_CATEGORY_SCRIPTS"),
            (.scriptBlocking, .scriptBlocking, "FILTER_LIST_CATEGORY_SCRIPT_BLOCKING"),
            (.scriptFunctionality, .scriptFunctionality, "FILTER_LIST_CATEGORY_SCRIPT_FUNCTIONALITY"),
            (.scriptAppearance, .scriptAppearance, "FILTER_LIST_CATEGORY_SCRIPT_APPEARANCE"),
            (.scriptOther, .scriptOther, "FILTER_LIST_CATEGORY_SCRIPT_OTHER"),
            (.scriptExperimental, .scriptExperimental, "FILTER_LIST_CATEGORY_SCRIPT_EXPERIMENTAL")
        ]
        for (category, protoCategory, protoName) in protobufCases {
            var record = Wblock_Data_UserScriptData()
            record.id = UUID().uuidString
            record.name = "category test"
            record.category = protoCategory
            let binary = try record.serializedData()
            let binaryDecoded = try Wblock_Data_UserScriptData(serializedBytes: binary)
            check(binaryDecoded.category == protoCategory, "protobuf binary round trip for \(category)")
            let json = try record.jsonString()
            check(json.contains("\"category\":\"\(protoName)\""),
                  "protobuf JSON uses the canonical name for \(category): \(json)")
            let jsonDecoded = try Wblock_Data_UserScriptData(jsonString: json)
            check(jsonDecoded.category == protoCategory, "protobuf JSON round trip for \(category)")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "wblock-category-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let manager = ProtobufDataManager.makeIsolatedForTesting(
            dataDirectoryURL: directory, standardDefaults: defaults, groupDefaults: defaults
        )
        var script = UserScript(name: "Experimental", url: URL(string: "https://example.com/experimental.js"))
        script.category = .scriptExperimental
        let saved = await manager.updateUserScripts([script])
        check(saved, "persist category")
        let reloaded = ProtobufDataManager.makeIsolatedForTesting(
            dataDirectoryURL: directory, standardDefaults: defaults, groupDefaults: defaults
        )
        _ = await reloaded.refreshFromDiskIfModified(forceRead: true)
        check(reloaded.getUserScripts().first?.category == .scriptExperimental, "disk persistence")
        print("PASS — category raw, binary/JSON protobuf, and disk persistence")
    }

}
