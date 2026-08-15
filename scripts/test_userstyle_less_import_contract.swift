#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let value = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("could not read \(path)")
    }
    return value
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func occurrences(of needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

let manager = source("wBlockCoreService/UserScriptManager.swift")
let compiler = source("wBlockCoreService/UserStyleCompiler.swift")
let style = source("wBlockCoreService/UserStyle.swift")
let script = source("wBlockCoreService/UserScript.swift")
let view = source("wBlock/UserScriptManagerView.swift")

expect(style.contains("requiresCompilation(normalizedPreprocessor)"), "compiler-backed styles must compile before section parsing")
expect(style.contains("parsed.isPreprocessorSupported && parsed.isCompiled"), "runtime injection must reject unsupported or failed compilation")
expect(style.range(of: "UserStylePreprocessorService.compile(request)")!.lowerBound < style.range(of: "let (globalCSS, sections) = parseSections(body)")!.lowerBound,
       "preprocessor service must compile before @-moz-document parsing")

expect(compiler.contains("javascriptEnabled: false"), "Less inline JavaScript must stay disabled")
expect(compiler.contains("processImports: false"), "Less must preserve ordinary CSS imports without resolving them")
let host = source("wBlockCoreService/UserStyleCompilerExecutionHost.swift")
expect(host.contains("WKWebViewConfiguration") && host.contains("nonPersistent()"), "compiler must use a fresh nonpersistent WebKit host")
expect(host.contains("new Worker") && host.contains("new Blob"), "compiler must use a fresh Blob Worker")
expect(!compiler.contains("JavaScriptCore") && !compiler.contains("JSContext()"), "production compiler must not use JavaScriptCore")
expect(!compiler.contains("XMLHttpRequest") && !compiler.contains("fetch") && !compiler.contains("navigator"), "compiler sandbox must not expose host APIs")
expect(compiler.contains("JSONSerialization.isValidJSONObject") && host.contains("callAsyncJavaScript"), "compiler inputs must be JSON-compatible before crossing into WebKit")
expect(!compiler.contains("context.setObject("), "compiler must not expose native bridge objects")
expect(!compiler.contains("@convention(block)"), "compiler must not bridge native callbacks")
expect(!compiler.contains("JSValue(object:") && !compiler.contains("bridge.call(withArguments:"), "compiler invocation must remain JSON-only")
expect(compiler.contains("compilerSourceOverrides"), "DEBUG overrides must be resource-specific")
expect(compiler.contains("serializedInputSize"), "compiler input must be bounded before evaluation")
expect(compiler.contains("maximumSourceBytes = 2 * 1024 * 1024"), "compiler source must be bounded")
expect(compiler.contains("maximumOutputBytes = 10 * 1024 * 1024"), "compiler output must be bounded")
expect(manager.contains("public func stageUserScriptImport(fromLocalFile fileURL: URL) async"), "instance staging must leave the main actor")
expect(manager.contains("setResourceValues") && manager.contains("isExcludedFromBackup = true"), "sidecars must be excluded from backup")

for ext in [".less", ".sass", ".scss", ".styl", ".pcss"] {
    expect(script.contains("hasSuffix(\"\(ext)\")"), "\(ext) URLs must validate")
}
expect(style.contains("expectedPreprocessor(for: url)"), "query-value style URLs must classify")
expect(manager.contains("stylePreprocessorMismatch"), "extension/preprocessor mismatches must be rejected")
expect(style.contains("lowercased.hasSuffix(\".less\")"), ".less paths must classify as userstyles")
expect(manager.contains("lowercased.hasSuffix(\".less\")"), ".less local files must stage")
expect(view.contains("UTType(filenameExtension: \"less\")"), "file importer must allow .less")
expect(FileManager.default.fileExists(atPath: "wBlockCoreService/Resources/UserStyleCompiler/less.min.js"),
       "vendored Less compiler bundle must exist")

expect(occurrences(of: ".styleCompilationFailed", in: manager) >= 5,
       "all import, edit, download, and update paths must handle compiler failure")
expect(manager.contains("var candidate = existing"), "editing must validate a copy")
expect(manager.contains("existing.isUserStyle && !candidate.isUserStyle"),
       "editing a userstyle must not remove its style classification")
expect(manager.range(of: "guard writeUserScriptFiles(candidate)")!.lowerBound < manager.range(of: "userScripts[index] = candidate")!.lowerBound,
       "editing must write successfully before mutating in-memory state")
expect(manager.contains("if !style.isPreprocessorSupported") && manager.contains("if !style.isCompiled"),
       "download/update validation must reject unsupported or failed compilation")

func body(of functionName: String) -> String {
    guard let start = manager.range(of: "func \(functionName)") else { return "" }
    let suffix = manager[start.upperBound...]
    let ends = [suffix.range(of: "\n    private func "), suffix.range(of: "\n    public func ")].compactMap { $0?.lowerBound }
    let end = ends.min() ?? suffix.endIndex
    return String(suffix[..<end])
}

for functionName in [
    "downloadUserScriptInBackground(\n        for scriptID: UUID",
    "updateUserScript(_ userScript: UserScript)",
    "updateSingleScript(_ candidate: UserScript)",
    "downloadAndEnableUserScript(_ userScript: UserScript)"
] {
    expect(body(of: functionName).contains("validatedDownloadedUserScriptContent"),
           "\(functionName) must validate downloaded existing-script classification")
}
expect(occurrences(of: "validatedDownloadedUserScriptContent(", in: manager) >= 5,
       "all four download/update paths and the shared validator must be covered")
expect(view.contains("let onSave: (String, String, String) async -> String?"), "editor save must return compiler errors")
expect(view.contains("validationMessage = error"), "editor must present compiler errors")

print("PASS: Less userstyle import contract")
