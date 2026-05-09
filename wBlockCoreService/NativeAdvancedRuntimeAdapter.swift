//
//  NativeAdvancedRuntimeAdapter.swift
//  wBlockCoreService
//
//  Safari WebExtension advanced-rule runtime backed by WBlockFilterCompiler.
//

import Foundation
import os.log
internal import WBlockFilterCompiler

enum NativeAdvancedRuntimeAdapter {
    static let runtimeFilename = "wblock_native_advanced_runtime.json"

    private struct CachedBundle {
        let path: String
        let modificationDate: Date
        let bundle: AdvancedRuleBundle
    }

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cachedBundle: CachedBundle?

    static func runtimeURL(groupIdentifier: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(runtimeFilename)
    }

    static func build(jsonBundleSnippets: [String], groupIdentifier: String) throws {
        let bundles = try jsonBundleSnippets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { try AdvancedRuleBundle.decode(jsonString: $0) }
        let combined = sanitizeForSafariRuntime(AdvancedRuleBundle.combine(bundles))

        guard let url = runtimeURL(groupIdentifier: groupIdentifier) else {
            throw CocoaError(.fileNoSuchFile)
        }

        if combined.ruleCount == 0 {
            try? FileManager.default.removeItem(at: url)
            return
        }

        try combined.jsonString().write(to: url, atomically: true, encoding: .utf8)
        cacheLock.withLock {
            cachedBundle = CachedBundle(path: url.path, modificationDate: Date.distantPast, bundle: combined)
        }
        os_log(
            .info,
            "Built native advanced runtime with %d rules at %@",
            combined.ruleCount,
            url.path
        )
    }

    private static func sanitizeForSafariRuntime(_ bundle: AdvancedRuleBundle) -> AdvancedRuleBundle {
        var sanitized = bundle
        sanitized.scriptlets = bundle.scriptlets.filter { !isFragileYouTubePlaybackScriptlet($0) }
        // Keep dynamic DNR conservative. Safari DNR is global extension state,
        // so allow only scoped header/CSP transformations that the page-local
        // runtime cannot emulate (for example uBO/BPC $inline-script rules).
        sanitized.dnrRules = bundle.dnrRules.filter(isSafeSafariRuntimeDNRRule)
        if sanitized != bundle {
            // Force the background runtime to replace previously-installed dynamic
            // rules even when an older on-disk native runtime bundle is reused.
            sanitized.engineTimestamp = Date().timeIntervalSince1970
        }
        return sanitized
    }

    private static func isSafeSafariRuntimeDNRRule(_ rule: AdvancedDNRRule) -> Bool {
        guard rule.action.type == "modifyHeaders" else { return false }
        guard rule.action.redirect == nil else { return false }
        guard rule.condition.regexFilter == nil else { return false }

        let hasDomainScope = rule.condition.requestDomains?.isEmpty == false ||
            rule.condition.initiatorDomains?.isEmpty == false
        guard hasDomainScope else { return false }

        let requestHeaders = rule.action.requestHeaders ?? []
        let responseHeaders = rule.action.responseHeaders ?? []
        guard !requestHeaders.isEmpty || !responseHeaders.isEmpty else { return false }

        for header in requestHeaders {
            guard header.operation == "remove" else { return false }
            guard ["cookie", "referer", "user-agent"].contains(header.header.lowercased()) else { return false }
        }

        for header in responseHeaders {
            let name = header.header.lowercased()
            if name == "content-security-policy" {
                guard header.operation == "set", header.value?.isEmpty == false else { return false }
                continue
            }
            guard header.operation == "remove" else { return false }
            guard ["set-cookie", "content-security-policy", "x-frame-options"].contains(name) else { return false }
        }

        return true
    }

    private static func isFragileYouTubePlaybackScriptlet(_ rule: AdvancedScriptletRule) -> Bool {
        guard isYouTubeScoped(rule.scope) else { return false }
        // Safari YouTube playback is currently too sensitive for page-world
        // scriptlet mutation: even response-only mutations correlate with SABR
        // buffering at 0x0 and repeated signed videoplayback 403s on sidebar
        // navigation. Suppress all YouTube scriptlets while keeping static/DNR
        // blocking and the diagnostic-only registered runtime active.
        return true
    }

