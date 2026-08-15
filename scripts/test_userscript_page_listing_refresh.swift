#!/usr/bin/env swift

import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let handler = try String(
    contentsOfFile: "wBlockCoreService/WebExtensionRequestHandler.swift",
    encoding: .utf8
)
let manager = try String(
    contentsOfFile: "wBlockCoreService/UserScriptManager.swift",
    encoding: .utf8
)

let pageRequestStart = handler.range(of: "private static func handleGetPageUserScriptsRequest")!.lowerBound
let pageRequestEnd = handler.range(
    of: "private static func handleSetUserScriptSiteDisabledState",
    range: pageRequestStart..<handler.endIndex
)!.lowerBound
let pageRequest = String(handler[pageRequestStart..<pageRequestEnd])

require(
    pageRequest.contains("await manager.refreshFromDiskForExecution()"),
    "popup userscript listing must reload shared-container records before reading versions"
)
require(
    pageRequest.range(of: "refreshFromDiskForExecution")!.lowerBound
        < pageRequest.range(of: "pageUserScripts(for:")!.lowerBound,
    "disk refresh must happen before the popup version list is built"
)
require(
    manager.contains("public func refreshFromDiskForExecution()"),
    "cross-process userscript listing depends on the shared disk-refresh boundary"
)
require(
    manager.contains("script1.version != script2.version"),
    "disk refresh must treat a newer persisted version as a real change"
)

print("PASS: popup userscript versions refresh from disk")
