#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)
let viewSource = try String(contentsOfFile: "wBlock/UserScriptManagerView.swift", encoding: .utf8)
let onboardingSource = try String(contentsOfFile: "wBlock/OnboardingView.swift", encoding: .utf8)
let tinyShieldURL = "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/tinyShield.user.js"
let tinyShieldDescription = "tinyShield helps block ads reinserted by Ad-Shield on matching sites."

guard !source.contains("name: \"YouTube Ad Blocking\"")
    && source.contains("removeRetiredYouTubeAdBlockIfNeeded()") else {
    fputs("FAIL: unverified YouTube ad blocking userscript should be retired\n", stderr)
    exit(1)
}

guard let definitionsStart = source.range(of: "static let definitions: [BuiltInUserScriptDefinition] = [") else {
    fputs("FAIL: BuiltInUserScripts.definitions block not found\n", stderr)
    exit(1)
}
var definitionsIndex = definitionsStart.upperBound
var definitionsDepth = 1
while definitionsIndex < source.endIndex && definitionsDepth > 0 {
    let character = source[definitionsIndex]
    if character == "[" { definitionsDepth += 1 }
    else if character == "]" { definitionsDepth -= 1 }
    definitionsIndex = source.index(after: definitionsIndex)
}
let definitionsBlock = String(source[definitionsStart.lowerBound..<definitionsIndex])
let sourceOutsideDefinitions = source.replacingOccurrences(of: definitionsBlock, with: "")

guard !definitionsBlock.contains("YouTube Classic")
    && !definitionsBlock.contains("adamlui/youtube-classic")
    && source.contains("retiredYouTubeClassicURL")
    && source.contains("removeRetiredYouTubeAdBlockIfNeeded()")
    && (source.contains("isRetiredYouTubeClassicScript")
        || sourceOutsideDefinitions.contains("adamlui/youtube-classic")) else {
    fputs("FAIL: retired YouTube Classic userscript should not be offered as a built-in\n", stderr)
    exit(1)
}

guard source.contains("name: \"tinyShield\"") else {
    fputs("FAIL: tinyShield built-in userscript definition is missing\n", stderr)
    exit(1)
}

guard source.contains(tinyShieldURL) else {
    fputs("FAIL: tinyShield should use the global upstream userscript URL, not a regional grouped URL\n", stderr)
    exit(1)
}

guard source.contains("name: \"tinyShield\",\n            url: tinyShieldURL,\n            isEnabledByDefault: true,\n            description: tinyShieldDescription") else {
    fputs("FAIL: tinyShield should be enabled by default with a usable description\n", stderr)
    exit(1)
}

guard !source.contains("tinyShieldGroupedDefinition")
    && source.contains("migrateLegacyTinyShieldVariantsIfNeeded()")
    && source.contains("legacyTinyShieldGroupedURLPrefix") else {
    fputs("FAIL: regional tinyShield defaults must be removed and migrated to the full script\n", stderr)
    exit(1)
}

guard source.contains("name: \"Bypass Paywalls Clean\"")
    && source.contains("languages: [\"en\"]")
    && source.contains("func builtInLanguages(for userScript: UserScript)")
    && onboardingSource.contains("!Set(languages).isDisjoint(with: selectedLanguages)")
    && onboardingSource.contains("selectedUserscripts = selectedUserscripts.intersection(visibleDefaultIDs)") else {
    fputs("FAIL: onboarding must show and retain only userscripts matching selected languages\n", stderr)
    exit(1)
}


guard source.contains("description: tinyShieldDescription") else {
    fputs("FAIL: tinyShield definitions should not fall back to the generic Default userscript description\n", stderr)
    exit(1)
}

guard source.contains("refreshDefaultUserScriptDescriptionsIfNeeded()") else {
    fputs("FAIL: existing default userscript placeholders should be refreshed\n", stderr)
    exit(1)
}


guard viewSource.contains("downloadingScriptIDs")
    && viewSource.contains("setUserScript(managedScript, isEnabled: newValue)")
    && !viewSource.contains("Image(systemName: \"arrow.down.circle\")")
    && !viewSource.contains(".disabled(!script.isDownloaded)")
else {
    fputs("FAIL: undownloaded remote userscripts should enable by downloading from the toggle without a separate download button\n", stderr)
    exit(1)
}



guard onboardingSource.contains("isBaselineUserscriptEnabledByDefault")
    && onboardingSource.contains("AdGuard Extra")
    && onboardingSource.contains("localizedCaseInsensitiveCompare(\"tinyShield\")")
    && onboardingSource.contains("visibleBaselineIDs")
else {
    fputs("FAIL: onboarding should enable baseline userscripts by default\n", stderr)
    exit(1)
}

print("PASS: built-in userscript definitions")
