#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlock/UserScriptManagerView.swift", encoding: .utf8)
let core = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)

guard source.contains("isBuiltIn: userScriptManager.isDefaultUserScript(script)") else {
    fputs("FAIL: userscript details do not classify remote built-ins by built-in identity\n", stderr)
    exit(1)
}
guard source.contains("isBuiltIn: isBuiltIn") else {
    fputs("FAIL: userscript badge view does not use the built-in identity\n", stderr)
    exit(1)
}
guard core.contains("name: \"AdGuard Extra\"") && core.contains("isDefaultUserScript") else {
    fputs("FAIL: AdGuard Extra built-in identity is not covered\n", stderr)
    exit(1)
}
print("PASS")
