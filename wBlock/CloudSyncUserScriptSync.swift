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
        deletedNames: Set<String>
    ) -> Set<String> {
        let localNormalized = Set(localNames.map(normalizedName))
        let desiredRemote = Set(remoteScripts.map { normalizedName($0.name) }).filter { !$0.isEmpty }
        let deletedNormalized = Set(deletedNames.map(normalizedName))

        return localNormalized.filter { normalizedLocal in
            deletedNormalized.contains(normalizedLocal) || !desiredRemote.contains(normalizedLocal)
        }
    }
}
