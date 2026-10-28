import Foundation
import wBlockCoreService

/// An extension process that loaded the built-in defaults before the user enabled a
/// script in the app must not delete that script's download (#1041).
@main
struct UserScriptStaleExtensionCleanupTests {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-stale-cleanup-\(UUID().uuidString)", isDirectory: true)
        let scripts = root.appendingPathComponent("userscripts", isDirectory: true)
        let data = root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        UserScriptManager.scriptsDirectoryOverrideForTesting = scripts

        func manager() async -> (UserScriptManager, ProtobufDataManager) {
            let dataManager = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: data)
            await dataManager.loadData()
            let manager = UserScriptManager.makeIsolatedForTesting(dataManager: dataManager)
            await manager.waitUntilReady()
            return (manager, dataManager)
        }

        // The extension loads first and sees AdGuard Extra disabled by default.
        let (ext, extData) = await manager()
        let (app, _) = await manager()
        guard let script = app.userScripts.first(where: { $0.name == "AdGuard Extra" }),
              let disabled = app.userScripts.first(where: { $0.name == "Bypass Paywalls Clean" }),
              ext.userScripts.first(where: { $0.id == script.id })?.isEnabled == false
        else { fatalError("both managers must share the seeded AdGuard Extra record") }

        func download(_ script: UserScript) throws -> URL {
            let file = scripts.appendingPathComponent("\(script.id.uuidString).user.js")
            try "// ==UserScript==\n// @name \(script.name)\n// @match *://*/*\n// ==/UserScript==\nvoid 0;\n"
                .write(to: file, atomically: true, encoding: .utf8)
            return file
        }
        let file = try download(script)
        let disabledFile = try download(disabled)
        await app.setUserScript(script, isEnabled: true)

        // Keep the extension's own enabled scripts off the network.
        let now = Int64(Date().timeIntervalSince1970)
        await extData.setScriptLastChecked(Dictionary(
            uniqueKeysWithValues: ext.userScripts.map { ($0.id.uuidString, now) }
        ))
        _ = await ext.autoUpdateEnabledUserScripts(skipFresh: true)

        guard FileManager.default.fileExists(atPath: file.path) else {
            fatalError("stale extension cleanup deleted a script the app enabled")
        }
        guard !FileManager.default.fileExists(atPath: disabledFile.path) else {
            fatalError("cleanup kept the download of a script disabled everywhere")
        }
        print("userscript stale extension cleanup passed")
    }
}
