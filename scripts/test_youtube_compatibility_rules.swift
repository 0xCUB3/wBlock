import Foundation

let serviceSource = try String(contentsOfFile: "wBlockCoreService/wBlockCoreService.swift", encoding: .utf8)

let requiredSnippets = [
    "embeddedCompatibilityRulesVersion = \"5\"",
    "www.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '\"adPlacements\"', '\"no_ads\"', 'player?')",
    "www.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '\"adSlots\"', '\"no_ads\"', 'player?')",
    "www.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '\"adPlacements\"', '\"no_ads\"', 'player?')",
    "www.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '\"adSlots\"', '\"no_ads\"', 'player?')",
    "www.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '\"adPlacements\"', '\"no_ads\"', 'get_watch?')",
    "www.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '\"adSlots\"', '\"no_ads\"', 'get_watch?')",
    "www.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '\"adPlacements\"', '\"no_ads\"', 'get_watch?')",
    "www.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '\"adSlots\"', '\"no_ads\"', 'get_watch?')",
    "www.youtube.com#%#//scriptlet('set-constant', 'ytInitialPlayerResponse.adSlots', 'undefined')",
    "www.youtube.com#%#//scriptlet('set-constant', 'playerResponse.playerAds', 'undefined')",
    "www.youtube.com#%#//scriptlet('set-constant', 'playerResponse.adSlots', 'undefined')"
]

for snippet in requiredSnippets {
    guard serviceSource.contains(snippet) else {
        fputs("FAIL: missing YouTube compatibility rule snippet: \(snippet)\n", stderr)
        exit(1)
    }
}

print("PASS: YouTube compatibility rules")
