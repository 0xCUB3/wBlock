import AppKit
import Foundation
import wBlockCoreService

// Compile this alongside app policy sources and link the real core framework.
// JSON is just transport; every operation below calls the production API.
typealias Values = [String: Any]
extension Dictionary where Key == String, Value == Any {
  func b(_ key: String) -> Bool { self[key] as! Bool }
  func n(_ key: String) -> Int { (self[key] as! NSNumber).intValue }
}

final class ResumeCount: @unchecked Sendable { var count = 0 }

@main struct PolicyProbe {
  @MainActor static func main() async throws {
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
    var pauseStore: [Int: [[Int]]] = [:]
    for (index, request) in requests.enumerated() where request["suite"] as? String == "pauseStore" {
      pauseStore[index] = await PauseStoreTrace.run(request["values"] as? [Values] ?? [])
    }
    let results = requests.enumerated().map { index, request -> Any in
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
      case "twoSyncs":
        // One built-in list at `current`; `old` is a moved list's address only 3.x uses, which this device leaves out.
        let current = "https://example.com/current", old = "https://example.com/old"
        let canonicalize = { (u: String) in u == old ? current : u }
        let reconcile = { (_: String) in false }
        func payload(_ named: Bool, _ selected: Bool) -> (selected: [String], known: [String]?) {
          let address = named ? current : old
          return (selected ? [address] : [], [address])
        }
        return values.map { e -> Values in
          let previous = payload(e.b("prevNamed"), e.b("prevSel")), first = payload(e.b("named1"), e.b("sel1"))
          let second = payload(e.b("named2"), e.b("sel2"))
          let localStart = e.b("localStart") ? [current] : []
          let customs1: Set<String> = e.b("custom1") ? [current] : []
          func apply(_ local: [String], _ baseline: [String], _ remote: (selected: [String], known: [String]?),
                     _ customs: Set<String> = []) -> Bool {
            let (selected, known) = CloudSyncCustomFilterReconciler.remoteBuiltInSelection(
              local: local, baseline: baseline, remote: remote.selected, remoteKnown: remote.known,
              remoteCustomURLs: customs, canonicalize: canonicalize, olderVersionsReconcile: reconcile)
            // As CloudSyncManager.applyRemoteFilters applies it to the list.
            return known.contains(current) ? selected.contains(current) : local.contains(current)
          }
          let after1 = apply(localStart, previous.selected, first, customs1)
          // As CloudSyncManager.applyRemotePayload saves the baseline after the first apply.
          let base1 = CloudSyncCustomFilterReconciler.baselineSelection(
            remote: first, previous: previous, local: (localStart, [current]), remoteCustomURLs: customs1,
            canonicalize: canonicalize, olderVersionsReconcile: reconcile)
          let local2 = after1 != e.b("toggled")
          return ["result": apply(local2 ? [current] : [], base1.selected, second)]
        }
      case "selection", "customImport":
        // One built-in list at `current`; `old` is an address only a 3.x device uses for it.
        let current = "https://example.com/current", old = "https://example.com/old"
        // Like FilterListLoader.migratedURL, which matches old addresses by list identity.
        let oldKey = FilterListURLSupport.identityKey(for: URL(string: old)!)
        let canonicalize = { (u: String) in URL(string: u).map(FilterListURLSupport.identityKey) == oldKey ? current : u }
        func list(_ e: Values, _ cur: String, _ legacy: String) -> [String] {
          (e.b(cur) ? [current] : []) + (e.b(legacy) ? [old] : [])
        }
        return values.map { e -> Values in
          if suite == "customImport" {
            // A kept copy of a purged list (PurgedFilterLists), at an address that is not a built-in's.
            let purged = "https://example.com/malware-filter/urlhaus-filter-vivaldi-online.txt"
            let url = e.b("builtInCurrent") ? current : e.b("builtInLegacy") ? old : e.b("purged") ? purged : "https://example.com/other"
            // The same list under another spelling of its address.
            let spelled = e.b("variant") ? url.replacingOccurrences(of: "example.com", with: "EXAMPLE.com").replacingOccurrences(of: "/o", with: "/%6F").replacingOccurrences(of: "/c", with: "/%63") + "/#copy" : url
            return ["import": CloudSyncCustomFilterReconciler.isImportable(
              spelled, builtInURLs: [current], canonicalize: canonicalize)]
          }
          let (selected, known) = CloudSyncCustomFilterReconciler.remoteBuiltInSelection(
            local: e.b("local") ? [current] : [], baseline: list(e, "base", "baseLegacy"),
            remote: list(e, "remote", "remoteLegacy"),
            remoteKnown: e.b("knownNil") ? nil : list(e, "knownCur", "knownLegacy"),
            remoteCustomURLs: e.b("custom") ? [current] : [], canonicalize: canonicalize,
            olderVersionsReconcile: { $0 == current && e.b("reconciled") })
          // As CloudSyncManager.applyRemoteFilters applies it to the list.
          return ["selected": known.contains(current) ? selected.contains(current) : e.b("local")]
        }
      case "frame":
        return values.map { e -> Values in
          // A web page on this host or on another host, or else a hostless or ftp URL; the frame flag never picks it.
          let page = e.b("webURL")
            ? (e.b("otherHost") ? "https://other.example/allowed/page" : "https://example.com/allowed/page")
            : (e.b("hostless") ? "https:///" : "ftp://example.com/allowed/page")
          var script = UserScript(name: "Frame policy", content: "")
          // "*://" expands to http and https only, so an ftp page needs its scheme spelled out to match.
          let scheme = page.hasPrefix("ftp:") ? "ftp" : "*", area = e.b("matched") ? "allowed" : "denied"
          script.matches = ["\(scheme)://example.com/\(area)/*"]
          script.excludeMatches = e.b("excluded") ? ["\(scheme)://example.com/allowed/*"] : []
          script.isEnabled = e.b("enabled")
          script.noframes = e.b("noframes")
          // The ftp page matches its pattern, so only the scheme guard can refuse it.
          if !e.b("webURL"), !e.b("hostless"), e.b("matched"), !e.b("excluded") {
            precondition(script.matches(url: page), "the ftp page must match, so the scheme guard decides")
          }
          return ["allowed": UserScriptFrameAuthorization.allows(
            script, pageURL: page, isTopFrame: e.b("top"), disabledOnSite: e.b("disabledOnSite"), paused: e.b("paused"))]
        }
      case "remoteMetadata":
        return values.map { e -> Values in
          let title = e.b("titlePresent") ? (e.b("titleBlank") ? " " : "Remote Title") : nil
          let description = e.b("descriptionPresent") ? (e.b("descriptionBlank") ? " " : "Remote Description") : nil
          let filter = FilterList(
            name: "Original", url: URL(string: "https://example.com/filter.txt")!, category: .custom,
            isCustom: e.b("custom"), description: "Original description",
            hasUserProvidedName: e.b("userName"), hasUserProvidedDescription: e.b("userDescription"))
          let result = FilterListRemoteMetadataPolicy.applying(
            title: title, description: description, version: e.b("versionPresent") ? "2025.1" : nil, to: filter)
          return ["name": result.name, "description": result.description, "version": result.version]
        }
      case "importReview":
        return values.map { e -> Values in
          let automatic = e.b("same") ? (e.b("blank") ? "" : "Remote") : "Other"
          let edited = e.b("present") ? (e.b("blank") ? "  " : "Remote") : nil
          let result = ImportMetadataReview.userProvided(edited, automatic: automatic)
          return ["override": result != nil, "cleared": result == ""]
        }
      case "persistedRunActive":
        return values.map { e -> Values in
          [
            "active": SharedAutoUpdateManager.isPersistedRunActive(
              persistedIsRunning: e.b("persisted"),
              runningSince: Int64(e.n("runningSince")),
              lastCheck: Int64(e.n("lastCheck")),
              now: TimeInterval(e.n("now")),
              staleInterval: TimeInterval(e.n("stale"))
            )
          ]
        }
      case "filterDueCheck":
        return values.map { e -> Values in
          [
            "due": SharedAutoUpdateManager.isFilterDueForCheck(
              force: e.b("force"),
              hasPendingRevision: e.b("pending"),
              lastChecked: Int64(e.n("lastChecked")),
              expirySeconds: e.b("hasExpiry") ? TimeInterval(e.n("expiry")) : nil,
              intervalSeconds: TimeInterval(e.n("interval")),
              now: TimeInterval(e.n("now"))
            )
          ]
        }
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
      case "gate":
        var gate = ForegroundRunGate()
        let resumes = ResumeCount()
        let wait: @Sendable () -> Void = { resumes.count += 1 }
        return values.map { e -> Values in
          var granted = false, resumed = 0
          switch e.n("op") {
          case 0: granted = gate.beginForegroundWork(orWait: wait)
          case 1: gate.endForegroundWork()
          case 2: granted = gate.startRun()
          default:
            let before = resumes.count
            gate.finishRun().forEach { $0() }
            resumed = resumes.count - before
          }
          return ["granted": granted, "work": gate.foregroundWork, "running": gate.runActive, "resumed": resumed]
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
      case "infoPopover":
        // Tokens 1 and 2 are two rows of one list (id "list", token 1 on top); token 3 is another item.
        // Each request is one trace, so every trace starts from a fresh state.
        let tokens = [UUID(), UUID(), UUID()], names = ["list", "list", "other"], ids = ["list", "other", "missing"]
        let frames: [CGFloat] = [400, 100, 250]
        let anchors = tokens.indices.map { i in
          InfoPopoverState.Anchor(token: tokens[i], id: names[i], windowNumber: 1,
                                  frame: CGRect(x: 300, y: frames[i], width: 16, height: 16))
        }
        var state = InfoPopoverState()
        func slot(_ token: UUID?) -> Int { token.flatMap { tokens.firstIndex(of: $0) }.map { $0 + 1 } ?? 0 }
        return values.map { e -> [Int] in
          let tok = e.n("tok"), mouse = e.b("mouse") ? e.n("ev") : nil
          var result = 0
          switch e["op"] as! String {
          case "clicked": state.clicked(tokens[tok - 1], id: names[tok - 1])
          case "anchor":
            // Production selects among the anchors on screen only.
            let visible = anchors.indices.filter { e.b("v\($0 + 1)") }.map { anchors[$0] }
            result = slot(state.anchor(for: ids[e.n("id") - 1], in: visible, fromKeyboard: e.b("fromKb")))
          case "request": result = state.request(tokens[tok - 1], mouseUp: mouse) ? 1 : 0
          case "dismiss": result = state.dismiss(tokens[tok - 1], mouseDown: mouse) ? 1 : 0
          default: state.clear()
          }
          return [slot(state.presented), result]
        }
      case "headlessBackoff":
        return values.map { e -> Values in
          ["d": Int(HeadlessLaunch.autoRebuildDelay(forFailureCount: e.n("f"))),
           "next": Int(HeadlessLaunch.autoRebuildDelay(forFailureCount: e.n("g")))]
        }
      case "headlessGate":
        // One gate directory, emptied before each trace; each step makes the production consume or record call on it.
        let directory = Scratch.directory
        Scratch.reset(nil)
        return values.map { e -> Values in
          let now = TimeInterval(e.n("now")), op = e["op"] as! String
          var granted = false
          if op == "consume" {
            granted = HeadlessLaunch.consumeAutoRebuildLaunchSlot(now: now, gateDirectory: directory)
          } else {
            precondition(HeadlessLaunch.recordAutoRebuildLaunchOutcome(
              HeadlessLaunch.AutoRebuildLaunchOutcome(rawValue: op)!, now: now, gateDirectory: directory))
          }
          let state = HeadlessLaunch.loadAutoRebuildGateState(gateDirectory: directory) ?? .init()
          return [
            "granted": granted, "last": Int(state.lastAttemptAt), "failures": state.failureCount,
            "outcome": state.lastOutcome.isEmpty ? "none" : state.lastOutcome,
          ]
        }
      case "headlessGateBlocked":
        // The gate directory is a file, so the lock and the write both fail and no slot is granted.
        let blocked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! Data().write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }
        return values.map { e -> Values in
          ["granted": HeadlessLaunch.consumeAutoRebuildLaunchSlot(now: TimeInterval(e.n("now")), gateDirectory: blocked)]
        }
      case "pauseStore": return pauseStore[index]!
      case "popup":
        // Each trace starts from an empty store; the suite and lock directory are shared and emptied between traces. Claim numbers name the
        // tokens that claims won, so a finish by a model claim is a finish by the production token it won with.
        let group = Scratch.popupGroup, directory = Scratch.directory
        Scratch.reset(group)
        var tokens: [Int: FilterUpdatePopupStatus.ClaimToken] = [:]
        let states: [FilterUpdatePopupStatus.State] = [.idle, .running, .succeeded, .noChange, .failed]
        func completed(_ result: SharedAutoUpdateManager.AutoUpdateCompletionResult) -> SharedAutoUpdateManager.AutoUpdateRunOutcome {
          .completed(.init(result: result, checkedFilters: 1, updatedFilters: 1, updatedScripts: 0, failedScripts: 0))
        }
        // Index order is the model's outcome input: applied, staged, no updates, no selection, then each failure kind.
        let outcomes: [SharedAutoUpdateManager.AutoUpdateRunOutcome] = [
          completed(.appliedUpdates), completed(.stagedUpdates), completed(.noFilterUpdates), completed(.noSelectedFilters),
          .failed(message: "failed"), .overLimit(message: "over limit"), .deferred(phase: "reading"),
          .cancelled, .skipped(reason: "disabled"),
        ]
        return values.map { e -> [Int] in
          let now = Date(timeIntervalSince1970: Double(e.n("now")))
          let claim = e.n("claim"), op = e.n("op")
          var ok = false
          switch op {
          case 0, 1:
            let token = op == 0
              ? FilterUpdatePopupStatus.beginIfIdle(groupIdentifier: group, now: now, lockDirectory: directory)
              : FilterUpdatePopupStatus.requestUpdate(groupIdentifier: group, now: now, lockDirectory: directory)
            ok = token != nil
            if let token { tokens[claim] = token }
          case 2:
            ok = FilterUpdatePopupStatus.consumeUpdateRequest(groupIdentifier: group, lockDirectory: directory) != nil
          case 3:
              ok = FilterUpdatePopupStatus.finish(
              outcomes[e.n("outcome")], claim: tokens[claim] ?? .init(rawValue: "unclaimed"),
              groupIdentifier: group, now: now, lockDirectory: directory)
          default: break
          }
          // consumeSnapshot reports the state it clears; every other operation reports the state after it.
          let view = op == 5
            ? FilterUpdatePopupStatus.consumeSnapshot(groupIdentifier: group, now: now, lockDirectory: directory)
            : FilterUpdatePopupStatus.snapshot(groupIdentifier: group, now: now, lockDirectory: directory)
          return [ok ? 1 : 0, states.firstIndex(of: view.state)!, Int(view.startedAt ?? 0), Int(view.finishedAt ?? 0)]
        }
      case "swipeBack":
        var state = SwipeBackGestureState()
        func phaseOf(_ name: String) -> NSEvent.Phase {
          switch name {
          case "mayBegin": return .mayBegin
          case "began": return .began
          case "changed": return .changed
          case "ended": return .ended
          case "cancelled": return .cancelled
          default: return []
          }
        }
        func modeName(_ mode: SwipeBackGestureState.Mode) -> String {
          switch mode {
          case .idle: return "idle"
          case .pendingAxis: return "pending"
          case .tracking: return "tracking"
          case .committing: return "committing"
          }
        }
        func progressPermille(_ mode: SwipeBackGestureState.Mode) -> Int {
          if case .tracking(let p, _, let rm) = mode { return rm ? 0 : Int((p * 1000).rounded()) }
          return 0
        }
        return values.map { e -> [Any] in
          let op = e["op"] as! String
          var action = "none", stopped = false
          switch op {
          case "scroll":
            let axis = e["axis"] as! String
            let dx: CGFloat = axis == "back" ? 10 : 0
            let dy: CGFloat = axis == "other" ? 10 : 0
            let outcome = state.handleScroll(
              phase: phaseOf(e["phase"] as! String),
              hasMomentum: e.b("hasMomentum"),
              dx: dx,
              dy: dy,
              swipeEnabled: e.b("swipeEnabled"),
              reduceMotion: e.b("reduceMotionIn")
            )
            if outcome == .startTracking { action = "start" }
          case "track":
            let res = state.handleTrackUpdate(
              amount: CGFloat(e.n("amount")) / 1000.0,
              phase: phaseOf(e["phase"] as! String),
              isComplete: e.b("isComplete")
            )
            switch res {
            case .ignore: action = "none"; stopped = true
            case .update: action = "update"
            case .cancel(let s): action = "cancel"; stopped = s
            case .commit(let s): action = "commit"; stopped = s
            }
          case "finishCommit":
            state.finishCommit()
          case "abort":
            state.abort()
          default:
            preconditionFailure("unknown swipeBack op \(op)")
          }
          return [modeName(state.mode), action, progressPermille(state.mode), stopped ? 1 : 0]
        }
      default: preconditionFailure("unknown policy suite \(suite)")
      }
    }
    try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]).write(
      to: URL(fileURLWithPath: CommandLine.arguments[2]))
  }
}

