import Foundation

@main struct CloudSyncCustomFilterTests {
  static func main() async throws {
    // Tombstone decisions are proven and compared with Swift in scripts/proofs.
    // Keep canonicalization and real file reads outside that abstract model.
    let gitflic = "https://gitflic.ru/bpc.txt"
    let mirror = "https://r2.example/bpc.txt"
    let selection = CloudSyncCustomFilterReconciler.builtInSelection(
      selectedURLs: [gitflic, "https://example.com/base.txt"], knownURLs: [mirror, "https://example.com/base.txt"],
      customURLs: [gitflic], canonicalize: { $0 == gitflic ? mirror : $0 })
    precondition(selection.selected == ["https://example.com/base.txt"] && selection.known.contains(mirror))
    precondition(
      CloudSyncCustomFilterReconciler.deletedURLsToMergeDuringUploadReconciliation(
        remoteDeletedURLs: [" https://example.com/list ", ""], localCustomURLs: ["https://example.com/list"]
      ).isEmpty)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let readable = directory.appendingPathComponent("list")
    let empty = directory.appendingPathComponent("empty")
    let invalid = directory.appendingPathComponent("invalid")
    try "||example.com^".write(to: readable, atomically: true, encoding: .utf8)
    try "".write(to: empty, atomically: true, encoding: .utf8)
    try Data([0xff]).write(to: invalid)
    let contents = try await CloudSyncInlineFilterContents.read([("list", readable), ("empty", empty)])
    precondition(contents == ["list": "||example.com^", "empty": ""])
    for file in [directory.appendingPathComponent("missing"), invalid] {
      do {
        _ = try await CloudSyncInlineFilterContents.read([("list", readable), ("failed", file)])
        fatalError("unreadable inline content must fail the payload")
      } catch {}
    }
    print("PASS: custom filter canonicalization and inline file reads")
  }
}
