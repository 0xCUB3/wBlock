import Foundation
import wBlockCoreService

@main
@MainActor
struct ProtobufReliabilityTests {
    static func main() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-protobuf-reliability-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        await testFilterAutomaticUpdates(root: root.appendingPathComponent("filter-updates"))
        await testBackgroundMetadataPreservesConfiguration(root: root.appendingPathComponent("background-metadata"))
        await testUnchangedMetadataPreservesForegroundDownload(root: root.appendingPathComponent("untouched-metadata"))
        await testSourceTimestampOwnership(root: root.appendingPathComponent("source-timestamp"))
        await testInlineFilterSelection(root: root.appendingPathComponent("inline-filters"))
        await testDurableMigrationAndCorruptionRecovery(root: root.appendingPathComponent("recovery"))
        await testMissingMainAndScriptTimestamp(root: root.appendingPathComponent("missing-main"))
        await testCorruptMainWithoutBackup(root: root.appendingPathComponent("no-backup-recovery"))
        await testMigrationFailureAndCanonicalPrecedence(root: root.appendingPathComponent("migration-failure"))
        await testThreeWayDeletionAndInsertion(root: root.appendingPathComponent("merge"))
        await testConditionalCloudDisabledHosts(root: root.appendingPathComponent("cloud-disabled-hosts"))
        await testSelectedSites(root: root.appendingPathComponent("selected-sites"))
        await testUserScriptMetadataOverrides(root: root.appendingPathComponent("metadata-overrides"))
        await testLegacyBpcURLMigration(root: root.appendingPathComponent("bpc-url"))
        print("PASS")
    }

    private static func testFilterAutomaticUpdates(root: URL) async {
        let suite = "test.wblock.filter-updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let writer = await makeManager(root: root, standard: defaults, group: defaults)
        await writer.loadData()
        let lists = [false, true].map { custom in
            FilterList(name: custom ? "Custom" : "Built-in",
                       url: URL(string: "https://example.com/\(custom).txt")!,
                       category: .ads, isCustom: custom, isSelected: true)
        }
        await writer.updateFilterLists(lists)
        let background = await makeManager(root: root, standard: defaults, group: defaults)
        await background.loadData()
        expect(background.getFilterLists().count == lists.count, "both list kinds must persist")
        expect(background.getFilterLists().allSatisfy(\.updatesAutomatically),
               "absent protobuf preference must keep automatic updates enabled")
        var optedOut = writer.getFilterLists()
        for index in optedOut.indices { optedOut[index].updatesAutomatically = false }
        await writer.updateFilterLists(optedOut)
        var metadata = background.getFilterLists()
        for index in metadata.indices { metadata[index].version = "2" }
        await background.updateFilterLists(metadata)
        let restarted = await makeManager(root: root, standard: defaults, group: defaults)
        await restarted.loadData()
        expect(restarted.getFilterLists().count == lists.count, "metadata saves must retain both lists")
        expect(restarted.getFilterLists().allSatisfy { !$0.updatesAutomatically && $0.version == "2" },
               "an unrelated metadata writer must preserve per-filter update opt-outs")
        var enabled = restarted.getFilterLists()
        for index in enabled.indices { enabled[index].updatesAutomatically = true }
        await restarted.updateFilterLists(enabled)
        let verifier = await makeManager(root: root, standard: defaults, group: defaults)
        await verifier.loadData()
        expect(verifier.getFilterLists().allSatisfy(\.updatesAutomatically), "re-enabling must persist")
        await restarted.removeFilterList(withId: lists[1].id)
        verifier.setUserScriptShowEnabledOnly(true)
        await verifier.saveDataImmediately()
        let afterDeletion = await makeManager(root: root, standard: defaults, group: defaults)
        await afterDeletion.loadData()
        expect(!afterDeletion.getFilterLists().contains { $0.id == lists[1].id },
               "a stale writer must not resurrect a removed subscription")
    }

    private static func testBackgroundMetadataPreservesConfiguration(root: URL) async {
        let suite = "test.wblock.filter-metadata.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let background = await makeManager(root: root, standard: defaults, group: defaults)
        await background.loadData()
        let filter = FilterList(name: "Remote title", url: URL(string: "https://example.com/list.txt")!,
                                category: .custom, isCustom: true, isSelected: true)
        let inlineID = UUID()
        let inline = FilterList(id: inlineID, name: "Local rules", url: URL(string: "wblock://userlist/\(inlineID)")!,
                                category: .custom, isCustom: true)
        let seeded = await background.updateFilterLists([filter, inline])
        expect(seeded, "seed background snapshot")
        let downloadBaseline = background.getFilterLists()
        var downloaded = downloadBaseline
        downloaded[0].version = "downloaded"
        let firstSave = await background.updateFilterMetadata(downloaded, baseline: downloadBaseline)
        expect(firstSave, "first metadata save")

        let editor = await makeManager(root: root, standard: defaults, group: defaults)
        await editor.loadData()
        var edited = editor.getFilterLists()
        edited[0].category = .privacy
        edited[1].category = .annoyances
        edited[0].name = "My title"
        edited[0].hasUserProvidedName = true
        edited[0].isSelected = false
        edited[0].excludedSites = ["example.com"]
        edited[0].selectedSites = ["selected.example"]
        edited[0].updatesAutomatically = false
        // Foreground Get finishes for a row this background operation never fetched.
        edited[1].version = "v2-foreground"
        edited[1].sourceRuleCount = 200
        edited[1].uniqueRuleCount = 150
        let inserted = FilterList(name: "Added during compilation", url: URL(string: "https://example.com/new.txt")!,
                                  category: .security, isCustom: true)
        edited.append(inserted)
        let userSave = await editor.updateFilterLists(edited)
        expect(userSave, "user edits while compilation is suspended")
        // An unrelated write refreshes the background process's baseline. A
        // whole-list save would now mistake the old category for an explicit edit.
        await background.setFilterValidators(filter.id.uuidString, etag: "new", lastModified: nil)
        expect(background.getFilterLists()[0].category == .privacy, "background baseline sees user edit")
        let admissionBaseline = downloaded
        downloaded[0].uniqueRuleCount = 7
        let secondSave = await background.updateFilterMetadata(downloaded, baseline: admissionBaseline)
        expect(secondSave, "second metadata save after compilation")

        let restarted = await makeManager(root: root, standard: defaults, group: defaults)
        await restarted.loadData()
        let result = restarted.getFilterLists().first { $0.id == filter.id }!
        expect(result.category == .privacy && result.name == "My title" && result.hasUserProvidedName,
               "metadata must not revert a category or explicit title after a baseline refresh")
        expect(!result.isSelected && !result.updatesAutomatically
               && result.excludedSites == ["example.com"] && result.selectedSites == ["selected.example"],
               "metadata must preserve configuration")
        let foreground = restarted.getFilterLists().first { $0.id == inlineID }!
        expect(foreground.version == "v2-foreground" && foreground.sourceRuleCount == 200
               && foreground.uniqueRuleCount == 150, "admission save must preserve an untouched foreground Get")
        expect(result.version == "downloaded" && result.uniqueRuleCount == 7, "downloaded metadata must survive restart")
        expect(restarted.getFilterLists().first { $0.id == inlineID }?.category == .annoyances,
               "background saves must also preserve a moved inline user list")
        expect(restarted.getFilterLists().contains { $0.id == inserted.id }, "metadata must not delete concurrent additions")

        var concurrentEdit = restarted.getFilterLists()
        concurrentEdit[0].category = .security
        async let metadataSave = background.updateFilterMetadata(downloaded, baseline: admissionBaseline)
        async let categorySave = restarted.updateFilterLists(concurrentEdit)
        let saves = await (metadataSave, categorySave)
        expect(saves.0 && saves.1, "concurrent metadata and category writes succeed")
        await restarted.refreshFromDiskIfModified(forceRead: true)
        expect(restarted.getFilterLists().first { $0.id == filter.id }?.category == .security,
               "category survives either atomic write order")

        var retargeted = restarted.getFilterLists()
        retargeted[0].url = URL(string: "https://example.com/replacement.txt")!
        retargeted[0].version = "replacement"
        let retargetSave = await restarted.updateFilterLists(retargeted)
        expect(retargetSave, "retarget fixture")
        let obsoleteDownload = await background.updateFilterMetadata(downloaded, baseline: admissionBaseline)
        expect(obsoleteDownload, "obsolete download save")
        await restarted.refreshFromDiskIfModified(forceRead: true)
        expect(restarted.getFilterLists().first { $0.id == filter.id }?.version == "replacement",
               "metadata must match both ID and current source URL")

        await restarted.removeFilterList(withId: filter.id)
        let staleSave = await background.updateFilterMetadata(downloaded, baseline: admissionBaseline)
        expect(staleSave, "metadata after deletion")
        await restarted.refreshFromDiskIfModified(forceRead: true)
        expect(!restarted.getFilterLists().contains { $0.id == filter.id }, "metadata must not resurrect a deleted list")
    }

    private static func testUnchangedMetadataPreservesForegroundDownload(root: URL) async {
        let suite = "test.wblock.untouched-metadata.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let background = await makeManager(root: root, standard: defaults, group: defaults)
        await background.loadData()
        var old = FilterList(name: "Untouched", url: URL(string: "https://example.com/untouched.txt")!,
                             category: .ads, isCustom: true, isSelected: true)
        old.version = "v1"; old.sourceRuleCount = 100; old.uniqueRuleCount = 90
        await background.updateFilterLists([old])
        let baseline = background.getFilterLists()
        let foreground = await makeManager(root: root, standard: defaults, group: defaults)
        await foreground.loadData()
        var downloaded = foreground.getFilterLists()
        downloaded[0].version = "v2"
        downloaded[0].sourceRuleCount = 200
        downloaded[0].uniqueRuleCount = 150
        downloaded[0].lastUpdated = Date(timeIntervalSince1970: 2_000)
        await foreground.updateFilterLists(downloaded)
        let expected = foreground.getFilterLists()[0]
        // This refresh must not turn an old operation snapshot into an explicit edit.
        await background.setFilterValidators(old.id.uuidString, etag: "refresh", lastModified: nil)
        let saved = await background.updateFilterMetadata(baseline, baseline: baseline)
        expect(saved, "unchanged metadata save")
        await foreground.refreshFromDiskIfModified(forceRead: true)
        expect(foreground.getFilterLists()[0] == expected, "unchanged row preserves newer metadata and timestamp")

        var admitted = baseline
        admitted[0].uniqueRuleCount = 80
        await background.updateFilterMetadata(admitted, baseline: baseline)
        await foreground.refreshFromDiskIfModified(forceRead: true)
        let result = foreground.getFilterLists()[0]
        expect(result.version == "v2" && result.sourceRuleCount == 200 && result.uniqueRuleCount == 80
               && result.lastUpdated == expected.lastUpdated, "admission changes only its count")
    }

    private static func testSourceTimestampOwnership(root: URL) async {
        let suite = "test.wblock.source-timestamp.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = await makeManager(root: root, standard: defaults, group: defaults)
        await manager.loadData()
        var seed = FilterList(name: "Unversioned", url: URL(string: "https://example.com/unversioned.txt")!,
                              category: .custom, isCustom: true)
        seed.sourceRuleCount = 10
        seed.lastUpdated = Date(timeIntervalSince1970: 1_000)
        await manager.updateFilterLists([seed])
        let baseline = manager.getFilterLists()
        var fetched = baseline
        let fetchedAt = Date(timeIntervalSince1970: 1_600)
        fetched[0].lastUpdated = fetchedAt
        let fetchedSave = await manager.updateFilterMetadata(fetched, baseline: baseline)
        expect(fetchedSave, "same-version source download persists")
        expect(manager.getFilterLists()[0].lastUpdated == fetchedAt,
               "a same-version, same-count download records its fetch timestamp")
        let hydrationBaseline = manager.getFilterLists()
        var hydrated = hydrationBaseline
        hydrated[0].sourceRuleCount = 11
        let hydrationSave = await manager.updateFilterMetadata(hydrated, baseline: hydrationBaseline)
        expect(hydrationSave, "source count hydration persists")
        var configured = manager.getFilterLists()
        configured[0].isSelected = true
        configured[0].updatesAutomatically = false
        configured[0].lastUpdated = nil
        let configurationSave = await manager.updateFilterLists(configured)
        expect(configurationSave, "configuration with an absent date persists")
        let restarted = await makeManager(root: root, standard: defaults, group: defaults)
        await restarted.loadData()
        expect(restarted.getFilterLists()[0].sourceRuleCount == 11
               && restarted.getFilterLists()[0].lastUpdated == fetchedAt,
               "hydration and configuration preserve the fetch timestamp across restart")
    }

    private static func testInlineFilterSelection(root: URL) async {
        let suite = "test.wblock.inline.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let url = URL(string: "wblock://userlist/\(id.uuidString)")!
        var filter = FilterList(id: id, name: "User Rules", url: url,
                                category: .custom, isCustom: true, isSelected: true)
        var manager = await makeManager(root: root, standard: defaults, group: defaults)
        await manager.loadData()
        for selected in [true, false, true] {
            filter.isSelected = selected
            let saved = await manager.updateFilterLists([filter])
            expect(saved, "inline filter must persist")
            manager = await makeManager(root: root, standard: defaults, group: defaults)
            await manager.loadData()
            let loaded = manager.getFilterLists().first { $0.id == id }!
            expect(loaded.url == url && loaded.isInlineUserList, "restart must retain the local rules address")
            expect(loaded.isSelected == selected, "restart must retain the user's selection")
            let rebased = FilterSelectionRebaser.rebaseSelection(snapshot: [filter], latestPersisted: [loaded])
            expect(rebased[0].isSelected == selected, "filter updates must retain inline selection")
            let updated = await manager.updateFilterLists(rebased)
            expect(updated, "updated inline filter must persist")
        }

        // Earlier versions saved the rejected local address inside a placeholder.
        var placeholder = URLComponents()
        placeholder.scheme = "wblock-invalid-filter"
        placeholder.path = "unavailable"
        placeholder.queryItems = [URLQueryItem(name: "source", value: url.absoluteString)]
        filter.url = placeholder.url!
        filter.isCustom = false
        filter.category = .ads
        filter.description = ""
        filter.isSelected = true
        let enabledLegacySave = await manager.updateFilterLists([filter])
        expect(enabledLegacySave, "legacy enabled placeholder fixture must persist")
        manager = await makeManager(root: root, standard: defaults, group: defaults)
        await manager.loadData()
        let recoveredEnabled = manager.getFilterLists().first { $0.id == id }!
        expect(recoveredEnabled.url == url && recoveredEnabled.isInlineUserList,
               "recover previously rejected local addresses")
        expect(recoveredEnabled.isCustom && recoveredEnabled.isSelected,
               "recovered local filters must remain custom and enabled")

        filter.isSelected = false
        let saved = await manager.updateFilterLists([filter])
        expect(saved, "legacy disabled placeholder fixture must persist")
        let file = root.appendingPathComponent("wblock_data.pb")
        let bytes = try! Data(contentsOf: file)
        try! (bytes + bytes).write(to: file, options: .atomic)
        manager = await makeManager(root: root, standard: defaults, group: defaults)
        await manager.loadData()
        expect(manager.getFilterLists().count == 1, "repeated stored identities must collapse before reaching any reader")
        let recovered = manager.getFilterLists().first { $0.id == id }!
        expect(recovered.url == url && recovered.isInlineUserList, "recover previously rejected local addresses")
        expect(recovered.isCustom && !recovered.isSelected,
               "recovery must preserve a disabled local filter")

        var builtIn = FilterList(name: "Built-in", url: URL(string: "https://example.com/builtin.txt")!, category: .custom)
        let movedSaved = await manager.updateFilterLists([filter, builtIn])
        expect(movedSaved, "category move must persist")
        manager = await makeManager(root: root, standard: defaults, group: defaults)
        await manager.loadData()
        let moved = manager.getFilterLists().first { $0.id == builtIn.id }!
        expect(moved.category == .custom && !moved.isCustom, "Custom placement must not change built-in ownership")
        for selected: [String]? in [nil, [], ["example.com"]] {
            builtIn.selectedSites = selected
            let saved = await manager.updateFilterLists([filter, builtIn])
            expect(saved, "selected-site mode must persist")
            manager = await makeManager(root: root, standard: defaults, group: defaults)
            await manager.loadData()
            expect(manager.getFilterLists().first { $0.id == builtIn.id }?.selectedSites == selected,
                   "protobuf must distinguish all sites from an empty selected-site list")
        }

        for raw in ["", "not a URL", "https:///", "ftp://example.com/filter.txt", "wblock://other/123"] {
            let rejected = PersistedFilterURL.resolve(raw)
            expect(!rejected.isUsable, "unsupported addresses must stay disabled")
            expect(!PersistedFilterURL.resolve(rejected.url.absoluteString).isUsable,
                   "invalid placeholders must stay disabled")
        }
        for raw in ["https://example.com/filter.txt", "http://example.com/filter.txt", "file:///tmp/rules.txt",
                    "WBLOCK://USERLIST/\(id.uuidString)"] {
            expect(PersistedFilterURL.resolve(raw).isUsable, "supported addresses must remain usable")
        }
    }

    private static func testMissingMainAndScriptTimestamp(root: URL) async {
        let suite = "test.wblock.protobuf.restart.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("recover-me", forKey: "selectedBlockingLevel")
        let first = await makeManager(root: root, standard: defaults, group: defaults)
        await first.loadData()
        let main = root.appendingPathComponent("wblock_data.pb")
        let backup = root.appendingPathComponent("wblock_data_backup.pb")
        let knownGood = try! Data(contentsOf: backup)
        try! Data([0xff, 0x00, 0xff]).write(to: main, options: .atomic)
        // Restart at the old implementation's quarantine/replace crash boundary.
        try! FileManager.default.moveItem(at: main, to: main.appendingPathExtension("corrupt"))
        let restarted = await makeManager(root: root, standard: defaults, group: defaults)
        await restarted.loadData()
        expect(restarted.selectedBlockingLevel == "recover-me", "missing main must recover backup settings")
        expect((try! Data(contentsOf: backup)) == knownGood, "restart must not overwrite good backup with defaults")
        var script = UserScript(name: "Dated", url: URL(string: "https://example.com/dated.user.js"))
        script.lastUpdated = Date()
        let saved = await restarted.updateUserScripts([script])
        expect(saved, "dated script must persist")
        expect(restarted.getUserScripts().first { $0.id == script.id }?.lastUpdated != nil,
               "protobuf decoding must retain the persisted script date")
    }

    private static func testUserScriptMetadataOverrides(root: URL) async {
        let suite = "test.wblock.protobuf.metadata-overrides.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = await makeManager(root: root, standard: defaults, group: defaults)
        await first.loadData()
        var script = UserScript(name: "Metadata overrides", url: URL(string: "https://example.com/metadata.user.js"))
        script.metadataAuthorOverride = "Local author"
        script.metadataHomepageOverride = "https://example.com/local-home"
        script.author = script.metadataAuthorOverride
        script.homepage = script.metadataHomepageOverride
        let updateSaved = await first.updateUserScripts([script])
        expect(updateSaved, "metadata overrides must persist through update")

        let updated = await makeManager(root: root, standard: defaults, group: defaults)
        await updated.loadData()
        let loaded = updated.getUserScripts().first { $0.id == script.id }!
        expect(loaded.metadataAuthorOverride == "Local author" && loaded.author == "Local author", "author override must survive update restart")
        expect(loaded.metadataHomepageOverride == "https://example.com/local-home" && loaded.homepage == "https://example.com/local-home", "homepage override must survive update restart")

        script.metadataAuthorOverride = "Replacement author"
        script.metadataHomepageOverride = "https://example.com/replacement-home"
        script.author = script.metadataAuthorOverride
        script.homepage = script.metadataHomepageOverride
        let replacementSaved = await updated.replaceUserScripts([script])
        expect(replacementSaved, "metadata overrides must persist through replacement")
        let replaced = await makeManager(root: root, standard: defaults, group: defaults)
        await replaced.loadData()
        let replacement = replaced.getUserScripts().first { $0.id == script.id }!
        expect(replacement.metadataAuthorOverride == "Replacement author" && replacement.author == "Replacement author", "author override must survive replacement restart")
        expect(replacement.metadataHomepageOverride == "https://example.com/replacement-home" && replacement.homepage == "https://example.com/replacement-home", "homepage override must survive replacement restart")
    }

    private static func testSelectedSites(root: URL) async {
        let suite = "test.wblock.selected-sites.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = await makeManager(root: root, standard: defaults, group: defaults)
        await first.loadData()
        let script = UserScript(name: "Selected sites", url: URL(string: "https://example.com/test.user.js"))
        let id = script.id.uuidString
        _ = await first.updateUserScripts([script])
        expect(first.userScriptSiteAccess(forScriptID: id).allows(host: "any.example"), "legacy scripts remain unrestricted")
        let empty = UserScriptSiteAccess(onlySelectedSites: true)
        _ = await first.setUserScriptSiteAccess(empty, forScriptID: id)
        let second = await makeManager(root: root, standard: defaults, group: defaults)
        await second.loadData()
        expect(second.getUserScriptAllowedHosts()[id] == [], "empty allowlist survives protobuf round trip")
        expect(!second.userScriptSiteAccess(forScriptID: id).allows(host: "example.com"), "empty selected mode runs nowhere")
        let selected = UserScriptSiteAccess(onlySelectedSites: true, hosts: ["https://Example.COM/path", "example.com"])
        expect(selected.hosts == ["example.com"], "selected sites normalize and deduplicate")
        expect(selected.allows(host: "news.example.com"), "selected domain includes subdomains")
        expect(!selected.allows(host: "notexample.com") && !selected.allows(host: "example.com.evil.test"), "host boundaries prevent lookalike matches")
        expect(!selected.allows(host: "example.com", excludedHosts: ["example.com"]), "exclusions take priority")
        expect(!selected.allows(host: ""), "unknown host is denied in selected mode")
        expect(selected.intersecting(empty) == empty, "duplicate repair keeps the narrower permission")
        let baseline = second.getUserScriptAllowedHosts()
        _ = await second.setUserScriptSiteAccess(selected, forScriptID: id)
        _ = await first.applyCloudUserScriptSiteAccess(desired: [id: .init()], baseline: baseline)
        await first.loadData()
        expect(first.userScriptSiteAccess(forScriptID: id) == selected, "stale cloud scope cannot overwrite a newer site choice")
        _ = await first.applyCloudUserScriptSiteAccess(desired: [:], baseline: first.getUserScriptAllowedHosts())
        expect(first.userScriptSiteAccess(forScriptID: id) == selected, "legacy cloud payload does not clear restrictions")
        _ = await first.applyCloudUserScriptSiteAccess(desired: [id: empty], baseline: first.getUserScriptAllowedHosts())
        expect(first.userScriptSiteAccess(forScriptID: id) == empty, "explicit empty cloud allowlist is authoritative")
        _ = await first.applyCloudUserScriptSiteAccess(desired: [id: .init()], baseline: first.getUserScriptAllowedHosts())
        expect(first.getUserScriptAllowedHosts()[id] == nil, "explicit all-sites mode removes the restriction")
        _ = await first.setUserScriptSiteAccess(selected, forScriptID: id)
        await first.removeUserScript(withId: script.id)
        expect(first.getUserScriptAllowedHosts()[id] == nil, "deleting a script removes its selected sites")
    }

    private static func testConditionalCloudDisabledHosts(root: URL) async {
        let standardSuite = "test.wblock.protobuf.cloudhosts.standard.\(UUID().uuidString)"
        let groupSuite = "test.wblock.protobuf.cloudhosts.group.\(UUID().uuidString)"
        let standard = UserDefaults(suiteName: standardSuite)!
        let group = UserDefaults(suiteName: groupSuite)!
        defer {
            standard.removePersistentDomain(forName: standardSuite)
            group.removePersistentDomain(forName: groupSuite)
        }

        let first = await makeManager(root: root, standard: standard, group: group)
        await first.loadData()
        let changedScript = UserScript(name: "Changed", url: URL(string: "https://example.com/changed.user.js"))
        let unchangedScript = UserScript(name: "Unchanged", url: URL(string: "https://example.com/unchanged.user.js"))
        let deletedScript = UserScript(name: "Deleted", url: URL(string: "https://example.com/deleted.user.js"))
        let seeded = await first.updateUserScripts([changedScript, unchangedScript, deletedScript])
        expect(seeded, "script fixtures must be persisted before host projection")
        let changedID = changedScript.id.uuidString
        let unchangedID = unchangedScript.id.uuidString
        let deletedID = deletedScript.id.uuidString
        let baseline = [
            changedID: ["baseline-changed.example"],
            unchangedID: ["baseline-unchanged.example"],
        ]
        await first.setAllUserScriptDisabledHosts(baseline)

        let second = await makeManager(root: root, standard: standard, group: group)
        await second.loadData()
        await second.setUserScriptDisabledHosts(["popup-newer.example"], forScriptID: changedID)
        await second.removeUserScript(withId: deletedScript.id)
        await second.setUserScriptDisabledHosts(["unrelated.example"], forScriptID: "unrelated-key")

        let cloudApplied = await first.applyCloudUserScriptDisabledHosts(
            desired: [
                changedID: ["remote-should-not-win.example"],
                unchangedID: ["remote-applied.example"],
                deletedID: ["must-not-resurrect.example"],
            ],
            baseline: baseline
        )
        expect(cloudApplied, "conditional Cloud disabled-host mutation should complete")

        let verifier = await makeManager(root: root, standard: standard, group: group)
        await verifier.loadData()
        let final = verifier.getUserScriptDisabledHosts()
        expect(final[changedID] == ["popup-newer.example"],
               "concurrent persisted popup edit must survive conditional Cloud projection")
        expect(final[unchangedID] == ["remote-applied.example"],
               "unchanged baseline key should receive remote disabled-host projection")
        expect(final[deletedID] == nil, "a script deleted during Cloud apply must not regain an orphan host entry")
        expect(final["unrelated-key"] == ["unrelated.example"], "Cloud apply must preserve unrelated persisted keys")

        let cleared = await verifier.applyCloudUserScriptDisabledHosts(
            desired: [unchangedID: []], baseline: final
        )
        expect(cleared && verifier.getUserScriptDisabledHosts()[unchangedID] == nil,
               "an explicit empty remote host list must clear an unchanged key")
    }

    private static func testCorruptMainWithoutBackup(root: URL) async {
        let standardSuite = "test.wblock.protobuf.no-backup.standard.\(UUID().uuidString)"
        let groupSuite = "test.wblock.protobuf.no-backup.group.\(UUID().uuidString)"
        let standard = UserDefaults(suiteName: standardSuite)!
        let group = UserDefaults(suiteName: groupSuite)!
        defer {
            standard.removePersistentDomain(forName: standardSuite)
            group.removePersistentDomain(forName: groupSuite)
        }

        let manager = await makeManager(root: root, standard: standard, group: group)
        await manager.loadData()
        let dataURL = root.appendingPathComponent("wblock_data.pb")
        let backupURL = root.appendingPathComponent("wblock_data_backup.pb")
        try! FileManager.default.removeItem(at: backupURL)
        let corruptBytes = Data([0xff, 0x01, 0xff])
        try! corruptBytes.write(to: dataURL, options: .atomic)

        await manager.loadData()
        let repairedBytes = try! Data(contentsOf: dataURL)
        expect(repairedBytes != corruptBytes, "no-backup corruption recovery must install a valid fallback canonical inside recovery")
        expect(FileManager.default.fileExists(atPath: backupURL.path), "fallback recovery must seed a new known-good backup")
        let restarted = await makeManager(root: root, standard: standard, group: group)
        await restarted.loadData()
        let restartedLevel = await restarted.selectedBlockingLevel
        expect(restartedLevel == "recommended", "fallback canonical must survive restart")
    }

    private static func testDurableMigrationAndCorruptionRecovery(root: URL) async {
        let standardSuite = "test.wblock.protobuf.standard.\(UUID().uuidString)"
        let groupSuite = "test.wblock.protobuf.group.\(UUID().uuidString)"
        let standard = UserDefaults(suiteName: standardSuite)!
        let group = UserDefaults(suiteName: groupSuite)!
        defer {
            standard.removePersistentDomain(forName: standardSuite)
            group.removePersistentDomain(forName: groupSuite)
        }
        standard.set(true, forKey: "hasCompletedOnboarding")
        standard.set("legacy-level", forKey: "selectedBlockingLevel")
        group.set(false, forKey: "autoUpdateEnabled")

        let manager = await makeManager(root: root, standard: standard, group: group)
        await manager.loadData()
        let migratedOnboarding = await manager.hasCompletedOnboarding
        let migratedLevel = await manager.selectedBlockingLevel
        let migratedAutoUpdate = await manager.autoUpdateEnabled
        expect(migratedOnboarding, "legacy onboarding state must survive first migration")
        expect(migratedLevel == "legacy-level", "legacy settings must be durably migrated before defaults")
        expect(!migratedAutoUpdate, "legacy auto-update setting must survive first migration")

        let dataURL = root.appendingPathComponent("wblock_data.pb")
        let backupURL = root.appendingPathComponent("wblock_data_backup.pb")
        let flagURL = root.appendingPathComponent("migration_completed.flag")
        expect(FileManager.default.fileExists(atPath: dataURL.path), "migration must persist main data")
        expect(FileManager.default.fileExists(atPath: backupURL.path), "first durable write must seed last-known-good backup")
        expect(FileManager.default.fileExists(atPath: flagURL.path), "migration flag must follow durable data")

        await manager.setSelectedBlockingLevel("newer-level")
        let savedNewer = await manager.saveDataImmediately()
        expect(savedNewer, "second state must persist")
        let corruptBytes = Data([0xff, 0x00, 0xff])
        let backupBytesBeforeUnreadableProbe = try! Data(contentsOf: backupURL)
        try! corruptBytes.write(to: dataURL, options: .atomic)

        // A transient backup read failure must not move/replace either original.
        try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: backupURL.path)
        await manager.loadData()
        let mainAfterUnreadableBackup = try! Data(contentsOf: dataURL)
        expect(mainAfterUnreadableBackup == corruptBytes, "unreadable backup must leave corrupt main in place for retry")
        try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        let backupAfterUnreadableProbe = try! Data(contentsOf: backupURL)
        expect(backupAfterUnreadableProbe == backupBytesBeforeUnreadableProbe, "transient backup read failure must not alter backup bytes")

        await manager.loadData()
        let recoveredLevel = await manager.selectedBlockingLevel
        expect(recoveredLevel == "legacy-level", "corrupt main must recover previous known-good backup")
        await manager.setSelectedBlockingLevel("after-recovery")
        let savedAfterRecovery = await manager.saveDataImmediately()
        expect(savedAfterRecovery, "recovered store must remain writable")

        let restarted = await makeManager(root: root, standard: standard, group: group)
        await restarted.loadData()
        let restartedLevel = await restarted.selectedBlockingLevel
        expect(restartedLevel == "after-recovery", "mutation after repair must survive restart")
    }

    private static func testMigrationFailureAndCanonicalPrecedence(root: URL) async {
        let standardSuite = "test.wblock.protobuf.failure.standard.\(UUID().uuidString)"
        let groupSuite = "test.wblock.protobuf.failure.group.\(UUID().uuidString)"
        let standard = UserDefaults(suiteName: standardSuite)!
        let group = UserDefaults(suiteName: groupSuite)!
        defer {
            standard.removePersistentDomain(forName: standardSuite)
            group.removePersistentDomain(forName: groupSuite)
        }

        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try! FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        let failing = await makeManager(root: root, standard: standard, group: group)
        await failing.loadData()
        let failedMain = root.appendingPathComponent("wblock_data.pb")
        let failedFlag = root.appendingPathComponent("migration_completed.flag")
        expect(!FileManager.default.fileExists(atPath: failedMain.path), "failed migration must not create defaults/main")
        expect(!FileManager.default.fileExists(atPath: failedFlag.path), "failed migration must not stamp completion flag")
        try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)

        standard.set("legacy-poison", forKey: "selectedBlockingLevel")
        let seed = await makeManager(root: root, standard: standard, group: group)
        await seed.loadData()
        await seed.setSelectedBlockingLevel("canonical")
        let canonicalSaved = await seed.saveDataImmediately()
        expect(canonicalSaved, "canonical seed must persist")
        try? FileManager.default.removeItem(at: failedFlag)

        standard.set("legacy-should-not-win", forKey: "selectedBlockingLevel")
        let canonicalReader = await makeManager(root: root, standard: standard, group: group)
        await canonicalReader.loadData()
        let canonicalLevel = await canonicalReader.selectedBlockingLevel
        expect(canonicalLevel == "canonical", "existing canonical store must win when migration flag is missing")
        expect(FileManager.default.fileExists(atPath: failedFlag.path), "valid canonical store should restamp missing migration flag")

        await testConcurrentInitialization(root: root.appendingPathComponent("concurrent-init"))
    }

    private static func testConcurrentInitialization(root: URL) async {
        let standardSuiteA = "test.wblock.protobuf.concurrent.standard.a.\(UUID().uuidString)"
        let standardSuiteB = "test.wblock.protobuf.concurrent.standard.b.\(UUID().uuidString)"
        let groupSuiteA = "test.wblock.protobuf.concurrent.group.a.\(UUID().uuidString)"
        let groupSuiteB = "test.wblock.protobuf.concurrent.group.b.\(UUID().uuidString)"
        let standardA = UserDefaults(suiteName: standardSuiteA)!
        let standardB = UserDefaults(suiteName: standardSuiteB)!
        let groupA = UserDefaults(suiteName: groupSuiteA)!
        let groupB = UserDefaults(suiteName: groupSuiteB)!
        defer {
            standardA.removePersistentDomain(forName: standardSuiteA)
            standardB.removePersistentDomain(forName: standardSuiteB)
            groupA.removePersistentDomain(forName: groupSuiteA)
            groupB.removePersistentDomain(forName: groupSuiteB)
        }
        standardA.set("candidate-a", forKey: "selectedBlockingLevel")
        standardB.set("candidate-b", forKey: "selectedBlockingLevel")

        let managerA = await makeManager(root: root, standard: standardA, group: groupA)
        let managerB = await makeManager(root: root, standard: standardB, group: groupB)
        async let loadA: Void = managerA.loadData()
        async let loadB: Void = managerB.loadData()
        _ = await (loadA, loadB)

        let finalA = await managerA.selectedBlockingLevel
        let finalB = await managerB.selectedBlockingLevel
        expect(finalA == finalB, "concurrent initializers must converge on one canonical store")
        expect(finalA == "candidate-a" || finalA == "candidate-b", "canonical store must be one complete migration candidate")
        expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration_completed.flag").path),
               "migration flag must be written only after coordinated canonical initialization")
    }

    private static func testThreeWayDeletionAndInsertion(root: URL) async {
        let standardSuite = "test.wblock.protobuf.merge.standard.\(UUID().uuidString)"
        let groupSuite = "test.wblock.protobuf.merge.group.\(UUID().uuidString)"
        let standard = UserDefaults(suiteName: standardSuite)!
        let group = UserDefaults(suiteName: groupSuite)!
        defer {
            standard.removePersistentDomain(forName: standardSuite)
            group.removePersistentDomain(forName: groupSuite)
        }

        let seed = await makeManager(root: root, standard: standard, group: group)
        await seed.loadData()
        let base = FilterList(
            name: "Base",
            url: URL(string: "https://example.com/base.txt")!,
            category: .ads,
            isSelected: true
        )
        await seed.updateFilterLists([base])

        let deleter = await makeManager(root: root, standard: standard, group: group)
        let staleWriter = await makeManager(root: root, standard: standard, group: group)
        await deleter.loadData()
        await staleWriter.loadData()
        await deleter.removeFilterList(withId: base.id)
        await MainActor.run { staleWriter.setUserScriptShowEnabledOnly(true) }
        let staleSave = await staleWriter.saveDataImmediately()
        expect(staleSave, "stale unrelated writer must save")

        let deletionVerifier = await makeManager(root: root, standard: standard, group: group)
        await deletionVerifier.loadData()
        let deletionResult = await deletionVerifier.getFilterLists()
        expect(deletionResult.isEmpty, "stale save must not resurrect externally deleted filter")

        await deletionVerifier.updateFilterLists([base])
        let inserter = await makeManager(root: root, standard: standard, group: group)
        let staleCollectionWriter = await makeManager(root: root, standard: standard, group: group)
        await inserter.loadData()
        await staleCollectionWriter.loadData()
        let inserted = FilterList(
            name: "Concurrent",
            url: URL(string: "https://example.com/concurrent.txt")!,
            category: .privacy
        )
        await inserter.updateFilterLists([base, inserted])
        await staleCollectionWriter.updateFilterLists([base])

        let insertionVerifier = await makeManager(root: root, standard: standard, group: group)
        await insertionVerifier.loadData()
        let insertionResult = await insertionVerifier.getFilterLists()
        let ids = Set(insertionResult.map(\.id))
        expect(ids == [base.id, inserted.id], "stale collection replacement must preserve concurrent insertion")
    }

    private static func testLegacyBpcURLMigration(root: URL) async {
        let suite = "test.wblock.bpc.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let gitflic = URL(string: "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=bpc-paywall-filter.txt")!
        let custom = FilterList(name: "BPC", url: gitflic, category: .custom, isCustom: true, isSelected: true)
        let builtIn = FilterList(name: "Bypass Paywalls Clean Filter", url: gitflic, category: .annoyances)
        let seed = await makeManager(root: root, standard: defaults, group: defaults)
        await seed.loadData()
        _ = await seed.updateFilterLists([custom, builtIn])

        let restarted = await makeManager(root: root, standard: defaults, group: defaults)
        await restarted.loadData()
        let lists = restarted.getFilterLists()
        expect(lists.first { $0.id == custom.id }?.url == gitflic, "a user-added gitflic BPC list must keep its URL (#871)")
        expect(lists.first { $0.id == builtIn.id }?.url.host == "pub-d303b9085c0b41b5aa749fc74609d4d9.r2.dev",
               "the built-in gitflic BPC list must still migrate")
    }

    private static func makeManager(
        root: URL,
        standard: UserDefaults,
        group: UserDefaults
    ) async -> ProtobufDataManager {
        ProtobufDataManager.makeIsolatedForTesting(
            dataDirectoryURL: root,
            standardDefaults: standard,
            groupDefaults: group
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
