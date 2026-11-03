import CryptoKit
import Foundation
import os.log

/// Builds the WebExtension DNR rules used for the subset of `$removeparam` that
/// Safari can express: literal query parameter names and strip-all query rules,
/// plus `$redirect` resource replacements (see RedirectDNRRules.swift).
///
/// This is intentionally conservative. Inverted, malformed, and otherwise
/// unsupported rules are skipped rather than widened into rules that would strip
/// parameters on the wrong requests. Regex-valued rules are expanded to the
/// literal names they match (see `NameVocabulary`); a regex matching no known
/// name is skipped.
public enum RemoveParamDNRRuleGenerator {
    public static let rulesFilename = "removeparam_dnr_rules.json"
    public static let ruleIDBase = 1_500_000
    public static let ruleIDLimit = 1_650_000

    // Current WebKit caps combined dynamic + session rules at 30,000. This is
    // the generated-file ceiling, not an assumption about every supported
    // Safari runtime: the WebExtension installer uses Safari's reported
    // MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES when available and a conservative
    // compatibility ceiling on older runtimes.
    public static let maxGeneratedRules = min(ruleIDLimit - ruleIDBase, 30_000)
    private static let urlFilterSpecialCharacters = CharacterSet(charactersIn: "|*^")
    private static let skippedOptionNames: Set<String> = [
        "app", "cname", "content", "cookie", "csp", "header",
        "hls", "jsonprune", "permissions", "redirect", "referrerpolicy",
        "removeheader", "replace", "strict1p", "strict3p", "urlblock", "webrtc"
    ]

    /// Option names that the generator understands. Any option whose name is
    /// not in this set (and not a negated resource type handled elsewhere)
    /// causes the rule to be skipped rather than silently dropped, which
    /// could widen its scope. For example, `$removeparam=v,hinta.fi` uses a
    /// bare-domain syntax that this generator cannot interpret; skipping
    /// the rule avoids generating a global `v`-stripping rule.
    private static let recognizedOptionNames: Set<String> = [
        "removeparam", "domain", "to", "denyallow", "third-party", "~third-party",
        "match-case", "important", "badfilter",
        "doc", "document", "main_frame", "subdocument", "sub_frame",
        "stylesheet", "script", "image", "font", "object",
        "xmlhttprequest", "xhr", "ping", "media", "websocket", "other",
    ]

