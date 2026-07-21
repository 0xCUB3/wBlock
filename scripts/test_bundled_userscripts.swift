#!/usr/bin/env swift

import Foundation

// Validates the bundled "cleaner" userscripts (Tube Cleaner / Player Cleaner):
//   1. each .user.js source passes `node --check`
//   2. each source carries the expected userscript metadata
//   3. the generated Swift constants match the .user.js sources (drift guard)
//   4. the generated Swift file parses
//   5. UserScriptManager wires the bundled scripts in and never fetches them
//      from the network

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func read(_ path: String) -> String {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("could not read \(path)")
    }
    return contents
}

@discardableResult
func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
    } catch {
        fail("could not launch \(launchPath): \(error)")
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (process.terminationStatus, output)
}

func which(_ tool: String) -> String? {
    let result = run("/usr/bin/env", ["which", tool])
    guard result.status == 0 else { return nil }
    let path = result.output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    return path.isEmpty ? nil : path
}

let tubeSource = read("wBlockCoreService/BundledUserscripts/tube-cleaner.user.js")
let playerSource = read("wBlockCoreService/BundledUserscripts/player-cleaner.user.js")
let generated = read("wBlockCoreService/BundledUserScriptSources.generated.swift")
let managerSource = read("wBlockCoreService/UserScriptManager.swift")

// --- 1. JavaScript syntax -------------------------------------------------

if let node = which("node") {
    for file in [
        "wBlockCoreService/BundledUserscripts/tube-cleaner.user.js",
        "wBlockCoreService/BundledUserscripts/player-cleaner.user.js",
    ] {
        let result = run(node, ["--check", file])
        if result.status != 0 {
            fail("node --check failed for \(file):\n\(result.output)")
        }
    }
} else {
    fputs("WARN: node not found; skipping JS syntax check\n", stderr)
}

// --- 2. Metadata ----------------------------------------------------------

func assertMetadata(_ source: String, _ needle: String, _ context: String) {
    guard source.contains(needle) else {
        fail("\(context) metadata is missing: \(needle)")
    }
}

// Tube Cleaner: YouTube only, document-start, page world.
assertMetadata(tubeSource, "// @name         Tube Cleaner", "Tube Cleaner")
assertMetadata(tubeSource, "// @match        https://www.youtube.com/*", "Tube Cleaner")
assertMetadata(tubeSource, "// @match        https://www.youtube-nocookie.com/*", "Tube Cleaner")
assertMetadata(tubeSource, "// @run-at       document-start", "Tube Cleaner")
assertMetadata(tubeSource, "// @inject-into  page", "Tube Cleaner")
assertMetadata(tubeSource, "// @grant        none", "Tube Cleaner")
assertMetadata(tubeSource, "// @version      4.1.0", "Tube Cleaner")
// Localized descriptions ride along in the metadata block.
assertMetadata(tubeSource, "// @description:de", "Tube Cleaner")
assertMetadata(tubeSource, "// @description:ja", "Tube Cleaner")

// Player Cleaner: all sites except YouTube, document-start, page world.
assertMetadata(playerSource, "// @name         Player Cleaner", "Player Cleaner")
assertMetadata(playerSource, "// @match        http://*/*", "Player Cleaner")
assertMetadata(playerSource, "// @match        https://*/*", "Player Cleaner")
assertMetadata(playerSource, "// @exclude      https://www.youtube.com/*", "Player Cleaner")
assertMetadata(playerSource, "// @run-at       document-start", "Player Cleaner")
assertMetadata(playerSource, "// @inject-into  page", "Player Cleaner")
assertMetadata(playerSource, "// @grant        none", "Player Cleaner")
assertMetadata(playerSource, "// @version      1.4.0", "Player Cleaner")
assertMetadata(playerSource, "// @description:de", "Player Cleaner")

