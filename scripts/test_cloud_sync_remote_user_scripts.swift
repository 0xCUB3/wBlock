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
