import Foundation

let serviceSource = try String(contentsOfFile: "wBlockCoreService/wBlockCoreService.swift", encoding: .utf8)

let playerHosts = "www.youtube.com,music.youtube.com"
let upstreamHosts = "m.youtube.com,music.youtube.com,tv.youtube.com,www.youtube.com,youtubekids.com,youtube-nocookie.com"

let replaceHostRules = [
    ("trusted-replace-xhr-response", "'\"adPlacements\"'", "'player?'"),
    ("trusted-replace-xhr-response", "'\"adSlots\"'", "'player?'"),
    ("trusted-replace-fetch-response", "'\"adPlacements\"'", "'player?'"),
    ("trusted-replace-fetch-response", "'\"adSlots\"'", "'player?'"),
    ("trusted-replace-xhr-response", "'\"adPlacements\"'", "'get_watch?'"),
    ("trusted-replace-xhr-response", "'\"adSlots\"'", "'get_watch?'"),
    ("trusted-replace-fetch-response", "'\"adPlacements\"'", "'get_watch?'"),
    ("trusted-replace-fetch-response", "'\"adSlots\"'", "'get_watch?'"),
]
for (name, marker, endpoint) in replaceHostRules {
    let snippet = "\(playerHosts)#%#//scriptlet('\(name)', \(marker), '\"no_ads\"', \(endpoint))"
    guard serviceSource.contains(snippet) else {
        fputs("FAIL: missing YouTube compatibility rule snippet: \(snippet)\n", stderr)
        exit(1)
    }
}

let setConstantPaths = [
    "ytInitialPlayerResponse.playerAds",
    "ytInitialPlayerResponse.adPlacements",
    "ytInitialPlayerResponse.adSlots",
    "playerResponse.playerAds",
    "playerResponse.adPlacements",
    "playerResponse.adSlots",
]
for path in setConstantPaths {
    let snippet = "\(upstreamHosts)#%#//scriptlet('set-constant', '\(path)', 'undefined')"
    guard serviceSource.contains(snippet) else {
        fputs("FAIL: missing YouTube compatibility rule snippet: \(snippet)\n", stderr)
        exit(1)
    }
}

let requiredSnippets = [
    "embeddedCompatibilityRulesVersion = \"6\"",
]
for snippet in requiredSnippets {
    guard serviceSource.contains(snippet) else {
        fputs("FAIL: missing YouTube compatibility rule snippet: \(snippet)\n", stderr)
        exit(1)
    }
}

print("PASS: YouTube compatibility rules")
