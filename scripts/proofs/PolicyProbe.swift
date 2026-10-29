import Foundation
import wBlockCoreService

// Compile this alongside app policy sources and link the real core framework.
// JSON is just transport; every operation below calls the production API.
typealias Values = [String: Any]
extension Dictionary where Key == String, Value == Any {
  func b(_ key: String) -> Bool { self[key] as! Bool }
  func n(_ key: String) -> Int { (self[key] as! NSNumber).intValue }
}

@main struct PolicyProbe {
  @MainActor static func main() throws {
    var pinned = FilterList(name: "pinned", url: URL(string: "https://example.com/list")!, category: .ads)
    pinned.updatesAutomatically = false
    let encoded = try JSONEncoder().encode(pinned)
    let decoded = try JSONDecoder().decode(FilterList.self, from: encoded)
    precondition(!decoded.updatesAutomatically)
    var legacy = try JSONSerialization.jsonObject(with: encoded) as! Values
    legacy.removeValue(forKey: "updatesAutomatically")
    let legacyDecoded = try JSONDecoder().decode(FilterList.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(legacyDecoded.updatesAutomatically)
    let requests =
      try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
      as! [Values]
    let results = requests.map { request -> Any in
      let suite = request["suite"] as! String
      let values = request["values"] as? [Values] ?? []
      let url = "https://example.com/item"
      func urls(_ e: Values, _ key: String) -> Set<String> { e.b(key) ? [url] : [] }
      switch suite {
      case "menus":
        return values.map { e -> Values in
          let source =
            e.b("remote") ? "https://example.com/list" : e.b("inline") ? "wblock://userlist/local" : "file:///list"
          let list = FilterList(name: "List", url: URL(string: source)!, category: .foreign, isCustom: e.b("custom"))
          let filterActions = ContextMenuActionAvailability.filterActions(for: list, isDownloaded: e.b("downloaded"))
          for category in FilterListCategory.allCases {
            var candidate = list
            candidate.category = category
            precondition(ContextMenuActionAvailability.filterActions(for: candidate, isDownloaded: e.b("downloaded")) == filterActions)
          }
          return [
            "filter": filterActions.map(\.rawValue),
            "script": ContextMenuActionAvailability.userScriptActions(
              isBuiltIn: e.b("builtIn"), isLocal: e.b("local"), isDownloaded: e.b("downloaded")
            ).map(\.rawValue),
          ]
        }
      case "refresh":
        let lists = values.enumerated().map { i, e -> FilterList in
          var f = FilterList(
            name: String(i), url: URL(string: e.b("remote") ? "https://example.com/\(i)" : "wblock://userlist/\(i)")!,
            category: .ads)
          f.updatesAutomatically = e.b("automatic")
          f.lastUpdated = e.b("hasDownload") ? Date(timeIntervalSince1970: Double(e.n("download"))) : nil
          return f
        }
        let first = values[0]
        let byID = Dictionary(uniqueKeysWithValues: zip(lists.map(\.id), values))
        let result = FilterRefreshPlanner.filtersRequiringNetworkRefresh(
          lists, fileExists: { byID[$0.id]!.b("exists") },
          lastSuccessfulCheck: first.b("hasGlobal") ? Date(timeIntervalSince1970: Double(first.n("global"))) : nil,
          lastChecked: { f in
            let e = byID[f.id]!
            return e.b("hasCheck") ? Date(timeIntervalSince1970: Double(e.n("check"))) : nil
          },
          interval: Double(first.n("interval")), now: Date(timeIntervalSince1970: Double(first.n("now"))))
        return result.map { Int($0.name)! }
      case "custom", "remote":
        return values.map { e -> Values in
          if suite == "custom" {
            return [
              "upload": CloudSyncCustomFilterReconciler.deletedURLsToMergeDuringUploadReconciliation(
                remoteDeletedURLs: urls(e, "tomb"), localCustomURLs: urls(e, "local")
              ).contains(url),
              "apply": CloudSyncCustomFilterReconciler.deletedURLsToMergeDuringRemoteApply(
                remoteDeletedURLs: urls(e, "tomb"), remoteCustomURLs: urls(e, "remote"),
                localCustomURLs: urls(e, "local")
              ).contains(url),
              "remove": CloudSyncCustomFilterReconciler.tombstonedURLsToDelete(
                tombstonedURLs: urls(e, "tomb"), snapshotCustomURLs: urls(e, "existed"),
                liveCustomURLs: urls(e, "local")
              ).contains(url),
              "clear": CloudSyncCustomFilterReconciler.deletedURLsToClearDuringReconciliation(
                existingDeletedURLMarkers: e.b("tomb") ? [url: Double(e.n("deletedAt"))] : [:],
                remoteCustomURLs: urls(e, "remote"), localCustomURLs: urls(e, "local"),
                remoteUpdatedAt: Double(e.n("remoteAt"))
              ).contains(url),
            ]
          }
          return [
            "upload": CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringUploadReconciliation(
              remoteDeletedURLs: urls(e, "tomb"), localRemoteScriptURLs: urls(e, "local"),
              locallyAddedURLs: urls(e, "added")
            ).contains(url),
            "apply": CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringRemoteApply(
              remoteDeletedURLs: urls(e, "tomb"), remoteRemoteScriptURLs: urls(e, "remote"),
              localRemoteScriptURLs: urls(e, "local"), locallyAddedURLs: urls(e, "added")
            ).contains(url),
            "clearUpload": CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringUploadReconciliation(
              existingDeletedURLs: urls(e, "tomb"), localRemoteScriptURLs: urls(e, "local"),
              locallyAddedURLs: urls(e, "added")
            ).contains(url),
            "clearApply": CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringReconciliation(
              existingDeletedURLs: urls(e, "tomb"), remoteRemoteScriptURLs: urls(e, "remote"),
              localRemoteScriptURLs: urls(e, "local"), locallyAddedURLs: urls(e, "added")
            ).contains(url),
            "keepAdd": !CloudSyncRemoteUserScriptReconciler.additionsAfterAcknowledging(
              current: [url: String(e.n("generation"))], snapshot: [url: String(e.n("snapshot"))],
              syncedURLs: urls(e, "synced")
            ).isEmpty,
          ]
        }
      case "rebase":
        let snapshots = values.enumerated().map { i, e -> FilterList in
          var f = FilterList(
            name: "snapshot-\(i)", url: URL(string: "https://example.com/\(i)")!, category: .ads, isSelected: true,
            description: "snapshot-\(i)", hasUserProvidedName: e.b("oldName"),
            hasUserProvidedDescription: e.b("oldDescription"))
          f.version = "downloaded"
          return f
        }
        let persisted = zip(snapshots, values).compactMap { f, e -> FilterList? in
          guard e.b("persisted") else { return nil }
          var f = f
          f.name = "persisted"
          f.description = "persisted"
          f.isSelected = e.b("selected")
          f.updatesAutomatically = e.b("automatic")
          f.category = .security
          f.excludedSites = ["excluded.test"]
          f.selectedSites = ["selected.test"]
          f.onlySelectedSites = e.b("onlySelected")
          f.hasUserProvidedName = e.b("newName")
          f.hasUserProvidedDescription = e.b("newDescription")
          return f
        }
        // Duplicate snapshots collapse, while the newest persisted duplicate wins.
        let result = FilterSelectionRebaser.rebaseSelection(
          snapshot: snapshots + [snapshots[0]],
          latestPersisted: snapshots.filter { f in persisted.contains { $0.id == f.id } } + persisted)
        return result.map { f -> Values in
          [
            "name": f.name, "description": f.description, "selected": f.isSelected, "automatic": f.updatesAutomatically,
            "nameFlag": f.hasUserProvidedName, "descriptionFlag": f.hasUserProvidedDescription,
            "onlySelected": f.onlySelectedSites,
            "category": f.category == .security, "excluded": f.excludedSites, "sites": f.selectedSites,
            "version": f.version, "url": f.url.absoluteString,
          ]
        }
      case "local":
        return values.map { e -> Values in
          let local = CloudSyncLocalUserScript(
            name: e.b("validName") ? "Item" : "  ", content: "local", isEnabled: true,
            localImportIdentity: e.b("identity") ? "id" : nil)
          let remote = CloudSyncLocalUserScript(
            name: e.b("sameName") ? local.name : "different", content: "remote", isEnabled: false,
            localImportIdentity: e.b("remoteIdentity") ? (e.b("sameIdentity") ? "id" : "other") : nil)
          let remoteScripts = e.b("remotePresent") ? [remote] : []
          func names(_ k: String) -> Set<String> { e.b(k) ? ["item"] : [] }
          func identities(_ k: String) -> Set<String> { e.b(k) ? ["id"] : [] }
          return [
            "matches": e.b("remotePresent")
              && CloudSyncLocalUserScriptReconciler.matches(existing: local, remote: remote),
            "remove": !CloudSyncLocalUserScriptReconciler.localScriptsToDeleteDuringRemoteApply(
              localScripts: [local], remoteScripts: remoteScripts, deletedNames: names("tombName"),
              lastSyncedNames: names("syncedName"), deletedIdentities: identities("tombIdentity"),
              lastSyncedIdentities: identities("syncedIdentity")
            ).isEmpty,
            "upload": !CloudSyncLocalUserScriptReconciler.localScriptsNeverSyncedToUpload(
              localScripts: [local], remoteScripts: remoteScripts, deletedNames: names("tombName"),
              deletedIdentities: identities("tombIdentity"), lastSyncedNames: names("syncedName"),
              lastSyncedIdentities: identities("syncedIdentity")
            ).isEmpty,
          ]
        }
      case "localSets":
        return values.map { e -> [Values] in
          let script = CloudSyncLocalUserScript(name: "Item", content: "", isEnabled: true, localImportIdentity: "item")
          func names(_ k: String) -> Set<String> { e.b(k) ? ["item"] : [] }
          let locals = e.b("local") ? [script] : []
          let remotes = e.b("remote") ? [script] : []
          return [
            [
              "clearUpload": CloudSyncLocalUserScriptReconciler.deletedNamesToClearDuringUploadReconciliation(
                existingDeletedNames: names("tomb"), localNames: locals.map(\.name)
              ).contains("item"),
              "mergeUpload": CloudSyncLocalUserScriptReconciler.deletedNamesToMergeDuringUploadReconciliation(
                remoteDeletedNames: names("tomb"), localNames: locals.map(\.name)
              ).contains("item"),
              "mergeApply": CloudSyncLocalUserScriptReconciler.deletedNamesToMergeDuringRemoteApply(
                remoteDeletedNames: names("tomb"), remoteLocalScripts: remotes, localNames: locals.map(\.name)
              ).contains("item"),
              "clearApply": CloudSyncLocalUserScriptReconciler.deletedNamesToClearDuringReconciliation(
                existingDeletedNames: names("tomb"), remoteLocalScripts: remotes, localNames: locals.map(\.name),
                remoteDeletedNames: names("remoteTomb")
              ).contains("item"),
            ],
            [
              "clearUpload": CloudSyncLocalUserScriptReconciler.deletedIdentitiesToClearDuringUploadReconciliation(
                existingDeletedIdentities: names("tomb"), localScripts: locals
              ).contains("item"),
              "mergeUpload": CloudSyncLocalUserScriptReconciler.deletedIdentitiesToMergeDuringUploadReconciliation(
                remoteDeletedIdentities: names("tomb"), localScripts: locals
              ).contains("item"),
              "mergeApply": CloudSyncLocalUserScriptReconciler.deletedIdentitiesToMergeDuringRemoteApply(
                remoteDeletedIdentities: names("tomb"), remoteLocalScripts: remotes, localScripts: locals
              ).contains("item"),
              "clearApply": CloudSyncLocalUserScriptReconciler.deletedIdentitiesToClearDuringReconciliation(
                existingDeletedIdentities: names("tomb"), remoteLocalScripts: remotes, localScripts: locals,
                remoteDeletedIdentities: names("remoteTomb")
              ).contains("item"),
            ],
          ]
        }
      case "upload":
        var coordinator = CloudSyncUploadCoordinator()
        return values.map { e -> [Int] in
          if e.b("take") { return [2, coordinator.takeDeferredTrigger().flatMap(Int.init).map { $0 + 1 } ?? 0] }
          switch coordinator.actionForUploadRequest(trigger: String(e.n("trigger")), isSyncing: e.b("syncing")) {
          case .deferUntilIdle: return [1, 0]
          case .startNow(let trigger): return [0, Int(trigger)! + 1]
          @unknown default: preconditionFailure("unknown upload action")
          }
        }
      case "revisions":
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = directory.appendingPathComponent(PendingFilterUpdateRevisions.filename)
        defer { try? FileManager.default.removeItem(at: directory) }
        var snapshot: [String: String] = [:]
        return values.map { e -> [[Int]] in
          let key = String(e.n("key"))
          switch e.n("op") {
          case 0:
            precondition(
              PendingFilterUpdateRevisions.markDownloaded(
                filterID: key, token: String(e.n("token") + 1), storeURL: store) != nil)
          case 1:
            snapshot[key] =
              PendingFilterUpdateRevisions.snapshot(filterIDs: [key], storeURL: store).tokensByFilterID[key]
          default: PendingFilterUpdateRevisions.acknowledge(.init(tokensByFilterID: snapshot), storeURL: store)
          }
          let current = PendingFilterUpdateRevisions.load(storeURL: store)
          return [
            (0..<3).map { current[String($0)].flatMap { Int($0.token) } ?? 0 },
            (0..<3).map { snapshot[String($0)].flatMap(Int.init) ?? 0 },
          ]
        }
      case "rail":
        let vm = ApplyChangesViewModel()
        vm.beginProgressRun()
        let phases = ApplyChangesPhase.allCases
        let statuses: [ApplyChangesPhaseStatus] = [.pending, .active, .complete, .failed]
        return values.map { e -> Values in
          vm.updateCurrentFilter("filter")
          vm.updateCurrentScript("script")
          let done = e.b("complete")
          switch e.n("op") {
          case 1: vm.markFailed(message: "failed")
          case 2: vm.markFinished()
          case 3: vm.beginProgressRun()
          default:
            switch e.n("phase") {
            case 0: vm.updatePhaseCompletion(updating: !done, scripts: done)
            case 1: vm.updatePhaseCompletion(reading: done)
            case 2: vm.updatePhaseCompletion(converting: done)
            case 3: vm.updatePhaseCompletion(reloading: done)
            default: vm.updatePhaseCompletion(saving: done)
            }
          }
          let presentation = ApplyProgressPresentation.make(from: vm.state)
          precondition(presentation.nodes.map(\.phase) == phases)
          return [
            "phases": vm.state.phases.map { statuses.firstIndex(of: $0.status)! },
            "failed": presentation.isFailed,
            "focus": phases.firstIndex(of: ApplyProgressPresentation.focusedStep(in: vm.state)!.phase)!,
            "cleared": vm.state.currentFilterName.isEmpty && vm.state.currentScriptName.isEmpty,
          ]
        }
      default: preconditionFailure("unknown policy suite \(suite)")
      }
    }
    try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]).write(
      to: URL(fileURLWithPath: CommandLine.arguments[2]))
  }
}
