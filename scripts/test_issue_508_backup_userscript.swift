#!/usr/bin/env swift

import Foundation

struct BackupProbe: Codable, Equatable {
    var name: String
    var category: String?
    var localImportIdentity: String?
    var isLocal: Bool
    var url: String?
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let source = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)
check(source.contains("copy.category = script.category"), "backupCopy must preserve category")
check(source.contains("copy.localImportIdentity = UserScriptImportIdentity.normalized(script.localImportIdentity)"), "backupCopy must preserve local identity")
check(source.contains("localImportIdentity) == restoredIdentity"), "restore must prefer stable local identity")
check(source.contains("guard script.isLocal else { return false }"), "local restore matching must exclude remote scripts")

let original = BackupProbe(
    name: "Display Override",
    category: "custom",
    localImportIdentity: "file:/tmp/source.user.js",
    isLocal: true,
    url: nil
)
let roundTrip = try JSONDecoder().decode(BackupProbe.self, from: JSONEncoder().encode(original))
check(roundTrip == original, "backup identity and category must survive a JSON round trip")

let replacement = BackupProbe(
    name: "Source Name",
    category: nil,
    localImportIdentity: original.localImportIdentity,
    isLocal: true,
    url: nil
)
check(replacement.localImportIdentity == original.localImportIdentity,
      "a changed metadata/display name must still select the same local import")
let remote = BackupProbe(
    name: original.name,
    category: "scripts",
    localImportIdentity: original.localImportIdentity,
    isLocal: false,
    url: "https://example.com/script.user.js"
)
check(!(remote.isLocal && remote.localImportIdentity == replacement.localImportIdentity),
      "a remote script must not collide with a local identity")

print("PASS: issue 508 backup userscript round trip and replacement")
