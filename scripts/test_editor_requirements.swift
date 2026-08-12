#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlock/UserScriptManagerView.swift", encoding: .utf8)
for required in [
    "Label(\"Use Editor\", systemImage: \"curlybraces\")",
    "addMode = .editor",
    ".liquidGlassCompat(cornerRadius: 12, material: .regularMaterial)",
    "CodeMirrorTextEditor(",
    "private var editorImportMessage",
] {
    guard source.contains(required) else {
        fputs("FAIL: missing editor requirement evidence: \(required)\n", stderr)
        exit(1)
    }
}
print("PASS")
