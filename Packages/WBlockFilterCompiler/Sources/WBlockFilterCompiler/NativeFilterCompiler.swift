import Foundation

public struct NativeFilterCompiler: FilterCompiling {
    public init() {}

    public func compile(
        _ sources: [FilterSource],
        configuration: FilterCompilerConfiguration = FilterCompilerConfiguration()
    ) throws -> FilterCompilationResult {
        var diagnostics = CompilationDiagnostics()
        var unsupportedRules: [UnsupportedRule] = []
        var networkRules: [NetworkRule] = []
        var cosmeticRules: [CosmeticRule] = []
        var cosmeticExceptionRules: [CosmeticRule] = []
        var advancedCSSRules: [AdvancedStyleRule] = []
        var advancedExtendedCSSRules: [AdvancedStyleRule] = []
        var advancedExtendedCSSExceptionRules: [AdvancedStyleRule] = []
        var advancedJSRules: [AdvancedStyleRule] = []
        var advancedScriptletRules: [AdvancedScriptletRule] = []
        var advancedScriptletExceptionRules: [AdvancedScriptletRule] = []
        var badfilterIdentities = Set<String>()

        for source in sources {
            var lines = LineReader.read(source: source)
            diagnostics.totalLines += lines.count

            if configuration.preprocessConditionals {
                lines = FilterPreprocessorEngine.evaluateConditionals(lines, platform: configuration.platform)
            }

            for line in lines {
                let kind = RuleClassifier.classify(line.text)
                diagnostics.classifiedRules[kind, default: 0] += 1

                let advancedRule = AdvancedRuleParser.parse(line)
                let advancedRuleEnabled = advancedRule.map { advancedRuleIsEnabled($0, configuration: configuration) } ?? false
                if let advancedRule, advancedRuleEnabled {
                    switch advancedRule {
                    case .css(let rule):
                        advancedCSSRules.append(rule)
                    case .extendedCss(let rule):
                        advancedExtendedCSSRules.append(rule)
                    case .extendedCssException(let rule):
                        advancedExtendedCSSExceptionRules.append(rule)
                    case .js(let rule):
                        advancedJSRules.append(rule)
                    case .scriptlet(let rule):
                        advancedScriptletRules.append(rule)
                    case .scriptletException(let rule):
                        advancedScriptletExceptionRules.append(rule)
                    }
                    continue
                }

                switch RuleParser.parse(line, configuration: configuration) {
                case .comment, .preprocessor:
                    continue
                case .network(let rule):
                    if rule.isBadfilter {
                        badfilterIdentities.insert(rule.canonicalIdentity)
                    } else if rule.requiresAdvancedURLHandling {
                        advancedJSRules.append(contentsOf: advancedURLHandlingScripts(for: rule))
                    } else {
                        networkRules.append(rule)
                    }
                case .cosmetic(let rule):
                    if configuration.enabledCapabilities.contains(.nativeCosmeticRules) {
                        cosmeticRules.append(rule)
                    } else {
                        unsupportedRules.append(unsupportedRule(line: line, reason: .noSafariEquivalent))
                    }
                case .cosmeticException(let rule):
                    cosmeticExceptionRules.append(rule)
                case .unsupported(let reason):
                    if !advancedRuleEnabled {
                        unsupportedRules.append(unsupportedRule(line: line, reason: reason))
                    }
                }
            }
        }

        let filteredNetworkRules = networkRules.filter { !badfilterIdentities.contains($0.canonicalIdentity) }
        let expandedNetworkRules = expandNetworkRules(filteredNetworkRules)
        let plannedCosmeticRules = applyCosmeticExceptions(cosmeticRules, exceptions: cosmeticExceptionRules)
        let runtimeCosmeticRules = plannedCosmeticRules
            .filter { !$0.ifDomains.isEmpty || !$0.unlessDomains.isEmpty }
            .map { rule in
                AdvancedStyleRule(
                    scope: AdvancedDomainScope(
                        ifDomains: rule.ifDomains,
                        unlessDomains: rule.unlessDomains
                    ),
                    content: rule.selector
                )
            }
        let advancedBundle = AdvancedRuleBundle(
            css: dedupeAdvancedStyleRules(advancedCSSRules + runtimeCosmeticRules),
            extendedCss: dedupeAdvancedStyleRules(applyAdvancedStyleExceptions(advancedExtendedCSSRules, exceptions: advancedExtendedCSSExceptionRules)),
            extendedCssExceptions: dedupeAdvancedStyleRules(advancedExtendedCSSExceptionRules),
            js: dedupeAdvancedStyleRules(advancedJSRules),
            scriptlets: dedupeAdvancedScriptletRules(applyAdvancedScriptletExceptions(advancedScriptletRules, exceptions: advancedScriptletExceptionRules)),
            scriptletExceptions: dedupeAdvancedScriptletRules(advancedScriptletExceptionRules)
        )
        let groupedCosmeticRules = groupCosmeticRules(plannedCosmeticRules)
        let safariRules = planSafariRules(networkRules: expandedNetworkRules, cosmeticRules: groupedCosmeticRules)
        let safariJSON = configuration.target == .diagnosticsOnly ? "[]" : try SafariRuleWriter.write(safariRules)
        let safariRuleCount = configuration.target == .diagnosticsOnly ? 0 : safariRules.count
        diagnostics.emittedSafariRules = safariRuleCount

        return FilterCompilationResult(
            safariRulesJSON: safariJSON,
            safariRuleCount: safariRuleCount,
            advancedRules: advancedBundle,
            diagnostics: diagnostics,
            unsupportedRules: unsupportedRules,
            fingerprints: CompilationFingerprints()
        )
    }

