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

                switch RuleParser.parse(line, configuration: configuration) {
                case .comment, .preprocessor:
                    continue
                case .network(let rule):
                    if rule.isBadfilter {
                        badfilterIdentities.insert(rule.canonicalIdentity)
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
                    unsupportedRules.append(unsupportedRule(line: line, reason: reason))
                }
            }
        }

        let filteredNetworkRules = networkRules.filter { !badfilterIdentities.contains($0.canonicalIdentity) }
        let plannedCosmeticRules = applyCosmeticExceptions(cosmeticRules, exceptions: cosmeticExceptionRules)
        let groupedCosmeticRules = groupCosmeticRules(plannedCosmeticRules)
        let safariRules = planSafariRules(networkRules: filteredNetworkRules, cosmeticRules: groupedCosmeticRules)
        let safariJSON = configuration.target == .diagnosticsOnly ? "[]" : try SafariRuleWriter.write(safariRules)
        let safariRuleCount = configuration.target == .diagnosticsOnly ? 0 : safariRules.count
        diagnostics.emittedSafariRules = safariRuleCount

        return FilterCompilationResult(
            safariRulesJSON: safariJSON,
            safariRuleCount: safariRuleCount,
            advancedRules: AdvancedRuleBundle(),
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

    private func safariRule(for networkRule: NetworkRule) -> SafariContentBlockerRule {
        SafariContentBlockerRule(
            action: SafariAction(
                type: networkRule.isException ? .ignorePreviousRules : safariActionType(for: networkRule.action),
                selector: nil
            ),
            trigger: SafariTrigger(
                urlFilter: SafariURLFilterTranslator.translate(networkRule.pattern),
                urlFilterIsCaseSensitive: networkRule.matchCase ? true : nil,
                resourceType: networkRule.resourceTypes.isEmpty ? nil : Array(networkRule.resourceTypes),
                loadType: networkRule.loadType.map { [$0] },
                ifDomain: networkRule.ifDomains.isEmpty ? nil : networkRule.ifDomains,
                unlessDomain: networkRule.unlessDomains.isEmpty ? nil : networkRule.unlessDomains
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
        SafariContentBlockerRule(
            action: SafariAction(type: .cssDisplayNone, selector: cosmeticRule.selector),
            trigger: SafariTrigger(
                urlFilter: ".*",
                urlFilterIsCaseSensitive: nil,
                resourceType: nil,
                loadType: nil,
                ifDomain: cosmeticRule.ifDomains.isEmpty ? nil : cosmeticRule.ifDomains,
                unlessDomain: cosmeticRule.unlessDomains.isEmpty ? nil : cosmeticRule.unlessDomains
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
