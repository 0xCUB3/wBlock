import Foundation
@testable import wBlockCoreService

private func require(_ value: Bool) { precondition(value) }

@main
struct SponsorBlockSettingsTransferTests {
    static func main() async throws {
        typealias Transfer = SponsorBlockSettingsTransfer
        let source = Data(#"{"userID":"PRIVATE-DO-NOT-COPY","payments":{"licenseKey":"LICENSE-SECRET"},"categorySelections":[{"name":"sponsor","option":2},{"name":"intro","option":1},{"name":"outro","option":0},{"name":"poi_highlight","option":1}],"disableSkipping":false,"dontShowNotice":true,"minDuration":3.5,"whitelistedChannels":["UC-example"]}"#.utf8)
        let settings = try Transfer.parse(source)
        require(settings.enabled && !settings.showNotice && settings.minimumDuration == 3.5)
        require(settings.modes["sponsor"] == "auto" && settings.modes["intro"] == "ask")
        require(settings.modes["outro"] == "off" && settings.modes["filler"] == "off")
        require(settings.modes["poi_highlight"] == nil && settings.excludedChannels == ["UC-example"])
        let exported = try Transfer.exportData(settings)
        let text = String(decoding: exported, as: UTF8.self)
        require(!text.contains("PRIVATE") && !text.contains("LICENSE") && !text.contains("userID"))
        require(try Transfer.parse(exported) == settings)
        let modern = try Transfer.parse(Data(#"{"categorySelections":[]}"#.utf8), current: settings)
        require(modern.modes.values.allSatisfy { $0 == "off" })
        require(modern.excludedChannels == settings.excludedChannels)
        print("PASS: upstream mapping, omitted categories, native round-trip and credential stripping")

        for invalid in [
            #"{"userID":"SECRET"}"#, #"{"debug":{},"config":{"categorySelections":[]}}"#,
            #"{"categorySelections":[],"minDuration":-1}"#,
            #"{"categorySelections":[],"minDuration":true}"#,
            #"{"categorySelections":[],"disableSkipping":1}"#,
            #"{"categorySelections":[],"whitelistedChannels":[42]}"#,
            #"{"categorySelections":[{"name":"sponsor","option":9}]}"#,
            #"{"categorySelections":[{"name":"sponsor","option":2},{"name":"sponsor","option":1}]}"#,
            #"{"format":"wblock-sponsorblock-settings","version":2,"settings":{}}"#,
            "[]", "null", "not JSON"
        ] {
            do { _ = try Transfer.parse(Data(invalid.utf8)); fatalError("accepted invalid input") }
            catch {}
        }
        do { _ = try Transfer.parse(Data(repeating: 32, count: Transfer.maximumBytes + 1)); fatalError("accepted oversized input") }
        catch {}
        print("PASS: malformed, unsupported, mistyped and oversized backups rejected")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = UserScriptStorageManager(directoryURL: directory)
        let id = UUID()
        require(try await Transfer.settings(scriptID: id, storage: storage) == nil)
        try await Transfer.persist(settings, scriptID: id, storage: storage)
        let snapshot = await storage.snapshot(for: id.uuidString)
        let raw = snapshot[Transfer.storageKey]!
        require(!raw.contains("PRIVATE") && !raw.contains("LICENSE"))
        require(try JSONDecoder().decode(Transfer.Settings.self, from: Data(raw.utf8)) == settings)
        let secondProcess = UserScriptStorageManager(directoryURL: directory)
        require(try await Transfer.settings(scriptID: id, storage: secondProcess) == settings)
        var edited = settings
        edited.modes["intro"] = "auto"
        let pageJSON = String(decoding: try JSONEncoder().encode(edited), as: UTF8.self)
        let result = await secondProcess.setSerializedValue(pageJSON, forKey: Transfer.storageKey, scriptID: id.uuidString)
        require(result.ok)
        let refreshed = try await Transfer.settings(scriptID: id, storage: storage)!
        require(try Transfer.parse(Transfer.exportData(refreshed)) == edited)
        var invalid = edited
        invalid.minimumDuration = -.infinity
        do { try await Transfer.persist(invalid, scriptID: id, storage: storage); fatalError("persisted invalid settings") }
        catch {}
        require(try await Transfer.settings(scriptID: id, storage: storage) == edited)
        print("PASS: native import -> GM snapshot -> player edit -> refreshed native export; failed writes preserve settings")
    }
}