    private func applyCosmeticExceptions(_ rules: [CosmeticRule], exceptions: [CosmeticRule]) -> [CosmeticRule] {
        guard !exceptions.isEmpty else { return rules }

        var exactExceptions = Set<String>()
        var genericExceptionDomainsBySelector: [String: Set<String>] = [:]

        for exception in exceptions {
            exactExceptions.insert(cosmeticExceptionKey(exception))
            if !exception.ifDomains.isEmpty, exception.unlessDomains.isEmpty {
                genericExceptionDomainsBySelector[exception.selector, default: []].formUnion(exception.ifDomains)
            }
        }

        var planned: [CosmeticRule] = []
        for rule in rules {
            if exactExceptions.contains(cosmeticExceptionKey(rule)) {
                continue
            }

            if rule.ifDomains.isEmpty,
               let exceptionDomains = genericExceptionDomainsBySelector[rule.selector],
               !exceptionDomains.isEmpty {
                var updated = rule
                updated.unlessDomains = Array(Set(updated.unlessDomains).union(exceptionDomains)).sorted()
                planned.append(updated)
            } else {
                planned.append(rule)
            }
        }

        return planned
    }

    private func groupCosmeticRules(_ rules: [CosmeticRule], maxSelectorLength: Int = 5000) -> [CosmeticRule] {
        var grouped: [String: [CosmeticRule]] = [:]
        for rule in rules {
            grouped[cosmeticScopeKey(rule), default: []].append(rule)
        }

        var output: [CosmeticRule] = []
        for key in grouped.keys.sorted() {
            guard let bucket = grouped[key], let first = bucket.first else { continue }
            var selector = ""
            var source = first.source

            for rule in bucket.sorted(by: { $0.selector < $1.selector }) {
                let candidate = selector.isEmpty ? rule.selector : selector + "," + rule.selector
                if !selector.isEmpty, candidate.count > maxSelectorLength {
                    output.append(
                        CosmeticRule(
                            source: source,
                            selector: selector,
                            ifDomains: first.ifDomains,
                            unlessDomains: first.unlessDomains
                        )
                    )
                    selector = rule.selector
                    source = rule.source
                } else {
                    selector = candidate
                }
            }

            if !selector.isEmpty {
                output.append(
                    CosmeticRule(
                        source: source,
                        selector: selector,
                        ifDomains: first.ifDomains,
                        unlessDomains: first.unlessDomains
                    )
                )
            }
        }

        return output
    }

    private func cosmeticExceptionKey(_ rule: CosmeticRule) -> String {
        [rule.selector, rule.ifDomains.sorted().joined(separator: "|"), rule.unlessDomains.sorted().joined(separator: "|")].joined(separator: "\u{1f}")
    }

    private func cosmeticScopeKey(_ rule: CosmeticRule) -> String {
        [rule.ifDomains.sorted().joined(separator: "|"), rule.unlessDomains.sorted().joined(separator: "|")].joined(separator: "\u{1f}")
    }

