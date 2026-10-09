import Foundation

// `$redirect` support: a matching request is served a bundled stand-in from
// wBlock Scripts instead of failing. Safari content blockers cannot redirect,
// so these become DNR rules, and native blockers get matching exceptions
// (carve-outs) so their block cannot win the race against the redirect.
//
// Conservative by design. A rule is skipped, never widened, when its options,
// pattern, domains, or resource are not exactly representable. `$redirect-rule`
// (replace only if something else blocks) has no DNR form; it is used only when
// the same list blocks the request's whole host and excepts nothing there.
extension RemoveParamDNRRuleGenerator {
    static let redirectPriority = 15_000
    static let importantRedirectPriority = 15_100
    public static let redirectCarveOutsFilename = "redirect_carveouts.txt"
    public static let redirectStatusFilename = "redirect_dnr_status.json"
    /// Carve-outs are dropped when wBlock Scripts has not confirmed its
    /// redirects for this long, so a disabled extension cannot leave native
    /// blocks lifted indefinitely.
    static let redirectStatusMaxAge: TimeInterval = 3 * 24 * 60 * 60

    private static let redirectTypeMap: [String: String] = [
        "script": "script", "xmlhttprequest": "xmlhttprequest", "xhr": "xmlhttprequest",
        "image": "image", "stylesheet": "stylesheet", "css": "stylesheet", "font": "font",
        "media": "media", "subdocument": "sub_frame", "frame": "sub_frame",
        "ping": "ping", "other": "other",
    ]
    private static let filterTypeNames: [String: String] = [
        "script": "script", "xmlhttprequest": "xmlhttprequest", "image": "image",
        "stylesheet": "stylesheet", "font": "font", "media": "media",
        "sub_frame": "subdocument", "ping": "ping", "other": "other",
    ]
    /// Types a typeless rule is narrowed to, by the stand-in's file type.
    private static let defaultTypesByExtension: [String: [String]] = [
        "js": ["script", "xmlhttprequest"], "txt": ["xmlhttprequest"], "json": ["xmlhttprequest"],
        "xml": ["xmlhttprequest"], "html": ["sub_frame"], "css": ["stylesheet"],
        "gif": ["image"], "png": ["image"], "mp3": ["media"], "mp4": ["media"],
    ]

    struct RedirectLine {
        var isException: Bool
        var pattern: String
        /// Options other than the redirect option itself.
        var options: [(name: String, value: String?)]
        /// Lowercased resource token without a uBO `:priority`; nil when an
        /// exception names no resource.
        var token: String?
        var isConditional: Bool
        var isBadfilter: Bool

        init?(_ rawLine: Substring) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("["),
                  !line.contains("##"), !line.contains("#@#"), !line.contains("#%#"),
                  !line.contains("#$#"), !line.contains("#?#"),
                  let dollar = line.lastIndex(of: "$")
            else { return nil }
            isException = line.hasPrefix("@@")
            pattern = String(line[..<dollar])
            if isException { pattern.removeFirst(2) }
            line = String(line[line.index(after: dollar)...])
            var token: String?
            var kind: String?
            var rest: [(name: String, value: String?)] = []
            for option in RemoveParamDNRRuleGenerator.splitOptions(line) {
                let pair = RemoveParamDNRRuleGenerator.optionNameAndValue(option)
                if pair.name == "redirect" || pair.name == "redirect-rule" {
                    guard kind == nil else { return nil }
                    kind = pair.name
                    token = pair.value.map { value in
                        let lowered = value.lowercased()
                        if let colon = lowered.lastIndex(of: ":"),
                           Int(lowered[lowered.index(after: colon)...]) != nil {
                            return String(lowered[..<colon])
                        }
                        return lowered
                    }
                } else {
                    rest.append(pair)
                }
            }
            guard let kind else { return nil }
            isConditional = kind == "redirect-rule"
            isBadfilter = rest.contains { $0.name == "badfilter" }
            options = rest.filter { $0.name != "badfilter" }
            self.token = token.flatMap { $0.isEmpty ? nil : $0 }
        }

