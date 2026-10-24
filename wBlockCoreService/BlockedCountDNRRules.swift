import Foundation

/// Counting rules for the toolbar's blocked-request badge.
///
/// Safari only counts blocks made by an extension's own DNR rules, and never
/// reports what the content blockers block. Safari evaluates every rule list
/// for every load, so a DNR copy of a filter-list block still gets counted
/// when a content blocker blocked the same request.
///
/// Only host-anchored blocks without site conditions are copied (`||host^`,
/// `||host/path`, optionally limited to third-party requests or resource
/// types), so the copies stay a subset of what the content blockers already
/// block. Exceptions become `allow` rules at the same priority, which wins
/// over a block. Every other wBlock DNR rule sits at priority 2 or higher, so
/// these allows only ever cancel counting rules.
extension RemoveParamDNRRuleGenerator {
    public static let blockedCountRulesFilename = "blocked_count_dnr_rules.json"
    public static let blockedCountRuleIDBase = 1_660_000
    /// Global Privacy Control's rule starts at 1,700,000.
    public static let blockedCountRuleIDLimit = 1_700_000
    static let blockedCountMaxRules = blockedCountRuleIDLimit - blockedCountRuleIDBase
    static let blockedCountDomainsPerRule = 1_000
    /// Removeparam, redirects, GPC and the CSP rule must stay above this.
    public static let blockedCountPriority = 1
    /// Bump when `extractBlockedCountLines` changes, so cached lists rescan.
    static let blockedCountExtractionFormat = 1

    /// Exception options that lift every block on the page, not just one host.
    private static let pageWideExceptionOptions: Set<String> = ["document", "doc", "urlblock", "genericblock", "all"]
    /// Exceptions that lift cosmetic, scripting or other non-blocking rules.
    private static let nonBlockingExceptionOptions: Set<String> = [
        "elemhide", "ehide", "generichide", "ghide", "specifichide", "shide",
        "jsinject", "content", "extension", "stealth", "popup", "csp",
        "redirect", "redirect-rule", "removeparam", "removeheader", "cookie",
        "replace", "header", "permissions", "jsonprune", "hls",
        "referrerpolicy", "urltransform", "webrtc"
    ]

    // MARK: - Extraction

    /// Compact per-list summary cached beside the removeparam lines, one
    /// tab-separated entry per line:
    /// `H host thirdParty` whole-host block, `P host urlFilter types thirdParty`
    /// path or typed block, `U pattern` badfilter, `S site` page-wide
    /// exception, `E host urlFilter sites` exception (host, filter and sites
    /// may each be empty), `X host` exception on a host it cannot express.
    static func extractBlockedCountLines(from contents: String) -> String {
        var result = ""
        RuleText.forEachLine(contents) { rawLine in
            let line = RuleText.trimmed(rawLine)
            guard line.hasPrefix("||") || line.hasPrefix("@@") else { return }
            for entry in blockedCountEntries(for: String(line)) {
                result.append(entry.joined(separator: "\t"))
                result.append("\n")
            }
        }
        return result
    }

