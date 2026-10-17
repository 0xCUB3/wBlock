import Foundation

/// Which way a sync moves when this device and iCloud hold different content.
enum CloudSyncDirection: Equatable {
    case upload
    /// Merge the remote payload into local state, then upload anything local kept.
    case download

    /// Once a device has a last-agreed base, direction follows what changed since then.
    /// Wall-clock stamps can't decide it: a device that only drifted while idle (an
    /// expired tombstone, an app update) stamps its stale snapshot as newest (#995).
    static func resolve(
        remoteHash: String,
        baseHash: String?,
        localUpdatedAt: TimeInterval,
        remoteUpdatedAt: TimeInterval
    ) -> CloudSyncDirection {
        if let baseHash { return remoteHash == baseHash ? .upload : .download }
        return remoteUpdatedAt > localUpdatedAt ? .download : .upload
    }
}