    private func advancedRuleIsEnabled(_ rule: AdvancedParsedRule, configuration: FilterCompilerConfiguration) -> Bool {
        switch rule {
        case .css, .js:
            return true
        case .extendedCss, .extendedCssException:
            return configuration.enabledCapabilities.contains(.proceduralCosmetics)
        case .scriptlet, .scriptletException:
            return configuration.enabledCapabilities.contains(.advancedScriptlets)
        }
    }

    private func applyAdvancedStyleExceptions(_ rules: [AdvancedStyleRule], exceptions: [AdvancedStyleRule]) -> [AdvancedStyleRule] {
        guard !exceptions.isEmpty else { return rules }
        let exceptionKeys = Set(exceptions.map(advancedStyleKey))
        return rules.filter { !exceptionKeys.contains(advancedStyleKey($0)) }
    }

    private func applyAdvancedScriptletExceptions(_ rules: [AdvancedScriptletRule], exceptions: [AdvancedScriptletRule]) -> [AdvancedScriptletRule] {
        guard !exceptions.isEmpty else { return rules }
        let exceptionKeys = Set(exceptions.map(advancedScriptletKey))
        return rules.filter { !exceptionKeys.contains(advancedScriptletKey($0)) }
    }

    private func advancedStyleKey(_ rule: AdvancedStyleRule) -> String {
        [
            rule.content,
            rule.scope.ifDomains.joined(separator: "|"),
            rule.scope.unlessDomains.joined(separator: "|")
        ].joined(separator: "\u{1f}")
    }

    private func advancedScriptletKey(_ rule: AdvancedScriptletRule) -> String {
        [
            rule.name,
            rule.args.joined(separator: "\u{1e}"),
            rule.scope.ifDomains.joined(separator: "|"),
            rule.scope.unlessDomains.joined(separator: "|")
        ].joined(separator: "\u{1f}")
    }

    private func dedupeAdvancedStyleRules(_ rules: [AdvancedStyleRule]) -> [AdvancedStyleRule] {
        var seen = Set<AdvancedStyleRule>()
        var output: [AdvancedStyleRule] = []
        for rule in rules where seen.insert(rule).inserted {
            output.append(rule)
        }
        return output
    }

    private func dedupeAdvancedScriptletRules(_ rules: [AdvancedScriptletRule]) -> [AdvancedScriptletRule] {
        var seen = Set<AdvancedScriptletRule>()
        var output: [AdvancedScriptletRule] = []
        for rule in rules where seen.insert(rule).inserted {
            output.append(rule)
        }
        return output
    }

    private func advancedURLHandlingScripts(for rule: NetworkRule) -> [AdvancedStyleRule] {
        var rules: [AdvancedStyleRule] = []
        let scope = advancedScope(for: rule)
        let hostPatterns = advancedHostPatterns(for: rule)
        let urlFilter = SafariURLFilterTranslator.translate(rule.pattern)

        if !rule.removeParameters.isEmpty {
            rules.append(
                AdvancedStyleRule(
                    scope: scope,
                    content: removeParameterScript(
                        parameters: rule.removeParameters,
                        hostPatterns: hostPatterns,
                        urlFilter: urlFilter
                    )
                )
            )
        }

        if let steps = rule.urlSkipSteps {
            rules.append(
                AdvancedStyleRule(
                    scope: scope,
                    content: urlSkipScript(
                        steps: steps,
                        hostPatterns: hostPatterns,
                        urlFilter: urlFilter
                    )
                )
            )
        }

        if let transform = rule.uriTransform {
            rules.append(
                AdvancedStyleRule(
                    scope: scope,
                    content: uriTransformScript(
                        transform: transform,
                        hostPatterns: hostPatterns,
                        urlFilter: urlFilter
                    )
                )
            )
        }

        return rules
    }

    private func advancedScope(for rule: NetworkRule) -> AdvancedDomainScope {
        let domains = advancedHostPatterns(for: rule)
        if !domains.isEmpty, domains.allSatisfy({ !$0.contains("*") }) {
            return AdvancedDomainScope(ifDomains: domains)
        }
        if !rule.ifDomains.isEmpty, rule.ifDomains.allSatisfy({ !$0.contains("*") }) {
            return AdvancedDomainScope(ifDomains: rule.ifDomains, unlessDomains: rule.unlessDomains)
        }
        return AdvancedDomainScope(unlessDomains: rule.unlessDomains)
    }

