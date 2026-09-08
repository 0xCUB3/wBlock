import Foundation
import wBlockCoreService

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct CloudSyncRemoteUserScriptTests {
    static func main() {
        let notificationScript = UserScript(name: "Notification probe", url: URL(string: "https://example.com/probe.user.js"))
        for origin: UserScriptMutationOrigin in [.local, .remoteSync] {
            for isNew in [false, true] {
                let info = UserScriptManagerNotificationKey.userInfo(
                    for: notificationScript, origin: origin, isNewAddition: isNew
                )
                expect(
                    UserScriptManagerNotificationKey.identifiesLocalAddition(info) == (origin == .local && isNew),
                    "only an actual local insertion may create a re-add intent"
                )
            }
        }
        expect(!UserScriptManagerNotificationKey.identifiesLocalAddition(nil), "missing notification metadata is not an add intent")
        expect(
            !UserScriptManagerNotificationKey.identifiesLocalAddition([UserScriptManagerNotificationKey.isRemoteSync: false]),
            "legacy update notifications without insertion evidence must not create an add intent"
        )
        let retiredTinyShield =
            "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/grouped/a/tinyShield-ar.user.js"
        expect(
            CloudSyncRemoteUserScriptReconciler.normalizedURL("  \(retiredTinyShield)  ").isEmpty,
            "retired regional tinyShield variants must not be restored from stale cloud payloads"
        )
        let retiredYouTubeURLs = [
            "https://raw.githubusercontent.com/SysAdminDoc/YoutubeAdblock/main/YoutubeAdblock.user.js",
            "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/greasemonkey/youtube-classic.user.js",
        ]
        for retiredURL in retiredYouTubeURLs {
            expect(
                CloudSyncRemoteUserScriptReconciler.normalizedURL("  \(retiredURL)  ").isEmpty,
                "retired YouTube userscripts must not be restored from stale cloud payloads"
            )
            expect(
                CloudSyncRemoteUserScriptReconciler.canonicalURL(retiredURL) == nil,
                "retired YouTube userscripts must not produce a restorable URL"
            )
        }
        let retiredYouTubeClassicVariant =
            "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/dist/youtube-classic.user.js"
        expect(
            CloudSyncRemoteUserScriptReconciler.normalizedURL(retiredYouTubeClassicVariant).isEmpty,
            "YouTube Classic path variants must not be restored from stale cloud payloads"
        )
        expect(
            CloudSyncRemoteUserScriptReconciler.canonicalURL(retiredYouTubeClassicVariant) == nil,
            "YouTube Classic path variants must not produce a restorable URL"
        )
        let globalTinyShield =
            "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/tinyShield.user.js"
        expect(
            CloudSyncRemoteUserScriptReconciler.normalizedURL(globalTinyShield) == globalTinyShield,
            "the supported global tinyShield userscript must remain syncable"
        )
        let liveScript = "https://example.com/live.user.js"
        expect(
            CloudSyncRemoteUserScriptReconciler.normalizedURL("  \(liveScript)  ") == liveScript,
            "live non-retired userscripts must still normalize"
        )
        let migratedURLs = [
            "https://bundled.wblock.invalid/tube-cleaner.user.js":
                "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/tube-cleaner/dist/tube-cleaner.user.js",
            "https://bundled.wblock.invalid/player-cleaner.user.js":
                "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/player-cleaner/dist/player-cleaner.user.js",
            "https://bundled.wblock.invalid/dark-reader.user.js":
                "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/dark-reader/dist/dark-reader.user.js",
        ]
        for (legacy, canonical) in migratedURLs {
            expect(
                CloudSyncRemoteUserScriptReconciler.normalizedURL("  \(legacy)  ") == canonical,
                "legacy userscript identity must normalize to \(canonical)"
            )
            expect(
                CloudSyncRemoteUserScriptReconciler.canonicalURL("  \(legacy)  ")?.absoluteString
                    == canonical,
                "legacy userscript restores must download the canonical URL"
            )
        }
        expect(
            CloudSyncRemoteUserScriptReconciler.canonicalURL(retiredTinyShield) == nil,
            "retired userscripts must not produce a restorable URL"
        )
        let canonicalTube = migratedURLs[
            "https://bundled.wblock.invalid/tube-cleaner.user.js"
        ]!
        expect(
            CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringRemoteApply(
                remoteDeletedURLs: ["https://bundled.wblock.invalid/tube-cleaner.user.js"],
                remoteRemoteScriptURLs: [canonicalTube],
                localRemoteScriptURLs: []
            ).isEmpty,
            "legacy tombstones must not delete a canonical remote userscript"
        )

        let mergedWithLocalReAdd =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringUploadReconciliation(
                remoteDeletedURLs: ["https://example.com/foo.user.js"],
                localRemoteScriptURLs: ["https://example.com/foo.user.js"],
                locallyAddedURLs: ["https://example.com/foo.user.js"]
            )
        expect(
            mergedWithLocalReAdd.isEmpty,
            "a locally re-added remote userscript should not be re-deleted by a stale tombstone"
        )

        let mergedWithoutLocalCopy =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringUploadReconciliation(
                remoteDeletedURLs: ["https://example.com/foo.user.js"],
                localRemoteScriptURLs: []
            )
        expect(
            mergedWithoutLocalCopy == ["https://example.com/foo.user.js"],
            "remote tombstones should still merge when the userscript is absent locally"
        )

        let mergedDuringRemoteApplyWithLiveRemote =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringRemoteApply(
                remoteDeletedURLs: ["https://example.com/foo.user.js"],
                remoteRemoteScriptURLs: ["https://example.com/foo.user.js"],
                localRemoteScriptURLs: []
            )
        expect(
            mergedDuringRemoteApplyWithLiveRemote.isEmpty,
            "a live remote userscript should win over a stale tombstone during remote apply"
        )

        let deletedToKeepDuringUpload =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringUploadReconciliation(
                existingDeletedURLs: ["https://example.com/foo.user.js"],
                localRemoteScriptURLs: []
            )
        expect(
            deletedToKeepDuringUpload.isEmpty,
            "a local delete marker must survive upload reconciliation while only the stale remote payload still has the userscript"
        )

        let deletedToClearFromRemoteApply =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringReconciliation(
                existingDeletedURLs: ["https://example.com/foo.user.js"],
                remoteRemoteScriptURLs: ["https://example.com/foo.user.js"],
                localRemoteScriptURLs: []
            )
        expect(
            deletedToClearFromRemoteApply == ["https://example.com/foo.user.js"],
            "a live remote userscript should clear a stale local delete marker during remote apply"
        )

        let deletedToClearAfterLocalReAdd =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringUploadReconciliation(
                existingDeletedURLs: ["https://example.com/foo.user.js"],
                localRemoteScriptURLs: ["https://example.com/foo.user.js"],
                locallyAddedURLs: ["https://example.com/foo.user.js"]
            )
        expect(
            deletedToClearAfterLocalReAdd == ["https://example.com/foo.user.js"],
            "re-adding a remote userscript locally should clear the local delete marker before upload"
        )

        let deletedToClear =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringReconciliation(
                existingDeletedURLs: ["https://example.com/foo.user.js"],
                remoteRemoteScriptURLs: [],
                localRemoteScriptURLs: ["https://example.com/foo.user.js"],
                locallyAddedURLs: ["https://example.com/foo.user.js"]
            )
        expect(
            deletedToClear == ["https://example.com/foo.user.js"],
            "re-adding a remote userscript locally should clear the local delete marker"
        )

        let url = "https://example.com/previously-synced.user.js"
        let deletedOnAnotherDevice: Set<String> = [url]
        let unchangedLocal: Set<String> = [url]
        let deletion = CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringRemoteApply(
            remoteDeletedURLs: deletedOnAnotherDevice, remoteRemoteScriptURLs: [],
            localRemoteScriptURLs: unchangedLocal
        )
        expect(deletion == [url], "an unchanged local copy must not veto a remote deletion")
        let survivors = unchangedLocal.subtracting(deletion)
        let uploadDeletion = CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringUploadReconciliation(
            remoteDeletedURLs: deletion, localRemoteScriptURLs: survivors
        )
        expect(survivors.isEmpty && uploadDeletion == [url], "the follow-up upload must converge to deletion")
        expect(
            CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringUploadReconciliation(
                remoteDeletedURLs: [url], localRemoteScriptURLs: [url]
            ) == [url],
            "an unrelated local setting change must not resurrect a remotely deleted script during upload"
        )
        expect(
            CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringUploadReconciliation(
                existingDeletedURLs: [url], localRemoteScriptURLs: [url]
            ).isEmpty,
            "mere presence is not an explicit re-add"
        )
        expect(
            CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringRemoteApply(
                remoteDeletedURLs: [url], remoteRemoteScriptURLs: [], localRemoteScriptURLs: [url],
                locallyAddedURLs: [url]
            ).isEmpty,
            "an explicit unsynced re-add must defeat a stale deletion"
        )
        let oldAdd = [url: "generation-1"]
        let newAdd = [url: "generation-2"]
        expect(
            CloudSyncRemoteUserScriptReconciler.additionsAfterAcknowledging(
                current: oldAdd, snapshot: oldAdd, syncedURLs: [url]
            ).isEmpty,
            "successful sync consumes the observed add intent"
        )
        expect(
            CloudSyncRemoteUserScriptReconciler.additionsAfterAcknowledging(
                current: newAdd, snapshot: oldAdd, syncedURLs: [url]
            ) == newAdd,
            "a re-add racing an older sync acknowledgement must survive"
        )
        expect(
            CloudSyncRemoteUserScriptReconciler.additionsAfterAcknowledging(
                current: oldAdd, snapshot: oldAdd, syncedURLs: []
            ) == oldAdd,
            "a payload missing the script cannot acknowledge its addition"
        )
        print("PASS")
    }
}
