#!/usr/bin/env swift

import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func section(_ source: String, from startNeedle: String, to endNeedle: String) -> String {
    guard let start = source.range(of: startNeedle),
          let end = source.range(of: endNeedle, range: start.upperBound..<source.endIndex)
    else {
        fputs("FAIL: missing section from \(startNeedle) to \(endNeedle)\n", stderr)
        exit(1)
    }
    return String(source[start.lowerBound..<end.lowerBound])
}

let apply = try read("wBlock/AppFilterManager+ApplyPipeline.swift")
let autoUpdate = try read("wBlockCoreService/SharedAutoUpdateManager.swift")
let service = try read("wBlockCoreService/wBlockCoreService.swift")
let affinity = try read("wBlockCoreService/SafariContentBlockerAffinityProcessor.swift")

let applyShield = section(
    apply,
    from: "private final class ApplySuspensionShield",
    to: "@MainActor\nprivate final class ApplyBackgroundTaskHandle"
)
let autoUpdateShield = section(
    autoUpdate,
    from: "private final class SuspensionShield",
    to: "/// Actor to ensure"
)
let engineShield = section(
    service,
    from: "private final class EnginePublishSuspensionShield",
    to: "/// Built-in compatibility rules"
)

for (name, shield) in [
    ("apply", applyShield),
    ("auto-update", autoUpdateShield),
    ("engine publish", engineShield),
] {
    require(
        shield.contains("expirationUnwindTimeout") &&
            shield.contains("waitUntilReleased(timeout:") &&
            shield.contains("condition.wait(until: deadline)"),
        "the \(name) expired callback must wait for release with the named bounded timeout"
    )
    require(
        shield.contains("NSCondition") && shield.contains("condition.broadcast()"),
        "the \(name) shield release must wake every concurrent waiter"
    )
    require(
        shield.contains("guard !released"),
        "the \(name) shield release must be idempotent"
    )
}

let appendFile = section(
    service,
    from: "public static func appendFile(",
    to: "public static func appendInline("
)
require(
    appendFile.contains("isCancelled: (() -> Bool)? = nil"),
    "appendFile must accept a defaulted cancellation predicate"
)
require(
    appendFile.contains("while true") && appendFile.contains("throw CancellationError()"),
    "appendFile must throw CancellationError from its chunk loop"
)

let firstAffinityAppend = section(
    affinity,
    from: "public static func appendAffinityFilteredContribution(",
    to: "/// Compatibility overload"
)
let affinityAppendRegion = section(
    affinity,
    from: "public static func appendAffinityFilteredContribution(",
    to: "public static func filteredContent("
)
require(
    firstAffinityAppend.contains("isCancelled: (() -> Bool)? = nil") &&
        firstAffinityAppend.contains("throw CancellationError()"),
    "appendAffinityFilteredContribution must accept cancellation and throw CancellationError"
)
require(
    affinityAppendRegion.components(separatedBy: "isCancelled: (() -> Bool)? = nil").count == 3,
    "both appendAffinityFilteredContribution overloads must accept cancellation"
)
require(
    affinity.contains("for rule in rules") && affinity.contains("if isCancelled?() == true"),
    "affinity filtering must check cancellation while processing rules"
)
require(
    firstAffinityAppend.contains("ContentBlockerChunkedHasher.update") &&
        firstAffinityAppend.contains("isCancelled: isCancelled"),
    "affinity output must hash and write in cancellable chunks"
)
let publicFilteredContent = section(
    affinity,
    from: "public static func filteredContent(",
    to: "private static func filteredContent("
)
require(
    publicFilteredContent.contains("do {") &&
        publicFilteredContent.contains("preconditionFailure") &&
        !publicFilteredContent.contains("try?") &&
        !publicFilteredContent.contains("?? (includeBaseRules ? content : \"\")"),
    "public affinity filtering must never fall back to unfiltered content after an error"
)

let conversion = section(
    service,
    from: "private static func convertFiltersMemoryEfficient(",
    to: "/// Fast update for disabled sites changes only"
)
require(
    conversion.contains("for filter in orderedSelectedFilters") &&
        conversion.contains("if cancellationRequested()") &&
        conversion.contains("throw CancellationError()"),
    "convertFiltersMemoryEfficient must check cancellation once per filter"
)
require(
    conversion.contains("Task.isCancelled || isCancelled?() == true"),
    "conversion cancellation must combine task cancellation with the threaded shield predicate"
)
require(
    conversion.contains("appendInline(") &&
        conversion.contains("isCancelled: cancellationRequested") &&
        conversion.contains("convertFilterFromFileWithOutputChange(") ,
    "inline input and Safari conversion must receive the conversion cancellation predicate"
)
require(
    service.contains("public nonisolated enum ContentBlockerChunkedHasher") &&
        service.contains("let end = min(offset + chunkSize, data.endIndex)"),
    "in-memory SHA-256 updates must use the shared 64KB chunk helper"
)
let converter = section(
    service,
    from: "private static func convertRules(",
    to: "private static func publicSuffixListResourcesAreAvailable"
)
require(
    converter.contains("Progress(totalUnitCount:") &&
        converter.contains("progress.cancel()") &&
        converter.contains("progress: progress") &&
        converter.contains("if progress.isCancelled || cancellationRequested()"),
    "SafariConverterLib conversion must be driven by a cancellable Progress and reject its empty cancel result"
)
require(
    !service.contains("SHA256.hash(data: data)"),
    "whole-buffer service hashes must use chunked SHA-256"
)

print("PASS: suspension unwind waits and hot-loop cancellation contract")
