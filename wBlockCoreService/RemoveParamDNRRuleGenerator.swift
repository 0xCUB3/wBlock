import CryptoKit
import Foundation
import os.log

/// Compiles request-time query transforms and saves the source selectors for
/// top-frame cleanup in RemoveParamPageRules. DNR gets literal names and safe
/// prefix expansions; value-dependent selectors retain their full semantics in
/// the page evaluator instead of guessing which names and values will arrive.
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
        "removeparam", "domain", "to", "denyallow", "method", "third-party", "~third-party",
        "match-case", "important", "badfilter",
        "doc", "document", "main_frame", "subdocument", "sub_frame",
        "stylesheet", "script", "image", "font", "object",
        "xmlhttprequest", "xhr", "ping", "media", "websocket", "other", "frame",
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
        "frame": ["sub_frame"],
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
        // Keep document and initiator scopes separate: WebKit's legacy domains
        // tests the top document. Actual initiating-frame scopes require 18.4.
        public var initiatorDomains: [String]? = nil
        public var excludedInitiatorDomains: [String]? = nil
        public var domains: [String]? = nil
        public var excludedDomains: [String]? = nil
        public var requestDomains: [String]? = nil
        public var excludedRequestDomains: [String]? = nil
        public var requestMethods: [String]? = nil
        public var domainType: String? = nil
        public var isUrlFilterCaseSensitive: Bool? = nil
    }

    struct ParsedRule: Codable {
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
                if isRegexRemoveValue(value) {
                    regexValues.insert(value)
                } else if isExpressibleLiteralRemoveValue(value) {
                    literals.insert(value)
                }
            }
            let names = literals.sorted()
            for value in regexValues {
                guard isNamePrefixRegex(value), let regex = compiledRemoveParamRegex(value) else { continue }
                matchesByRegex[value] = names.filter { name in
                    let input = name + "="
                    return regex.firstMatch(in: input, range: NSRange(location: 0, length: input.utf16.count)) != nil
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

        let activeText = activeRulesText(rulesText)
        let vocabulary = NameVocabulary(rulesText: activeText)
        let networkValues = Set(activeText.components(separatedBy: .newlines).compactMap { line -> String? in
            guard let parsed = parseRule(line), !parsed.isException,
                  !buildRules(from: line, vocabulary: vocabulary).rules.isEmpty else { return nil }
            return parsed.removeParamValue ?? ""
        })
        for rawLine in activeText.split(whereSeparator: \.isNewline) {
            var result = buildRules(from: String(rawLine), vocabulary: vocabulary)
            if let parsed = parseRule(String(rawLine)), parsed.isException,
               let value = parsed.removeParamValue, isRegexRemoveValue(value), !networkValues.contains(value) {
                // A value-specific exception only cancels that same selector in uBO.
                // With no corresponding network transform it needs no DNR allow.
                result.rules = []; result.skipped = false
            }
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
                } else {
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
                func rank(_ rule: DeclarativeRule) -> Int {
                    if rule.action.redirect?.extensionPath != nil { return 2 }
                    return rule.condition.domains == nil && rule.condition.requestDomains == nil &&
                        (rule.condition.urlFilter == nil || rule.condition.urlFilter?.hasPrefix("^") == true) ? 1 : 0
                }
                admittedSourceRules = protectiveRules + Array(redirectRules.enumerated().sorted {
                    let a = rank($0.element), b = rank($1.element)
                    return a == b ? $0.offset < $1.offset : a > b
                }.prefix(redirectCapacity).map(\.element))
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
    private static let generationLock = NSLock()

    public static func saveRules(
        for filters: [FilterList],
        disabledSites: [String],
        blockedCount: Bool,
        groupIdentifier: String,
        containerURL explicitContainerURL: URL? = nil
    ) throws -> Summary {
        generationLock.lock()
        defer { generationLock.unlock() }
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
        try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(generationStateFilename))
        try FilterArtifactStorage.write(JSONEncoder().encode(extracted.pageRules), to: containerURL.appendingPathComponent(pageRulesFilename))
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
    private static let generationSchema = 8
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
            canonical += "\(sourceURL.lastPathComponent)|\(fileFingerprint(at: sourceURL) ?? "missing")"
            canonical += "|\(filter.isSelected)|" + FilterListSiteExclusion.scopeMarker(
                excluding: filter.appliedExcludedSites, including: filter.appliedSelectedSites) + "\n"
        }
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
        [rulesFilename, pageRulesFilename, blockedCountRulesFilename].allSatisfy {
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
    ) -> (removeParam: String, redirectSources: [String], blockedCount: String, pageRules: [PageRule]) {
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
        let selected = filters.filter(\.isSelected)
        let sources: [(key: String, url: URL, fingerprint: String, cached: ExtractionEntry?, filter: FilterList)] = selected.compactMap { filter in
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
            return (key, sourceURL, fingerprint, cached, filter)
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
        var allLines = ""
        var pageRules: [PageRule] = []
        var scopedExceptions = Set<String>()
        var blockedCount = ""
        var redirectSources: [String] = []
        var updated: [String: ExtractionEntry] = [:]
        var cacheChanged = false
        for (index, source) in sources.enumerated() {
            guard let entry = source.cached ?? scanned[index] else { continue }
            if source.cached == nil { cacheChanged = true }
            updated[source.key] = entry
            allLines.append(entry.lines)
            let scoped = !source.filter.appliedExcludedSites.isEmpty || source.filter.appliedSelectedSites != nil
            // DNR cannot intersect arbitrary list scopes with a rule's own scope.
            if !scoped { combined.append(entry.lines) }
            pageRules += entry.lines.components(separatedBy: .newlines).compactMap { line in
                guard var page = pageRule(line) else { return nil }
                if scoped && page.rule.isException { scopedExceptions.insert(page.rule.removeParamValue ?? "") }
                page.excludedSites = source.filter.appliedExcludedSites
                page.includedSites = source.filter.appliedSelectedSites
                return page
            }
            if includeBlockedCount { blockedCount.append(entry.blockedCountLines ?? "") }
            if !entry.redirectLines.isEmpty { redirectSources.append(entry.redirectLines) }
        }

        if cacheChanged || updated.count != cache.count {
            if let data = try? JSONEncoder().encode(updated) {
                try? FilterArtifactStorage.write(data, to: cacheURL)
            }
        }
        let active = Set(activeRulesText(allLines).components(separatedBy: .newlines).compactMap(parseRule).map { ruleKey($0) })
        pageRules.removeAll { !active.contains(ruleKey($0.rule)) }
        combined = combined.components(separatedBy: .newlines).filter { line in
            guard let rule = parseRule(line), active.contains(ruleKey(rule)) else { return false }
            return rule.isException || rule.options.contains("important") ||
                (!scopedExceptions.contains("") && !scopedExceptions.contains(rule.removeParamValue ?? ""))
        }.joined(separator: "\n")
        return (combined, redirectSources, blockedCount, pageRules)
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
        return "\(attrs[.systemFileNumber] ?? 0)|\(size)|\(Int64(modDate * 1_000_000))"
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
        generationLock.lock()
        defer { generationLock.unlock() }
        let rules: [DeclarativeRule] = []
        try saveRules(rules, containerURL: containerURL)
        try FilterArtifactStorage.write(Data("[]".utf8), to: containerURL.appendingPathComponent(pageRulesFilename))
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

    /// The rules viewer counts both network transforms and page-only selectors.
    static func supportsRule(_ line: String, vocabulary: NameVocabulary) -> Bool? {
        let dnr = supportsDNRRule(line, vocabulary: vocabulary)
        guard dnr == false, let page = pageRule(line) else { return dnr }
        let types = resourceTypes(from: page.rule.options.map(optionNameAndValue))
        return (types?.contains("main_frame") ?? true) && !page.rule.options.contains("third-party")
    }

    static func supportsDNRRule(_ line: String, vocabulary: NameVocabulary) -> Bool? {
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

        let value = parsed.removeParamValue == "|" ? "" : (parsed.removeParamValue ?? "")
        let isRegex = isRegexRemoveValue(value)
        let values: [String]
        if parsed.isException {
            values = [""]
        } else if isRegex {
            guard let matched = vocabulary.literalNames(matching: value), !matched.isEmpty else { return skipped }
            values = matched
        } else {
            values = [value]
        }

        // One rule per name, each with the name's token, as a literal rule has. A
        // token-less rule listing many names is a no-op on most navigations, and
        // Safari applies the highest-priority match, so it would shadow the lower
        // priority rules that do strip.
        let groups = values.map { (value: $0, names: $0.isEmpty ? [] : [$0]) }

        var rules: [DeclarativeRule] = []
        for group in groups {
            guard let made = makeCondition(parsed: parsed, removeValue: group.value),
                  made.resourceTypes != [] else { return skipped }
            let priority = parsed.isException ? 10_000 : (options.contains("important") ? 15_000 : 4)
            let action: RuleAction
            if parsed.isException {
                action = RuleAction(type: "allow", redirect: nil)
            } else if group.names.isEmpty {
                action = RuleAction(type: "redirect", redirect: Redirect(transform: URLTransform(query: "")))
            } else {
                let decoded = group.names.compactMap(decodeRemoveParamValue)
                guard decoded.count == group.names.count, decoded.allSatisfy(isSupportedLiteralParameterName) else { return skipped }
                action = RuleAction(type: "redirect", redirect: Redirect(transform: URLTransform(
                    queryTransform: QueryTransform(removeParams: decoded))))
            }
            var condition = made
            if condition.domains != nil || condition.excludedDomains != nil {
                // Safari's legacy domains means top-document, not the initiating
                // frame. A main-frame request is its own document in uBO.
                if condition.resourceTypes?.contains("main_frame") == true {
                    var document = condition
                    document.resourceTypes = ["main_frame"]
                    rules.append(DeclarativeRule(id: 0, priority: priority, action: action, condition: document))
                }
                condition.resourceTypes?.removeAll { $0 == "main_frame" }
                condition.initiatorDomains = condition.domains
                condition.excludedInitiatorDomains = condition.excludedDomains
                condition.domains = nil; condition.excludedDomains = nil
            }
            if condition.resourceTypes != [] {
                rules.append(DeclarativeRule(id: 0, priority: priority, action: action, condition: condition))
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
            if line.hasPrefix("/"), line.contains("/$"), line[..<dollar].last != "/" {
                search = line.index(after: dollar); continue
            }
            if splitOptions(tail).contains(where: { optionNameAndValue($0).name == "removeparam" }) {
                return dollar
            }
            search = line.index(after: dollar)
        }
        return nil
    }

    static func parseRule(_ rawLine: String) -> ParsedRule? {
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

    static func splitOptions(_ text: String) -> [String] {
        var result: [String] = [], token = ""
        var inRegex = false, escaped = false
        for char in text {
            if char == "," && !inRegex && !escaped {
                result.append(token); token = ""; continue
            }
            if char == "/" && !escaped {
                if inRegex { inRegex = false }
                else if token == "removeparam=" || token == "removeparam=~" { inRegex = true }
            }
            token.append(char)
            if char == "\\" && !escaped { escaped = true } else { escaped = false }
        }
        result.append(token)
        return result.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { option in
            let pair = optionNameAndValue(option)
            let name = ["from": "domain", "3p": "third-party", "1p": "~third-party",
                        "~3p": "~third-party", "~1p": "third-party"][pair.name] ?? pair.name
            return name + (pair.value.map { "=" + $0 } ?? "")
        }
    }

    static func ruleKey(_ rule: ParsedRule) -> String {
        (rule.isException ? "@@" : "") + rule.pattern + "$" + rule.options
            .filter { $0 != "badfilter" }.sorted().joined(separator: ",")
    }

    static func activeRulesText(_ text: String) -> String {
        let parsed = text.components(separatedBy: .newlines).compactMap { line -> (String, ParsedRule)? in
            parseRule(line).map { (line, $0) }
        }
        let disabled = Set(parsed.filter { $0.1.options.contains("badfilter") }.map { ruleKey($0.1) })
        return parsed.filter { !disabled.contains(ruleKey($0.1)) }.map(\.0).joined(separator: "\n")
    }

    static func optionNameAndValue(_ option: String) -> (name: String, value: String?) {
        let parts = option.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = parts.count > 1 ? String(parts[1]) : nil
        return (name, value)
    }

    private static func makeCondition(
        parsed: ParsedRule,
        removeValue: String
    ) -> RuleCondition? {
        let allPairs = parsed.options.map(optionNameAndValue)
        guard !containsUnsupportedCriticalOptions(allPairs) else { return nil }
        guard isSupportedRemoveParamValue(removeValue) else { return nil }
        // A broader allow is safe; a broader redirect is not. Retain the URL and
        // resource scope when an exception's entity restriction needs the page
        // evaluator, rather than disabling every unrelated network transform.
        let optionPairs = allPairs.filter { option in
            !(parsed.isException && ["domain", "to", "denyallow"].contains(option.name)
              && option.value?.contains(".*") == true)
        }

        let isURLRegex = parsed.pattern.hasPrefix("/") && parsed.pattern.hasSuffix("/")
        var urlFilter = normalizeURLFilterPattern(parsed.pattern)
        if !parsed.isException && !isURLRegex && !removeValue.isEmpty, let decoded = decodeRemoveParamValue(removeValue) {
            guard let token = removeParamURLFilterToken(for: decoded) else { return nil }
            urlFilter = urlFilter.map { $0 + "*" + token } ?? token
        }

        var condition = RuleCondition()
        condition.urlFilter = urlFilter
        if isURLRegex { condition.regexFilter = String(parsed.pattern.dropFirst().dropLast()) }
        condition.resourceTypes = resourceTypes(from: optionPairs)
        if condition.resourceTypes == nil {
            condition.resourceTypes = ["main_frame", "sub_frame", "image", "xmlhttprequest"]
        }

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

        if let method = optionPairs.first(where: { $0.name == "method" }) {
            let methods = (method.value ?? "").lowercased().split(separator: "|").map(String.init)
            guard !methods.isEmpty, methods.allSatisfy({ ["get", "post", "put", "delete", "head", "options", "patch", "connect", "trace"].contains($0) }) else { return nil }
            condition.requestMethods = methods
        }
        if optionPairs.contains(where: { $0.name == "third-party" }) {
            condition.domainType = "thirdParty"
        } else if optionPairs.contains(where: { $0.name == "~third-party" }) {
            condition.domainType = "firstParty"
        }

        if optionPairs.contains(where: { $0.name == "match-case" }) {
            condition.isUrlFilterCaseSensitive = true
        }

        return condition
    }

    static func containsUnsupportedCriticalOptions(_ options: [(name: String, value: String?)]) -> Bool {
        for option in options {
            if option.name.hasPrefix("~"), resourceTypeMap[String(option.name.dropFirst())] != nil {
                continue
            }
            if skippedOptionNames.contains(option.name) { return true }
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

    static func resourceTypes(from options: [(name: String, value: String?)]) -> [String]? {
        let included = options.flatMap { resourceTypeMap[$0.name] ?? [] }
        let excluded = Set(options.filter { $0.name.hasPrefix("~") }
            .flatMap { resourceTypeMap[String($0.name.dropFirst())] ?? [] })
        guard !included.isEmpty || !excluded.isEmpty else { return nil }
        return (included.isEmpty ? ["main_frame", "sub_frame", "image", "xmlhttprequest"] : included)
            .uniqued().filter { !excluded.contains($0) }
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
        guard !value.hasPrefix("~") && !isRegexRemoveValue(value) else { return false }
        if value.contains("|") { return false }
        if value.isEmpty { return true }
        guard let decoded = decodeRemoveParamValue(value) else { return false }
        return isSupportedLiteralParameterName(decoded)
    }

    private static func decodeRemoveParamValue(_ value: String) -> String? {
        value
    }

    static func isRegexRemoveValue(_ value: String) -> Bool {
        value.hasPrefix("/") && value.count > 2 && (value.hasSuffix("/") || value.hasSuffix("/i"))
    }

    private static func isNamePrefixRegex(_ value: String) -> Bool {
        guard let end = value.lastIndex(of: "/"), value.hasPrefix("/^") else { return false }
        var body = String(value[value.index(value.startIndex, offsetBy: 2)..<end])
        if body.hasPrefix("\\??") { body.removeFirst(3) }
        if body.hasSuffix(".*$") { body.removeLast(3) }
        if body.hasSuffix("=") { body.removeLast() }
        // This deliberately excludes value-dependent expressions and lookarounds.
        return !body.isEmpty && body.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_-|()".contains($0)) }
    }

    /// `/body/` or `/body/i`. Other flags, an empty body, or an invalid pattern yield nil.
    static func compiledRemoveParamRegex(_ value: String) -> NSRegularExpression? {
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
