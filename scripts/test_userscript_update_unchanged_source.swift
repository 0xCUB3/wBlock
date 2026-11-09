import Foundation
import Network
@testable import wBlockCoreService

// A CDN can keep serving the installed file after .meta.js announces a newer
// version. Updating to identical source must report failure, not success, and a
// real bump must still be saved.
@main
@MainActor
struct UserScriptUpdateUnchangedSourceRegression {
    nonisolated(unsafe) static var servedVersion = "1.0"

    static func main() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                let body = """
                // ==UserScript==
                // @name Update Probe
                // @version \(servedVersion)
                // @match *://*/*
                // ==/UserScript==
                void 0;
                """
                let head = "HTTP/1.1 200 OK\r\nContent-Type: application/javascript\r\n"
                    + "Cache-Control: max-age=300\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        listener.start(queue: .main)
        while (listener.port?.rawValue ?? 0) == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        defer { listener.cancel() }
        let url = URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/probe.user.js")!

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wblock-update-\(UUID())")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("userscripts"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        UserScriptManager.scriptsDirectoryOverrideForTesting = root.appendingPathComponent("userscripts")
        let store = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: root)
        await store.loadData()
        let manager = UserScriptManager.makeIsolatedForTesting(dataManager: store)
        await manager.waitUntilReady()

        let addError = await manager.addUserScript(from: url)
        precondition(addError == nil, "install probe script: \(String(describing: addError))")
        let script = manager.userScripts.first { $0.url == url }!
        precondition(script.version == "1.0")

        let unchanged = await manager.updateUserScript(script, showAlerts: false)
        precondition(!unchanged, "identical source must not be reported as updated")

        servedVersion = "1.1"
        let bumped = await manager.updateUserScript(script, showAlerts: false)
        precondition(bumped, "a real version bump must update")
        precondition(manager.userScript(withId: script.id)?.version == "1.1")
        let restarted = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: root)
        await restarted.loadData()
        precondition(restarted.getUserScripts().first { $0.id == script.id }?.version == "1.1", "persist bump")
        print("PASS: unchanged userscript source is not reported as an update")
    }
}