    private static func isYouTubeScoped(_ scope: AdvancedDomainScope) -> Bool {
        ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "tv.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com", "youtubekids.com", "www.youtubekids.com"].contains { scope.matches(host: $0) }
    }

    private static func isTrustedReplaceNodeTextName(_ name: String) -> Bool {
        name == "ubo-trusted-rpnt" ||
            name == "ubo-trusted-rpnt.js" ||
            name == "trusted-rpnt" ||
            name == "trusted-rpnt.js" ||
            name == "ubo-trusted-replace-node-text" ||
            name == "ubo-trusted-replace-node-text.js" ||
            name == "trusted-replace-node-text" ||
            name == "trusted-replace-node-text.js"
    }

    private static func isTrustedJSONEditRequestName(_ name: String) -> Bool {
        name == "ubo-trusted-json-edit-xhr-request" ||
            name == "ubo-trusted-json-edit-xhr-request.js" ||
            name == "trusted-json-edit-xhr-request" ||
            name == "trusted-json-edit-xhr-request.js" ||
            name == "ubo-trusted-json-edit-fetch-request" ||
            name == "ubo-trusted-json-edit-fetch-request.js" ||
            name == "trusted-json-edit-fetch-request" ||
            name == "trusted-json-edit-fetch-request.js"
    }

    private static func isTrustedJSONEditResponseName(_ name: String) -> Bool {
        name == "ubo-trusted-json-edit-xhr-response" ||
            name == "ubo-trusted-json-edit-xhr-response.js" ||
            name == "trusted-json-edit-xhr-response" ||
            name == "trusted-json-edit-xhr-response.js" ||
            name == "ubo-trusted-json-edit-fetch-response" ||
            name == "ubo-trusted-json-edit-fetch-response.js" ||
            name == "trusted-json-edit-fetch-response" ||
            name == "trusted-json-edit-fetch-response.js"
    }

    private static func normalizedScriptletName(_ rawName: String) -> String {
        var name = rawName.lowercased()
        if name.hasPrefix("ubo-") { name.removeFirst(4) }
        if name.hasSuffix(".js") { name.removeLast(3) }
        return name
    }

    private static func isEarlyRegisteredScriptletName(_ rawName: String) -> Bool {
        switch normalizedScriptletName(rawName) {
        case "set", "set-constant", "trusted-set", "trusted-set-constant",
             "nano-setTimeout-booster", "nano-stb",
             "no-fetch-if", "prevent-fetch", "trusted-prevent-fetch",
             "no-xhr-if", "prevent-xhr", "trusted-prevent-xhr",
             "json-prune", "json-prune-fetch-response", "json-prune-xhr-response",
             "json-edit-fetch-request", "json-edit-xhr-request",
             "trusted-json-edit-fetch-request", "trusted-json-edit-xhr-request",
             "trusted-replace-fetch-response", "trusted-replace-xhr-response",
             "trusted-prevent-dom-bypass":
            return true
        default:
            return false
        }
    }

    static func clear(groupIdentifier: String) throws {
        guard let url = runtimeURL(groupIdentifier: groupIdentifier) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        cacheLock.withLock {
            cachedBundle = nil
        }
    }

    static func lookupPayload(pageURL: URL, topURL: URL?, groupIdentifier: String) -> [String: Any]? {
        guard let bundle = loadBundle(groupIdentifier: groupIdentifier) else { return nil }

        let configuration = AdvancedRuleRuntime(bundle: bundle).lookup(pageURL: pageURL, topURL: topURL)
        var payload: [String: Any] = [:]
        payload["css"] = configuration.css
        payload["extendedCss"] = configuration.extendedCss
        payload["js"] = configuration.js
        payload["scriptlets"] = configuration.scriptlets.map { scriptlet in
            ["name": scriptlet.name, "args": scriptlet.args]
        }
        payload["dnrRules"] = configuration.dnrRules.map { rule in
            dnrRuleDictionary(rule)
        }
        payload["userScripts"] = []
        payload["engineTimestamp"] = configuration.engineTimestamp
        return payload
    }

    static func registeredScriptletPayload(groupIdentifier: String, disabledSites: [String]) -> [String: Any]? {
        guard let bundle = loadBundle(groupIdentifier: groupIdentifier) else { return nil }
        let scriptlets = bundle.scriptlets
            .filter { isEarlyRegisteredScriptletName($0.name) && !isYouTubeScoped($0.scope) && !isFragileYouTubePlaybackScriptlet($0) }
            .map { rule -> [String: Any] in
                [
                    "name": rule.name,
                    "args": rule.args,
                    "ifDomains": rule.scope.ifDomains,
                    "unlessDomains": rule.scope.unlessDomains
                ]
            }

        return [
            "engineTimestamp": bundle.engineTimestamp,
            "disabledSites": disabledSites,
            "scriptlets": scriptlets
        ]
    }

    private static func dnrRuleDictionary(_ rule: AdvancedDNRRule) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(rule),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return [:] }
        return dictionary
    }

    private static func loadBundle(groupIdentifier: String) -> AdvancedRuleBundle? {
        guard let url = runtimeURL(groupIdentifier: groupIdentifier),
              FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        if let cached = cacheLock.withLock({ cachedBundle }),
           cached.path == url.path,
           cached.modificationDate == modificationDate {
            return cached.bundle
        }

        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let bundle = try? AdvancedRuleBundle.decode(jsonString: text) else {
            return nil
        }

        let sanitized = sanitizeForSafariRuntime(bundle)
        cacheLock.withLock {
            cachedBundle = CachedBundle(path: url.path, modificationDate: modificationDate, bundle: sanitized)
        }
        return sanitized
    }
}