    private func advancedHostPatterns(for rule: NetworkRule) -> [String] {
        if !rule.toDomains.isEmpty { return rule.toDomains }
        if !rule.ifDomains.isEmpty { return rule.ifDomains }
        return []
    }

    private func removeParameterScript(parameters: [String], hostPatterns: [String], urlFilter: String) -> String {
        let parametersJSON = jsonLiteral(parameters)
        let hostsJSON = jsonLiteral(hostPatterns)
        let filterJSON = jsonLiteral(urlFilter)
        return #"""
        (()=>{const p=\#(parametersJSON),h=\#(hostsJSON),f=\#(filterJSON);const hm=x=>!h.length||h.some(d=>{const e=d.replace(/[.+?^${}()|[\]\\]/g,'\\$&').replace(/\\\*/g,'.*');return new RegExp('(^|\\.)'+e+'$','i').test(x)});if(!hm(location.hostname))return;try{if(f&&!(new RegExp(f)).test(location.href))return}catch{}const m=n=>p.some(r=>{if(r==='*')return true;if(r.includes('|'))return r.split('|').some(x=>x&&m.call(null,x));if(/^\/.+\/[a-z]*$/i.test(r)){const i=r.lastIndexOf('/');try{return new RegExp(r.slice(1,i),r.slice(i+1)).test(n)}catch{return false}}return n===r});const c=u=>{let x;try{x=new URL(u,location.href)}catch{return null}let z=false;for(const k of Array.from(x.searchParams.keys()))if(m(k)){x.searchParams.delete(k);z=true}return z?x.href:null};const n=c(location.href);if(n)history.replaceState(history.state,document.title,n);const s=r=>{try{for(const a of r.querySelectorAll('a[href]')){const n=c(a.getAttribute('href'));if(n)a.setAttribute('href',n)}}catch{}};s(document);new MutationObserver(a=>{for(const q of a)for(const n of q.addedNodes)n.nodeType===1&&s(n)}).observe(document.documentElement,{childList:true,subtree:true})})();
        """#
    }

    private func urlSkipScript(steps: String, hostPatterns: [String], urlFilter: String) -> String {
        let stepsJSON = jsonLiteral(steps)
        let hostsJSON = jsonLiteral(hostPatterns)
        let filterJSON = jsonLiteral(urlFilter)
        return #"""
        (()=>{const st=\#(stepsJSON),h=\#(hostsJSON),f=\#(filterJSON);const hm=x=>!h.length||h.some(d=>{const e=d.replace(/[.+?^${}()|[\]\\]/g,'\\$&').replace(/\\\*/g,'.*');return new RegExp('(^|\\.)'+e+'$','i').test(x)});if(!hm(location.hostname))return;try{if(f&&!(new RegExp(f)).test(location.href))return}catch{}const u=(url,steps)=>{try{let o=url;for(const step of steps){const c=step.charCodeAt(0);if(c===35&&step==='#'){const p=o.indexOf('#');o=p!==-1?o.slice(p+1):'';continue}if(c===38){const i=(parseInt(step.slice(1))||0)-1;if(i<0)return;const x=new URL(o);const a=Array.from(x.searchParams.keys());if(i>=a.length)return;o=decodeURIComponent(a[i]);continue}if(c===43&&step==='+https'){const s=o.replace(/^https?:\/\//,'');if(/^[\w-]:\/\//.test(s))return;o='https://'+s;continue}if(c===45){if(step==='-base64'){o=atob(o);continue}if(step==='-safebase64'){o=atob(o.replace(/[-_]/g,m=>m==='-'?'+':'/'));continue}if(step==='-uricomponent'){o=decodeURIComponent(o);continue}}if(c===47){const r=new RegExp(step.slice(1,-1));const m=r.exec(o);if(!m||m.length<2)return;o=m[1];continue}if(c===63){const v=new URL(o).searchParams.get(step.slice(1));if(v==null)return;o=v.includes(' ')?v.replace(/ /g,'%20'):v;continue}return}const x=new URL(o);if(x.protocol!=='https:'&&x.protocol!=='http:')return;return o}catch{}};const n=u(location.href,st.split(/\s+/).filter(Boolean));if(n&&n!==location.href)location.replace(n)})();
        """#
    }

    private func uriTransformScript(transform: String, hostPatterns: [String], urlFilter: String) -> String {
        let transformJSON = jsonLiteral(transform)
        let hostsJSON = jsonLiteral(hostPatterns)
        let filterJSON = jsonLiteral(urlFilter)
        return #"""
        (()=>{const t=\#(transformJSON),h=\#(hostsJSON),f=\#(filterJSON);const hm=x=>!h.length||h.some(d=>{const e=d.replace(/[.+?^${}()|[\]\\]/g,'\\$&').replace(/\\\*/g,'.*');return new RegExp('(^|\\.)'+e+'$','i').test(x)});if(!hm(location.hostname))return;try{if(f&&!(new RegExp(f)).test(location.href))return}catch{}const i=t.lastIndexOf('/');if(!t.startsWith('/')||i<1)return;try{const n=location.href.replace(new RegExp(t.slice(1,i)),t.slice(i+1));if(n&&n!==location.href)location.replace(n)}catch{}})();
        """#
    }

    private func jsonLiteral<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else { return "null" }
        return string
    }

    private func expandNetworkRules(_ rules: [NetworkRule]) -> [NetworkRule] {
        rules.flatMap(expandNetworkRule)
    }

    private func expandNetworkRule(_ rule: NetworkRule) -> [NetworkRule] {
        var scopedRules: [NetworkRule]
        if !rule.isException, !rule.ifDomains.isEmpty, !rule.unlessDomains.isEmpty {
            var primary = rule
            primary.unlessDomains = []

            var contextException = rule
            contextException.isException = true
            contextException.ifDomains = rule.unlessDomains
            contextException.unlessDomains = []
            contextException.toDomains = []
            contextException.denyAllowDomains = []
            contextException.canonicalIdentity += "\u{1f}mixed-domain-exclusion"
            scopedRules = [primary, contextException]
        } else {
            scopedRules = [rule]
        }

        return scopedRules
            .flatMap(expandToDomainRule)
            .flatMap(expandDenyAllowRule)
    }

    private func expandToDomainRule(_ rule: NetworkRule) -> [NetworkRule] {
        guard !rule.toDomains.isEmpty, rule.pattern == "*" else { return [rule] }

        return rule.toDomains.map { domain in
            var copy = rule
            copy.pattern = "||\(domain)^"
            copy.toDomains = []
            copy.canonicalIdentity += "\u{1f}to=\(domain)"
            return copy
        }
    }

    private func expandDenyAllowRule(_ rule: NetworkRule) -> [NetworkRule] {
        guard !rule.denyAllowDomains.isEmpty else { return [rule] }

        var primary = rule
        primary.denyAllowDomains = []

        let exceptions = rule.denyAllowDomains.map { domain in
            var copy = rule
            copy.isException = true
            copy.pattern = "||\(domain)^"
            copy.denyAllowDomains = []
            copy.toDomains = []
            copy.canonicalIdentity += "\u{1f}denyallow=\(domain)"
            return copy
        }

        return [primary] + exceptions
    }

    private func planSafariRules(networkRules: [NetworkRule], cosmeticRules: [CosmeticRule]) -> [SafariContentBlockerRule] {
        var rules: [SafariContentBlockerRule] = []
        var seen = Set<String>()

        for networkRule in networkRules where !networkRule.isException && !networkRule.important {
            append(rule: safariRule(for: networkRule), dedupeSuffix: "normal", to: &rules, seen: &seen)
        }

        for cosmeticRule in cosmeticRules {
            append(rule: safariRule(for: cosmeticRule), to: &rules, seen: &seen)
        }

        for networkRule in networkRules where networkRule.isException && !networkRule.important {
            append(rule: safariRule(for: networkRule), dedupeSuffix: "normal", to: &rules, seen: &seen)
        }

        for networkRule in networkRules where !networkRule.isException && networkRule.important {
            append(rule: safariRule(for: networkRule), dedupeSuffix: "important", to: &rules, seen: &seen)
        }

        for networkRule in networkRules where networkRule.isException && networkRule.important {
            append(rule: safariRule(for: networkRule), dedupeSuffix: "important", to: &rules, seen: &seen)
        }

        return rules
    }

    private func append(
        rule: SafariContentBlockerRule,
        dedupeSuffix: String = "",
        to rules: inout [SafariContentBlockerRule],
        seen: inout Set<String>
    ) {
        let key = ruleKey(rule) + "\u{1e}" + dedupeSuffix
        guard seen.insert(key).inserted else { return }
        rules.append(rule)
    }

    private func safariDomainConditions(ifDomains: [String], unlessDomains: [String]) -> (ifDomain: [String]?, unlessDomain: [String]?) {
        if ifDomains.isEmpty {
            return (nil, unlessDomains.isEmpty ? nil : unlessDomains)
        }
        if unlessDomains.isEmpty {
            return (ifDomains, nil)
        }

        // Safari content blocker triggers cannot contain both if-domain and unless-domain.
        // Keep the positive scope to avoid accidentally broadening the rule; exact exception
        // parity for mixed scopes needs a later split/ignore-previous-rules planner.
        let excluded = Set(unlessDomains)
        let filteredIfDomains = ifDomains.filter { !excluded.contains($0) }
        return (filteredIfDomains.isEmpty ? nil : filteredIfDomains, nil)
    }

    private func safariRule(for networkRule: NetworkRule) -> SafariContentBlockerRule {
        let domains = safariDomainConditions(
            ifDomains: networkRule.ifDomains,
            unlessDomains: networkRule.unlessDomains
        )
        return SafariContentBlockerRule(
            action: SafariAction(
                type: networkRule.isException ? .ignorePreviousRules : safariActionType(for: networkRule.action),
                selector: nil
            ),
            trigger: SafariTrigger(
                urlFilter: SafariURLFilterTranslator.translate(networkRule.pattern),
                urlFilterIsCaseSensitive: networkRule.matchCase ? true : nil,
                resourceType: networkRule.resourceTypes.isEmpty ? nil : Array(networkRule.resourceTypes),
                loadType: networkRule.loadType.map { [$0] },
                ifDomain: domains.ifDomain,
                unlessDomain: domains.unlessDomain
            )
        )
    }

    private func safariActionType(for action: NetworkAction) -> SafariActionType {
        switch action {
        case .block:
            return .block
        case .blockCookies:
            return .blockCookies
        case .makeHTTPS:
            return .makeHTTPS
        }
    }

    private func safariRule(for cosmeticRule: CosmeticRule) -> SafariContentBlockerRule {
        let domains = safariDomainConditions(
            ifDomains: cosmeticRule.ifDomains,
            unlessDomains: cosmeticRule.unlessDomains
        )
        return SafariContentBlockerRule(
            action: SafariAction(type: .cssDisplayNone, selector: cosmeticRule.selector),
            trigger: SafariTrigger(
                urlFilter: ".*",
                urlFilterIsCaseSensitive: nil,
                resourceType: nil,
                loadType: nil,
                ifDomain: domains.ifDomain,
                unlessDomain: domains.unlessDomain
            )
        )
    }

    private func unsupportedRule(line: SourceLine, reason: UnsupportedReason) -> UnsupportedRule {
        UnsupportedRule(
            sourceIdentifier: line.sourceIdentifier,
            line: line.number,
            text: line.text,
            reason: reason
        )
    }

    private func ruleKey(_ rule: SafariContentBlockerRule) -> String {
        let trigger = rule.trigger
        var parts: [String] = []
        parts.append(rule.action.type.rawValue)
        parts.append(rule.action.selector ?? "")
        parts.append(trigger.urlFilter)
        parts.append(trigger.urlFilterIsCaseSensitive.map(String.init) ?? "")
        parts.append(trigger.resourceType?.map(\.rawValue).sorted().joined(separator: "|") ?? "")
        parts.append(trigger.loadType?.map(\.rawValue).sorted().joined(separator: "|") ?? "")
        parts.append(trigger.ifDomain?.sorted().joined(separator: "|") ?? "")
        parts.append(trigger.unlessDomain?.sorted().joined(separator: "|") ?? "")
        return parts.joined(separator: "\u{1f}")
    }
}

public typealias DiagnosticsOnlyCompiler = NativeFilterCompiler
