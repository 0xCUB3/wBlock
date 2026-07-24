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
assertMetadata(tubeSource, "// @noframes", "Tube Cleaner")
assertMetadata(tubeSource, "// @run-at       document-start", "Tube Cleaner")
assertMetadata(tubeSource, "// @inject-into  page", "Tube Cleaner")
assertMetadata(tubeSource, "// @grant        none", "Tube Cleaner")
assertMetadata(tubeSource, "// @version      0.1.0", "Tube Cleaner")
// Localized descriptions ride along in the metadata block.
assertMetadata(tubeSource, "// @description:de", "Tube Cleaner")
assertMetadata(tubeSource, "// @description:ja", "Tube Cleaner")

// Player Cleaner: all sites except YouTube, document-start, page world.
assertMetadata(playerSource, "// @name         Player Cleaner", "Player Cleaner")
assertMetadata(playerSource, "// @match        http://*/*", "Player Cleaner")
assertMetadata(playerSource, "// @match        https://*/*", "Player Cleaner")
assertMetadata(playerSource, "// @exclude      https://www.youtube.com/*", "Player Cleaner")
assertMetadata(playerSource, "// @noframes", "Player Cleaner")
assertMetadata(playerSource, "// @run-at       document-start", "Player Cleaner")
assertMetadata(playerSource, "// @inject-into  page", "Player Cleaner")
assertMetadata(playerSource, "// @grant        none", "Player Cleaner")
assertMetadata(playerSource, "// @version      0.1.0", "Player Cleaner")
assertMetadata(playerSource, "// @description:de", "Player Cleaner")

// Feature coverage: the advertised Vinegar/Baking Soda behaviors.
for needle in [
    "requestPictureInPicture",   // Picture-in-Picture
    "audioOnly",                 // audio-only mode
    "ytp-ad-module",             // ad overlay hiding (CSS)
    "yt-navigate-finish",        // SPA navigation handling
    "visibilityState",           // background playback
    "documentPlayerObserver",    // pre-paint player detection
    "controls",                  // native controls
    "setPlaybackQualityRange",   // quality control via internal API
    "QUALITY_LABELS",            // quality picker labels
    "getPreferredQuality",       // quality preference persistence
    "maxTouchPoints",            // desktop-UA iPadOS detection
    "safe-area-inset-bottom",    // iPhone/iPad toolbar placement
    "findPlayer",                // active Shorts player selection
    "x-webkit-airplay",          // native Safari media capabilities
    "sponsor.ajay.app/api/skipSegments/", // SponsorBlock API
    "crypto.subtle.digest('SHA-256'",      // k-anonymous video-id lookup
    "wblock.tubeCleaner.sponsorBlock",     // persistent SponsorBlock settings
    "data-sponsor-category",               // per-category settings UI
    "Using SponsorBlock",                  // API data attribution
    "cacheSponsorBlockSegments",           // per-session SponsorBlock result cache
    "scheduleNextBoundary",                // precise SponsorBlock boundary timer
    "sponsor.ajay.app/api/branding",        // DeArrow branding API
    "dearrow-thumb.ajay.app",               // DeArrow thumbnail cache
    "wblock.tubeCleaner.deArrow",           // persistent, opt-in DeArrow settings
    "data-dearrow-setting",                 // DeArrow settings panel
    "Using DeArrow",                        // DeArrow attribution
    "cacheDeArrowBranding",                 // bounded per-session branding cache
    "wblock-tc-services-row",               // SB/DA row separate from playback controls
    "data-wblock-native-subtitle",          // native Safari subtitle tracks
    "preferYouTubeCaptions",                // avoid duplicate native + movable captions
    "ANDROID_VR",                          // token-safe YouTube caption metadata fallback
] {
    guard tubeSource.contains(needle) else {
        fail("Tube Cleaner is missing expected feature code: \(needle)")
    }
}
if tubeSource.contains("video::-webkit-media-controls") {
    fail("Tube Cleaner must not style Safari's private media-controls tree")
}
guard tubeSource.contains("buildToolbar(player, video);") else {
    fail("Tube Cleaner must build its quality toolbar for every YouTube player")
}
guard tubeSource.contains("if (getPreferredQuality() !== 'auto') { setPreferredQuality('auto'); }") &&
      tubeSource.contains("if (IS_IOS) {\n            if (getPreferredQuality()") else {
    fail("Tube Cleaner must restore adaptive quality on iOS")
}
guard tubeSource.contains("if (!video.disableRemotePlayback) { video.disableRemotePlayback = true; }") &&
      tubeSource.contains("WebKit requires remote playback to stay disabled") else {
    fail("Tube Cleaner must preserve iOS ManagedMediaSource remote-playback safety")
}
guard tubeSource.contains("#player-control-container,") &&
      tubeSource.contains(".wblock-tc-native .ytp-player-content") else {
    fail("Tube Cleaner must suppress mobile YouTube controls above the native video")
}
guard tubeSource.contains(".wblock-tc-native .ytp-settings-menu,") &&
      tubeSource.contains(".wblock-tc-native .ytp-panel-menu,") else {
    fail("Tube Cleaner must hide YouTube's settings shell while changing quality")
}
guard tubeSource.contains("if (!IS_IOS) { playbackRow.appendChild(audioBtn); }") &&
      tubeSource.contains("if (!IS_IOS) { setPreferredQuality(q); }") else {
    fail("Tube Cleaner must expose non-persistent quality-only controls on iOS")
}
guard tubeSource.contains("playbackRow.appendChild(qualityWrap);") &&
      tubeSource.contains("servicesRow.appendChild(sponsorWrap);") &&
      tubeSource.contains("servicesRow.appendChild(deArrowWrap);") else {
    fail("Tube Cleaner must keep SB and DA on a separate row from quality and audio")
}
for (name, source) in [("Tube Cleaner", tubeSource), ("Player Cleaner", playerSource)] {
    if source.contains("window.addEventListener('blur', onBlur)") {
        fail("\(name) must not enter PiP merely because the window loses focus")
    }
}

for needle in [
    ".video-js",                 // video.js detection
    ".jwplayer",                 // JW Player detection
    ".plyr",                     // Plyr detection
    "playsInline",                // native controls/PiP
    "recoverSidecarTracks",       // native subtitle/chapter recovery
    "navigator.mediaSession",     // system Now Playing integration
    "wblock.playerCleaner.preferences", // persistent playback preferences
    "wblock.playerCleaner.resume",      // per-page resume positions
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
