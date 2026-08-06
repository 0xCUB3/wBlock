import Foundation

let processorSource = try String(contentsOfFile: "wBlockCoreService/SafariContentBlockerAffinityProcessor.swift", encoding: .utf8)
let serviceSource = try String(contentsOfFile: "wBlockCoreService/wBlockCoreService.swift", encoding: .utf8)
let applyPipelineSource = try String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)
let autoUpdateSource = try String(contentsOfFile: "wBlockCoreService/SharedAutoUpdateManager.swift", encoding: .utf8)
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
require(processorSource.contains("public let contentsByFilterID: [UUID: String]"), "affinity sources should be held in an immutable per-run snapshot")
require(processorSource.contains("public static func snapshot("), "apply runs should create one affinity snapshot")
require(processorSource.components(separatedBy: "String(contentsOf: sourceURL").count == 2, "each affinity source should be read only while creating the snapshot")
require(processorSource.contains("affinitySnapshot.content(for: filter.id)"), "affinity contributions should use the per-run snapshot")
require(serviceSource.contains("let hasAffinityFilters = !affinitySnapshot.isEmpty"), "cache reuse must be disabled for every target when any selected filter has affinity")
require(!serviceSource.contains("filters.contains { affinityFilterIDs.contains($0.id) }"), "cache scope must not depend on the target-assigned filters")
require(applyPipelineSource.contains("let affinitySnapshot = await Task.detached"), "the app apply run should snapshot affinity sources once")
require(autoUpdateSource.contains("let affinitySnapshot = SafariContentBlockerAffinityProcessor.snapshot"), "background rebuilds should pass one affinity snapshot through all targets")

require(!processorSource.contains("private enum BlockDestination"), "local affinity block destination parser should be removed")
require(!processorSource.contains("private static func parseDirective"), "local affinity directive parser should be removed")
require(!processorSource.contains("private static func mappedSlots"), "local affinity token-to-slot parser should be removed")

print("PASS: Safari affinity grouper adoption")
