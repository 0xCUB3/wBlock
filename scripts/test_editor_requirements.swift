#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlock/UserScriptManagerView.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

for required in [
    "case text = \"Text\"",
    "TextEditor(text: $textInput)",
    "Button(action: openEditorSheet)",
    ".sheet(isPresented: $isShowingEditor)",
    "AddUserScriptEditorSheet(",
    "onTextChanged: applyEditorText",
    "private var editorRequirementsPanel",
    "if let editorImportError",
    "CodeMirrorTextEditor(",
    ".liquidGlassCompat(cornerRadius: 12, material: .regularMaterial)",
    "private func syncTextFromEditor()",
    "private func addScriptFromText()",
] {
    require(source.contains(required), "missing editor/text requirement evidence: \(required)")
}

let textStart = source.range(of: "private var textTab")!.lowerBound
let textEnd = source.range(of: "private var fileTab", range: textStart..<source.endIndex)!.lowerBound
let textSurface = String(source[textStart..<textEnd])
require(!textSurface.contains("CodeMirrorTextEditor("), "simple Text mode must not embed CodeMirror")
require(!textSurface.contains("openSearch()"), "simple Text mode must not expose Search")
require(!textSurface.contains("Wrap Lines"), "simple Text mode must not expose Wrap controls")

let contentStart = source.range(of: "private var simpleTextContent")!.lowerBound
let contentEnd = source.range(of: "private var macosTextCard", range: contentStart..<source.endIndex)!.lowerBound
let content = String(source[contentStart..<contentEnd])
let textEditor = content.range(of: "TextEditor(text: $textInput)")
let requirements = content.range(of: "editorRequirementsPanel")
let metadata = content.range(of: "userScriptMetaFields")
require(textEditor != nil && requirements != nil && metadata != nil, "Text mode needs its static editor requirements and metadata fields")
require(textEditor!.lowerBound < requirements!.lowerBound, "requirements must follow the text editor")
require(requirements!.lowerBound < metadata!.lowerBound, "requirements must precede metadata fields")
require(source.contains("private var macosTextCard: some View"), "macOS must use the shared static Text mode surface")
require(source.contains("macosTextCard\n"), "macOS mode selection must place the Text surface")

print("PASS: editor sheet and simple text contract")
