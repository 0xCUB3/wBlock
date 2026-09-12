import Foundation

/// Each discarded record points to a survivor, never to another discarded record.
/// Repeated UUIDs are storage corruption and are repaired without deleting their files.
enum UserScriptDuplicateResolver {
    static func removalPairs(
        in scripts: [UserScript],
        protectedIDs: Set<UUID> = []
    ) -> [(older: UserScript, newer: UserScript)] {
        let ranked = scripts.enumerated().sorted { lhs, rhs in
            let a = lhs.element
            let b = rhs.element
            if protectedIDs.contains(a.id) != protectedIDs.contains(b.id) {
                return protectedIDs.contains(a.id)
            }
            if UserScript.isVersionNewer(a.version, than: b.version) { return true }
            if UserScript.isVersionNewer(b.version, than: a.version) { return false }
            if a.isEnabled != b.isEnabled { return a.isEnabled }
            return lhs.offset < rhs.offset
        }
        var seenIDs = Set<UUID>()
        var survivors: [UserScript] = []
        var pairs: [(older: UserScript, newer: UserScript)] = []
        for entry in ranked {
            let script = entry.element
            guard seenIDs.insert(script.id).inserted else { continue }
            if let survivor = survivors.first(where: { matches(script, $0) }) {
                pairs.append((script, survivor))
            } else {
                survivors.append(script)
            }
        }
        return pairs
    }

    private static func matches(_ a: UserScript, _ b: UserScript) -> Bool {
        if let urlA = a.url?.absoluteString, !urlA.isEmpty,
           urlA == b.url?.absoluteString { return true }
        let nameA = a.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nameB = b.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !nameA.isEmpty && nameA == nameB
    }
}
