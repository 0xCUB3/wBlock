import Foundation
internal import SwiftProtobuf

@main
struct UserScriptPersistenceRaceTests {
    static func main() throws {
        func record(_ id: String, _ enabled: Bool, _ name: String) -> Wblock_Data_UserScriptData {
            var value = Wblock_Data_UserScriptData()
            value.id = id
            value.isEnabled = enabled
            value.name = name
            return value
        }

        let a = record("A", false, "old A")
        let b = record("B", true, "old B")
        let c = record("C", true, "external C")
        let staleMetadata = record("A", true, "new A metadata")
        let merged = UserScriptPersistence.merge(
            persisted: [a, b, c],
            incoming: [staleMetadata],
            explicitEnabledStates: [:]
        )
        guard merged.map(\.id) == ["A", "B", "C"],
              merged.first(where: { $0.id == "C" })?.name == "external C",
              merged.first(where: { $0.id == "A" })?.isEnabled == false,
              merged.first(where: { $0.id == "A" })?.name == "new A metadata"
        else { fatalError("ordinary ID merge lost an external record or enabled state") }

        let explicitlyEnabled = UserScriptPersistence.merge(
            persisted: merged,
            incoming: [staleMetadata],
            explicitEnabledStates: ["A": true]
        )
        guard explicitlyEnabled.first(where: { $0.id == "A" })?.isEnabled == true else {
            fatalError("explicit enable intent did not rebase persisted state")
        }
        let authoritative = UserScriptPersistence.replace(with: [a, b])
        guard authoritative.map(\.id) == ["A", "B"] else {
            fatalError("authoritative replacement did not remove C")
        }

        let manager = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)
        let persistence = try String(contentsOfFile: "wBlockCoreService/ProtobufDataManager+Extensions.swift", encoding: .utf8)
        let handler = try String(contentsOfFile: "wBlockCoreService/WebExtensionRequestHandler.swift", encoding: .utf8)
        guard persistence.contains("public func replaceUserScripts"),
              persistence.contains("public func removeUserScript(withId id: UUID)"),
              manager.contains("dataManager.removeUserScript(withId: removedScript.id)"),
              handler.contains("let payloadMutationRevision = userScriptManager.payloadMutationRevision"),
              handler.contains("guard payloadMutationRevision == userScriptManager.payloadMutationRevision else"),
              manager.contains("payloadMutationRevision &+= 1"),
              persistence.contains("userScriptsAreAuthoritative: true"),
              handler.contains("error: \"userscript-state-changed\""),
              handler.contains("private static let documentStartCacheAllowed = false")
        else { fatalError("authoritative deletion or payload revision contract is missing") }

        print("PASS: userscript persistence race contracts")
    }
}
