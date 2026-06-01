import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct CloudSyncLocalUserScriptTests {
    static func main() {
        let bypass = CloudSyncLocalUserScript(name: "Bypass Paywalls Clean", content: "// script A", isEnabled: true)
        let other = CloudSyncLocalUserScript(name: "Other Script", content: "// script B", isEnabled: false)

        let missingAfterDelete = CloudSyncLocalUserScriptReconciler.missingRemoteScriptsToRestore(
            remoteScripts: [bypass],
            localNames: [],
            deletedNames: ["bypass paywalls clean"]
        )
        expect(
            missingAfterDelete.isEmpty,
            "deleted local imports should not be restored during upload reconciliation"
        )

        let missingWithoutDelete = CloudSyncLocalUserScriptReconciler.missingRemoteScriptsToRestore(
            remoteScripts: [bypass, other],
            localNames: ["Bypass Paywalls Clean"],
            deletedNames: []
        )
        expect(
            missingWithoutDelete == [other],
            "only remote local scripts missing locally should be restored"
        )

        let namesToDelete = CloudSyncLocalUserScriptReconciler.localNamesToDeleteDuringRemoteApply(
            localNames: ["Bypass Paywalls Clean", "Local Only Script"],
            remoteScripts: [other],
            deletedNames: ["bypass paywalls clean"]
        )
        expect(
            namesToDelete == ["bypass paywalls clean", "local only script"],
            "remote apply should remove deleted locals and locals absent from the winning payload"
        )

        let normalized = CloudSyncLocalUserScriptReconciler.normalizedName("  Bypass Paywalls Clean  ")
        expect(normalized == "bypass paywalls clean", "names should be normalized consistently")

        // 1. deletedNamesToMergeDuringUploadReconciliation
        let mergedWithLocalReAdd =
            CloudSyncLocalUserScriptReconciler.deletedNamesToMergeDuringUploadReconciliation(
                remoteDeletedNames: ["bypass paywalls clean"],
                localNames: ["Bypass Paywalls Clean"]
            )
        expect(
            mergedWithLocalReAdd.isEmpty,
            "a locally re-added local userscript should not be re-deleted by a stale tombstone"
        )

        let mergedWithoutLocalCopy =
            CloudSyncLocalUserScriptReconciler.deletedNamesToMergeDuringUploadReconciliation(
                remoteDeletedNames: ["bypass paywalls clean"],
                localNames: []
            )
        expect(
            mergedWithoutLocalCopy == ["bypass paywalls clean"],
            "remote local script tombstones should still merge when the script is absent locally"
        )

        // 2. deletedNamesToMergeDuringRemoteApply
        let mergedDuringRemoteApplyWithLiveLocal =
            CloudSyncLocalUserScriptReconciler.deletedNamesToMergeDuringRemoteApply(
                remoteDeletedNames: ["bypass paywalls clean"],
                remoteLocalScripts: [bypass],
                localNames: []
            )
        expect(
            mergedDuringRemoteApplyWithLiveLocal.isEmpty,
            "a live local userscript should win over a stale tombstone during remote apply"
        )

        // 3. deletedNamesToClearDuringUploadReconciliation
        let deletedToKeepDuringUpload =
            CloudSyncLocalUserScriptReconciler.deletedNamesToClearDuringUploadReconciliation(
                existingDeletedNames: ["bypass paywalls clean"],
                localNames: []
            )
        expect(
            deletedToKeepDuringUpload.isEmpty,
            "a local delete marker must survive upload reconciliation while only the stale remote payload still has the script"
        )

        let deletedToClearAfterLocalReAdd =
            CloudSyncLocalUserScriptReconciler.deletedNamesToClearDuringUploadReconciliation(
                existingDeletedNames: ["bypass paywalls clean"],
                localNames: ["Bypass Paywalls Clean"]
            )
        expect(
            deletedToClearAfterLocalReAdd == ["bypass paywalls clean"],
            "re-adding a local userscript locally should clear the local delete marker before upload"
        )

        // 4. deletedNamesToClearDuringReconciliation
        let deletedToClearFromRemoteApply =
            CloudSyncLocalUserScriptReconciler.deletedNamesToClearDuringReconciliation(
                existingDeletedNames: ["bypass paywalls clean"],
                remoteLocalScripts: [bypass],
                localNames: []
            )
        expect(
            deletedToClearFromRemoteApply == ["bypass paywalls clean"],
            "a live remote local userscript should clear a stale local delete marker during remote apply"
        )

        let deletedToClear =
            CloudSyncLocalUserScriptReconciler.deletedNamesToClearDuringReconciliation(
                existingDeletedNames: ["bypass paywalls clean"],
                remoteLocalScripts: [],
                localNames: ["Bypass Paywalls Clean"]
            )
        expect(
            deletedToClear == ["bypass paywalls clean"],
            "re-adding a local userscript locally should clear the local delete marker"
        )

        print("PASS")
    }
}
