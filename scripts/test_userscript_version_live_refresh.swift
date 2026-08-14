#!/usr/bin/env swift

import Foundation

let source = try String(
    contentsOfFile: "wBlock/UserScriptManagerView.swift",
    encoding: .utf8
)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let receiveStart = source.range(of: ".onReceive(userScriptManager.$userScripts)")!.lowerBound
let receiveEnd = source.range(of: ".onChangeCompat(of: tabSelection)", range: receiveStart..<source.endIndex)!.lowerBound
let receiveBody = String(source[receiveStart..<receiveEnd])

require(receiveBody.contains("{ updatedScripts in"), "userscript updates must consume the emitted array")
require(receiveBody.contains("refreshScripts(updatedScripts)"), "userscript updates must refresh from the emitted array")
require(!receiveBody.contains("refreshScripts()"), "userscript updates must not read the pre-assignment manager value")
require(source.contains("private func refreshScripts(_ updatedScripts: [UserScript])"), "the list refresh helper must accept an explicit snapshot")
require(source.contains("scripts = updatedScripts.map { script in"), "list rows must be built from the emitted snapshot")

print("PASS: userscript versions refresh from the published snapshot")