    private static func blockedCountEntries(for line: String) -> [[String]] {
        let isException = line.hasPrefix("@@")
        let body = isException ? String(line.dropFirst(2)) : line
        // A regex may contain `$`; its options follow the closing slash.
        let isRegex = body.hasPrefix("/") && (body.range(of: "/$", options: .backwards) != nil
            || body.hasSuffix("/") && body.count > 1)
        let optionsStart = isRegex
            ? body.range(of: "/$", options: .backwards).map { body.index(before: $0.upperBound) }
            : body.lastIndex(of: "$")
        let pattern = optionsStart.map { String(body[..<$0]) } ?? body
        let options = optionsStart.map {
            splitOptions(String(body[body.index(after: $0)...])).map(optionNameAndValue)
        } ?? []
        let names = Set(options.map(\.name))

        guard isException else {
            if names.contains("badfilter") { return [["U", pattern]] }
            return blockEntry(pattern: pattern, names: names).map { [$0] } ?? []
        }

        if names.contains("badfilter") { return [] }
        let sites = options.first { $0.name == "domain" }.flatMap { $0.value }
            .map { $0.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces).lowercased() } }
        let includedSites = sites?.filter { !$0.hasPrefix("~") && isCountableHost($0) } ?? []
        // DNR cannot express negated or `name.*` sites. Widening such an
        // exception to everywhere only means fewer requests get counted.
        let scopedSites = sites != nil && includedSites.count == sites?.count ? includedSites : []

        if !names.isDisjoint(with: pageWideExceptionOptions) {
            if !scopedSites.isEmpty { return scopedSites.map { ["S", $0] } }
            return anchoredHost(pattern).flatMap { isCountableHost($0) ? [["S", $0]] : nil } ?? []
        }
        if !names.isDisjoint(with: nonBlockingExceptionOptions) { return [] }

        let host = isRegex ? nil : anchoredHost(pattern).flatMap { isCountableHost($0) ? $0 : nil }
        let urlFilter = !isRegex && isCountableURLFilter(pattern) ? pattern : ""
        // Widened to everywhere, a catch-all like `*` or `|http` would
        // cancel every count, so keep it to the sites DNR can express.
        if host == nil, isCatchAll(pattern), scopedSites.isEmpty {
            return includedSites.map { ["S", $0] }
        }
        if urlFilter.isEmpty {
            // A regex or odd pattern could lift any block, so the only safe
            // reading is that it lifts every block on its sites.
            if !scopedSites.isEmpty, host == nil { return scopedSites.map { ["S", $0] } }
            guard let host else { return [] }
            if scopedSites.isEmpty { return [["X", host]] }
        }
        return [["E", host ?? "", urlFilter, scopedSites.joined(separator: "|")]]
    }

    private static func blockEntry(pattern: String, names: Set<String>) -> [String]? {
        guard pattern.hasPrefix("||"), let host = anchoredHost(pattern), isCountableHost(host) else { return nil }
        var thirdParty = false
        var types: [String] = []
        for name in names {
            switch name {
            case "third-party", "3p": thirdParty = true
            case "important": break
            default:
                guard let mapped = resourceTypeMap[name], !mapped.contains("main_frame") else { return nil }
                types.append(contentsOf: mapped)
            }
        }
        let flag = thirdParty ? "1" : "0"
        if pattern == "||\(host)^", types.isEmpty { return ["H", host, flag] }
        guard isCountableURLFilter(pattern) else { return nil }
        return ["P", host, pattern, Set(types).sorted().joined(separator: ","), flag]
    }

    private static func isCountableHost(_ host: String) -> Bool {
        host.contains(".") && host.allSatisfy(\.isASCII) && isSupportedDomain(host)
            && !host.hasPrefix(".") && !host.hasSuffix(".") && !host.hasPrefix("-")
    }

    private static func isCatchAll(_ pattern: String) -> Bool {
        var rest = pattern.lowercased()
        for token in ["https", "http", "wss", "ws"] { rest = rest.replacingOccurrences(of: token, with: "") }
        return rest.allSatisfy { "*|^:/.".contains($0) }
    }

    /// Plain ASCII in filter syntax, which DNR's `urlFilter` shares.
    private static func isCountableURLFilter(_ pattern: String) -> Bool {
        !pattern.isEmpty && pattern.count <= 512 && !pattern.hasPrefix("||*")
            && pattern.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F }
    }

    // MARK: - Generation

    private struct PathBlock: Hashable {
        var host: String
        var urlFilter: String
        var types: [String]
        var thirdParty: Bool
    }

    private struct Exception: Hashable {
        var host: String
        var urlFilter: String
        var sites: [String]
    }

    public static func generateBlockedCountRules(
        from summary: String,
        disabledSites: [String] = []
    ) -> [DeclarativeRule] {
        var hostBlocks: [String: Bool] = [:]  // host -> third-party only
        var pathBlocks: [PathBlock] = []
        var listCount: [String: Int] = [:]  // how many entries name a host
        var badfilters = Set<String>()
        var exceptedHosts = Set<String>()
        var exceptions = Set<Exception>()
        var pageWideSites = Set(disabledSites
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter(isCountableHost))

        RuleText.forEachLine(summary) { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return }
            switch (parts[0], parts.count) {
            case ("H", 3):
                hostBlocks[parts[1]] = (hostBlocks[parts[1]] ?? true) && parts[2] == "1"
                listCount[parts[1], default: 0] += 1
            case ("P", 5):
                pathBlocks.append(PathBlock(
                    host: parts[1], urlFilter: parts[2],
                    types: parts[3].isEmpty ? [] : parts[3].split(separator: ",").map(String.init),
                    thirdParty: parts[4] == "1"
                ))
                listCount[parts[1], default: 0] += 1
            case ("U", _): badfilters.insert(parts[1])
            case ("X", _): exceptedHosts.insert(parts[1])
            case ("S", _): pageWideSites.insert(parts[1])
            case ("E", 4):
                exceptions.insert(Exception(
                    host: parts[1], urlFilter: parts[2],
                    sites: parts[3].isEmpty ? [] : parts[3].split(separator: "|").map(String.init)
                ))
            default: break
            }
        }
        for host in hostBlocks.keys where badfilters.contains("||\(host)^") { hostBlocks[host] = nil }
        pathBlocks.removeAll { badfilters.contains($0.urlFilter) }

        func selfAndParents(_ host: String) -> [String] {
            var result = [host]
            var rest = Substring(host)
            while let dot = rest.firstIndex(of: ".") {
                rest = rest[rest.index(after: dot)...]
                if rest.contains(".") { result.append(String(rest)) }
            }
            return result
        }
        // A block on a host also covers its subdomains, so an exception on
        // either side of it can let some of its requests through.
        let exceptedSelfOrParent = Set(exceptedHosts.flatMap(selfAndParents))
        func isExcepted(_ host: String) -> Bool {
            exceptedSelfOrParent.contains(host) || selfAndParents(host).contains(where: exceptedHosts.contains)
        }
        /// A host block with the same or wider scope already counts it.
        func coveringHostBlock(_ host: String, thirdParty: Bool, includingSelf: Bool) -> Bool {
            selfAndParents(host).dropFirst(includingSelf ? 0 : 1).contains {
                guard let blockThirdParty = hostBlocks[$0] else { return false }
                return !blockThirdParty || thirdParty
            }
        }
        func rank(_ a: String, _ b: String) -> Bool {
            let (ca, cb) = (listCount[a] ?? 0, listCount[b] ?? 0)
            return ca != cb ? ca > cb : a < b
        }

        var seenPaths = Set<PathBlock>()
        let paths = pathBlocks
            .filter { !isExcepted($0.host) && !coveringHostBlock($0.host, thirdParty: $0.thirdParty, includingSelf: true) }
            .filter { seenPaths.insert($0).inserted }
            .sorted { $0.host != $1.host ? rank($0.host, $1.host) : $0.urlFilter < $1.urlFilter }
        let hosts = hostBlocks
            .filter { !isExcepted($0.key) && !coveringHostBlock($0.key, thirdParty: $0.value, includingSelf: false) }
            .sorted { rank($0.key, $1.key) }
        let countedSelfOrParent = Set((paths.map(\.host) + hosts.map(\.key)).flatMap(selfAndParents))
        let countedHosts = Set(paths.map(\.host) + hosts.map(\.key))

        var rules: [DeclarativeRule] = []
        func append(_ type: String, _ condition: RuleCondition) {
            guard rules.count < blockedCountMaxRules else { return }
            rules.append(DeclarativeRule(
                id: blockedCountRuleIDBase + rules.count,
                priority: blockedCountPriority,
                action: RuleAction(type: type, redirect: nil),
                condition: condition
            ))
        }
        func chunks(_ items: [String]) -> [[String]] {
            stride(from: 0, to: items.count, by: blockedCountDomainsPerRule).map {
                Array(items[$0..<min($0 + blockedCountDomainsPerRule, items.count)])
            }
        }

        // Allows come first: the extension installs them all or no counting
        // rules at all.
        for sites in chunks(pageWideSites.sorted()) {
            var condition = RuleCondition()
            condition.domains = sites
            append("allow", condition)
        }
        let relevant = exceptions.filter {
            $0.host.isEmpty || countedSelfOrParent.contains($0.host)
                || selfAndParents($0.host).contains(where: countedHosts.contains)
        }
        let sortKey = { (e: Exception) in "\(e.host)\t\(e.urlFilter)\t\(e.sites.joined(separator: "|"))" }
        for exception in relevant.sorted(by: { sortKey($0) < sortKey($1) }) {
            var condition = RuleCondition()
            if exception.urlFilter.isEmpty {
                condition.requestDomains = [exception.host]
            } else {
                condition.urlFilter = exception.urlFilter
            }
            condition.domains = exception.sites.isEmpty ? nil : exception.sites
            append("allow", condition)
        }

        // Path rules next: they cost one rule each and cover the busiest
        // trackers, which lists usually block by path rather than whole host.
        for path in paths {
            var condition = RuleCondition()
            condition.urlFilter = path.urlFilter
            condition.resourceTypes = path.types.isEmpty ? nil : path.types
            condition.domainType = path.thirdParty ? "thirdParty" : nil
            append("block", condition)
        }
        // Most-listed hosts first, so a tight budget drops the obscure ones.
        for thirdParty in [false, true] {
            for chunk in chunks(hosts.filter { $0.value == thirdParty }.map(\.key)) {
                var condition = RuleCondition()
                condition.requestDomains = chunk
                condition.domainType = thirdParty ? "thirdParty" : nil
                append("block", condition)
            }
        }
        return rules
    }

    // MARK: - Storage

    static func saveBlockedCountRules(_ rules: [DeclarativeRule], containerURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FilterArtifactStorage.write(
            encoder.encode(rules),
            to: containerURL.appendingPathComponent(blockedCountRulesFilename)
        )
    }

    private struct ParsedBlockedCountRules {
        let fileNumber: Int
        let modified: Date
        let size: Int
        let version: String
        let rules: [[String: Any]]
    }

    private static let blockedCountRulesLock = NSLock()
    nonisolated(unsafe) private static var parsedBlockedCountRules: ParsedBlockedCountRules?

    /// The extension pages through the file, so parse it once per write.
    private static func blockedCountRules(containerURL: URL) -> ParsedBlockedCountRules? {
        let url = containerURL.appendingPathComponent(blockedCountRulesFilename)
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.intValue,
            let modified = attributes[.modificationDate] as? Date,
            let size = (attributes[.size] as? NSNumber)?.intValue
        else { return nil }
        blockedCountRulesLock.lock()
        defer { blockedCountRulesLock.unlock() }
        if let cached = parsedBlockedCountRules,
           cached.fileNumber == fileNumber, cached.modified == modified, cached.size == size {
            return cached
        }
        guard let data = try? Data(contentsOf: url),
              let rules = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return nil }
        let parsed = ParsedBlockedCountRules(
            fileNumber: fileNumber, modified: modified, size: size,
            version: sha256Hex(data: data), rules: rules
        )
        parsedBlockedCountRules = parsed
        return parsed
    }

    /// Pages hold up to `limit` rules but stop at about 20,000 domains, since
    /// one host rule can carry a thousand.
    public static func loadBlockedCountRulesPayload(
        groupIdentifier: String,
        enabled: Bool,
        offset: Int,
        limit: Int
    ) -> [String: Any] {
        let safeOffset = max(0, offset)
        let safeLimit = max(1, min(limit, 1_000))
        var payload: [String: Any] = [
            "ok": true,
            "enabled": enabled,
            "offset": safeOffset,
            "ruleIdBase": blockedCountRuleIDBase,
            "ruleIdLimit": blockedCountRuleIDLimit
        ]
        guard enabled,
              let containerURL = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: groupIdentifier
              ),
              let parsed = blockedCountRules(containerURL: containerURL)
        else {
            payload["version"] = ""
            payload["count"] = 0
            payload["rules"] = [] as [[String: Any]]
            return payload
        }
        var page: [[String: Any]] = []
        var domains = 0
        var index = safeOffset
        while index < parsed.rules.count, page.count < safeLimit {
            let ruleDomains = ((parsed.rules[index]["condition"] as? [String: Any])?["requestDomains"] as? [Any])?.count ?? 1
            if !page.isEmpty, domains + ruleDomains > 20_000 { break }
            page.append(parsed.rules[index])
            domains += ruleDomains
            index += 1
        }
        payload["version"] = parsed.version
        payload["count"] = parsed.rules.count
        payload["rules"] = page
        return payload
    }
}
