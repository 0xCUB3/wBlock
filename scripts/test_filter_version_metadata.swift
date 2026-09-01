import Foundation

let processingSource = try read("wBlockCoreService/Utils.swift")
let appUpdaterSource = try read("wBlock/FilterListUpdater.swift")
let sharedUpdaterSource = try read("wBlockCoreService/SharedAutoUpdateManager.swift")

expect(
    processingSource.contains("? rawMetadata.version.map { Self.sanitizeMetadata($0) }")
        && processingSource.contains(": rawMetadata.version"),
    "expected shared metadata parsing to preserve slashes in version values"
)
expect(
    !processingSource.contains("rawMetadata.version.map { Self.sanitizeMetadata($0.replacingOccurrences"),
    "expected shared metadata parsing to stop rewriting version slashes"
)
expect(
    appUpdaterSource.contains("FilterListContentProcessing.parseMetadata(from: content, sanitize: true)"),
    "app updater should use shared metadata parsing with App Store sanitization"
)
expect(
    sharedUpdaterSource.contains("FilterListContentProcessing.parseMetadata(from: content)"),
    "shared auto-update should use shared metadata parsing"
)
expect(
    !sharedUpdaterSource.contains("rawMetadata.version?.replacingOccurrences(of: \"/\", with: \" & \")"),
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
