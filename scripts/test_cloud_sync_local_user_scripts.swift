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
        let foo = CloudSyncLocalUserScript(name: "Foo", content: "// script C", isEnabled: true)

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
            deletedNames: ["bypass paywalls clean"],
            lastSyncedNames: ["local only script"]
        )
        expect(
            namesToDelete == ["bypass paywalls clean", "local only script"],
            "remote apply should remove tombstoned locals and previously-synced locals absent from the winning payload"
        )

        // #437: a brand-new local userscript that was never synced must NOT be deleted on the
        // download path just because it is absent from a newer remote payload.
        let neverSyncedKept = CloudSyncLocalUserScriptReconciler.localNamesToDeleteDuringRemoteApply(
            localNames: ["Foo"],
            remoteScripts: [],
            deletedNames: [],
            lastSyncedNames: []
        )
        expect(
            neverSyncedKept.isEmpty,
            "a never-synced, non-tombstoned local script must not be deleted on the download path (#437)"
        )

        // A local script that WAS previously synced and is now absent from remote (e.g. deleted on
        // another device after its tombstone aged out) should still be removed.
        let previouslySyncedRemoved =
            CloudSyncLocalUserScriptReconciler.localNamesToDeleteDuringRemoteApply(
                localNames: ["Foo"],
                remoteScripts: [],
                deletedNames: [],
                lastSyncedNames: ["foo"]
            )
        expect(
            previouslySyncedRemoved == ["foo"],
            "a previously-synced local script absent from the winning remote payload should be removed"
        )

        // A tombstoned local script is removed even when it was never synced.
        let tombstonedRemoved = CloudSyncLocalUserScriptReconciler.localNamesToDeleteDuringRemoteApply(
            localNames: ["Foo"],
            remoteScripts: [],
            deletedNames: ["foo"],
            lastSyncedNames: []
        )
        expect(
            tombstonedRemoved == ["foo"],
            "a tombstoned local script should be removed on the download path"
        )

        // A local script still present in the remote payload is always kept.
        let presentInRemoteKept = CloudSyncLocalUserScriptReconciler.localNamesToDeleteDuringRemoteApply(
            localNames: ["Foo"],
            remoteScripts: [foo],
            deletedNames: [],
            lastSyncedNames: ["foo"]
        )
        expect(
            presentInRemoteKept.isEmpty,
            "a local script still present in the remote payload must be kept"
        )

        // Mixed case: only the tombstoned local is removed; the never-synced local is kept.
        let namesToDeleteNeverSynced =
            CloudSyncLocalUserScriptReconciler.localNamesToDeleteDuringRemoteApply(
                localNames: ["Bypass Paywalls Clean", "Local Only Script"],
                remoteScripts: [other],
                deletedNames: ["bypass paywalls clean"],
                lastSyncedNames: []
            )
        expect(
            namesToDeleteNeverSynced == ["bypass paywalls clean"],
            "a never-synced local absent from remote must be kept; only the tombstoned local is removed (#437)"
        )

        // localNamesNeverSyncedToUpload identifies kept scripts that still need uploading.
        let neverSyncedToUpload = CloudSyncLocalUserScriptReconciler.localNamesNeverSyncedToUpload(
            localNames: ["Foo", "Bar"],
            remoteScripts: [other],
            deletedNames: [],
            lastSyncedNames: []
        )
        expect(
            neverSyncedToUpload == ["foo", "bar"],
            "never-synced, non-tombstoned locals absent from remote should be scheduled for upload (#437)"
        )

        let nothingToUpload = CloudSyncLocalUserScriptReconciler.localNamesNeverSyncedToUpload(
            localNames: ["Foo", "Bar", "Other Script"],
            remoteScripts: [other],
            deletedNames: ["bar"],
            lastSyncedNames: ["foo"]
        )
        expect(
            nothingToUpload.isEmpty,
            "synced, tombstoned, and remote-present locals should not be scheduled for upload"
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
