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

let filterView = source("wBlock/ContentView.swift")
let scriptView = source("wBlock/UserScriptManagerView.swift")
let manager = source("wBlockCoreService/UserScriptManager.swift")
let persistence = source("wBlockCoreService/ProtobufDataManager+Extensions.swift")

// The file importer callback only stages after successful validation; the old
// direct persist-and-dismiss path must not be reachable from the callback.
expect(filterView.contains("stageFile(at: url)"), "filter importer should stage files")
expect(filterView.contains("stagedFile != nil"), "filter Add must require staged content")
expect(filterView.contains("content: stagedFile.content"), "filter Add should persist staged content")
expect(filterView.contains("Text(\"Change File\")"), "filter selection should expose Change File")
expect(!filterView.contains("Text(\"Choose File…\")"), "filter UI must not use an ellipsis Choose File label")

expect(scriptView.contains("stageFile(at: url)"), "userscript importer should stage files")
expect(scriptView.contains("stagedFile != nil && !stagedName"), "userscript Add must require staged valid metadata")
expect(scriptView.contains("fromStagedImport: stagedFile.parsed"), "userscript Add should use the staged parse")
expect(scriptView.contains("Text(\"Change File\")"), "userscript selection should expose Change File")
expect(!scriptView.contains("Text(\"Choose File…\")"), "userscript UI must not use an ellipsis Choose File label")

// Staging must replace metadata fields only after validation, while failures
// leave the existing staged value untouched.
let filterStage = filterView.components(separatedBy: "private func stageFile(at url: URL)").dropFirst().first ?? ""
expect(filterStage.contains("guard !trimmedContent.isEmpty"), "filter staging should validate content")
expect(filterStage.range(of: "stagedFile =")!.lowerBound < filterStage.range(of: "catch")!.lowerBound,
       "filter staging should commit state only after validation")
let scriptStage = scriptView.components(separatedBy: "private func stageFile(at url: URL)").dropFirst().first ?? ""
expect(scriptStage.contains("stageUserScriptImport(fromLocalFile: url)"), "userscript staging should use scoped core parsing")
expect(scriptStage.range(of: "stagedFile =")!.lowerBound < scriptStage.range(of: "catch")!.lowerBound,
       "userscript staging should commit state only after validation")

// Overrides are applied to display metadata only; the import still copies all
// parsed execution descriptors and persists the selected category.
expect(manager.contains("nameOverride: String? = nil"), "import API should accept name overrides")
expect(manager.contains("descriptionOverride: String? = nil"), "import API should accept description overrides")
expect(manager.contains("newUserScript.matches = tempScript.matches"), "import must preserve match patterns")
expect(manager.contains("newUserScript.updateURL = tempScript.updateURL"), "import must preserve update URL")
expect(manager.contains("newUserScript.isUserStyle = tempScript.isUserStyle"), "import must preserve script type")
expect(manager.contains("newUserScript.category = categoryOverride"), "import must persist category override")
expect(persistence.contains("protoUserScript.category = mapFilterListCategoryToProto(userScript.category)"),
       "userscript category must be persisted")

print("PASS: issue 508 staged file import contract")
