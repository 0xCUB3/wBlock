#!/usr/bin/env swift

import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let utils = try String(contentsOfFile: "wBlockCoreService/Utils.swift", encoding: .utf8)
let loader = try String(contentsOfFile: "wBlock/FilterListLoader.swift", encoding: .utf8)
check(utils.contains("safeLegacyFileURL"), "legacy cache migration must use a constrained path helper")
check(utils.contains("!name.contains(\"/\")") && utils.contains("!name.contains(\"\\\\\")"), "legacy names must reject path separators")
check(utils.contains("name != \".\"") && utils.contains("name != \"..\""), "legacy names must reject traversal components")
check(utils.contains("resolvingSymlinksInPath"), "legacy paths must remain inside the app-group directory")
check(loader.contains("ContentBlockerIncrementalCache.safeLegacyFileURL"), "all legacy migrations must use the constrained helper")
check(!loader.contains("containerURL.appendingPathComponent(\"\\(filter.name).txt\")"), "loader must not interpolate an unsafe legacy name directly")

print("PASS: legacy filter cache migration path safety")
