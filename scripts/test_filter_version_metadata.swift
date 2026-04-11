import Foundation

let appUpdaterSource = try read("wBlock/FilterListUpdater.swift")
let sharedUpdaterSource = try read("wBlockCoreService/SharedAutoUpdateManager.swift")

expect(
    appUpdaterSource.contains(
        """
        let normalizedVersion =
                    rawMetadata.version
                    .map { sanitizeMetadata($0) }
        """
    ),
    "expected app metadata parsing to preserve slashes in version values"
)
expect(
    !appUpdaterSource.contains(
        """
        let normalizedVersion =
                    rawMetadata.version
                    .map { sanitizeMetadata($0.replacingOccurrences(of: "/", with: " & ")) }
        """
    ),
    "expected app metadata parsing to stop rewriting version slashes"
)
expect(
    sharedUpdaterSource.contains("let normalizedVersion = rawMetadata.version"),
    "expected shared auto-update metadata parsing to preserve raw version text"
)
expect(
    !sharedUpdaterSource.contains("let normalizedVersion = rawMetadata.version?.replacingOccurrences(of: \"/\", with: \" & \")"),
    "expected shared auto-update metadata parsing to stop rewriting version slashes"
)

print("ok")

private func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

private func expect(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