// One trace per request, each from an empty store in its own UserDefaults suite. Stored state is read from the
// raw keys, so observing a step never migrates the mask. Op numbers match `pause` in policies.mjs.
@MainActor enum PauseStoreTrace {
  enum ScopeFailure: Error { case body }
  static let statuses: [BlockingPauseStore.ResumeStatus] = [.idle, .pending, .applying, .succeeded, .failed]

  static func run(_ steps: [Values]) async -> [[Int]] {
    let suite = Scratch.pauseGroup
    Scratch.reset(suite)
    guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("could not create suite") }
    return await observe(steps, defaults: defaults, suite: suite)
  }

  static func observe(_ steps: [Values], defaults: UserDefaults, suite: String) async -> [[Int]] {
    // The global and content-blocking queries migrate a legacy store, so they run on a copy of the raw keys that
    // this trace owns. Observing a step must not change the trace's store.
    let copySuite = suite + "-observed"
    Scratch.reset(copySuite)
    guard let copy = UserDefaults(suiteName: copySuite) else { preconditionFailure("could not create suite") }
    var observed: [[Int]] = []
    for e in steps {
      let mask = BlockingPauseComponents(
        rawValue: (e.b("fMask") ? 1 : 0) | (e.b("sMask") ? 2 : 0) | (e.b("zMask") ? 4 : 0))
      var out = 0
      switch e.n("op") {
      case 0: BlockingPauseStore.setPausedComponents(mask, groupIdentifier: suite)
      case 1: BlockingPauseStore.setPaused(e.b("paused"), groupIdentifier: suite)
      case 2: out = BlockingPauseStore.pausedComponents(groupIdentifier: suite).rawValue
      case 3: out = statuses.firstIndex(of: BlockingPauseStore.requestResume(groupIdentifier: suite))!
      case 4: out = BlockingPauseStore.consumeResumeRequest(groupIdentifier: suite) ? 1 : 0
      case 5: BlockingPauseStore.setResumeApplying(groupIdentifier: suite)
      case 6: BlockingPauseStore.setResumeSucceeded(groupIdentifier: suite)
      case 7: BlockingPauseStore.setResumeFailed("failed", groupIdentifier: suite)
      case 8:
        out = await BlockingPauseStore.withContentBlockingResumed(groupIdentifier: suite) { () async -> Int in
          insideMask(suite)
        }
      case 9:
        do {
          _ = try await BlockingPauseStore.withContentBlockingResumed(groupIdentifier: suite) { () async throws -> Int in
            throw ScopeFailure.body
          }
          preconditionFailure("a failing resume must propagate its error")
        } catch { out = 0 }
      case 10:
        out = await Task { @MainActor () async -> Int in
          await BlockingPauseStore.withContentBlockingResumed(groupIdentifier: suite) { () async -> Int in
            withUnsafeCurrentTask { $0?.cancel() }
            await Task.yield()
            return Task.isCancelled ? 1 : 0
          }
        }.value
      default:
        defaults.set(e.b("paused"), forKey: BlockingPauseStore.key)
        defaults.removeObject(forKey: BlockingPauseStore.componentsKey)
      }
      let status = BlockingPauseStore.resumeStatus(groupIdentifier: suite)
      let stored = defaults.object(forKey: BlockingPauseStore.componentsKey) != nil
      let paused = pauseReads(defaults, copy: copy, copySuite: copySuite)
      observed.append([
        defaults.bool(forKey: BlockingPauseStore.key) ? 1 : 0,
        stored ? 1 : 0,
        stored ? defaults.integer(forKey: BlockingPauseStore.componentsKey) : 0,
        defaults.bool(forKey: BlockingPauseStore.resumeRequestKey) ? 1 : 0,
        statuses.firstIndex(of: status.status)!,
        status.error == nil ? 0 : 1,
        out,
        paused.any ? 1 : 0,
        paused.content ? 1 : 0,
      ])
    }
    return observed
  }

  // Copies the trace's raw keys into the copy suite, then asks the production queries about it.
  static func pauseReads(_ defaults: UserDefaults, copy: UserDefaults, copySuite: String) -> (any: Bool, content: Bool) {
    copy.set(defaults.bool(forKey: BlockingPauseStore.key), forKey: BlockingPauseStore.key)
    if let mask = defaults.object(forKey: BlockingPauseStore.componentsKey) {
      copy.set(mask, forKey: BlockingPauseStore.componentsKey)
    } else {
      copy.removeObject(forKey: BlockingPauseStore.componentsKey)
    }
    return (BlockingPauseStore.isPaused(groupIdentifier: copySuite),
            BlockingPauseStore.isContentBlockingPaused(groupIdentifier: copySuite))
  }

  static func insideMask(_ suite: String) -> Int {
    [(BlockingPauseComponents.filters, 1), (.userScripts, 2), (.elementZapper, 4)].reduce(0) { bits, pair in
      bits | (BlockingPauseStore.isPaused(pair.0, groupIdentifier: suite) ? pair.1 : 0)
    }
  }
}

// Creating a UserDefaults suite per trace slows every later suite down, so the stateful probes share one suite each
// and one scratch directory, emptied before each trace and removed when the probe exits.
@MainActor enum Scratch {
  static let id = UUID().uuidString
  static let popupGroup = "test.wblock.policy-probe.popup.\(id)", pauseGroup = "policy-probe-pause-\(id)"
  static let directory: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("policy-probe-\(id)", isDirectory: true)
    atexit {
      for group in [Scratch.popupGroup, Scratch.pauseGroup, Scratch.pauseGroup + "-observed"] {
        UserDefaults(suiteName: group)?.removePersistentDomain(forName: group)
      }
      try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("policy-probe-\(Scratch.id)"))
    }
    return url
  }()

  static func reset(_ group: String?) {
    if let group { UserDefaults(suiteName: group)?.removePersistentDomain(forName: group) }
    try? FileManager.default.removeItem(at: directory)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
}
