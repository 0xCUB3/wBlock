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

        print("PASS")
    }
}
