import Foundation

struct CloudSyncLocalUserScript: Equatable {
    let name: String
    let content: String
    let isEnabled: Bool
    let updatesAutomatically: Bool?

    var resolvedUpdatesAutomatically: Bool {
        updatesAutomatically ?? true
    }

    init(name: String, content: String, isEnabled: Bool, updatesAutomatically: Bool? = nil) {
        self.name = name
        self.content = content
        self.isEnabled = isEnabled
        self.updatesAutomatically = updatesAutomatically
    }
}

enum CloudSyncLocalUserScriptReconciler {
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func missingRemoteScriptsToRestore(
        remoteScripts: [CloudSyncLocalUserScript],
        localNames: [String],
        deletedNames: Set<String>
    ) -> [CloudSyncLocalUserScript] {
        let localNormalized = Set(localNames.map(normalizedName))
        let deletedNormalized = Set(deletedNames.map(normalizedName))

        return remoteScripts.filter { remote in
            let normalizedRemote = normalizedName(remote.name)
            return !normalizedRemote.isEmpty
                && !localNormalized.contains(normalizedRemote)
                && !deletedNormalized.contains(normalizedRemote)
        }
    }

    static func localNamesToDeleteDuringRemoteApply(
        localNames: [String],
        remoteScripts: [CloudSyncLocalUserScript],
        deletedNames: Set<String>,
        lastSyncedNames: Set<String>
    ) -> Set<String> {
        let localNormalized = Set(localNames.map(normalizedName))
        let desiredRemote = Set(remoteScripts.map { normalizedName($0.name) }).filter { !$0.isEmpty }
        let deletedNormalized = normalizedNames(deletedNames)
        let syncedNormalized = normalizedNames(lastSyncedNames)

        return localNormalized.filter { normalizedLocal in
            if deletedNormalized.contains(normalizedLocal) {
                return true
            }
            // Only remove a local script the user previously had synced and that the winning
            // remote payload no longer contains. A local script that was never synced (e.g. a
            // brand-new import that has not uploaded yet) must be kept, not deleted — otherwise
            // it is silently and unrecoverably lost (#437).
            return syncedNormalized.contains(normalizedLocal) && !desiredRemote.contains(normalizedLocal)
        }
    }

    /// Local scripts that should be kept and scheduled for upload during a remote apply: ones that
    /// were never synced, are not tombstoned, and are absent from the winning remote payload.
    static func localNamesNeverSyncedToUpload(
        localNames: [String],
        remoteScripts: [CloudSyncLocalUserScript],
        deletedNames: Set<String>,
        lastSyncedNames: Set<String>
    ) -> Set<String> {
        let desiredRemote = Set(remoteScripts.map { normalizedName($0.name) }).filter { !$0.isEmpty }
        let deletedNormalized = normalizedNames(deletedNames)
        let syncedNormalized = normalizedNames(lastSyncedNames)

        return normalizedNames(localNames).filter { normalizedLocal in
            !deletedNormalized.contains(normalizedLocal)
                && !syncedNormalized.contains(normalizedLocal)
                && !desiredRemote.contains(normalizedLocal)
        }
    }

    static func deletedNamesToClearDuringUploadReconciliation(
        existingDeletedNames: Set<String>,
        localNames: [String]
    ) -> Set<String> {
        normalizedNames(existingDeletedNames)
            .intersection(normalizedNames(localNames))
    }

    static func deletedNamesToMergeDuringUploadReconciliation(
        remoteDeletedNames: Set<String>,
        localNames: [String]
    ) -> Set<String> {
        deletedNamesToMerge(
            remoteDeletedNames: remoteDeletedNames,
            liveLocalNames: normalizedNames(localNames)
        )
    }

    static func deletedNamesToMergeDuringRemoteApply(
        remoteDeletedNames: Set<String>,
        remoteLocalScripts: [CloudSyncLocalUserScript],
        localNames: [String]
    ) -> Set<String> {
        deletedNamesToMerge(
            remoteDeletedNames: remoteDeletedNames,
            liveLocalNames: normalizedNames(remoteLocalScripts.map(\.name))
                .union(normalizedNames(localNames))
        )
    }

    static func deletedNamesToClearDuringReconciliation(
        existingDeletedNames: Set<String>,
        remoteLocalScripts: [CloudSyncLocalUserScript],
        localNames: [String]
    ) -> Set<String> {
        normalizedNames(existingDeletedNames)
            .intersection(normalizedNames(remoteLocalScripts.map(\.name)).union(normalizedNames(localNames)))
    }

    private static func deletedNamesToMerge(
        remoteDeletedNames: Set<String>,
        liveLocalNames: Set<String>
    ) -> Set<String> {
        normalizedNames(remoteDeletedNames).filter { remoteName in
            !remoteName.isEmpty && !liveLocalNames.contains(remoteName)
        }
    }

    private static func normalizedNames(_ names: [String]) -> Set<String> {
        Set(names.map(normalizedName).filter { !$0.isEmpty })
    }

    private static func normalizedNames(_ names: Set<String>) -> Set<String> {
        Set(names.map(normalizedName).filter { !$0.isEmpty })
    }
}
