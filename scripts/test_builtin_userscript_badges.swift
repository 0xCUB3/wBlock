#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlock/UserScriptManagerView.swift", encoding: .utf8)
let core = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)

guard source.contains("isBuiltIn: userScriptManager.isDefaultUserScript(script)") else {
    fputs("FAIL: userscript details do not classify remote built-ins by built-in identity\n", stderr)
    exit(1)
}
guard source.contains("isIntegrated = builtInSection != nil")
    && source.contains(#"Text(script.isIntegrated ? "Integrated" : (script.isUserStyle ? "Userstyle" : "Userscript"))"#) else {
    fputs("FAIL: app-shipped multi-feature cleaners need a compact Integrated type label\n", stderr)
    exit(1)
}
guard !source.contains("Badge(\n                        text: script.isUserStyle")
    && !source.contains(#"Badge(text: "Built-in""#) else {
    fputs("FAIL: type and built-in labels must not clutter the title row\n", stderr)
    exit(1)
}
guard core.contains("name: \"AdGuard Extra\"") && core.contains("isDefaultUserScript") else {
    fputs("FAIL: AdGuard Extra built-in identity is not covered\n", stderr)
    exit(1)
}
print("PASS")
