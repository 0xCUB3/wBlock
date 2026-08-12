import Foundation
import wBlockCoreService

struct CloudSyncLocalUserScript: Equatable {
    let name: String
    let content: String
    let isEnabled: Bool
    let updatesAutomatically: Bool?
    let category: String?
    let localImportIdentity: String?

    var resolvedUpdatesAutomatically: Bool {
        updatesAutomatically ?? true
    }

    var resolvedCategory: FilterListCategory {
        FilterListCategory(rawValue: category ?? "") ?? .scripts
    }

    init(
        name: String,
        content: String,
        isEnabled: Bool,
        updatesAutomatically: Bool? = nil,
        category: String? = nil,
        localImportIdentity: String? = nil
    ) {
        self.name = name
        self.content = content
        self.isEnabled = isEnabled
        self.updatesAutomatically = updatesAutomatically
        self.category = category
        self.localImportIdentity = localImportIdentity
    }
}

enum CloudSyncLocalUserScriptReconciler {
    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedIdentity(_ identity: String?) -> String? {
        guard let identity else { return nil }
        let value = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func matches(existing: UserScript, remote: CloudSyncLocalUserScript) -> Bool {
        guard existing.isLocal else { return false }
        return matches(
            existing: CloudSyncLocalUserScript(
                name: existing.name,
                content: existing.content,
                isEnabled: existing.isEnabled,
                localImportIdentity: existing.localImportIdentity
            ),
            remote: remote
        )
    }

    static func matches(existing: CloudSyncLocalUserScript, remote: CloudSyncLocalUserScript) -> Bool {
        let existingIdentity = normalizedIdentity(existing.localImportIdentity)
        let remoteIdentity = normalizedIdentity(remote.localImportIdentity)
        if let existingIdentity, let remoteIdentity {
            // Once both sides carry an identity, names are not a fallback: distinct
            // local files are allowed to have the same display name.
            return existingIdentity == remoteIdentity
        }
        // A missing identity means a legacy local record or sync payload. Preserve
        // the historical name match so old data can be upgraded safely.
        return normalizedName(existing.name) == normalizedName(remote.name)
    }

    static func missingRemoteScriptsToRestore(
        remoteScripts: [CloudSyncLocalUserScript],
        localNames: [String],
        deletedNames: Set<String>
    ) -> [CloudSyncLocalUserScript] {
        let legacyLocalScripts = localNames.map {
            CloudSyncLocalUserScript(name: $0, content: "", isEnabled: true)
        }
        return missingRemoteScriptsToRestore(
            remoteScripts: remoteScripts,
            localScripts: legacyLocalScripts,
            deletedNames: deletedNames
        )
    }

    static func localScriptsToDeleteDuringRemoteApply(
        localScripts: [CloudSyncLocalUserScript],
        remoteScripts: [CloudSyncLocalUserScript],
        deletedNames: Set<String>,
        lastSyncedNames: Set<String>,
        deletedIdentities: Set<String> = [],
        lastSyncedIdentities: Set<String> = []
    ) -> Set<String> {
        let deletedNormalizedNames = normalizedNames(deletedNames)
        let syncedNormalizedNames = normalizedNames(lastSyncedNames)
        let deletedNormalizedIdentities = normalizedIdentities(deletedIdentities)
        let syncedNormalizedIdentities = normalizedIdentities(lastSyncedIdentities)

        return Set(localScripts.compactMap { local in
            let normalizedLocalName = normalizedName(local.name)
            guard !normalizedLocalName.isEmpty,
                  !remoteScripts.contains(where: { matches(existing: local, remote: $0) })
            else { return nil }

            if let identity = normalizedIdentity(local.localImportIdentity) {
                if deletedNormalizedIdentities.contains(identity)
                    || syncedNormalizedIdentities.contains(identity) {
                    return identity
                }

                // A legacy name-only marker cannot identify which of two stable
                // imports with the same name was deleted. Keep the local entry when
                // the winning payload contains another stable entry with that name.
                let hasDistinctStableRemoteWithSameName = remoteScripts.contains { remote in
                    normalizedName(remote.name) == normalizedLocalName
                        && normalizedIdentity(remote.localImportIdentity) != nil
                }
                if hasDistinctStableRemoteWithSameName {
                    return nil
                }
                if deletedNormalizedNames.contains(normalizedLocalName)
                    || syncedNormalizedNames.contains(normalizedLocalName) {
                    return identity
                }
                return nil
            }

            guard deletedNormalizedNames.contains(normalizedLocalName)
                    || syncedNormalizedNames.contains(normalizedLocalName)
            else { return nil }
            return normalizedLocalName
        })
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
            return syncedNormalized.contains(normalizedLocal) && !desiredRemote.contains(normalizedLocal)
        }
    }

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

    static func missingRemoteScriptsToRestore(
        remoteScripts: [CloudSyncLocalUserScript],
        localScripts: [CloudSyncLocalUserScript],
        deletedNames: Set<String>,
        deletedIdentities: Set<String> = []
    ) -> [CloudSyncLocalUserScript] {
        let deletedNormalizedNames = normalizedNames(deletedNames)
        let deletedNormalizedIdentities = normalizedIdentities(deletedIdentities)
        return remoteScripts.filter { remote in
            let normalizedRemoteName = normalizedName(remote.name)
            guard !normalizedRemoteName.isEmpty,
                  !localScripts.contains(where: { matches(existing: $0, remote: remote) })
            else { return false }

            if let identity = normalizedIdentity(remote.localImportIdentity) {
                return !deletedNormalizedIdentities.contains(identity)
            }
            return !deletedNormalizedNames.contains(normalizedRemoteName)
        }
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

    private static func normalizedIdentities(_ identities: Set<String>) -> Set<String> {
        Set(identities.compactMap(normalizedIdentity))
    }
}
