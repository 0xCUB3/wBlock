import Foundation

@main struct CloudSyncLocalUserScriptTests {
  static func main() throws {
    // Identity/name decisions and tombstone sets are proven in scripts/proofs.
    // Keep serialization, normalization, restore composition, and preferences here.
    for access in [
      UserScriptSiteAccess(), .init(onlySelectedSites: true), .init(onlySelectedSites: true, hosts: ["example.com"]),
    ] {
      let record = CloudSyncLocalUserScript(
        name: "Scope", content: "source", isEnabled: true, description: "description", siteAccess: access)
      let decoded = try JSONDecoder().decode(CloudSyncLocalUserScript.self, from: JSONEncoder().encode(record))
      precondition(decoded == record)
    }
    let legacy = try JSONDecoder().decode(
      CloudSyncLocalUserScript.self, from: Data(#"{"name":"Legacy Name","content":"source","isEnabled":true}"#.utf8))
    precondition(legacy.description == nil && legacy.siteAccess == nil && legacy.category == nil)
    precondition(legacy.resolvedUpdatesAutomatically && legacy.resolvedCategory == .scripts)
    var existing = UserScript(name: "Old", url: nil, content: "source")
    existing.description = "old"
    for description: String? in [nil, "", "new"] {
      let remote = CloudSyncLocalUserScript(
        name: "Renamed", content: "source", isEnabled: true, description: description)
      let metadata = CloudSyncLocalUserScriptReconciler.metadataOverrides(existing: existing, remote: remote)
      precondition(metadata.name == "Renamed" && metadata.description == (description ?? "old"))
    }
    func record(_ identity: String?, name: String = "Duplicate") -> CloudSyncLocalUserScript {
      .init(name: name, content: identity ?? "source", isEnabled: true, localImportIdentity: identity)
    }
    let a = record("a")
    let b = record("b")
    let named = record(nil, name: "Legacy Name")
    precondition(CloudSyncLocalUserScriptReconciler.normalizedName(" Legacy NAME ") == "legacy name")
    precondition(
      CloudSyncLocalUserScriptReconciler.matches(existing: record("  ", name: "Legacy Name"), remote: legacy))
    for tombNames: Set<String> in [[], ["duplicate"], ["legacy name"]] {
      for tombIDs: Set<String> in [[], ["a"], ["b"]] {
        let candidates = [a, b, named]
        let expected = candidates.filter { r in
          r.localImportIdentity.map { !tombIDs.contains($0) } ?? !tombNames.contains("legacy name")
        }
        precondition(
          CloudSyncLocalUserScriptReconciler.remoteScriptsAllowedAfterTombstones(
            candidates, deletedNames: tombNames, deletedIdentities: tombIDs) == expected)
        precondition(
          CloudSyncLocalUserScriptReconciler.missingRemoteScriptsToRestore(
            remoteScripts: candidates, localScripts: [b], deletedNames: tombNames, deletedIdentities: tombIDs)
            == expected.filter { $0 != b })
      }
    }
    precondition(
      CloudSyncLocalUserScriptReconciler.localScriptsNeverSyncedToUpload(
        localScripts: [a, b], remoteScripts: [b], deletedNames: [], deletedIdentities: [], lastSyncedNames: [],
        lastSyncedIdentities: []) == [a])
    precondition(
      CloudSyncLocalUserScriptReconciler.localScriptsToDeleteDuringRemoteApply(
        localScripts: [a, b], remoteScripts: [b], deletedNames: ["duplicate"], lastSyncedNames: ["duplicate"]
      ).isEmpty)
    let suite = "CloudSyncLocalUserScriptTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    precondition(CloudSyncUserScriptEnabledStatePolicy.syncEnabled(in: defaults))
    for enabled in [true, false] {
      CloudSyncUserScriptEnabledStatePolicy.setSyncEnabled(enabled, in: defaults)
      precondition(CloudSyncUserScriptEnabledStatePolicy.syncEnabled(in: UserDefaults(suiteName: suite)!) == enabled)
    }
    for initial in [true, false] {
      var shared: [String: Bool] = [:]
      for value in [initial, !initial, initial] {
        precondition(
          CloudSyncUserScriptEnabledStatePolicy.projectedState(localValue: value, key: "key", sharedValues: &shared)
            == initial)
      }
      shared["key"] = !initial
      precondition(
        CloudSyncUserScriptEnabledStatePolicy.projectedState(localValue: initial, key: "key", sharedValues: &shared)
          == !initial)
    }
    precondition(
      CloudSyncUserScriptEnabledStatePolicy.localKey(identity: " stable-id ", name: "Renamed")
        == "local-identity:stable-id")
    precondition(
      CloudSyncUserScriptEnabledStatePolicy.localKey(identity: nil, name: " Legacy Name ") == "local-name:legacy name")
    precondition(
      CloudSyncUserScriptEnabledStatePolicy.remoteKey("https://bundled.wblock.invalid/tube-cleaner.user.js")
        == "remote:https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/tube-cleaner/dist/tube-cleaner.user.js"
    )
    precondition(
      CloudSyncUserScriptEnabledStatePolicy.remoteKey(
        "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/grouped/example.user.js") == nil)
    print("PASS: cloud script serialization, restore composition, and preferences")
  }
}