    /// Common UTM and click-ID names that regex `$removeparam` rules can expand
    /// into even when no list writes them as literals.
    static let commonTrackingParameterNames = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "utm_name", "utm_cid", "utm_reader", "utm_referrer", "utm_social", "utm_brand",
        "utm_place", "utm_pubreferrer", "utm_swu", "utm_viz_id", "utm_creative_format",
        "utm_marketing_tactic", "utm_source_platform"
    ]

    static let resourceTypeMap: [String: [String]] = [
        "doc": ["main_frame"],
        "document": ["main_frame"],
        "main_frame": ["main_frame"],
        "subdocument": ["sub_frame"],
        "sub_frame": ["sub_frame"],
        "stylesheet": ["stylesheet"],
        "script": ["script"],
        "image": ["image"],
        "font": ["font"],
        "object": ["object"],
        "xmlhttprequest": ["xmlhttprequest"],
        "xhr": ["xmlhttprequest"],
        "ping": ["ping"],
        "media": ["media"],
        "websocket": ["websocket"],
        "other": ["other"]
    ]

    public struct Summary: Equatable, Codable {
        func withRedirectCarveOuts(_ count: Int) -> Summary {
            Summary(
                generatedRules: generatedRules, removeParamRules: removeParamRules,
                exceptionRules: exceptionRules, skippedRules: skippedRules,
                truncatedRules: truncatedRules, disabledSiteAllowRules: disabledSiteAllowRules,
                resourceRedirectRules: resourceRedirectRules, redirectCarveOuts: count, version: version
            )
        }

        public let generatedRules: Int
        public let removeParamRules: Int
        public let exceptionRules: Int
        /// Rules the generator could not express safely in DNR.
        public let skippedRules: Int
        /// Supported rules dropped only because the dynamic-rule budget was full.
        public let truncatedRules: Int
        public let disabledSiteAllowRules: Int
        /// Admitted `$redirect` resource replacements.
        public let resourceRedirectRules: Int
        /// Native content-blocker exceptions that let those replacements win.
        public let redirectCarveOuts: Int
        public let version: String

        public init(
            generatedRules: Int,
            removeParamRules: Int,
            exceptionRules: Int,
            skippedRules: Int,
            truncatedRules: Int = 0,
            disabledSiteAllowRules: Int,
            resourceRedirectRules: Int = 0,
            redirectCarveOuts: Int = 0,
            version: String
        ) {
            self.resourceRedirectRules = resourceRedirectRules
            self.redirectCarveOuts = redirectCarveOuts
            self.generatedRules = generatedRules
            self.removeParamRules = removeParamRules
            self.exceptionRules = exceptionRules
            self.skippedRules = skippedRules
            self.truncatedRules = truncatedRules
            self.disabledSiteAllowRules = disabledSiteAllowRules
            self.version = version
        }
    }

    public struct DeclarativeRule: Codable, Equatable {
        public var id: Int
        public var priority: Int
        public var action: RuleAction
        public var condition: RuleCondition
    }

    public struct RuleAction: Codable, Equatable {
        public var type: String
        public var redirect: Redirect?
    }

    public struct Redirect: Codable, Equatable {
        public var transform: URLTransform? = nil
        /// Bundled replacement served by wBlock Scripts for `$redirect` rules.
        public var extensionPath: String? = nil
    }

    public struct URLTransform: Codable, Equatable {
        public var query: String?
        public var queryTransform: QueryTransform?
    }

    public struct QueryTransform: Codable, Equatable {
        public var removeParams: [String]
    }

    public struct RuleCondition: Codable, Equatable {
        public var urlFilter: String? = nil
        /// Safari matches this regex against the request URL (macOS 12.3, iOS 15.4).
        public var regexFilter: String? = nil
        public var resourceTypes: [String]? = nil
        // Safari has supported the legacy initiator-site spelling since the
        // original DNR implementation; `initiatorDomains` arrived much later.
        public var domains: [String]? = nil
        public var excludedDomains: [String]? = nil
        public var requestDomains: [String]? = nil
        public var excludedRequestDomains: [String]? = nil
        public var domainType: String? = nil
        public var isUrlFilterCaseSensitive: Bool? = nil
    }

    private struct ParsedRule {
        var isException: Bool
        var pattern: String
        var removeParamValue: String?
        var options: [String]
    }

    private struct BuildResult {
        var rules: [DeclarativeRule]
        var wasRemoveParamRule: Bool
        var wasExceptionRule: Bool
        var skipped: Bool
    }

    /// The literal `$removeparam` names a regex can expand into: every literal
    /// name in the rules text plus `commonTrackingParameterNames`. A regex is
    /// matched against each name's decoded form, honoring `/i`, so each
    /// regex is evaluated once here rather than once per rule.
    struct NameVocabulary {
        private var matchesByRegex: [String: [String]] = [:]

        init(rulesText: String) {
            var literals = Set(commonTrackingParameterNames)
            var regexValues = Set<String>()
            RuleText.forEachLine(rulesText) { rawLine in
                guard RuleText.containsIgnoringASCIICase(rawLine, "removeparam"),
                      let value = parseRule(String(rawLine))?.removeParamValue,
                      !value.isEmpty
                else { return }
                if value.hasPrefix("/") {
                    regexValues.insert(value)
                } else if isExpressibleLiteralRemoveValue(value) {
                    literals.insert(value)
                }
            }
            let names = literals.sorted()
            for value in regexValues {
                guard let regex = compiledRemoveParamRegex(value) else { continue }
                matchesByRegex[value] = names.filter { name in
                    let decoded = decodeRemoveParamValue(name) ?? name
                    return regex.firstMatch(in: decoded, range: NSRange(location: 0, length: decoded.utf16.count)) != nil
                }
            }
        }

        /// Nil when `value` is not a regex this vocabulary could evaluate; empty when it matches nothing.
        func literalNames(matching value: String) -> [String]? {
            matchesByRegex[value]
        }
    }

    public static func generateRules(
        from rulesText: String,
        redirectSources: [String] = [],
        disabledSites: [String] = []
    ) -> (rules: [DeclarativeRule], summary: Summary) {
        let resolvedRedirects = resourceRedirectRules(fromSources: redirectSources)
        let disabledRules = makeDisabledSiteAllowRules(
            disabledSites,
            startingID: ruleIDBase,
            remainingCapacity: maxGeneratedRules
        )
        let disabledAllowRulesCount = disabledRules.count
        var sourceRulesInOrder: [DeclarativeRule] = []
        var protectiveRules: [DeclarativeRule] = []
        var redirectRules: [DeclarativeRule] = []
        sourceRulesInOrder.reserveCapacity(1024)
        protectiveRules.reserveCapacity(128)
        redirectRules.reserveCapacity(1024)
        var generatedSourceRuleCount = 0

        var removeParamRules = 0
        var exceptionRules = 0
        var skippedRules = resolvedRedirects.skipped

        // Resource replacements stand in for blocks, so they are admitted before
        // query stripping when the budget is tight.
        for rule in resolvedRedirects.rules {
            generatedSourceRuleCount += 1
            sourceRulesInOrder.append(rule)
            redirectRules.append(rule)
        }

        let vocabulary = NameVocabulary(rulesText: rulesText)
        for rawLine in rulesText.split(whereSeparator: \.isNewline) {
            let result = buildRules(from: String(rawLine), vocabulary: vocabulary)
            if result.wasRemoveParamRule { removeParamRules += 1 }
            if result.wasExceptionRule { exceptionRules += 1 }
            if result.skipped { skippedRules += 1 }
            for rule in result.rules {
                generatedSourceRuleCount += 1
                if sourceRulesInOrder.count < maxGeneratedRules {
                    sourceRulesInOrder.append(rule)
                }
                if rule.action.type == "allow" {
                    if protectiveRules.count < maxGeneratedRules {
                        protectiveRules.append(rule)
                    }
                } else if redirectRules.count < maxGeneratedRules {
                    redirectRules.append(rule)
                }
            }
        }

        let availableSourceCapacity = max(0, maxGeneratedRules - disabledRules.count)
        let admittedSourceRules: [DeclarativeRule]
        if generatedSourceRuleCount <= availableSourceCapacity {
            admittedSourceRules = sourceRulesInOrder
        } else {
            if protectiveRules.count >= availableSourceCapacity {
                // Never keep stripping rules when protections alone consume the
                // budget. This avoids widening behavior by dropping exceptions.
                admittedSourceRules = Array(protectiveRules.prefix(availableSourceCapacity))
            } else {
                let redirectCapacity = availableSourceCapacity - protectiveRules.count
                admittedSourceRules = protectiveRules + Array(redirectRules.prefix(redirectCapacity))
            }
        }

        var rules = disabledRules + admittedSourceRules
        for index in rules.indices {
            rules[index].id = ruleIDBase + index
        }
        let truncatedRules = max(0, generatedSourceRuleCount - admittedSourceRules.count)

        let version = versionHex(for: rules)
        let summary = Summary(
            generatedRules: rules.count,
            removeParamRules: removeParamRules,
            exceptionRules: exceptionRules,
            skippedRules: skippedRules,
            truncatedRules: truncatedRules,
            disabledSiteAllowRules: disabledAllowRulesCount,
            resourceRedirectRules: rules.filter { $0.action.redirect?.extensionPath != nil }.count,
            version: version
        )
        return (rules, summary)
    }

    /// `blockedCount` writes the blocked-request count's rules; otherwise
    /// their file is emptied.
    public static func saveRules(
        for filters: [FilterList],
        disabledSites: [String],
        blockedCount: Bool,
        groupIdentifier: String,
        containerURL explicitContainerURL: URL? = nil
    ) throws -> Summary {
        guard let containerURL = explicitContainerURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let inputKey = generationInputKey(
            for: filters, disabledSites: disabledSites, blockedCount: blockedCount, containerURL: containerURL
        )
        if let saved = savedGeneration(containerURL: containerURL), saved.inputKey == inputKey,
           rulesFilesExist(containerURL: containerURL) {
            // The rules are unchanged. Carve-outs also depend on the redirect status
            // file, which changes without any input here, so they are rechecked.
            let carveOuts = saveRedirectCarveOutLines(saved.carveOutLines, containerURL: containerURL)
            return saved.summary.withRedirectCarveOuts(carveOuts)
        }

        let extracted = extractedDNRSourceRules(
            for: filters,
            containerURL: containerURL,
            includeBlockedCount: blockedCount
        )

        let generated = generateRules(
            from: extracted.removeParam,
            redirectSources: extracted.redirectSources,
            disabledSites: disabledSites
        )
        try saveRules(generated.rules, containerURL: containerURL)
        let blockedCountRules = blockedCount
            ? generateBlockedCountRules(from: extracted.blockedCount, disabledSites: disabledSites)
            : []
        try saveBlockedCountRules(blockedCountRules, containerURL: containerURL)
        let carveOutLines = generated.rules.compactMap(carveOutLine)
        let carveOuts = saveRedirectCarveOutLines(carveOutLines, containerURL: containerURL)
        let summary = Summary(
            generatedRules: generated.summary.generatedRules,
            removeParamRules: generated.summary.removeParamRules,
            exceptionRules: generated.summary.exceptionRules,
            skippedRules: generated.summary.skippedRules,
            truncatedRules: generated.summary.truncatedRules,
            disabledSiteAllowRules: generated.summary.disabledSiteAllowRules,
            resourceRedirectRules: generated.summary.resourceRedirectRules,
            redirectCarveOuts: carveOuts,
            version: generated.summary.version
        )
        // Written last: a generation that stopped midway has no state to match.
        saveGeneration(SavedGeneration(
            schema: generationSchema, inputKey: inputKey, summary: summary, carveOutLines: carveOutLines
        ), containerURL: containerURL)
        os_log(
            .info,
            "Saved %d DNR rules (%d source removeparam, %d exceptions, %d skipped, %d truncated, %d disabled-site allow rules, %d resource redirects, %d native carve-outs, %d blocked-count rules)",
            summary.generatedRules,
            summary.removeParamRules,
            summary.exceptionRules,
            summary.skippedRules,
            summary.truncatedRules,
            summary.disabledSiteAllowRules,
            summary.resourceRedirectRules,
            summary.redirectCarveOuts,
            blockedCountRules.count
        )
        return summary
    }

    // MARK: - Generation state

    /// What the saved rules were generated from. A match skips extraction,
    /// generation, and the rule writes; the carve-out check still runs.
    private struct SavedGeneration: Codable {
        let schema: Int
        let inputKey: String
        let summary: Summary
        let carveOutLines: [String]
    }

    /// Bump when the generator's output changes for the same inputs.
    private static let generationSchema = 4
    private static let generationStateFilename = "dnr-generation-state.json"

    private final class BuildMarker {}

    /// Source files count by name, size, and modification time, as in the extraction cache.
    private static func generationInputKey(
        for filters: [FilterList],
        disabledSites: [String],
        blockedCount: Bool,
        containerURL: URL
    ) -> String {
        let bundle = Bundle(for: BuildMarker.self)
        var canonical = "schema=\(generationSchema)\nbuild=\(bundle.infoDictionary?["CFBundleShortVersionString"] ?? "")"
        canonical += "|\(bundle.infoDictionary?["CFBundleVersion"] ?? "")\n"
        canonical += "blocked=\(blockedCount ? blockedCountExtractionFormat : 0)\n"
        canonical += "disabled=\(disabledSites.joined(separator: "\n"))\n"
        for filter in filters {
            guard let sourceURL = ContentBlockerIncrementalCache.existingLocalFileURL(
                for: filter,
                containerURL: containerURL
            ) else { continue }
            canonical += "\(sourceURL.lastPathComponent)|\(fileFingerprint(at: sourceURL) ?? "missing")\n"
        }
        canonical += "redirect=\(RedirectFeed.sources(for: filters).joined(separator: "\n"))"
        return sha256Hex(data: Data(canonical.utf8))
    }

    private static func savedGeneration(containerURL: URL) -> SavedGeneration? {
        guard let data = try? Data(contentsOf: containerURL.appendingPathComponent(generationStateFilename)),
              let saved = try? JSONDecoder().decode(SavedGeneration.self, from: data),
              saved.schema == generationSchema
        else { return nil }
        return saved
    }

    private static func saveGeneration(_ saved: SavedGeneration, containerURL: URL) {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FilterArtifactStorage.write(data, to: containerURL.appendingPathComponent(generationStateFilename))
    }

    private static func rulesFilesExist(containerURL: URL) -> Bool {
        [rulesFilename, blockedCountRulesFilename].allSatisfy {
            FileManager.default.fileExists(atPath: containerURL.appendingPathComponent($0).path)
        }
    }

    // MARK: - Extraction cache

    /// Sidecar that remembers the removeparam and redirect lines extracted from
    /// each filter source, keyed by the source file's size and modification
    /// time. Site toggles regenerate DNR rules often, and re-scanning every
    /// filter list from disk each time was the dominant cost; with the sidecar
    /// only lists whose file actually changed are rescanned.
    private struct ExtractionEntry: Codable {
        var fingerprint: String
        var lines: String
        var redirectLines: String
        /// Missing in caches written before the blocked-request count.
        var blockedCountLines: String?
        var blockedCountFormat: Int?
    }

    private static let extractionCacheFilename = "dnr-extraction-cache.json"
    private static let legacyExtractionCacheFilename = "removeparam-extraction-cache.json"

    static func extractedDNRSourceRules(
        for filters: [FilterList],
        containerURL: URL,
        includeBlockedCount: Bool
    ) -> (removeParam: String, redirectSources: [String], blockedCount: String) {
        try? FileManager.default.removeItem(
            at: containerURL.appendingPathComponent(legacyExtractionCacheFilename)
        )
        let cacheURL = containerURL.appendingPathComponent(extractionCacheFilename)
        var cache: [String: ExtractionEntry] = [:]
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: ExtractionEntry].self, from: data) {
            cache = decoded
        }

        // Lists whose cached entry is stale are scanned together; the cache, the
        // result order, and the combined text stay in filter order.
        let sources: [(key: String, url: URL, fingerprint: String, cached: ExtractionEntry?)] = filters.compactMap { filter in
            guard let sourceURL = ContentBlockerIncrementalCache.existingLocalFileURL(
                for: filter,
                containerURL: containerURL
            ) else { return nil }
            let key = sourceURL.lastPathComponent
            let fingerprint = fileFingerprint(at: sourceURL) ?? "missing"
            let cached = cache[key].flatMap { entry in
                entry.fingerprint == fingerprint
                    && (!includeBlockedCount || entry.blockedCountFormat == blockedCountExtractionFormat)
                    ? entry : nil
            }
            return (key, sourceURL, fingerprint, cached)
        }
        var scanned = [ExtractionEntry?](repeating: nil, count: sources.count)
        scanned.withUnsafeMutableBufferPointer { results in
            forEachSourceIndex(sources.indices.filter { sources[$0].cached == nil }) { index in
                guard let contents = try? String(contentsOf: sources[index].url, encoding: .utf8) else { return }
                results[index] = ExtractionEntry(
                    fingerprint: sources[index].fingerprint,
                    lines: extractRemoveParamLines(from: contents),
                    redirectLines: extractRedirectLines(from: contents),
                    blockedCountLines: includeBlockedCount ? extractBlockedCountLines(from: contents) : nil,
                    blockedCountFormat: includeBlockedCount ? blockedCountExtractionFormat : nil
                )
            }
        }

        var combined = ""
        var blockedCount = ""
        var redirectSources = RedirectFeed.sources(for: filters)
        var updated: [String: ExtractionEntry] = [:]
        var cacheChanged = false
        for (index, source) in sources.enumerated() {
            guard let entry = source.cached ?? scanned[index] else { continue }
            if source.cached == nil { cacheChanged = true }
            updated[source.key] = entry
            combined.append(entry.lines)
            if includeBlockedCount { blockedCount.append(entry.blockedCountLines ?? "") }
            if !entry.redirectLines.isEmpty { redirectSources.append(entry.redirectLines) }
        }

        if cacheChanged || updated.count != cache.count {
            if let data = try? JSONEncoder().encode(updated) {
                try? FilterArtifactStorage.write(data, to: cacheURL)
            }
        }
        return (combined, redirectSources, blockedCount)
    }

    /// Scans lists in parallel on macOS. Phones scan one at a time, since each
    /// scan holds a whole list's text.
    private static func forEachSourceIndex(_ indices: [Int], _ body: (Int) -> Void) {
        #if os(macOS)
        DispatchQueue.concurrentPerform(iterations: indices.count) { body(indices[$0]) }
        #else
        indices.forEach(body)
        #endif
    }

    static func extractRemoveParamLines(from contents: String) -> String {
        var result = ""
        RuleText.forEachLine(contents) { rawLine in
            guard RuleText.containsIgnoringASCIICase(rawLine, "removeparam") else { return }
            result.append(contentsOf: rawLine)
            result.append("\n")
        }
        return result
    }

    private static func fileFingerprint(at url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)|\(Int64(modDate * 1_000_000))"
    }

    public static func clearSavedRules(groupIdentifier: String) throws -> Summary {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try clearSavedRules(containerURL: containerURL)
    }

    static func clearSavedRules(containerURL: URL) throws -> Summary {
        let rules: [DeclarativeRule] = []
        try saveRules(rules, containerURL: containerURL)
        _ = saveRedirectCarveOutLines([], containerURL: containerURL)
        try saveBlockedCountRules([], containerURL: containerURL)
        try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(generationStateFilename))
        return Summary(
            generatedRules: 0,
            removeParamRules: 0,
            exceptionRules: 0,
            skippedRules: 0,
            disabledSiteAllowRules: 0,
            version: versionHex(for: rules)
        )
    }

    public static func emptyRulesPayload(offset: Int, limit: Int) -> [String: Any] {
        let safeOffset = max(0, offset)
        let safeLimit = max(1, min(limit, 500))
        return [
            "ok": true,
            "version": versionHex(for: []),
            "offset": safeOffset,
            "limit": safeLimit,
            "count": 0,
            "rules": [] as [[String: Any]],
            "ruleIdBase": ruleIDBase,
            "ruleIdLimit": ruleIDLimit
        ]
    }

    public static func loadRulesPayload(
        groupIdentifier: String,
        offset: Int,
        limit: Int
    ) -> [String: Any] {
        let safeOffset = max(0, offset)
        let safeLimit = max(1, min(limit, 500))
        guard let saved = parsedSavedRules(groupIdentifier: groupIdentifier) else {
            return emptyRulesPayload(offset: safeOffset, limit: safeLimit)
        }

        let version = saved.version
        guard let json = saved.rules else {
            return [
                "ok": false,
                "error": "Failed to decode saved removeparam DNR rules",
                "version": version,
                "offset": safeOffset,
                "limit": safeLimit,
                "count": 0,
                "rules": [] as [[String: Any]]
            ]
        }

        let end = min(json.count, safeOffset + safeLimit)
        let slice: [[String: Any]] = safeOffset < json.count ? Array(json[safeOffset..<end]) : []
        return [
            "ok": true,
            "version": version,
            "offset": safeOffset,
            "limit": safeLimit,
            "count": json.count,
            "rules": slice,
            "ruleIdBase": ruleIDBase,
            "ruleIdLimit": ruleIDLimit
        ]
    }

    private static func saveRules(_ rules: [DeclarativeRule], containerURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(rules)
        let url = containerURL.appendingPathComponent(rulesFilename)
        try FilterArtifactStorage.write(data, to: url)
    }

    private struct ParsedSavedRules {
        /// Atomic writes replace the file, so its number tells rewrites apart
        /// even when the timestamp and size match.
        let fileNumber: Int
        let modified: Date
        let size: Int
        let version: String
        let rules: [[String: Any]]?
    }

    private static let parsedRulesLock = NSLock()
    nonisolated(unsafe) private static var parsedRules: ParsedSavedRules?

    /// The extension pages through the saved rules in small chunks; read,
    /// hash, and parse the file once per write instead of once per chunk.
    private static func parsedSavedRules(groupIdentifier: String) -> ParsedSavedRules? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return nil
        }
        let url = containerURL.appendingPathComponent(rulesFilename)
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.intValue,
            let modified = attributes[.modificationDate] as? Date,
            let size = (attributes[.size] as? NSNumber)?.intValue
        else { return nil }
        parsedRulesLock.lock()
        defer { parsedRulesLock.unlock() }
        if let cached = parsedRules, cached.fileNumber == fileNumber, cached.modified == modified, cached.size == size {
            return cached
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let parsed = ParsedSavedRules(
            fileNumber: fileNumber,
            modified: modified,
            size: size,
            version: sha256Hex(data: data),
            rules: (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        )
        parsedRules = parsed
        return parsed
    }

    /// Nil means this is not a removeparam rule; otherwise use the actual DNR builder.
    static func supportsRule(_ line: String, vocabulary: NameVocabulary) -> Bool? {
        let result = buildRules(from: line, vocabulary: vocabulary)
        return result.wasRemoveParamRule ? !result.rules.isEmpty : nil
    }

    private static func buildRules(from rawLine: String, vocabulary: NameVocabulary) -> BuildResult {
        guard let parsed = parseRule(rawLine) else {
            return BuildResult(rules: [], wasRemoveParamRule: false, wasExceptionRule: false, skipped: false)
        }
        let skipped = BuildResult(rules: [], wasRemoveParamRule: true, wasExceptionRule: parsed.isException, skipped: true)

        let options = parsed.options.map { optionNameAndValue($0).name }
        if options.contains("badfilter") || parsed.options.contains(where: { $0.hasPrefix("~removeparam") }) {
            return skipped
        }

        let value = parsed.removeParamValue ?? ""
        let isRegex = value.hasPrefix("/")
        let values: [String]
        if isRegex {
            guard let matched = vocabulary.literalNames(matching: value), !matched.isEmpty else { return skipped }
            values = matched
        } else {
            values = [value]
        }

        // A regex redirect is one rule that lists every name it matches, with no
        // per-name token. Exceptions keep one rule per name, since a token-less
        // allow would also switch off replacements the literal rules leave alone.
        let groups: [(value: String, names: [String])]
        if isRegex && !parsed.isException {
            groups = [("", values)]
        } else {
            groups = values.map { (value: $0, names: $0.isEmpty ? [] : [$0]) }
        }

        // Priorities: 1 blocked-request count, 2 entity-excluded redirects, 3 their
        // companion allows, 4 ordinary removeparam, 1000 important, 10000 exceptions.
        // An allow suppresses every matching rule below it, so ordinary rules sit
        // above the companions, and only entity-excluded redirects fall beneath them.
        var rules: [DeclarativeRule] = []
        for group in groups {
            guard let made = makeCondition(parsed: parsed, removeValue: group.value) else { return skipped }
            // An exception with entity exclusions would need the inverse carve-out; skip it.
            if parsed.isException && !made.entities.isEmpty { return skipped }
            let condition = made.condition
            let priority: Int
            if parsed.isException {
                priority = 10_000
            } else if !made.entities.isEmpty {
                priority = entityRedirectPriority
            } else {
                priority = options.contains("important") ? 1_000 : 4
            }
            let action: RuleAction
            if parsed.isException {
                action = RuleAction(type: "allow", redirect: nil)
            } else if group.names.isEmpty {
                action = RuleAction(
                    type: "redirect",
                    redirect: Redirect(transform: URLTransform(query: "", queryTransform: nil))
                )
            } else {
                let decoded = group.names.compactMap(decodeRemoveParamValue)
                guard decoded.count == group.names.count, decoded.allSatisfy(isSupportedLiteralParameterName) else {
                    return skipped
                }
                action = RuleAction(
                    type: "redirect",
                    redirect: Redirect(
                        transform: URLTransform(
                            query: nil,
                            queryTransform: QueryTransform(removeParams: decoded)
                        )
                    )
                )
            }
            rules.append(DeclarativeRule(id: 0, priority: priority, action: action, condition: condition))
            // DNR cannot exclude a domain by pattern, so an allow one priority above
            // the redirect exempts each entity. It overrides only the rules beneath it,
            // which are the blocked-request count and the other entity redirects.
            for entity in made.entities {
                rules.append(DeclarativeRule(
                    id: 0,
                    priority: priority + 1,
                    action: RuleAction(type: "allow", redirect: nil),
                    condition: RuleCondition(
                        regexFilter: entityRegexFilter(entity),
                        resourceTypes: ["main_frame"]
                    )
                ))
            }
        }

        return BuildResult(
            rules: rules,
            wasRemoveParamRule: true,
            wasExceptionRule: parsed.isException,
            skipped: false
        )
    }

    /// The options start at the first `$` whose tail has a `removeparam` option.
    /// Regex values can contain `$`, so the last `$` is not always the separator.
    private static func optionsSeparator(in line: String) -> String.Index? {
        var search = line.startIndex
        while let dollar = line[search...].firstIndex(of: "$") {
            let tail = String(line[line.index(after: dollar)...])
            if splitOptions(tail).contains(where: { optionNameAndValue($0).name == "removeparam" }) {
                return dollar
            }
            search = line.index(after: dollar)
        }
        return nil
    }

    private static func parseRule(_ rawLine: String) -> ParsedRule? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        guard !line.hasPrefix("!") && !line.hasPrefix("#") && !line.hasPrefix("[") else { return nil }

        let isException = line.hasPrefix("@@")
        if isException { line.removeFirst(2) }

        guard let dollarIndex = optionsSeparator(in: line) else { return nil }
        let pattern = String(line[..<dollarIndex]).trimmingCharacters(in: .whitespaces)
        let optionsText = String(line[line.index(after: dollarIndex)...])
        let options = splitOptions(optionsText)

        let removeParamValue = options.compactMap { option -> String? in
            let pair = optionNameAndValue(option)
            guard pair.name == "removeparam" else { return nil }
            return pair.value ?? ""
        }.first ?? ""

        return ParsedRule(
            isException: isException,
            pattern: pattern,
            removeParamValue: removeParamValue,
            options: options
        )
    }

    static func splitOptions(_ optionsText: String) -> [String] {
        optionsText.split(separator: ",", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func optionNameAndValue(_ option: String) -> (name: String, value: String?) {
        let parts = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = parts.count > 1 ? String(parts[1]) : nil
        return (name, value)
    }

    /// The condition for one rule, plus the entities whose `~entity.*` exclusions
    /// were moved out of `domain=` into companion allow rules (see buildRules).
    /// Entity-excluded redirects sit here, and their companion allows one above.
    private static let entityRedirectPriority = 2

    private static func makeCondition(
        parsed: ParsedRule,
        removeValue: String
    ) -> (condition: RuleCondition, entities: [String])? {
        let allPairs = parsed.options.map(optionNameAndValue)

        guard !containsUnsupportedCriticalOptions(allPairs) else { return nil }

        guard isSupportedRemoveParamValue(removeValue) else { return nil }
        guard let split = entityExclusions(in: allPairs) else { return nil }
        let optionPairs = split.options

        var urlFilter = normalizeURLFilterPattern(parsed.pattern)
        if !removeValue.isEmpty, let decoded = decodeRemoveParamValue(removeValue) {
            guard let token = removeParamURLFilterToken(for: decoded) else { return nil }
            urlFilter = urlFilter.map { $0 + "*" + token } ?? token
        }

        var condition = RuleCondition()
        condition.urlFilter = urlFilter
        condition.resourceTypes = resourceTypes(from: optionPairs)
        if condition.resourceTypes == nil {
            condition.resourceTypes = ["main_frame", "sub_frame"]
        }
        // The companion matches the request URL, which is the document only for
        // main_frame. For subresources `domain=` names the page, so skip them.
        if !split.entities.isEmpty && condition.resourceTypes != ["main_frame"] { return nil }

        guard let domains = parseDomainOption(named: "domain", from: optionPairs),
              let toDomains = parseDomainOption(named: "to", from: optionPairs),
              // `denyallow=a.com` means the same as `to=~a.com` (#975).
              let denyAllow = parseDomainOption(named: "denyallow", from: optionPairs),
              denyAllow.excluded.isEmpty
        else {
            return nil
        }
        let excludedRequestDomains = (toDomains.excluded + denyAllow.included).sorted()
        if !domains.included.isEmpty { condition.domains = domains.included }
        if !domains.excluded.isEmpty { condition.excludedDomains = domains.excluded }

        if !toDomains.included.isEmpty { condition.requestDomains = toDomains.included }
        if !excludedRequestDomains.isEmpty { condition.excludedRequestDomains = excludedRequestDomains }

        if optionPairs.contains(where: { $0.name == "third-party" }) {
            condition.domainType = "thirdParty"
        } else if optionPairs.contains(where: { $0.name == "~third-party" }) {
            condition.domainType = "firstParty"
        }

        if optionPairs.contains(where: { $0.name == "match-case" }) {
            condition.isUrlFilterCaseSensitive = true
        }

        return (condition, split.entities)
    }

    /// Moves `~entity.*` tokens out of `domain=` options. DNR excluded domains are
    /// exact, so the entities are returned for companion rules instead. Nil when
    /// an entity is combined with an included domain, which those rules cannot express.
    private static func entityExclusions(
        in options: [(name: String, value: String?)]
    ) -> (options: [(name: String, value: String?)], entities: [String])? {
        var entities: [String] = []
        var hasIncludedDomain = false
        var rewritten: [(name: String, value: String?)] = []
        for option in options {
            guard option.name == "domain", let value = option.value,
                  value.split(separator: "|").contains(where: { entityName(inExclusion: String($0)) != nil })
            else {
                if option.name == "domain", let value = option.value,
                   value.split(separator: "|").contains(where: { !$0.hasPrefix("~") }) {
                    hasIncludedDomain = true
                }
                rewritten.append(option)
                continue
            }
            var kept: [String] = []
            for token in value.split(separator: "|", omittingEmptySubsequences: false).map(String.init) {
                if let entity = entityName(inExclusion: token) {
                    entities.append(entity)
                } else {
                    if !token.hasPrefix("~") { hasIncludedDomain = true }
                    kept.append(token)
                }
            }
            if !kept.isEmpty { rewritten.append((name: "domain", value: kept.joined(separator: "|"))) }
        }
        if !entities.isEmpty && hasIncludedDomain { return nil }
        return (rewritten, entities.uniqued())
    }

    /// The lowercase entity name in `~entity.*`, or nil for any other token.
    private static func entityName(inExclusion token: String) -> String? {
        let lowered = token.lowercased()
        guard lowered.hasPrefix("~"), lowered.hasSuffix(".*") else { return nil }
        let name = lowered.dropFirst().dropLast(2)
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            return nil
        }
        return String(name)
    }

    /// Matches a main-frame request to any TLD of `entity`, or a subdomain of one.
    /// The host ends after one label, so `entity.evil.com` and `user@host` do not match.
    private static func entityRegexFilter(_ entity: String) -> String {
        "^https?://([^/@]*\\.)?\(entity)\\.[^/.:?#@]+(:[0-9]+)?([/?#]|$)"
    }

    private static func containsUnsupportedCriticalOptions(_ options: [(name: String, value: String?)]) -> Bool {
        for option in options {
            if option.name.hasPrefix("~"), resourceTypeMap[String(option.name.dropFirst())] != nil {
                return true
            }
            if skippedOptionNames.contains(option.name) { return true }
            if option.name == "method" { return true }
            // Skip rules with options we do not understand. Silently ignoring
            // an unrecognized option (e.g. a bare domain list like
            // `hinta.fi|carrefoursa.com` without a `domain=` prefix) would
            // drop the intended restriction and widen the rule to all sites.
            if !recognizedOptionNames.contains(option.name) { return true }
        }
        return false
    }

    static func normalizeURLFilterPattern(_ rawPattern: String) -> String? {
        var pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return nil }
        guard !(pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 1) else { return nil }
        if pattern.hasPrefix("||*") {
            pattern.removeFirst(2)
        }
        return pattern.isEmpty ? nil : pattern
    }

    private static func resourceTypes(from options: [(name: String, value: String?)]) -> [String]? {
        var ordered: [String] = []
        var seen = Set<String>()
        for option in options {
            guard let mapped = resourceTypeMap[option.name] else { continue }
            for resourceType in mapped where !seen.contains(resourceType) {
                seen.insert(resourceType)
                ordered.append(resourceType)
            }
        }
        return ordered.isEmpty ? nil : ordered
    }

    private static func parseDomainOption(
        named optionName: String,
        from options: [(name: String, value: String?)]
    ) -> (included: [String], excluded: [String])? {
        let matchingOptions = options.filter { $0.name == optionName }
        guard let firstOption = matchingOptions.first else {
            return ([], [])
        }

        guard let firstValue = firstOption.value,
              let parsed = parseDomainOptionValue(firstValue)
        else {
            return nil
        }

        // Preserve the existing first-option behavior while validating every
        // duplicate option so a later malformed scope cannot widen the rule.
        for option in matchingOptions.dropFirst() {
            guard let value = option.value, parseDomainOptionValue(value) != nil else {
                return nil
            }
        }
        return parsed
    }

    private static func parseDomainOptionValue(
        _ value: String
    ) -> (included: [String], excluded: [String])? {
        guard !value.isEmpty else { return nil }

        let rawDomains = value.split(separator: "|", omittingEmptySubsequences: false)
        guard !rawDomains.isEmpty else { return nil }

        var included: [String] = []
        var excluded: [String] = []
        for rawDomain in rawDomains {
            var domain = String(rawDomain).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !domain.isEmpty else { return nil }
            let isExcluded = domain.hasPrefix("~")
            if isExcluded { domain.removeFirst() }
            guard isSupportedDomain(domain) else { return nil }
            if isExcluded {
                excluded.append(domain)
            } else {
                included.append(domain)
            }
        }
        return (included.sorted(), excluded.sorted())
    }

    static func isSupportedDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty else { return false }
        guard !domain.contains("*") && !domain.contains("/") && !domain.contains(":") else { return false }
        return domain.allSatisfy { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
        }
    }

    private static func isSupportedRemoveParamValue(_ value: String) -> Bool {
        guard !value.hasPrefix("~") && !value.hasPrefix("/") else { return false }
        if value.contains("|") { return false }
        if value.isEmpty { return true }
        guard let decoded = decodeRemoveParamValue(value) else { return false }
        return isSupportedLiteralParameterName(decoded)
    }

    private static func decodeRemoveParamValue(_ value: String) -> String? {
        value.removingPercentEncoding
    }

    /// `/body/` or `/body/i`. Other flags, an empty body, or an invalid pattern yield nil.
    private static func compiledRemoveParamRegex(_ value: String) -> NSRegularExpression? {
        guard value.hasPrefix("/"), let closing = value.lastIndex(of: "/"), closing > value.startIndex else {
            return nil
        }
        let body = value[value.index(after: value.startIndex)..<closing]
        let flags = value[value.index(after: closing)...]
        guard !body.isEmpty, flags.isEmpty || flags == "i" else { return nil }
        return try? NSRegularExpression(
            pattern: String(body),
            options: flags.isEmpty ? [] : [.caseInsensitive]
        )
    }

    private static func isSupportedLiteralParameterName(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        guard value.trimmingCharacters(in: .whitespacesAndNewlines) == value else { return false }
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        return true
    }

    /// A literal value a single rule can express; the same test a literal rule applies.
    private static func isExpressibleLiteralRemoveValue(_ value: String) -> Bool {
        guard isSupportedRemoveParamValue(value), !value.isEmpty else { return false }
        return decodeRemoveParamValue(value).flatMap(removeParamURLFilterToken(for:)) != nil
    }

    private static func removeParamURLFilterToken(for decodedValue: String) -> String? {
        guard isSupportedLiteralParameterName(decodedValue) else { return nil }
        guard decodedValue.rangeOfCharacter(from: urlFilterSpecialCharacters) == nil else { return nil }
        return "^\(decodedValue)="
    }

    private static func makeDisabledSiteAllowRules(
        _ disabledSites: [String],
        startingID: Int,
        remainingCapacity: Int
    ) -> [DeclarativeRule] {
        var rules: [DeclarativeRule] = []
        let domains = disabledSites
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter(isSupportedDomain)
            .uniqued()

        for domain in domains where rules.count + 2 <= remainingCapacity {
            rules.append(DeclarativeRule(
                id: startingID + rules.count,
                priority: 20_000,
                action: RuleAction(type: "allow", redirect: nil),
                condition: RuleCondition(
                    urlFilter: nil,
                    resourceTypes: ["main_frame", "sub_frame"],
                    domains: nil,
                    excludedDomains: nil,
                    requestDomains: [domain],
                    excludedRequestDomains: nil,
                    domainType: nil,
                    isUrlFilterCaseSensitive: nil
                )
            ))
            // No resource types: every subresource, so resource replacements
            // also stay off on a disabled site.
            rules.append(DeclarativeRule(
                id: startingID + rules.count,
                priority: 20_000,
                action: RuleAction(type: "allow", redirect: nil),
                condition: RuleCondition(
                    urlFilter: nil,
                    resourceTypes: nil,
                    domains: [domain],
                    excludedDomains: nil,
                    requestDomains: nil,
                    excludedRequestDomains: nil,
                    domainType: nil,
                    isUrlFilterCaseSensitive: nil
                )
            ))
        }

        return rules
    }

    private static func versionHex(for rules: [DeclarativeRule]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(rules)) ?? Data()
        return sha256Hex(data: data)
    }

    static func sha256Hex(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        for element in self where !seen.contains(element) {
            seen.insert(element)
            result.append(element)
        }
        return result
    }
}
