#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) -> String { try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }

let compiler = source("wBlockCoreService/UserStyleCompiler.swift")
let style = source("wBlockCoreService/UserStyle.swift")
let script = source("wBlockCoreService/UserScript.swift")
let manager = source("wBlockCoreService/UserScriptManager.swift")
let handler = source("wBlockCoreService/WebExtensionRequestHandler.swift")

expect(compiler.contains("SHA256"), "artifacts must use SHA-256 identities")
expect(compiler.contains("compilerRevision") && compiler.contains("optionsDigest"), "artifact must record compiler revision and options")
expect(compiler.contains("UserStylePreprocessorBackend"), "compiler seam must be backend-neutral")
expect(script.contains("compiledStyleBody") && !script.contains("case compiledStyleBody"), "compiled body must remain transient")
expect(manager.contains(".user.css.compiled.v1.json"), "compiled output must use a versioned sidecar")
expect(compiler.contains("optionsDigest") && compiler.contains("compiledBodyDigest") && compiler.contains("validate"), "sidecars must be validated before use")
expect(manager.contains("writeCompiledStyleArtifact") && manager.contains("options: .atomic"), "sidecars must be written atomically")
expect(manager.contains("removeCompiledStyleArtifact"), "sidecars must be removed on plain styles and deletion")
expect(manager.contains("Task.detached") && manager.contains("UserStylePreprocessorService.compile(request)"), "hydration must compile off-main")
expect(handler.contains("compiledBody: script.compiledStyleBody"), "runtime must consume the hydrated artifact")
expect(handler.contains("compiledStyleBody") && handler.contains("compilerRevision(for:"), "runtime payload cache must include artifact identity")
expect(!handler.contains("UserStyleCompiler.compile"), "runtime handler must not invoke the compiler")
expect(style.contains("compileSource: false") && style.contains("requiresCompilation(parsed.preprocessor)"), "runtime parsing must fail closed without a compiled body")
expect(style.range(of: "UserStylePreprocessorService.compile(request)")!.lowerBound < style.range(of: "let (globalCSS, sections) = parseSections(body)")!.lowerBound, "service compilation must precede section parsing")
expect(style.contains("compiledArtifact: UserStyleCompiledArtifact?"), "parsed styles must carry the neutral artifact")
expect(script.contains("compiledStyleCacheKey") && script.contains("digest(content)"), "transient bodies must be keyed by source identity")
expect(script.contains("compiledBody: String? = nil"), "source replacement must atomically accept an optional body")
expect(manager.contains("guard writeUserScriptFiles(newUserScript) else") && manager.contains("CocoaError(.fileWriteUnknown)"), "local import writes before observable mutation")

print("PASS: issue #511 compiled style contract")
