import Foundation
internal import WBEngine

// `$redirect` support: a matching request is served a bundled stand-in from
// wBlock Scripts instead of failing. Safari content blockers cannot redirect,
// so these become DNR rules, and native blockers get matching exceptions
// (carve-outs) so their block cannot win the race against the redirect.
//
// Conservative by design. A rule is skipped, never widened, when its options,
// pattern, domains, or resource are not exactly representable. `$redirect-rule`
// (replace only if something else blocks) has no DNR form; it is used only when
// the same list blocks the request's whole host and excepts nothing there.
//
// A blocking exception (`@@||host/path$script`) from any list also stops a
// redirect of the requests it covers, as it stops the block they stand in for.
extension RemoveParamDNRRuleGenerator {
    /// Bump when `extractRedirectLines` changes, so cached lists rescan.
    static let redirectExtractionFormat = 2
    /// The built-in compatibility rules reach every content blocker, so their
    /// exceptions are weighed against every list's redirects too.
    static let compatibilityRedirectLines = extractRedirectLines(
        from: ContentBlockerService.embeddedCompatibilityRules
    )
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

    /// DNR type of a resource-type option, including types no stand-in serves.
    private static func requestType(_ option: String) -> String? {
        redirectTypeMap[option] ?? resourceTypeMap[option]?.first
    }

    private static func domainType(_ option: String) -> String? {
        switch option {
        case "third-party", "3p", "~first-party", "~1p": return "thirdParty"
        case "~third-party", "~3p", "first-party", "1p": return "firstParty"
        default: return nil
        }
    }

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
        /// A blocking exception with no redirect option, such as `@@||host^$script`.
        var isPlain: Bool

        init?(_ rawLine: Substring) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // The byte check spares the five searches: few network rules have a `#`.
            guard !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("["),
                  !line.utf8.contains(UInt8(ascii: "#"))
                    || !["##", "#@#", "#%#", "#$#", "#?#"].contains(where: line.contains)
            else { return nil }
            isException = line.hasPrefix("@@")
            let dollar = line.lastIndex(of: "$")
            pattern = String(line[..<(dollar ?? line.endIndex)])
            if isException { pattern.removeFirst(2) }
            var token: String?
            var kind: String?
            var rest: [(name: String, value: String?)] = []
            for option in RemoveParamDNRRuleGenerator.splitOptions(
                dollar.map { String(line[line.index(after: $0)...]) } ?? ""
            ) {
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
            isPlain = kind == nil
            isConditional = kind == "redirect-rule"
            isBadfilter = rest.contains { $0.name == "badfilter" }
            options = rest.filter { $0.name != "badfilter" }
            self.token = token.flatMap { $0.isEmpty ? nil : $0 }
            // Any other option makes it an exception from something other than
            // blocking (`$elemhide`, `$csp`), or narrows it in a way not modelled
            // here (`$to`). A regex pattern cannot be compared with a directive.
            if isPlain {
                guard isException, !(pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 1),
                      options.allSatisfy({ option in
                          switch option.name {
                          case "domain": return option.value != nil
                          case "important": return option.value == nil
                          default:
                              let name = option.name.hasPrefix("~") ? String(option.name.dropFirst()) : option.name
                              return option.value == nil && (RemoveParamDNRRuleGenerator.domainType(option.name) != nil
                                  || RemoveParamDNRRuleGenerator.requestType(name) != nil)
                          }
                      })
                else { return nil }
            }
        }

