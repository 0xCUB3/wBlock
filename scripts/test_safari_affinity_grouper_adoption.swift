import Foundation

let processorSource = try String(contentsOfFile: "wBlockCoreService/SafariContentBlockerAffinityProcessor.swift", encoding: .utf8)
let projectSource = try String(contentsOfFile: "wBlock.xcodeproj/project.pbxproj", encoding: .utf8)
let resolvedSource = try String(contentsOfFile: "wBlock.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved", encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(projectSource.contains("minimumVersion = 4.3.0;"), "SafariConverterLib minimum version should require the affinity grouper API")
require(resolvedSource.contains("\"identity\" : \"safariconverterlib\"") && resolvedSource.contains("\"version\" : \"4.3.0\""), "Package.resolved should pin SafariConverterLib 4.3.0")

require(processorSource.contains("internal import ContentBlockerConverter"), "affinity processor should import SafariConverterLib")
require(processorSource.contains("AffinityRulesGrouper.group"), "affinity processor should delegate directive parsing to AffinityRulesGrouper")
require(processorSource.contains("return [.socialWidgetsAndAnnoyances, .security]"), "slot 3 should merge social and security affinity groups")
require(processorSource.contains("seenLines.insert(rule).inserted"), "merged affinity groups should de-duplicate rules that map to the same wBlock slot")

require(!processorSource.contains("private enum BlockDestination"), "local affinity block destination parser should be removed")
require(!processorSource.contains("private static func parseDirective"), "local affinity directive parser should be removed")
require(!processorSource.contains("private static func mappedSlots"), "local affinity token-to-slot parser should be removed")

print("PASS: Safari affinity grouper adoption")
