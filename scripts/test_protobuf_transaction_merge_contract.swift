import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let source = try String(contentsOfFile: "wBlockCoreService/ProtobufDataManager.swift", encoding: .utf8)
let disabled = try String(contentsOfFile: "wBlock/AppFilterManager+DisabledSites.swift", encoding: .utf8)
let extensions = try String(contentsOfFile: "wBlockCoreService/ProtobufDataManager+Extensions.swift", encoding: .utf8)

expect(source.contains("storageGeneration &+= 1"), "reset must advance the storage generation")
expect(source.contains("resetFiles(dataURL:"), "reset must use one coordinated storage transaction")
expect(source.contains("guard writeGeneration == storageGeneration else { return false }"), "stale writers must not publish")
expect(source.contains("mergeSettings"), "settings need field-level three-way merge")
expect(source.contains("mergeFilterLists"), "filter lists need ID/field-level three-way merge")
expect(source.contains("explicitlyDeletedFilterIDs"), "filter deletion must be explicit")
expect(extensions.contains("explicitlyDeletedFilterIDs: [id.uuidString]"), "filter deletion API must pass an authoritative tombstone")
expect(disabled.contains("performExclusiveApply"), "fast updates must share full-apply exclusivity")
expect(disabled.contains("self.hasError = !succeeded"), "partial fast failures must remain errors")
expect(disabled.contains("lastKnownDisabledSites = appliedSnapshot"), "fast snapshots advance only after success")
print("PASS: protobuf transaction and merge contract")
