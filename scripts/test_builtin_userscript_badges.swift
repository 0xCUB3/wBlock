#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlock/UserScriptManagerView.swift", encoding: .utf8)
let badges = try String(contentsOfFile: "wBlock/InfoBadgeSupport.swift", encoding: .utf8)
let core = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)

guard source.contains("isBuiltIn: userScriptManager.isDefaultUserScript(script)") else {
    fputs("FAIL: userscript details do not classify remote built-ins by built-in identity\n", stderr)
    exit(1)
}
guard source.contains("isBuiltIn && builtInDisplayRole == .functionality")
    && source.contains(#"script.name == "Dark Reader""#)
    && source.contains(#"script.name == "Tube Cleaner""#)
    && source.contains(#"script.name == "Player Cleaner""#)
    && source.contains(#"Text(script.isIntegrated ? "Integrated" : (script.isUserStyle ? "Userstyle" : "Userscript"))"#) else {
    fputs("FAIL: Dark Reader and the app-shipped multi-feature cleaners need a compact Integrated type label\n", stderr)
    exit(1)
}
guard badges.contains("case integrated")
    && badges.contains("if isIntegrated {")
    && badges.contains("badges[0] = .integrated")
    && source.contains("isIntegrated: isIntegrated") else {
    fputs("FAIL: integrated scripts need an Integrated badge instead of a Userscript badge in Info\n", stderr)
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
guard !source.contains("if script.name == \"AdGuard Extra\" {") else {
    fputs("FAIL: AdGuard Extra must not duplicate the row's details action with an inline info button\n", stderr)
    exit(1)
}
print("PASS")
