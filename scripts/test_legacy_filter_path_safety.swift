#!/usr/bin/env swift

import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func safeLegacyURL(name: String, root: URL, prefix: String = "") -> URL? {
    guard !name.isEmpty,
          !name.contains("/"),
          !name.contains("\\"),
          !name.contains("\0"),
          name != ".",
          name != ".."
    else { return nil }
    let expected = root.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = root.appendingPathComponent("\(prefix)\(name).txt")
        .standardizedFileURL.resolvingSymlinksInPath()
    let expectedPath = expected.path.hasSuffix("/") ? expected.path : expected.path + "/"
    return candidate.path.hasPrefix(expectedPath) ? candidate : nil
}

let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("wblock-legacy-path-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

for malicious in ["../escape", "..", ".", "nested/name", "nested\\name", "name\0escape"] {
    check(safeLegacyURL(name: malicious, root: root) == nil,
          "malicious legacy name must be rejected: \(malicious.debugDescription)")
}

let oldURL = try XCTUnwrap(safeLegacyURL(name: "Old Filter", root: root))
let newURL = root.appendingPathComponent("custom-\(UUID().uuidString).txt")
try Data("legacy content".utf8).write(to: oldURL)
try FileManager.default.moveItem(at: oldURL, to: newURL)
check(FileManager.default.fileExists(atPath: newURL.path), "normal legacy migration must still work")
check(!FileManager.default.fileExists(atPath: oldURL.path), "normal legacy migration must remove the old path")

let loader = try String(contentsOfFile: "wBlock/FilterListLoader.swift", encoding: .utf8)
let updater = try String(contentsOfFile: "wBlock/FilterListUpdater.swift", encoding: .utf8)
let affinity = try String(contentsOfFile: "wBlockCoreService/SafariContentBlockerAffinityProcessor.swift", encoding: .utf8)
let manager = try String(contentsOfFile: "wBlock/AppFilterManager+CustomFilters.swift", encoding: .utf8)
for source in [loader, updater, affinity, manager] {
    check(source.contains("safeLegacyFileURL"), "legacy path use must go through the containment-safe helper")
}
check(loader.contains("prefix: \"diff-baseline-\""), "legacy baseline migration must use the safe helper")
check(manager.contains("prefix: \"diff-baseline-\""), "legacy baseline cleanup must use the safe helper")

print("PASS: legacy filter path safety and normal migration")

@inline(__always)
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "test", code: 1) }
    return value
}
