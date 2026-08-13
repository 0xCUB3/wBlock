import Foundation
import wBlockCoreService

struct CloudSyncLocalUserScript: Codable, Equatable {
    let name: String
    let content: String
    let isEnabled: Bool
    let description: String?
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
        description: String? = nil,
        updatesAutomatically: Bool? = nil,
        category: String? = nil,
        localImportIdentity: String? = nil
    ) {
        self.name = name
        self.content = content
        self.isEnabled = isEnabled
        self.description = description
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
                description: existing.description,
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
            guard !normalizedLocalName.isEmpty else { return nil }

            if let identity = normalizedIdentity(local.localImportIdentity) {
                // A stable tombstone is authoritative even if a stale payload also
                // contains a live record with the same identity.
                if deletedNormalizedIdentities.contains(identity) {
                    return identity
                }
                guard !remoteScripts.contains(where: { matches(existing: local, remote: $0) })
                else { return nil }
                if syncedNormalizedIdentities.contains(identity) {
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

            guard !remoteScripts.contains(where: { matches(existing: local, remote: $0) }),
                  deletedNormalizedNames.contains(normalizedLocalName)
                    || syncedNormalizedNames.contains(normalizedLocalName)
            else { return nil }
            return normalizedLocalName
        })
    }

    /// Returns stable local imports that are absent from the winning payload.
    /// Identity-bearing imports are compared by identity, not display name, so
    /// two files named "Duplicate" can be uploaded independently.
    static func localScriptsNeverSyncedToUpload(
        localScripts: [CloudSyncLocalUserScript],
        remoteScripts: [CloudSyncLocalUserScript],
        deletedNames: Set<String>,
        deletedIdentities: Set<String>,
        lastSyncedNames: Set<String>,
        lastSyncedIdentities: Set<String>
    ) -> [CloudSyncLocalUserScript] {
        let deletedNormalizedNames = normalizedNames(deletedNames)
        let deletedNormalizedIdentities = normalizedIdentities(deletedIdentities)
        let syncedNormalizedNames = normalizedNames(lastSyncedNames)
        let syncedNormalizedIdentities = normalizedIdentities(lastSyncedIdentities)

        return localScripts.filter { local in
            let name = normalizedName(local.name)
            guard !name.isEmpty else { return false }
            if let identity = normalizedIdentity(local.localImportIdentity) {
                guard !deletedNormalizedIdentities.contains(identity),
                      !syncedNormalizedIdentities.contains(identity),
                      !remoteScripts.contains(where: { matches(existing: local, remote: $0) })
                else { return false }
                return true
            }
            guard !deletedNormalizedNames.contains(name),
                  !syncedNormalizedNames.contains(name),
                  !remoteScripts.contains(where: { matches(existing: local, remote: $0) })
            else { return false }
            return true
        }
    }

    static func deletedNamesToClearDuringUploadReconciliation(
        existingDeletedNames: Set<String>,
        localNames: [String]
    ) -> Set<String> {
        normalizedNames(existingDeletedNames)
            .intersection(normalizedNames(localNames))
    }

    static func deletedIdentitiesToClearDuringUploadReconciliation(
        existingDeletedIdentities: Set<String>,
        localScripts: [CloudSyncLocalUserScript]
    ) -> Set<String> {
        normalizedIdentities(existingDeletedIdentities)
            .intersection(identitySet(in: localScripts))
    }

    static func deletedIdentitiesToMergeDuringUploadReconciliation(
        remoteDeletedIdentities: Set<String>,
        localScripts: [CloudSyncLocalUserScript]
    ) -> Set<String> {
        normalizedIdentities(remoteDeletedIdentities)
            .subtracting(identitySet(in: localScripts))
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

    static func deletedIdentitiesToMergeDuringRemoteApply(
        remoteDeletedIdentities: Set<String>,
        remoteLocalScripts: [CloudSyncLocalUserScript],
        localScripts: [CloudSyncLocalUserScript]
    ) -> Set<String> {
        normalizedIdentities(remoteDeletedIdentities)
            .subtracting(identitySet(in: remoteLocalScripts))
            .subtracting(identitySet(in: localScripts))
    }

    static func deletedNamesToClearDuringReconciliation(
        existingDeletedNames: Set<String>,
        remoteLocalScripts: [CloudSyncLocalUserScript],
        localNames: [String],
        remoteDeletedNames: Set<String> = []
    ) -> Set<String> {
        normalizedNames(existingDeletedNames)
            .intersection(normalizedNames(remoteLocalScripts.map(\.name)).union(normalizedNames(localNames)))
            .subtracting(normalizedNames(remoteDeletedNames))
    }

    static func deletedIdentitiesToClearDuringReconciliation(
        existingDeletedIdentities: Set<String>,
        remoteLocalScripts: [CloudSyncLocalUserScript],
        localScripts: [CloudSyncLocalUserScript],
        remoteDeletedIdentities: Set<String> = []
    ) -> Set<String> {
        let liveIdentities = identitySet(in: remoteLocalScripts).union(identitySet(in: localScripts))
        return normalizedIdentities(existingDeletedIdentities)
            .intersection(liveIdentities)
            .subtracting(normalizedIdentities(remoteDeletedIdentities))
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

    static func remoteScriptsAllowedAfterTombstones(
        _ remoteScripts: [CloudSyncLocalUserScript],
        deletedNames: Set<String>,
        deletedIdentities: Set<String>
    ) -> [CloudSyncLocalUserScript] {
        let deletedNormalizedNames = normalizedNames(deletedNames)
        let deletedNormalizedIdentities = normalizedIdentities(deletedIdentities)
        return remoteScripts.filter { remote in
            if let identity = normalizedIdentity(remote.localImportIdentity) {
                return !deletedNormalizedIdentities.contains(identity)
            }
            return !deletedNormalizedNames.contains(normalizedName(remote.name))
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

    private static func identitySet(in scripts: [CloudSyncLocalUserScript]) -> Set<String> {
        Set(scripts.compactMap { normalizedIdentity($0.localImportIdentity) })
    }
}
