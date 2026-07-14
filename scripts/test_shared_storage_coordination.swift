import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
}

func expect(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let protobuf = try read("wBlockCoreService/ProtobufDataManager.swift")
let userscriptStorage = try read("wBlockCoreService/UserScriptStorageManager.swift")

for source in [protobuf, userscriptStorage] {
    expect(
        source.contains("let coordinationURL = fileExists(at: dataURL) ? dataURL : directoryURL"),
        "shared storage should coordinate the target file after first creation"
    )
    expect(
        source.contains("coordinate(writingItemAt: coordinationURL"),
        "shared storage should use the narrowed coordination URL"
    )
    expect(
        source.contains("File coordination held for \\(durationMs) ms"),
        "shared storage should report slow coordination windows"
    )
}

expect(
    protobuf.contains("mergePersistedChanges("),
    "protobuf saves should merge fields changed by another process"
)
for field in ["filterLists", "userScripts", "userScriptDisabledHosts"] {
    expect(
        protobuf.contains("\\.\(field)"),
        "cross-process merge should preserve \(field)"
    )
}
expect(
    protobuf.contains("snapshot.autoUpdate = autoUpdate"),
    "cross-process merge should preserve individual auto-update fields"
)

print("PASS: shared storage coordination")
