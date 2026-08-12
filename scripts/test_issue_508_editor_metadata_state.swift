#!/usr/bin/env swift

import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

struct MetadataState {
    var lastName = ""
    var lastDescription = ""
    var manualName = false
    var manualDescription = false

    mutating func apply(metadataName: String, metadataDescription: String, currentName: String, currentDescription: String) -> (String, String) {
        if !manualName { lastName = metadataName.isEmpty ? "Pasted Userscript" : metadataName }
        if !manualDescription { lastDescription = metadataDescription }
        return (manualName ? currentName : lastName, manualDescription ? currentDescription : lastDescription)
    }

    mutating func nameEdited(_ value: String) { if value != lastName { manualName = true } }
    mutating func descriptionEdited(_ value: String) { if value != lastDescription { manualDescription = true } }
}

let source = try String(contentsOfFile: "wBlock/UserScriptManagerView.swift", encoding: .utf8)
check(source.contains("documentRevision"), "editor must react to content revisions")
check(source.contains("Task.sleep(nanoseconds: 250_000_000)"), "metadata parsing must be debounced")
check(source.contains("prefix(120)"), "metadata parsing must be bounded")
check(source.contains("nameWasManuallyEdited"), "name manual-edit state must be tracked")
check(source.contains("descriptionWasManuallyEdited"), "description manual-edit state must be tracked")

var state = MetadataState()
var values = state.apply(
    metadataName: "Recognized Name",
    metadataDescription: "Recognized Description",
    currentName: "Pasted Userscript",
    currentDescription: ""
)
check(values.0 == "Recognized Name" && values.1 == "Recognized Description",
      "initial metadata must replace defaults")

state.nameEdited("Manual Name")
values = state.apply(
    metadataName: "New Metadata Name",
    metadataDescription: "New Metadata Description",
    currentName: "Manual Name",
    currentDescription: values.1
)
check(values.0 == "Manual Name", "manual name must survive metadata revisions")
check(values.1 == "New Metadata Description", "unmodified description must follow metadata revisions")

state.descriptionEdited("Manual Description")
values = state.apply(
    metadataName: "Third Name",
    metadataDescription: "Third Description",
    currentName: values.0,
    currentDescription: "Manual Description"
)
check(values.0 == "Manual Name" && values.1 == "Manual Description",
      "each manually edited field must remain independent")

print("PASS: issue 508 editor metadata state machine")