        /// Identity shared by a rule and its `$badfilter`.
        var identity: String {
            let opts = options.map { option in option.value.map { "\(option.name)=\($0)" } ?? option.name }
                + [(isConditional ? "redirect-rule" : "redirect") + (token.map { "=\($0)" } ?? "")]
            return (isException ? "@@" : "") + pattern.lowercased() + "$" + opts.sorted().joined(separator: ",")
        }
    }

    /// `host` of a `||host…` pattern.
    static func anchoredHost(_ pattern: String) -> String? {
        guard pattern.hasPrefix("||") else { return nil }
        let rest = pattern.dropFirst(2)
        let end = rest.firstIndex { "^/$|?*:".contains($0) } ?? rest.endIndex
        let host = rest[..<end].lowercased()
        return host.contains(".") ? host : nil
    }

    private static func isSameOrParent(_ parent: String, of host: String) -> Bool {
        host == parent || host.hasSuffix("." + parent)
    }

    /// Lines one list needs for redirect resolution: redirect directives,
    /// their exceptions and badfilters, and for hosts named by `$redirect-rule`
    /// the list's whole-host blocks and its exceptions touching those hosts.
    public static func extractRedirectLines(from contents: String) -> String {
        var result = ""
        var conditionalHosts = Set<String>()
        for rawLine in lines(containing: "redirect", in: contents) {
            guard let parsed = RedirectLine(rawLine) else { continue }
            result.append(contentsOf: rawLine)
            result.append("\n")
            if parsed.isConditional, !parsed.isException, let host = anchoredHost(parsed.pattern) {
                conditionalHosts.insert(host)
            }
        }
        guard !conditionalHosts.isEmpty else { return result }
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("||") || line.hasPrefix("@@||"), !line.contains("redirect") else { continue }
            let isException = line.hasPrefix("@@")
            guard let host = anchoredHost(isException ? String(line.dropFirst(2)) : line) else { continue }
            let related = conditionalHosts.contains {
                isSameOrParent(host, of: $0) || (isException && isSameOrParent($0, of: host))
            }
            if related {
                result.append(line)
                result.append("\n")
            }
        }
        return result
    }

    /// Lines containing `needle`, found by substring search instead of
    /// splitting the whole list (most lists never mention it).
    private static func lines(containing needle: String, in contents: String) -> [Substring] {
        var result: [Substring] = []
        var searchStart = contents.startIndex
        while let match = contents.range(of: needle, range: searchStart..<contents.endIndex) {
            let line = contents.lineRange(for: match)
            result.append(contents[line].trimmingTrailingNewlines)
            searchStart = line.upperBound
        }
        return result
    }

    /// Resolves redirect directives from each list's extracted lines. Badfilters
    /// and redirect exceptions apply across lists; `$redirect-rule` blocking
    /// dependencies are checked within the list that declared them.
    static func resourceRedirectRules(
        fromSources sources: [String]
    ) -> (rules: [DeclarativeRule], skipped: Int) {
        var parsedSources: [[RedirectLine]] = []
        var otherLines: [[String]] = []
        var badfilters = Set<String>()
        var exceptions: [RedirectLine] = []
        for source in sources {
            var parsed: [RedirectLine] = []
            var plain: [String] = []
            for rawLine in source.split(whereSeparator: \.isNewline) {
                guard let line = RedirectLine(rawLine) else {
                    plain.append(rawLine.trimmingCharacters(in: .whitespaces))
                    continue
                }
                if line.isBadfilter {
                    badfilters.insert(line.identity)
                } else if line.isException || line.token == "none" {
                    var exception = line
                    if exception.token == "none" { exception.token = nil }
                    exceptions.append(exception)
                } else {
                    parsed.append(line)
                }
            }
            parsedSources.append(parsed)
            otherLines.append(plain)
        }

        var rules: [DeclarativeRule] = []
        var seen = Set<Data>()
        var skipped = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (index, lines) in parsedSources.enumerated() {
            for line in lines where !badfilters.contains(line.identity) {
                guard !line.isConditional || isBlockedWholeHost(line, in: otherLines[index]),
                      let token = line.token,
                      let path = RedirectResourceCatalog.paths[token],
                      var condition = redirectCondition(for: line, path: path),
                      exceptions.allSatisfy({ apply($0, to: line, condition: &condition) })
                else {
                    skipped += 1
                    continue
                }
                let important = line.options.contains { $0.name == "important" }
                let rule = DeclarativeRule(
                    id: 0,
                    priority: important ? importantRedirectPriority : redirectPriority,
                    action: RuleAction(type: "redirect", redirect: Redirect(extensionPath: path)),
                    condition: condition
                )
                if let key = try? encoder.encode(rule), seen.insert(key).inserted {
                    rules.append(rule)
                }
            }
        }
        return (rules, skipped)
    }

    /// Applies a redirect exception to a directive's condition. Errs toward
    /// suppressing: it applies when it names the same or any resource and
    /// shares the pattern or anchored host, or has no pattern. A plain
    /// `domain=` scope is subtracted from the condition; any other scope, or
    /// one the condition cannot exclude exactly, drops the directive.
    /// Returns false when the directive must be dropped.
    private static func apply(
        _ exception: RedirectLine, to line: RedirectLine, condition: inout RuleCondition
    ) -> Bool {
        if let token = exception.token,
           RedirectResourceCatalog.paths[token] != line.token.flatMap({ RedirectResourceCatalog.paths[$0] }) {
            return true
        }
        let pattern = exception.pattern.trimmingCharacters(in: .whitespaces)
        var related = pattern.isEmpty || pattern == "*" || pattern.lowercased() == line.pattern.lowercased()
        if !related, let a = anchoredHost(pattern), let b = anchoredHost(line.pattern) {
            related = isSameOrParent(a, of: b) || isSameOrParent(b, of: a)
        }
        guard related else { return true }

        let scopes = exception.options.filter { $0.name == "domain" || $0.name == "from" }
        guard scopes.count == 1, let value = scopes[0].value else { return false }
        var excepted: [String] = []
        for raw in value.split(separator: "|", omittingEmptySubsequences: false) {
            let domain = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard isSupportedDomain(domain) else { return false }
            excepted.append(domain)
        }
        if var included = condition.domains {
            for domain in excepted {
                if included.contains(where: { $0 != domain && isSameOrParent($0, of: domain) }) { return false }
                included.removeAll { isSameOrParent(domain, of: $0) }
            }
            guard !included.isEmpty else { return false }
            condition.domains = included
        } else {
            condition.excludedDomains = Array(Set((condition.excludedDomains ?? []) + excepted)).sorted()
        }
        return true
    }

    /// The list blocks the directive's whole host (or a parent) and has no
    /// exception touching it, so the directive's requests are always blocked.
    private static func isBlockedWholeHost(_ line: RedirectLine, in lines: [String]) -> Bool {
        guard let host = anchoredHost(line.pattern) else { return false }
        let isThirdParty = line.options.contains { $0.name == "third-party" || $0.name == "3p" }
        var blocked = false
        for other in lines {
            if other.hasPrefix("@@") {
                if let exceptionHost = anchoredHost(String(other.dropFirst(2))),
                   isSameOrParent(exceptionHost, of: host) || isSameOrParent(host, of: exceptionHost) {
                    return false
                }
                continue
            }
            let parts = other.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
            let pattern = String(parts[0])
            let options = parts.count > 1 ? String(parts[1]).lowercased() : ""
            guard options.isEmpty || (isThirdParty && (options == "third-party" || options == "3p")),
                  let blockHost = anchoredHost(pattern),
                  ["||\(blockHost)", "||\(blockHost)^", "||\(blockHost)/", "||\(blockHost)^|"].contains(pattern.lowercased()),
                  isSameOrParent(blockHost, of: host)
            else { continue }
            blocked = true
        }
        return blocked
    }

    private static func redirectCondition(for line: RedirectLine, path: String) -> RuleCondition? {
        var pattern = line.pattern.trimmingCharacters(in: .whitespaces)
        if pattern == "*" { pattern = "" }
        guard !(pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 1),
              pattern.allSatisfy(\.isASCII)
        else { return nil }

        var condition = RuleCondition()
        condition.urlFilter = normalizeURLFilterPattern(pattern)
        condition.isUrlFilterCaseSensitive = false
        var types: [String] = []
        for option in line.options {
            switch option.name {
            case "important":
                continue
            case "match-case":
                condition.isUrlFilterCaseSensitive = true
            case "third-party", "3p", "~first-party", "~1p":
                condition.domainType = "thirdParty"
            case "~third-party", "~3p", "first-party", "1p":
                condition.domainType = "firstParty"
            case "domain", "from":
                guard condition.domains == nil, condition.excludedDomains == nil,
                      let value = option.value, let scope = redirectDomainScope(value)
                else { return nil }
                condition.domains = scope.included
                condition.excludedDomains = scope.excluded
            default:
                guard option.value == nil, let type = redirectTypeMap[option.name] else { return nil }
                if !types.contains(type) { types.append(type) }
            }
        }
        if types.isEmpty {
            guard let defaults = defaultTypesByExtension[(path as NSString).pathExtension] else { return nil }
            types = defaults
        }
        condition.resourceTypes = types
        // A pattern-less, unscoped directive would replace a whole resource
        // type everywhere. Older Safari ignores excludedDomains next to
        // domains, which would widen the rule.
        guard condition.urlFilter != nil || condition.domains != nil,
              condition.domains == nil || condition.excludedDomains == nil
        else { return nil }
        return condition
    }

    /// `domain=` scope. Wildcard-TLD inclusions (`site.*`) are dropped, which
    /// only narrows the rule; a wildcard exclusion cannot be narrowed safely.
    private static func redirectDomainScope(_ value: String) -> (included: [String]?, excluded: [String]?)? {
        var included: [String] = []
        var excluded: [String] = []
        var droppedInclusion = false
        for raw in value.split(separator: "|", omittingEmptySubsequences: false) {
            var domain = raw.trimmingCharacters(in: .whitespaces).lowercased()
            let isExcluded = domain.hasPrefix("~")
            if isExcluded { domain.removeFirst() }
            if domain.hasSuffix(".*"), !isExcluded {
                droppedInclusion = true
                continue
            }
            guard isSupportedDomain(domain) else { return nil }
            if isExcluded {
                if !excluded.contains(domain) { excluded.append(domain) }
            } else if !included.contains(domain) {
                included.append(domain)
            }
        }
        if droppedInclusion && included.isEmpty { return nil }
        return (included.isEmpty ? nil : included.sorted(), excluded.isEmpty ? nil : excluded.sorted())
    }

    /// Native exception equivalent to a redirect rule's condition, or nil for
    /// other rules.
    public static func carveOutLine(for rule: DeclarativeRule) -> String? {
        guard rule.action.redirect?.extensionPath != nil else { return nil }
        let condition = rule.condition
        var options = (condition.resourceTypes ?? []).compactMap { filterTypeNames[$0] }
        let domains = (condition.domains ?? []) + (condition.excludedDomains ?? []).map { "~" + $0 }
        if !domains.isEmpty { options.append("domain=" + domains.joined(separator: "|")) }
        if condition.domainType == "thirdParty" { options.append("third-party") }
        if condition.domainType == "firstParty" { options.append("~third-party") }
        if condition.isUrlFilterCaseSensitive == true { options.append("match-case") }
        options.append("important")
        return "@@" + (condition.urlFilter ?? "*") + "$" + options.joined(separator: ",")
    }

    // MARK: - Native carve-outs

    /// What wBlock Scripts last reported about its installed redirects.
    public struct RedirectStatus: Codable, Equatable {
        public var installedRedirects: Int
        public var hostAccess: Bool
        public var privateAccess: Bool?
        public var reportedAt: Date

        public init(installedRedirects: Int, hostAccess: Bool, privateAccess: Bool?, reportedAt: Date) {
            self.installedRedirects = installedRedirects
            self.hostAccess = hostAccess
            self.privateAccess = privateAccess
            self.reportedAt = reportedAt
        }
    }

    public static func saveRedirectStatus(_ status: RedirectStatus, containerURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(status).write(
            to: containerURL.appendingPathComponent(redirectStatusFilename), options: .atomic
        )
    }

    static func loadRedirectStatus(containerURL: URL) -> RedirectStatus? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let data = try? Data(contentsOf: containerURL.appendingPathComponent(redirectStatusFilename)) else {
            return nil
        }
        return try? decoder.decode(RedirectStatus.self, from: data)
    }

    /// Lifting a native block is only safe while wBlock Scripts serves the
    /// replacement: it must have reported recently, with access to every site
    /// and private windows, and at least as many redirects as are planned.
    public static func carveOutsAllowed(status: RedirectStatus?, redirectCount: Int, now: Date = Date()) -> Bool {
        guard let status, redirectCount > 0 else { return false }
        return status.hostAccess
            && status.privateAccess == true
            && status.installedRedirects >= redirectCount
            && now.timeIntervalSince(status.reportedAt) < redirectStatusMaxAge
    }

    /// Writes the carve-outs the next content-blocker conversion appends, or
    /// an empty file when they are not safe. Returns the number written.
    static func saveRedirectCarveOuts(for rules: [DeclarativeRule], containerURL: URL) -> Int {
        let lines = rules.compactMap(carveOutLine)
        let allowed = carveOutsAllowed(
            status: loadRedirectStatus(containerURL: containerURL), redirectCount: lines.count
        )
        let text = allowed
            ? "! wBlock: requests wBlock Scripts replaces with stand-ins\n" + lines.joined(separator: "\n")
            : ""
        try? text.write(
            to: containerURL.appendingPathComponent(redirectCarveOutsFilename), atomically: true, encoding: .utf8
        )
        return allowed ? lines.count : 0
    }

    public static func savedRedirectCarveOuts(containerURL: URL) -> String {
        (try? String(contentsOf: containerURL.appendingPathComponent(redirectCarveOutsFilename), encoding: .utf8)) ?? ""
    }
}

private extension Substring {
    var trimmingTrailingNewlines: Substring {
        var line = self
        while let last = line.last, last.isNewline { line = line.dropLast() }
        return line
    }
}

/// Redirect directives AdGuard strips from its Safari builds, taken from the
/// matching Chromium builds by scripts/update-redirect-feed.swift.
enum RedirectFeed {
    private final class BundleMarker {}

    private static let lists: [String: String] = {
        guard let url = Bundle(for: BundleMarker.self).url(forResource: "redirect-feed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }()

    /// AdGuard filter ID of a list served from AdGuard's Safari or iOS build.
    static func adGuardFilterID(for url: URL) -> String? {
        let path = url.path
        guard path.contains("/extension/safari/filters/") || path.contains("/ios/filters/") else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let id = name.hasSuffix("_optimized") ? String(name.dropLast("_optimized".count)) : name
        return id.allSatisfy(\.isNumber) && !id.isEmpty ? id : nil
    }

    static func sources(for filters: [FilterList]) -> [String] {
        var seen = Set<String>()
        return filters.compactMap { filter in
            guard let id = adGuardFilterID(for: filter.url), seen.insert(id).inserted else { return nil }
            return lists[id]
        }
    }
}
