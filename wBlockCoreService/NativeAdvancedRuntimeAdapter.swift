//
//  NativeAdvancedRuntimeAdapter.swift
//  wBlockCoreService
//
//  Experimental Safari WebExtension advanced-rule runtime backed by WBlockFilterCompiler.
//  This intentionally coexists with SafariConverterLib's FilterEngine until parity gates pass.
//

import Foundation
import os.log
@_implementationOnly import WBlockFilterCompiler

enum NativeAdvancedRuntimeAdapter {
    static let runtimeFilename = "wblock_native_advanced_runtime.json"

    private struct CachedBundle {
        let path: String
        let modificationDate: Date
        let bundle: AdvancedRuleBundle
    }

    private static let cacheLock = NSLock()
    private static var cachedBundle: CachedBundle?

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
        sanitized.scriptlets = bundle.scriptlets.filter { !isUnsupportedYouTubePlaybackProbe($0) }
        return sanitized
    }

    private static func isUnsupportedYouTubePlaybackProbe(_ rule: AdvancedScriptletRule) -> Bool {
        guard rule.scope.matches(host: "www.youtube.com") else { return false }
        let name = rule.name.lowercased()
        let args = rule.args.joined(separator: "\u{1f}")

        // uBlock's Experimental list currently contains broader YouTube playback
        // probes that cycle several client identities after buffering failures.
        // They are effective in uBO's exact runtime, but in Safari's page-world
        // bridge they can keep invalidating googlevideo URLs and cause repeated
        // 403/reload oscillation. Keep the Quick fixes rules and suppress only
        // the broader experimental probes.
        if name == "ubo-trusted-rpnt" || name == "trusted-rpnt" || name == "trusted-replace-node-text" {
            return args.contains("adunit") &&
                args.contains("lactmilli") &&
                args.contains("instream") &&
                args.contains("eafg") &&
                args.contains("serverContract")
        }

        if name == "ubo-trusted-json-edit-xhr-request" || name == "trusted-json-edit-xhr-request" {
            return args.contains("userAgent*=\"adunit\"") ||
                args.contains("userAgent*=\"lactmilli\"") ||
                args.contains("userAgent*=\"instream\"") ||
                args.contains("userAgent*=\"eafg\"")
        }

        if name == "ubo-trusted-json-edit-xhr-response" || name == "trusted-json-edit-xhr-response" {
            return args.contains("minimumPlaybackRate==100")
        }

        return false
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
        payload["userScripts"] = []
        payload["engineTimestamp"] = configuration.engineTimestamp
        return payload
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

        cacheLock.withLock {
            cachedBundle = CachedBundle(path: url.path, modificationDate: modificationDate, bundle: bundle)
        }
        return bundle
    }
}
