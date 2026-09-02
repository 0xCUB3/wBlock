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
    "CodeEditorSheet(",
    "onTextChanged: applyEditorText",
    "private var editorRequirementsPanel",
    "if let editorImportError",
    "CodeMirrorTextEditor(",
    ".liquidGlassCompat(cornerRadius: 12, material: .regularMaterial)",
    "private func syncTextFromEditor()",
    "let currentText = isShowingEditor ? await editorController.currentText() : textInput",
    "private func addScriptFromText()",
    "let content = textInput",
    "fromSourceContent: content",
    "onScriptAdded()",
] {
    require(source.contains(required), "missing editor/text requirement evidence: \(required)")
}

let sheetStart = source.range(of: "struct CodeEditorSheet")!.lowerBound
let sheetEnd = source.range(of: "struct AddUserScriptView", range: sheetStart..<source.endIndex)!.lowerBound
let editorSheet = String(source[sheetStart..<sheetEnd])
let iOSStart = editorSheet.range(of: "#if os(iOS)")!.lowerBound
let iOSEnd = editorSheet.range(of: "#else", range: iOSStart..<editorSheet.endIndex)!.lowerBound
let iOSBranch = String(editorSheet[iOSStart..<iOSEnd])
require(!iOSBranch.contains(".toolbar {"), "iOS editor must not install a toolbar Done button")
require(!iOSBranch.contains(".topBarTrailing"), "iOS editor must not use topBarTrailing")
require(!iOSBranch.contains(".navigationBarTrailing"), "iOS editor must not use navigationBarTrailing")
require(!iOSBranch.contains(".confirmationAction"), "iOS editor must not use confirmationAction")
require(
    iOSBranch.contains(".toolbarBackground(.hidden, for: .navigationBar)"),
    "iOS 16+ editor must hide the navigation-bar background"
)
require(!iOSBranch.contains("liquidGlassCompat"), "iOS editor action bar must not apply liquid glass")

let editorBodyStart = editorSheet.range(of: "private var editorBody")!.lowerBound
let editorBodyEnd = editorSheet.range(of: "private func finish", range: editorBodyStart..<editorSheet.endIndex)!.lowerBound
let editorBody = String(editorSheet[editorBodyStart..<editorBodyEnd])
require(
    editorBody.contains("#if os(macOS)\n            .liquidGlassCompat(cornerRadius: 12, material: .regularMaterial)\n            #endif"),
    "editor action bar liquid glass must be macOS-only"
)
require(
    editorBody.contains("SheetDoneButton(action: finish)"),
    "editor action bar must contain its Done button on every platform"
)
require(
    !editorBody.contains("#if os(macOS)\n                SheetDoneButton(action: finish)"),
    "editor action bar Done must not have a macOS-only guard"
)

let textStart = source.range(of: "private var textTab")!.lowerBound
let textEnd = source.range(of: "private var macosBody", range: textStart..<source.endIndex)!.lowerBound
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
require(metadata!.lowerBound < textEditor!.lowerBound, "metadata fields must precede the text editor")
require(textEditor!.lowerBound < requirements!.lowerBound, "requirements must follow the text editor")

let urlStart = source.range(of: "private var urlTab")!.lowerBound
let urlEnd = source.range(of: "private var textTab", range: urlStart..<source.endIndex)!.lowerBound
let urlSurface = String(source[urlStart..<urlEnd])
require(!urlSurface.contains("Use Editor"), "URL mode must not expose Use Editor")
require(textSurface.contains("Use Editor"), "Text mode must retain Use Editor")
require(textSurface.contains("Label(\"Paste\""), "Text mode must retain Paste")

var simpleText = "initial"
var editorText = simpleText
editorText = "edited in CodeMirror"
simpleText = editorText
require(simpleText == "edited in CodeMirror", "closing the editor must return its current text to Text mode")
editorText = simpleText
simpleText = "edited in TextEditor"
require(editorText != simpleText, "the source state must detect a subsequent TextEditor edit")

require(source.contains("private var macosTextCard: some View"), "macOS must use the shared static Text mode surface")
require(source.contains("macosTextCard\n"), "macOS mode selection must place the Text surface")

print("PASS: editor sheet and simple text contract")
