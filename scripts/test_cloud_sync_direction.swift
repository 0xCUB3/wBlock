import Foundation

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct CloudSyncDirectionTests {
    static func main() {
        expect(
            CloudSyncDirection.resolve(remoteHash: "theirs", baseHash: "agreed", localUpdatedAt: 200, remoteUpdatedAt: 100) == .download,
            "a device whose stamp moved forward while idle must merge newer remote changes instead of overwriting them"
        )
        expect(
            CloudSyncDirection.resolve(remoteHash: "agreed", baseHash: "agreed", localUpdatedAt: 100, remoteUpdatedAt: 200) == .upload,
            "an unchanged remote should take local edits even when its stamp is newer"
        )
        expect(
            CloudSyncDirection.resolve(remoteHash: "theirs", baseHash: nil, localUpdatedAt: 200, remoteUpdatedAt: 100) == .upload,
            "without a base, the newer local stamp still decides"
        )
        expect(
            CloudSyncDirection.resolve(remoteHash: "theirs", baseHash: nil, localUpdatedAt: 100, remoteUpdatedAt: 200) == .download,
            "without a base, the newer remote stamp still decides"
        )
    }
}
