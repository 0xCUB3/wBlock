import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let cloud = try String(contentsOfFile: "wBlock/CloudSyncManager.swift", encoding: .utf8)
let manager = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)
expect(cloud.contains("stableLocalPayloadAndMutationBaseline()"), "remote apply must use a stable payload baseline")
expect(cloud.contains("localPayloadBaseline: SyncPayload"), "remote apply must receive the payload baseline")
expect(cloud.contains("currentSettings.selectedBlockingLevel == settingsBaseline.selectedBlockingLevel"), "settings must merge field by field")
expect(cloud.contains("Self.mergeStringSet("), "set-valued sync fields need three-way merging")
expect(cloud.contains("Self.mergeDictionary("), "zapper hosts need per-key three-way merging")
expect(cloud.contains("locallyChangedCustomURLs"), "custom filters need per-URL conflict guards")
expect(cloud.contains("localPayloadDiffersFromRemote"), "final content hash must decide whether remote is current")
expect(cloud.contains("isSelected: mayApplyRemoteSelection ? remoteCustom.isSelected : false"), "new custom selections must honor the race guard")
expect(!cloud.contains("isSelected: remoteCustom.isSelected"), "every new custom-filter path must honor the selection race guard")
expect(cloud.contains("origin: .remoteSync"), "Cloud userscript mutations must identify their origin")
expect(!cloud.contains("URL(string: remote.url)"), "Cloud userscript restores must canonicalize legacy aliases before lookup and download")
expect(manager.contains("if origin == .local { recordScriptMutation"), "remote userscript mutations must not advance local revision")
expect(manager.contains("public func removeUserScript(\n        _ userScript: UserScript,\n        origin:"), "deletions must carry mutation origin")

guard let applyStart = cloud.range(of: "private func applyRemotePayload("),
      let applyEnd = cloud.range(of: "private func encodedSectionEqual", range: applyStart.upperBound..<cloud.endIndex)
else {
    fputs("FAIL: applyRemotePayload not found\n", stderr)
    exit(1)
}
let apply = String(cloud[applyStart.lowerBound..<applyEnd.lowerBound])

func branchesOnOptionalRemote(_ field: String) -> Bool {
    apply.contains("= payload.\(field)")
        || apply.contains("payload.\(field) != nil")
        || apply.contains("payload.\(field) == nil")
}

expect(branchesOnOptionalRemote("filterDisabledDomains"), "missing optional remote filterDisabledDomains must branch on if let / != nil")
expect(!apply.contains("payload.filterDisabledDomains ??"), "missing optional remote filterDisabledDomains must not be coalesced to [] before merge")
expect(branchesOnOptionalRemote("zapperRules"), "missing optional remote zapperRules must branch on if let / != nil")
expect(!apply.contains("payload.zapperRules ??"), "missing optional remote zapperRules must not be coalesced to [:] before merge")
expect(branchesOnOptionalRemote("zapperDisabledDomains"), "missing optional remote zapperDisabledDomains must branch on if let / != nil")
expect(!apply.contains("payload.zapperDisabledDomains ??"), "missing optional remote zapperDisabledDomains must not be coalesced to [] before merge")
print("PASS")
