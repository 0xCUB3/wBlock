// Usage: ag-lookup ADVANCED_RULES URLS ITERATIONS WORK_DIR [SAFARI_VERSION]
//
// Builds a FilterEngine from AdGuard advanced rules through WebExtension.buildFilterEngine,
// then times WebExtension.lookup(pageUrl:topUrl:) over every URL in URLS. Prints one JSON object.
// engineBuildMs covers rule storage plus engine serialization; loadMs is the first lookup
// on a fresh WebExtension, which deserializes the engine from disk.

import ContentBlockerConverter
import FilterEngine
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let args = CommandLine.arguments
guard args.count >= 5, let iterations = Int(args[3]), iterations > 0 else {
    fail("usage: ag-lookup ADVANCED_RULES URLS ITERATIONS WORK_DIR [SAFARI_VERSION]")
}
guard let rulesText = try? String(contentsOfFile: args[1], encoding: .utf8) else {
    fail("cannot read \(args[1])")
}
guard let urlsText = try? String(contentsOfFile: args[2], encoding: .utf8) else {
    fail("cannot read \(args[2])")
}
let pages = urlsText.split(whereSeparator: \.isNewline).compactMap { URL(string: String($0)) }
guard !pages.isEmpty else { fail("no URLs in \(args[2])") }

let workDir = URL(fileURLWithPath: args[4], isDirectory: true)
let safari = args.count > 5 ? SafariVersion(Double(args[5]) ?? 18.0) : SafariVersion(18.0)

func millis(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}

try? FileManager.default.removeItem(at: workDir)
let buildStart = DispatchTime.now()
let builder: WebExtension
do {
    builder = try WebExtension(containerURL: workDir, version: safari)
    _ = try builder.buildFilterEngine(rules: rulesText)
} catch {
    fail("engine build failed: \(error)")
}
let engineBuildMs = millis(since: buildStart)

let reader = try WebExtension(containerURL: workDir, version: safari)
let loadStart = DispatchTime.now()
_ = reader.lookup(pageUrl: pages[0], topUrl: nil)
let loadMs = millis(since: loadStart)

for page in pages { _ = reader.lookup(pageUrl: page, topUrl: nil) }

var samplesUs: [Double] = []
samplesUs.reserveCapacity(pages.count * iterations)
var pagesWithRules = 0
for iteration in 0..<iterations {
    for page in pages {
        let start = DispatchTime.now()
        let config = reader.lookup(pageUrl: page, topUrl: nil)
        samplesUs.append(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1000)
        if iteration == 0, let config,
           !(config.css.isEmpty && config.extendedCss.isEmpty && config.js.isEmpty && config.scriptlets.isEmpty) {
            pagesWithRules += 1
        }
    }
}

samplesUs.sort()
func percentile(_ p: Double) -> Double {
    samplesUs[min(samplesUs.count - 1, Int(Double(samplesUs.count) * p))]
}
let result: [String: Any] = [
    "engineBuildMs": engineBuildMs,
    "loadMs": loadMs,
    "urls": pages.count,
    "iterations": iterations,
    "lookups": samplesUs.count,
    "p50Us": percentile(0.50),
    "p99Us": percentile(0.99),
    "meanUs": samplesUs.reduce(0, +) / Double(samplesUs.count),
    "pagesWithCosmeticRules": pagesWithRules,
]
let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
FileHandle.standardOutput.write(json)
FileHandle.standardOutput.write(Data("\n".utf8))