// Feature coverage: the advertised Vinegar/Baking Soda behaviors.
for needle in [
    "requestPictureInPicture",   // Picture-in-Picture
    "audioOnly",                 // audio-only mode
    "ytp-ad-module",             // ad overlay hiding (CSS)
    "yt-navigate-finish",        // SPA navigation handling
    "visibilityState",           // background playback
    "_wblockPatched",            // video element listener interception
    "controls",                  // native controls
    "setPlaybackQualityRange",   // quality control via internal API
    "QUALITY_LABELS",            // quality picker labels
    "getPreferredQuality",       // quality preference persistence
] {
    guard tubeSource.contains(needle) else {
        fail("Tube Cleaner is missing expected feature code: \(needle)")
    }
}
for needle in [
    ".video-js",                 // video.js detection
    ".jwplayer",                 // JW Player detection
    ".plyr",                     // Plyr detection
    "requestPictureInPicture".count > 0 ? "playsInline" : "playsInline", // native controls/PiP
] {
    guard playerSource.contains(needle) else {
        fail("Player Cleaner is missing expected feature code: \(needle)")
    }
}

// --- 3. Drift guard: generated constants match the .user.js sources -------

func extractConstant(_ source: String, _ name: String) -> String {
    let openMarker = "static let \(name) = ###\"\"\"\n"
    guard let openRange = source.range(of: openMarker) else {
        fail("generated Swift is missing constant \(name)")
    }
    let bodyStart = openRange.upperBound
    guard let closeRange = source.range(of: "\n\"\"\"###", range: bodyStart..<source.endIndex) else {
        fail("generated Swift constant \(name) is not terminated")
    }
    return String(source[bodyStart..<closeRange.lowerBound])
}

func normalized(_ value: String) -> String {
    var result = value
    while result.hasSuffix("\n") { result.removeLast() }
    return result
}

let tubeConstant = extractConstant(generated, "tubeCleaner")
let playerConstant = extractConstant(generated, "playerCleaner")

if normalized(tubeConstant) != normalized(tubeSource) {
    fail("generated tubeCleaner constant drifted from tube-cleaner.user.js; run scripts/generate_bundled_userscripts.py")
}
if normalized(playerConstant) != normalized(playerSource) {
    fail("generated playerCleaner constant drifted from player-cleaner.user.js; run scripts/generate_bundled_userscripts.py")
}

// --- 4. Generated Swift parses --------------------------------------------

if let swiftc = which("swiftc") {
    let result = run(swiftc, ["-parse", "wBlockCoreService/BundledUserScriptSources.generated.swift"])
    if result.status != 0 {
        fail("generated Swift does not parse:\n\(result.output)")
    }
} else {
    fputs("WARN: swiftc not found; skipping generated Swift parse check\n", stderr)
}

// --- 5. Swift wiring ------------------------------------------------------

for needle in [
    "let bundledContent: String?",
    "static let tubeCleanerURL",
    "static let playerCleanerURL",
    "bundledContent: BundledUserScriptSources.tubeCleaner",
    "bundledContent: BundledUserScriptSources.playerCleaner",
    "static func bundledContent(forURL url: String) -> String?",
    "private func applyBundledContent(to userScript: inout UserScript, content: String)",
    "private func refreshBundledUserScriptsIfNeeded() async",
    "await refreshBundledUserScriptsIfNeeded()",
] {
    guard managerSource.contains(needle) else {
        fail("UserScriptManager is missing bundled wiring: \(needle)")
    }
}

// Bundled scripts must be excluded from every network fetch path.
for needle in [
    "// Bundled userscripts ship embedded in the app and are refreshed by",  // downloadMissingDefaultScripts
    "// Bundled userscripts carry their metadata in the app; never fetch it.",  // shouldPrefetchMetadata
    "// Bundled userscripts update with the app, never from a URL.",  // autoUpdateEnabledUserScripts
    "// Bundled userscripts are reinstalled from the app, never downloaded.",  // ensureScriptReadyForEnabling
] {
    guard managerSource.contains(needle) else {
        fail("UserScriptManager lost a bundled network-fetch guard: \(needle)")
    }
}

print("PASS: bundled cleaner userscripts")