        /// Identity shared by a rule and its `$badfilter`.
        var identity: String {
            let opts = options.map { option in option.value.map { "\(option.name)=\($0)" } ?? option.name }
                + (isPlain ? [] : [(isConditional ? "redirect-rule" : "redirect") + (token.map { "=\($0)" } ?? "")])
            return (isException ? "@@" : "") + pattern.lowercased() + "$" + opts.sorted().joined(separator: ",")
        }
    }

    /// `host` of a `||host…` pattern.
    static func anchoredHost<S: StringProtocol>(_ pattern: S) -> String? where S.SubSequence == Substring {
        guard pattern.hasPrefix("||") else { return nil }
        let rest = pattern.dropFirst(2)
        let host: String
        if rest.utf8.allSatisfy({ $0 < 0x80 }) {
            // ASCII bytes are whole characters, so the bytes give the same answer quickly.
            let end = rest.utf8.firstIndex { "^/$|?*:".utf8.contains($0) } ?? rest.endIndex
            host = RuleText.lowercased(rest[..<end])
        } else {
            let end = rest.firstIndex { "^/$|?*:".contains($0) } ?? rest.endIndex
            host = rest[..<end].lowercased()
        }
        return host.contains(".") ? host : nil
    }

    private static func isSameOrParent(_ parent: String, of host: String) -> Bool {
        host == parent || host.hasSuffix("." + parent)
    }

    /// Every `parent` for which `isSameOrParent(parent, of: host)` holds:
    /// `host` and what follows each of its dots.
    private static func selfAndParents(of host: String) -> [Substring] {
        [host[...]] + host.indices.filter { host[$0] == "." }.map { host[host.index(after: $0)...] }
    }

    /// Lines one list needs for redirect resolution: redirect directives,
    /// their exceptions and badfilters, every blocking exception (another
    /// list's redirect may be the one it stops), and for hosts named by
    /// `$redirect-rule` the list's whole-host blocks and its exceptions
    /// touching those hosts.
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
        // Set lookups instead of comparing each line's host with every conditional host.
        let conditionalParents = Set(conditionalHosts.flatMap(selfAndParents))
        RuleText.forEachLine(contents) { rawLine in
            let line = RuleText.trimmed(rawLine)
            let isException = line.hasPrefix("@@")
            guard isException || !conditionalHosts.isEmpty && line.hasPrefix("||"),
                  !RuleText.contains(line, "redirect")
            else { return }
            var needed = isException && RedirectLine(line) != nil
            if !needed, !conditionalHosts.isEmpty, let host = anchoredHost(isException ? line.dropFirst(2) : line) {
                needed = conditionalParents.contains(host[...])
                    || isException && selfAndParents(of: host).contains { conditionalHosts.contains(String($0)) }
            }
            if needed {
                result.append(contentsOf: line)
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
        while let match = RuleText.range(of: needle, in: contents[searchStart...]) {
            let line = contents.lineRange(for: match)
            result.append(contents[line].trimmingTrailingNewlines)
            searchStart = line.upperBound
        }
        return result
    }

    /// Resolves redirect directives from each list's extracted lines. Badfilters
    /// and exceptions apply across lists; `$redirect-rule` blocking
    /// dependencies are checked within the list that declared them.
    static func resourceRedirectRules(
        fromSources sources: [String], scopedSources: Set<Int> = []
    ) -> (rules: [DeclarativeRule], skipped: Int) {
        var parsedSources: [[RedirectLine]] = []
        var hostBlocks: [HostBlocks] = []
        var badfilters = Set<String>()
        var exceptions: [RedirectLine] = []
        var plainExceptions: [Substring] = []
        for (sourceIndex, source) in sources.enumerated() {
            var parsed: [RedirectLine] = []
            var blocks = HostBlocks()
            for rawLine in source.split(whereSeparator: \.isNewline) {
                let candidate = RuleText.contains(rawLine, "redirect") ? RedirectLine(rawLine) : nil
                let line = candidate?.isPlain == false ? candidate : nil
                if line == nil {
                    let plain = RuleText.trimmed(rawLine)
                    blocks.add(plain)
                    if line == nil, plain.hasPrefix("@@"), !scopedSources.contains(sourceIndex) {
                        plainExceptions.append(plain)
                    }
                }
                guard let line else { continue }
                if line.isBadfilter {
                    badfilters.insert(line.identity)
                } else if line.isException || line.token == "none" {
                    exceptions.append(line)
                } else {
                    parsed.append(line)
                }
            }
            parsedSources.append(parsed)
            hostBlocks.append(blocks)
        }
        // Plain exceptions run to thousands. Only one on a directive's host or
        // a parent of it can cover that directive, so the rest are not parsed.
        let directiveHosts = Set(parsedSources.joined().compactMap { anchoredHost($0.pattern) }
            .flatMap { selfAndParents(of: $0).map(String.init) })
        for plain in plainExceptions {
            if let host = anchoredHost(plain.dropFirst(2)), !directiveHosts.contains(host) { continue }
            guard let line = RedirectLine(plain) else { continue }
            if line.isBadfilter {
                badfilters.insert(line.identity)
            } else {
                exceptions.append(line)
            }
        }

        // Redirect exceptions are few, and each is weighed against every
        // directive. A directive looks up the plain ones by its pattern, its
        // host, and that host's parents.
        var redirectExceptions: [RedirectException] = []
        var plainAt: [String: [RedirectException]] = [:]
        for line in exceptions where !badfilters.contains(line.identity) {
            guard let exception = RedirectException(line) else { continue }
            guard exception.isPlain else {
                redirectExceptions.append(exception)
                continue
            }
            plainAt[exception.pattern.host ?? exception.pattern.text, default: []].append(exception)
        }

        var rules: [DeclarativeRule] = []
        var seen = Set<Data>()
        var skipped = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (index, lines) in parsedSources.enumerated() {
            for line in lines where !badfilters.contains(line.identity) {
                guard !line.isConditional || hostBlocks[index].blocksWholeHost(line),
                      let token = line.token,
                      let path = RedirectResourceCatalog.paths[token],
                      var condition = redirectCondition(for: line, path: path)
                else {
                    skipped += 1
                    continue
                }
                let important = line.options.contains { $0.name == "important" }
                let pattern = HostPattern(line.pattern)
                let site = pattern.host.flatMap(WBEngine.registrableDomain)
                var keys = pattern.host.map { selfAndParents(of: $0).map(String.init) } ?? [pattern.text]
                if keys != [""] { keys.append("") }
                let applies = { (exception: RedirectException) in
                    apply(exception, to: pattern, site: site, path: path, important: important, condition: &condition)
                }
                guard redirectExceptions.allSatisfy(applies),
                      keys.allSatisfy({ plainAt[$0]?.allSatisfy(applies) ?? true })
                else {
                    skipped += 1
                    continue
                }
                condition.excludedDomains = condition.excludedDomains.map { Array(Set($0)).sorted() }
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

    /// A lowercased pattern, its `||host`, and the bytes that follow that host.
    private struct HostPattern {
        let text: String
        let host: String?
        let tail: [UInt8]

        init(_ pattern: String) {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            text = trimmed == "*" ? "" : trimmed.lowercased()
            host = anchoredHost(trimmed)
            tail = Array(text.utf8.dropFirst(host.map { 2 + $0.utf8.count } ?? text.utf8.count))
        }
    }

    /// An exception, read once: its resource, pattern, and `domain=` scope,
    /// and for a plain exception the requests it lifts blocking for.
    private struct RedirectException {
        let namesResource: Bool
        let path: String?
        let pattern: HostPattern
        /// Nil unless the scope is one `domain=` list of supported domains.
        let excepted: [String]?
        let isPlain: Bool
        let isImportant: Bool
        let party: String?
        /// The registrable domain of each excepted domain, when `party` is set.
        let exceptedSites: [String?]
        /// Empty when the exception names no resource type.
        private var types = Set<String>()
        private var excludedTypes = Set<String>()

        /// Nil for a plain exception scoped only to sites a condition cannot
        /// name (`site.*`). Dropping the directive everywhere for it would
        /// cost far more than the exception covers.
        init?(_ line: RedirectLine) {
            let token = line.token == "none" ? nil : line.token
            namesResource = token != nil
            path = token.flatMap { RedirectResourceCatalog.paths[$0] }
            pattern = HostPattern(line.pattern)
            let scopes = line.options.filter { $0.name == "domain" || $0.name == "from" }
            let domains = scopes.count == 1 ? scopes[0].value.map {
                $0.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            } : nil
            isPlain = line.isPlain
            if isPlain, !scopes.isEmpty {
                // Exclusions cannot be represented by subtracting the included sites.
                guard scopes.count == 1, let scope = scopes[0].value.flatMap(redirectDomainScope),
                      scope.excluded == nil, scope.included != nil else { return nil }
                excepted = scope.included
            } else {
                excepted = domains?.allSatisfy(isSupportedDomain) == true ? domains : nil
            }
            isImportant = line.options.contains { $0.name == "important" }
            party = line.options.lazy.compactMap { domainType($0.name) }.first
            exceptedSites = party == nil ? [] : (excepted ?? []).map(WBEngine.registrableDomain)
            for option in line.options {
                if option.name.hasPrefix("~") {
                    if let type = requestType(String(option.name.dropFirst())) { excludedTypes.insert(type) }
                } else if let type = requestType(option.name) {
                    types.insert(type)
                }
            }
        }

        func lifts(type: String) -> Bool {
            (types.isEmpty || types.contains(type)) && !excludedTypes.contains(type)
        }

        /// Whether a plain exception matches every URL the directive matches.
        func covers(_ directive: HostPattern) -> Bool {
            if pattern.text.isEmpty || pattern.text == directive.text { return true }
            guard let own = pattern.host, let host = directive.host, isSameOrParent(own, of: host) else { return false }
            return pathCovers(pattern.tail, directive.tail)
        }
    }

    /// Whether an exception's text after its host matches every URL a
    /// directive's does. False when that cannot be shown.
    private static func pathCovers(_ exception: [UInt8], _ directive: [UInt8]) -> Bool {
        let star = UInt8(ascii: "*"), separator = UInt8(ascii: "^")
        func separates(_ byte: UInt8) -> Bool {
            byte == separator || !(byte >= 0x80 || (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x30 && byte <= 0x39)
                || "_-.%*".utf8.contains(byte))
        }
        var e = 0, d = 0
        var resume: (e: Int, d: Int)?
        while e < exception.count {
            let byte = exception[e]
            if byte == star {
                e += 1
                resume = (e, d)
            } else if d == directive.count {
                return exception[e...].allSatisfy { $0 == star }
            } else if byte == directive[d]
                        // An exception separator covers a literal separator, not vice versa.
                        || byte == separator && separates(directive[d]) {
                e += 1
                d += 1
            } else if let last = resume {
                // The wildcard takes one more byte of the directive's text.
                (e, d) = (last.e, last.d + 1)
                resume = (e, d)
            } else {
                return false
            }
        }
        return true
    }

    /// Applies an exception to a directive's condition. Returns false when
    /// the directive must be dropped.
    ///
    /// A redirect exception errs toward suppressing: it applies when it names
    /// the same or any resource and shares the pattern or anchored host, or
    /// has no pattern.
    ///
    /// A plain exception applies only when it covers every URL of the
    /// directive, for the resource types and party it lifts blocking for, and
    /// not against `$important` unless it is important itself. No condition
    /// can leave out part of a directive's URLs, and dropping a host-wide
    /// directive for one excepted file would cost every other request there.
    ///
    /// Plain exceptions are applied only when their type, party and site
    /// intersection can be represented without losing unrelated requests.
    private static func apply(
        _ exception: RedirectException, to pattern: HostPattern, site: String?, path: String, important: Bool,
        condition: inout RuleCondition
    ) -> Bool {
        var excepted = exception.excepted
        if exception.isPlain {
            guard exception.isImportant || !important, exception.covers(pattern) else { return true }
            if let party = exception.party {
                if let own = condition.domainType {
                    guard own == party else { return true }
                } else if let domains = excepted {
                    guard let site, exception.exceptedSites.allSatisfy({ $0 != nil }) else { return true }
                    // Seen from one site, every request to the directive's host is the same party.
                    excepted = zip(domains, exception.exceptedSites)
                        .filter { ($0.1 == site) == (party == "firstParty") }.map(\.0)
                    guard excepted != [] else { return true }
                }
            }
            let types = condition.resourceTypes ?? []
            let kept = types.filter { !exception.lifts(type: $0) }
            guard kept.count < types.count else { return true }
            if excepted != nil && !kept.isEmpty { return true }
            if excepted == nil {
                if !kept.isEmpty {
                    guard exception.party == nil || condition.domainType != nil else { return true }
                    condition.resourceTypes = kept
                    return true
                }
                if let party = exception.party, condition.domainType == nil {
                    condition.domainType = party == "firstParty" ? "thirdParty" : "firstParty"
                    return true
                }
            }
        } else {
            if exception.namesResource, exception.path != path { return true }
            var related = exception.pattern.text.isEmpty || exception.pattern.text == pattern.text
            if !related, let a = exception.pattern.host, let b = pattern.host {
                related = isSameOrParent(a, of: b) || isSameOrParent(b, of: a)
            }
            guard related else { return true }
        }
        guard let excepted else { return false }
        if var included = condition.domains {
            for domain in excepted {
                if included.contains(where: { $0 != domain && isSameOrParent($0, of: domain) }) {
                    return exception.isPlain
                }
                included.removeAll { isSameOrParent(domain, of: $0) }
            }
            guard !included.isEmpty else { return false }
            condition.domains = included
        } else {
            condition.excludedDomains = (condition.excludedDomains ?? []) + excepted
        }
        return true
    }

    /// One list's whole-host blocks and the hosts its exceptions name, which
    /// decide its `$redirect-rule` directives.
    private struct HostBlocks {
        /// Blocked host, and whether the block covers first-party requests too.
        private var blocks: [String: Bool] = [:]
        private var exceptionHosts = Set<String>()
        private var exceptionHostParents = Set<String>()

        mutating func add(_ line: Substring) {
            if line.hasPrefix("@@") {
                guard let host = anchoredHost(line.dropFirst(2)) else { return }
                exceptionHosts.insert(host)
                exceptionHostParents.formUnion(selfAndParents(of: host).map(String.init))
                return
            }
            let parts = line.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
            let options = parts.count > 1 ? parts[1].lowercased() : ""
            let thirdPartyOnly = options == "third-party" || options == "3p"
            guard options.isEmpty || thirdPartyOnly, let host = anchoredHost(parts[0]),
                  ["||\(host)", "||\(host)^", "||\(host)/", "||\(host)^|"].contains(parts[0].lowercased())
            else { return }
            blocks[host] = blocks[host] == true || !thirdPartyOnly
        }

        /// The list blocks the directive's whole host (or a parent) and has no
        /// exception touching it, so the directive's requests are always blocked.
        func blocksWholeHost(_ line: RedirectLine) -> Bool {
            guard let host = anchoredHost(line.pattern), !exceptionHostParents.contains(host) else { return false }
            let parents = selfAndParents(of: host).map(String.init)
            let isThirdParty = line.options.contains { $0.name == "third-party" || $0.name == "3p" }
            return !parents.contains(where: exceptionHosts.contains)
                && parents.contains { blocks[$0].map { $0 || isThirdParty } ?? false }
        }
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
            case "domain", "from":
                guard condition.domains == nil, condition.excludedDomains == nil,
                      let value = option.value, let scope = redirectDomainScope(value)
                else { return nil }
                condition.domains = scope.included
                condition.excludedDomains = scope.excluded
            default:
                if let party = domainType(option.name) {
                    condition.domainType = party
                    continue
                }
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
    static func saveRedirectCarveOutLines(_ lines: [String], containerURL: URL) -> Int {
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
