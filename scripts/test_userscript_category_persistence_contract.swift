#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) -> String {
    try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let backup = source("wBlock/BackupManager.swift")
let cloud = source("wBlock/CloudSyncManager.swift")
let manager = source("wBlockCoreService/UserScriptManager.swift")
let proto = source("wBlockCoreService/DataModels.proto")

expect(backup.contains("var category: String?"), "backup category must be additive and optional")
expect(backup.contains("decodeIfPresent(String.self, forKey: .category)"), "old backups must decode without category")
expect(backup.contains("script.category = category.flatMap"), "backup import must restore category")
expect(backup.contains("category = userScript.category.rawValue"), "backup export must include category")
expect(cloud.contains("let category: String?"), "CloudSync category must be optional")
expect(cloud.contains("category: script.category.rawValue"), "CloudSync payload must include category")
expect(cloud.contains("if let category = local.category")
    && cloud.contains("setUserScript(existing, category: resolvedCategory, origin: .remoteSync)"), "CloudSync apply must restore local category")
let remoteCategoryGuardPattern = #"if let category = remote\.category,\s+let resolvedCategory = FilterListCategory\(rawValue: category\) \{"#
let remoteCategoryGuardCount = try! NSRegularExpression(pattern: remoteCategoryGuardPattern).numberOfMatches(
    in: cloud,
    range: NSRange(cloud.startIndex..., in: cloud)
)
expect(remoteCategoryGuardCount == 3, "all remote URL category applies must guard and validate remote.category")
expect(!cloud.contains("category: remote.resolvedCategory"), "remote URL category applies must not use resolvedCategory")
expect(cloud.contains("existing.content == local.content"), "CloudSync must compare content before skipping")
expect(cloud.contains("setUserScript(existing, category:"), "CloudSync category changes must not be skipped")
expect(manager.contains("updated.category = existing.category"), "remote updates must preserve category overrides")
expect(proto.contains("FilterListCategory category = 21;"), "protobuf category field must remain compatible")

print("PASS: userscript category persistence contract")
