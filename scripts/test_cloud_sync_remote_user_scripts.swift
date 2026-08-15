import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct CloudSyncRemoteUserScriptTests {
    static func main() {
        let retiredTinyShield =
            "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/grouped/a/tinyShield-ar.user.js"
        expect(
            CloudSyncRemoteUserScriptReconciler.normalizedURL("  \(retiredTinyShield)  ").isEmpty,
            "retired regional tinyShield variants must not be restored from stale cloud payloads"
        )
        expect(
            !CloudSyncRemoteUserScriptReconciler.normalizedURL(
                "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/tinyShield.user.js"
            ).isEmpty,
            "the supported global tinyShield userscript must remain syncable"
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
                localRemoteScriptURLs: ["https://example.com/foo.user.js"]
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
                localRemoteScriptURLs: ["https://example.com/foo.user.js"]
            )
        expect(
            deletedToClearAfterLocalReAdd == ["https://example.com/foo.user.js"],
            "re-adding a remote userscript locally should clear the local delete marker before upload"
        )

        let deletedToClear =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringReconciliation(
                existingDeletedURLs: ["https://example.com/foo.user.js"],
                remoteRemoteScriptURLs: [],
                localRemoteScriptURLs: ["https://example.com/foo.user.js"]
            )
        expect(
            deletedToClear == ["https://example.com/foo.user.js"],
            "re-adding a remote userscript locally should clear the local delete marker"
        )

        print("PASS")
    }
}
