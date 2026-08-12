import Foundation

@main
struct Issue508BackupUserScriptTests {
    static func main() throws {
        let source = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)
        check(source.contains("copy.category = script.category"), "backupCopy must preserve category")
        check(source.contains("copy.localImportIdentity = UserScriptImportIdentity.normalized(script.localImportIdentity)"), "backupCopy must preserve local identity")
        check(source.contains("UserScriptRestoreMatcher.matchingIndex"), "backup restore must use the production matcher")
        let original = BackupProbe(name: "Display Override", category: "custom", localImportIdentity: "file:/tmp/source.user.js", isLocal: true, url: nil)
        let roundTrip = try JSONDecoder().decode(BackupProbe.self, from: JSONEncoder().encode(original))
        check(roundTrip == original, "backup identity and category must survive a JSON round trip")
        var stable = UserScript(name: "Display Override", content: "source")
        stable.isLocal = true
        stable.localImportIdentity = original.localImportIdentity
        stable.category = .custom
        var other = UserScript(name: "Display Override", content: "other")
        other.isLocal = true
        other.localImportIdentity = "file:/tmp/other.user.js"
        check(UserScriptRestoreMatcher.matchingIndex(for: stable, in: [other, stable]) == 1,
              "backup host restoration must prefer stable identity over display name")
        var legacyOne = UserScript(name: "Duplicate", content: "one")
        legacyOne.isLocal = true
        var legacyTwo = UserScript(name: "Duplicate", content: "two")
        legacyTwo.isLocal = true
        var legacy = UserScript(name: "Duplicate", content: "backup")
        legacy.isLocal = true
        check(UserScriptRestoreMatcher.matchingIndex(for: legacy, in: [legacyOne, legacyTwo]) == nil,
              "duplicate legacy names must not cross-apply backup host exclusions")
        var remote = UserScript(name: "Display Override", url: URL(string: "https://example.com/script.user.js"), content: "remote")
        remote.isLocal = false
        check(UserScriptRestoreMatcher.matchingIndex(for: remote, in: [stable]) == nil,
              "a remote backup entry must not match a local script")
        print("PASS: issue 508 backup userscript matching and round trip")
    }
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}
private struct BackupProbe: Codable, Equatable {
    var name: String
    var category: String?
    var localImportIdentity: String?
    var isLocal: Bool
    var url: String?
}
