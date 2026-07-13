import Foundation

let sourceURL = URL(fileURLWithPath: "wBlockCoreService/UserScriptManager.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)

func expect(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expect(
    source.contains("let candidateIDs = userScripts.map(\\.id)"),
    "default downloads should snapshot stable userscript IDs"
)
expect(
    source.contains("private func downloadUserScriptInBackground(for scriptID: UUID"),
    "download helper should accept a stable userscript ID"
)
expect(
    !source.contains("downloadUserScriptInBackground(at:"),
    "download callers must not pass an array index across an await"
)
expect(
    source.contains("guard let currentIndex = indexOfUserScript(withId: scriptID)"),
    "async download callers should re-find scripts after suspension"
)

print("PASS: userscript download index safety")