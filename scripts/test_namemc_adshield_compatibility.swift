import Foundation

let serviceSource = try String(contentsOfFile: "wBlockCoreService/wBlockCoreService.swift", encoding: .utf8)
let injectorSource = try String(contentsOfFile: "wBlock Scripts (iOS)/Resources/userscript-injector.js", encoding: .utf8)

let requiredRules = [
    "||html-load.com^$script,domain=namemc.com",
    "||kumo.network-n.com^$script,domain=namemc.com",
    "||btloader.com^$script,domain=namemc.com",
    "||securepubads.g.doubleclick.net/tag/js/gpt.js$script,domain=namemc.com",
    "||ad-delivery.net^$domain=namemc.com",
    "||k.streamrail.com^$domain=namemc.com",
    "namemc.com##.ad-container",
    "namemc.com##[id^=\"nn_\"]",
    "namemc.com##iframe[src*=\"html-load.com\"]"
]

for rule in requiredRules {
    guard serviceSource.contains(rule) else {
        fputs("FAIL: missing NameMC compatibility rule: \(rule)\n", stderr)
        exit(1)
    }
}

guard serviceSource.contains("embeddedCompatibilityRulesVersion = \"5\"") else {
    fputs("FAIL: compatibility rule version should be bumped when embedded rules change\n", stderr)
    exit(1)
}

guard !injectorSource.contains("window.frameElement") else {
    fputs("FAIL: userscript injector should not inspect window.frameElement in cross-origin ad frames\n", stderr)
    exit(1)
}

guard injectorSource.contains("Page-context injection already verifies execution with a DOM side effect") else {
    fputs("FAIL: userscript injector should document why frameElement probing is avoided\n", stderr)
    exit(1)
}

print("PASS: NameMC Ad-Shield compatibility")
