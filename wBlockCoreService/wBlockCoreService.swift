//
//  wBlockCoreService.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 5/23/25.
//

import CryptoKit
import Foundation
import SafariServices
#if canImport(Darwin)
import Darwin
#endif
import os.log

/// ContentBlockerService converts ABP/uBO-compatible filter rules to Safari content blocker JSON
/// and manages content blocker extension artifacts.
public enum ContentBlockerService {
    /// Version marker for built-in compatibility rules that are appended to
    /// every conversion. Bump this when changing `embeddedCompatibilityRules`
    /// so cached base JSON gets invalidated.
    private static let embeddedCompatibilityRulesVersion = "11"

    /// Minimal built-in rules that improve blocking of common dynamic ad script
    /// patterns and dynamic ad containers across filter sets. YouTube media
    /// requests are intentionally not blocked here because Safari can classify
    /// normal playback requests as XHR/fetch, which breaks videos.
    private static let embeddedCompatibilityRules = #"""
/js/widget/ads.js$script
/js/pagead.js$script
/widget/pagead.js$script
||www.googletagmanager.com/gtag/js$script,domain=adblock-tester.com,important
||sentry-cdn.com^$script,domain=adblock-tester.com,important
||browser.sentry-cdn.com^$script,domain=adblock-tester.com,important
||js.sentry-cdn.com^$script,domain=adblock-tester.com,important
||adblock-tester.com/banners/pr_advertising_ads_banner.$important
||adblock-tester.com/banners/pr_advertising_ads_banner.$xhr,important
||adblock-tester.com/banners/pr_advertising_ads_banner.gif$image,important
||adblock-tester.com/banners/pr_advertising_ads_banner.gif$xhr,important
||adblock-tester.com/banners/pr_advertising_ads_banner.png$image,important
||adblock-tester.com/banners/pr_advertising_ads_banner.png$xhr,important
||adblock-tester.com/banners/pr_advertising_ads_banner.swf$media,important
||adblock-tester.com/banners/pr_advertising_ads_banner.swf$xhr,important
adblock-tester.com#%#//scriptlet('set-constant', 'Sentry', 'undefined')
adblock-tester.com##+js(set-constant, Sentry, undefined)
adblock-tester.com#%#(()=>{const f=fetch.bind(window);window.fetch=(i,n)=>{const u=String(i&&i.url||i);return u.includes('/banners/pr_advertising_ads_banner.')?Promise.reject(new TypeError('Failed to fetch')):f(i,n);};})();
adblock-tester.com##img[src*="/banners/pr_advertising_ads_banner."]
adblock-tester.com##object[data*="/banners/pr_advertising_ads_banner."]
adblock-tester.com##embed[src*="/banners/pr_advertising_ads_banner."]
adblock.turtlecute.org##.adbox.banner_ads.adsbox
adblock.turtlecute.org##.textads
adblock.turtlecute.org##.textads.banner-ads.banner_ads.ad-unit.afs_ads.ad-zone.ad-space.adsbox
||adblock.turtlecute.org/js/widget/ads.js$script,important
||adblock.turtlecute.org/js/pagead.js$script,important
adblock.turtlecute.org#%#(()=>{const f=fetch.bind(window);window.fetch=(i,n)=>{const u=String(i&&i.url||i);return /^https:\/\/[^/]+\/fakepage\.html(?:[?#]|$)/.test(u)?Promise.reject(new TypeError('Failed to fetch')):f(i,n);};})();
##.adbox.banner_ads.adsbox
"""#

    private static func combinedRulesWithEmbeddedCompatibility(_ rawRules: String) -> String {
        let trimmedExtraRules = embeddedCompatibilityRules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExtraRules.isEmpty else { return rawRules }

        let trimmedBaseRules = rawRules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseRules.isEmpty else { return trimmedExtraRules }

        return rawRules + "\n" + trimmedExtraRules
    }

    private static func compatibilityRulesFingerprintHex() -> String {
        let payload = "\(embeddedCompatibilityRulesVersion)\n\(embeddedCompatibilityRules)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Derives an effective conversion hash from the caller-provided rules hash
    /// plus built-in compatibility-rules fingerprint so cache keys are invalidated
    /// when embedded compatibility rules change.
    private static func effectiveRulesHashHex(baseRulesHashHex: String) -> String {
        let fingerprint = compatibilityRulesFingerprintHex()
        let material = "\(baseRulesHashHex)|\(fingerprint)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the default filter file contents from the main bundle.
    ///
    /// - Returns: The contents of the default filter list or an error message if the file cannot be read.
    public static func readDefaultFilterList() -> String {
        do {
            if let filePath = Bundle.main.url(forResource: "filter", withExtension: "txt") {
                return try String(contentsOf: filePath, encoding: .utf8)
            }

            return "Not found the default filter file"
        } catch {
            return "Failed to read the filter file: \(error)"
        }
    }

    public struct ReloadAttemptResult: Sendable {
        public let success: Bool
        public let attempts: Int
        public let durationMs: Int
    }


    /// Reloads the Safari content blocker extension with the specified identifier.
    ///
    /// - Parameters:
    ///   - identifier: Bundle ID of the content blocker extension to reload.
    /// - Returns: A Result indicating success or containing an error if the reload failed.
    @MainActor
    public static func reloadContentBlocker(
        withIdentifier identifier: String
    ) async -> Result<Void, Error> {
        os_log(.info, "Start reloading the content blocker")

        let error: Error? = await withCheckedContinuation { continuation in
            SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { error in
                continuation.resume(returning: error)
            }
        }

        let result: Result<Void, Error> = if let error { .failure(error) } else { .success(()) }

        switch result {
        case .success:
            os_log(.info, "Content blocker reloaded successfully.")
        case .failure(let error):
            // WKErrorDomain error 6 is a common error when the content blocker
            // cannot access the blocker list file.
            let nsError = error as NSError
            os_log(
                .error,
                "Failed to reload content blocker: domain=%@ code=%d description=%@ userInfo=%@",
                nsError.domain,
                nsError.code,
                error.localizedDescription,
                String(describing: nsError.userInfo)
            )
        }

        return result
    }

    public static func reloadWithRetry(
        identifier: String,
        maxRetries: Int = 5
    ) async -> ReloadAttemptResult {
        let startTime = Date()
        let elapsedMs = { Int(Date().timeIntervalSince(startTime) * 1000) }

        for attempt in 1...maxRetries {
            if Task.isCancelled {
                return ReloadAttemptResult(
                    success: false,
                    attempts: max(0, attempt - 1),
                    durationMs: elapsedMs()
                )
            }

            let result = await reloadContentBlocker(withIdentifier: identifier)
            if case .success = result {
                return ReloadAttemptResult(
                    success: true,
                    attempts: attempt,
                    durationMs: elapsedMs()
                )
            }

            guard attempt < maxRetries else {
                break
            }

            let delayMs = min(200 * attempt, 1500)
            do {
                try await TaskSleep.sleep(for: .milliseconds(delayMs))
            } catch {
                return ReloadAttemptResult(
                    success: false,
                    attempts: attempt,
                    durationMs: elapsedMs()
                )
            }
        }

        return ReloadAttemptResult(
            success: false,
            attempts: maxRetries,
            durationMs: elapsedMs()
        )
    }

    /// Saves the provided JSON content to the content blocker file in the shared container
    /// without attempting to convert the rules.
    ///
    /// - Parameters:
    ///   - jsonRules: Safari content blocker JSON contents in proper format.
    ///   - groupIdentifier: Group ID to use for the shared container where
    ///                      the file will be saved.
    /// - Returns: The number of entries in the JSON array.
    public static func saveContentBlocker(jsonRules: String, groupIdentifier: String, targetRulesFilename: String) -> Int {
        os_log(.info, "Saving pre-formatted JSON content blocker rules to %@", targetRulesFilename)
        do {
            guard let jsonData = jsonRules.data(using: .utf8) else {
                os_log(.error, "Failed to convert string to bytes for %@", targetRulesFilename)
                return 0
            }
            let rules = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]]

            measure(label: "Saving pre-formatted file \(targetRulesFilename)") {
                saveBlockerListFile(contents: jsonRules, groupIdentifier: groupIdentifier, filename: targetRulesFilename)
            }
            return rules?.count ?? 0
        } catch {
            os_log(
                .error,
                "Failed to decode/save pre-formatted content blocker JSON for %@: %@",
                targetRulesFilename,
                error.localizedDescription
            )
        }
        return 0
    }

    /// Converts filter rules to Safari content blocker format and saves them to the shared container.
    /// This version includes per-site disable functionality by injecting ignore-previous-rules for disabled sites.
    ///
    /// - Parameters:
    ///   - rules: Filter rules to be converted.
    ///   - groupIdentifier: Group ID to use for the shared container where
    ///                      the file will be saved.
    ///   - targetRulesFilename: Target filename for the rules file.
    ///   - disabledSites: Optional list of disabled sites. If nil, attempts to read from legacy UserDefaults.
    /// - Returns: A tuple containing the number of Safari content blocker rules generated 
    ///           and the advanced rules text (if any).
    public static func convertFilter(rules: String, groupIdentifier: String, targetRulesFilename: String, disabledSites: [String]? = nil) throws -> (safariRulesCount: Int, advancedRulesText: String?) {
        let sitesToUse = disabledSites ?? getDisabledSites(groupIdentifier: groupIdentifier)

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            os_log(.error, "Failed to access App Group container for %@", targetRulesFilename)
            return (safariRulesCount: 0, advancedRulesText: nil)
        }

        let digest = SHA256.hash(data: Data(rules.utf8))
        let baseRulesHashHex = digest.map { String(format: "%02x", $0) }.joined()
        let rulesSHA256Hex = effectiveRulesHashHex(baseRulesHashHex: baseRulesHashHex)

        let baseFilename = ContentBlockerIncrementalCache.baseRulesFilename(for: targetRulesFilename)
        let baseCountFilename = "\(baseFilename).count"
        let baseHashFilename = "\(baseFilename).sha256"
        let advancedFilename = ContentBlockerIncrementalCache.baseAdvancedRulesFilename(
            for: targetRulesFilename
        )

        let baseURL = containerURL.appendingPathComponent(baseFilename)
        let baseHashURL = containerURL.appendingPathComponent(baseHashFilename)
        let advancedURL = containerURL.appendingPathComponent(advancedFilename)

        if let cachedHash = try? String(contentsOf: baseHashURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            cachedHash == rulesSHA256Hex,
            FileManager.default.fileExists(atPath: baseURL.path),
            let baseJSON = try? String(contentsOf: baseURL, encoding: .utf8)
        {
            let finalJSON = injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sitesToUse)
            saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

            let advancedText =
                (try? String(contentsOf: advancedURL, encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }

            return (safariRulesCount: countRulesInJSON(finalJSON), advancedRulesText: advancedText)
        }

        let effectiveRules = combinedRulesWithEmbeddedCompatibility(rules)
        let result = try convertRules(rules: effectiveRules)

        saveBlockerListFile(contents: result.safariRulesJSON, groupIdentifier: groupIdentifier, filename: baseFilename)
        saveBlockerListFile(contents: String(result.safariRulesCount), groupIdentifier: groupIdentifier, filename: baseCountFilename)
        saveBlockerListFile(contents: rulesSHA256Hex, groupIdentifier: groupIdentifier, filename: baseHashFilename)
        saveBlockerListFile(contents: result.advancedRulesText ?? "", groupIdentifier: groupIdentifier, filename: advancedFilename)

        let finalJSON = injectIgnoreRulesForDisabledSites(json: result.safariRulesJSON, disabledSites: sitesToUse)
        saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

        return (safariRulesCount: countRulesInJSON(finalJSON), advancedRulesText: result.advancedRulesText)
    }

    /// Converts rules from a file, with a persistent on-disk cache keyed by the caller-provided SHA256.
    /// This avoids re-running native conversion when the combined rules for a target haven't changed.
    public static func convertFilterFromFile(
        rulesFileURL: URL,
        rulesSHA256Hex: String,
        groupIdentifier: String,
        targetRulesFilename: String,
        disabledSites: [String]? = nil
    ) throws -> (safariRulesCount: Int, advancedRulesText: String?) {
        let sitesToUse = disabledSites ?? getDisabledSites(groupIdentifier: groupIdentifier)
        let effectiveRulesHash = effectiveRulesHashHex(baseRulesHashHex: rulesSHA256Hex)

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            os_log(.error, "Failed to access App Group container for %@", targetRulesFilename)
            return (safariRulesCount: 0, advancedRulesText: nil)
        }

        let baseFilename = ContentBlockerIncrementalCache.baseRulesFilename(for: targetRulesFilename)
        let baseCountFilename = "\(baseFilename).count"
        let baseHashFilename = "\(baseFilename).sha256"
        let advancedFilename = ContentBlockerIncrementalCache.baseAdvancedRulesFilename(
            for: targetRulesFilename
        )

        let baseURL = containerURL.appendingPathComponent(baseFilename)
        let baseHashURL = containerURL.appendingPathComponent(baseHashFilename)
        let advancedURL = containerURL.appendingPathComponent(advancedFilename)

        if let cachedHash = try? String(contentsOf: baseHashURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            cachedHash == effectiveRulesHash,
            FileManager.default.fileExists(atPath: baseURL.path),
            let baseJSON = try? String(contentsOf: baseURL, encoding: .utf8)
        {
            let finalJSON = injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sitesToUse)
            saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

            let advancedText =
                (try? String(contentsOf: advancedURL, encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }

            return (safariRulesCount: countRulesInJSON(finalJSON), advancedRulesText: advancedText)
        }

        // Cache miss: read rules file and run conversion.
        let combinedRules = (try? String(contentsOf: rulesFileURL, encoding: .utf8)) ?? ""
        let effectiveRules = combinedRulesWithEmbeddedCompatibility(combinedRules)
        let result = try convertRules(rules: effectiveRules)

        saveBlockerListFile(contents: result.safariRulesJSON, groupIdentifier: groupIdentifier, filename: baseFilename)
        saveBlockerListFile(contents: String(result.safariRulesCount), groupIdentifier: groupIdentifier, filename: baseCountFilename)
        saveBlockerListFile(contents: effectiveRulesHash, groupIdentifier: groupIdentifier, filename: baseHashFilename)
        saveBlockerListFile(contents: result.advancedRulesText ?? "", groupIdentifier: groupIdentifier, filename: advancedFilename)

        let finalJSON = injectIgnoreRulesForDisabledSites(json: result.safariRulesJSON, disabledSites: sitesToUse)
        saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

        return (safariRulesCount: countRulesInJSON(finalJSON), advancedRulesText: result.advancedRulesText)
    }
    
    /// Fast update for disabled sites changes only - skips full native conversion
    /// Reads existing JSON files and re-injects ignore rules without full conversion
    ///
    /// - Parameters:
    ///   - groupIdentifier: Group ID to use for the shared container
    ///   - targetRulesFilename: Target filename for the rules file
    ///   - disabledSites: Optional list of disabled sites. If nil, attempts to read from legacy UserDefaults.
    /// - Returns: A tuple containing the number of Safari content blocker rules and advanced rules text
    public static func fastUpdateDisabledSites(groupIdentifier: String, targetRulesFilename: String, disabledSites: [String]? = nil) -> (safariRulesCount: Int, advancedRulesText: String?) {
        let sitesToUse = disabledSites ?? getDisabledSites(groupIdentifier: groupIdentifier)
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            os_log(.error, "Failed to access App Group container for fast update")
            return (safariRulesCount: 0, advancedRulesText: nil)
        }
        
        let baseFilename = ContentBlockerIncrementalCache.baseRulesFilename(for: targetRulesFilename)
        let baseCountFilename = "\(baseFilename).count"

        // Preferred path: use cached base JSON (no ignore rules) + cheap string injection.
        let baseURL = containerURL.appendingPathComponent(baseFilename)
        if FileManager.default.fileExists(atPath: baseURL.path),
           let baseJSON = try? String(contentsOf: baseURL, encoding: .utf8) {
            let finalJSON = injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sitesToUse)
            saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

            let finalRuleCount = countRulesInJSON(finalJSON)

            os_log(.info, "Fast updated %@ with %d rules for %d disabled sites", targetRulesFilename, finalRuleCount, sitesToUse.count)
            return (safariRulesCount: finalRuleCount, advancedRulesText: nil)
        }

        // Fallback/migration: derive a base JSON by stripping legacy disabled-site ignore rules (only),
        // then persist it for future fast updates.
        let targetURL = containerURL.appendingPathComponent(targetRulesFilename)
        let existingJSON = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? "[]"
        let derived = deriveBaseRulesFromLegacyFinalJSON(existingJSON)

        saveBlockerListFile(contents: derived.baseJSON, groupIdentifier: groupIdentifier, filename: baseFilename)
        saveBlockerListFile(contents: String(derived.baseRuleCount), groupIdentifier: groupIdentifier, filename: baseCountFilename)

        let finalJSON = injectIgnoreRulesForDisabledSites(json: derived.baseJSON, disabledSites: sitesToUse)
        saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

        let finalRuleCount = countRulesInJSON(finalJSON)
        os_log(.info, "Fast updated %@ with %d rules for %d disabled sites", targetRulesFilename, finalRuleCount, sitesToUse.count)
        return (safariRulesCount: finalRuleCount, advancedRulesText: nil)
    }
    
    /// Retrieves the list of sites where wBlock is disabled.
    ///
    /// - Parameter groupIdentifier: The app group identifier for shared storage.
    /// - Returns: Array of disabled site hostnames.
    private static func getDisabledSites(groupIdentifier: String) -> [String] {
        let defaults = UserDefaults(suiteName: groupIdentifier)
        return defaults?.stringArray(forKey: "disabledSites") ?? []
    }

    private struct DerivedBaseRules {
        let baseJSON: String
        let baseRuleCount: Int
    }

    private static func deriveBaseRulesFromLegacyFinalJSON(_ json: String) -> DerivedBaseRules {
        guard let jsonData = json.data(using: .utf8),
              let existingRules = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return DerivedBaseRules(baseJSON: json, baseRuleCount: countRulesInJSON(json))
        }

        let filteredRules = existingRules.filter { !isLegacyDisabledSiteIgnoreRule($0) }
        if let updatedData = try? JSONSerialization.data(withJSONObject: filteredRules, options: []),
           let baseJSON = String(data: updatedData, encoding: .utf8) {
            return DerivedBaseRules(baseJSON: baseJSON, baseRuleCount: filteredRules.count)
        }

        return DerivedBaseRules(baseJSON: json, baseRuleCount: existingRules.count)
    }

    private static func isLegacyDisabledSiteIgnoreRule(_ rule: [String: Any]) -> Bool {
        guard let action = rule["action"] as? [String: Any],
              let type = action["type"] as? String,
              type == "ignore-previous-rules",
              let trigger = rule["trigger"] as? [String: Any],
              let urlFilter = trigger["url-filter"] as? String,
              urlFilter == ".*",
              let ifDomain = trigger["if-domain"] as? [String],
              ifDomain.count == 2 else {
            return false
        }

        // Legacy injected rules used only these trigger keys and encoded subdomains as "*.<domain>".
        if Set(trigger.keys) != Set(["url-filter", "if-domain"]) {
            return false
        }

        let domainSet = Set(ifDomain)
        for item in ifDomain where item.hasPrefix("*.") {
            let base = String(item.dropFirst(2))
            if domainSet.contains(base) {
                return true
            }
        }

        return false
    }

    private static func escapeForJSONString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func disabledSiteIgnoreRuleJSON(for site: String) -> String {
        let trimmedSite = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let wildcardDomain = trimmedSite.hasPrefix("*") ? trimmedSite : "*\(trimmedSite)"
        let escapedDomain = escapeForJSONString(wildcardDomain)

        return "{\"action\":{\"type\":\"ignore-previous-rules\"},\"trigger\":{\"url-filter\":\".*\",\"if-domain\":[\"\(escapedDomain)\"]}}"
    }
    
    private static let youtubePlaybackURLFilter = #".*googlevideo\.com/videoplayback.*"#
    private static let legacyYouTubePlaybackURLFilter = #"^[a-z][a-z0-9+.-]*://([^/?#]+\.)?googlevideo\.com/videoplayback"#

    private static func youtubePlaybackIgnoreRules() -> [[String: Any]] {
        let playbackTrigger: [String: Any] = [
            "url-filter": youtubePlaybackURLFilter
        ]
        let youtubePageTrigger: [String: Any] = [
            "url-filter": ".*",
            "if-domain": ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "tv.youtube.com", "*youtube.com", "*www.youtube.com"]
        ]

        var rules: [[String: Any]] = [
            ["action": ["type": "ignore-previous-rules"], "trigger": playbackTrigger],
            ["action": ["type": "ignore-previous-rules"], "trigger": youtubePageTrigger]
        ]

        // WebKit has reported YouTube playback fetches as raw, media, or other
        // request classes across releases. Keep typed fallbacks for older content-
        // blocker compilers which require matching resource-type to ignore a prior
        // rule. The broad YouTube page ignore is intentionally blunt while Safari
        // playback is being stabilized.
        for resourceType in ["raw", "media", "document", "script", "image"] {
            var playbackTypedTrigger = playbackTrigger
            playbackTypedTrigger["resource-type"] = [resourceType]
            rules.append([
                "action": ["type": "ignore-previous-rules"],
                "trigger": playbackTypedTrigger
            ])

            var pageTypedTrigger = youtubePageTrigger
            pageTypedTrigger["resource-type"] = [resourceType]
            rules.append([
                "action": ["type": "ignore-previous-rules"],
                "trigger": pageTypedTrigger
            ])
        }
        return rules
    }

    private static func isBuiltInYouTubePlaybackIgnoreRule(_ rule: [String: Any]) -> Bool {
        guard let action = rule["action"] as? [String: Any],
              action["type"] as? String == "ignore-previous-rules",
              let trigger = rule["trigger"] as? [String: Any],
              let urlFilter = trigger["url-filter"] as? String else {
            return false
        }
        if urlFilter == ".*" {
            guard domainListContainsYouTube(trigger["if-domain"] as? [String]) else { return false }
        } else if urlFilter != youtubePlaybackURLFilter && urlFilter != legacyYouTubePlaybackURLFilter {
            return false
        }
        if let resourceTypes = trigger["resource-type"] as? [String] {
            guard resourceTypes.count == 1, ["raw", "media", "document", "script", "image"].contains(resourceTypes[0]) else {
                return false
            }
        }
        if let domains = trigger["if-domain"] as? [String] {
            return domains.contains("youtube.com") || domains.contains("*youtube.com")
        }
        return true
    }

    private static func domainListContainsYouTube(_ domains: [String]?) -> Bool {
        guard let domains else { return false }
        return domains.contains { domain in
            let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "youtube.com"
                || normalized == "www.youtube.com"
                || normalized == "m.youtube.com"
                || normalized == "*youtube.com"
                || normalized == "*www.youtube.com"
                || normalized.hasSuffix(".youtube.com")
        }
    }

    private static func isYouTubePlaybackBlockRule(_ rule: [String: Any]) -> Bool {
        guard let action = rule["action"] as? [String: Any],
              action["type"] as? String == "block",
              let trigger = rule["trigger"] as? [String: Any],
              let urlFilter = (trigger["url-filter"] as? String)?.lowercased() else {
            return false
        }

        // Temporary safety-first policy: do not ship static block rules scoped to
        // YouTube pages. Safari's request classification around googlevideo playback
        // is too fragile, and one false positive makes all videos spin forever.
        if domainListContainsYouTube(trigger["if-domain"] as? [String]) {
            return true
        }

        if isGoogleVideoPlaybackURLFilter(urlFilter) {
            return true
        }

        // Safari/WebKit may classify signed googlevideo playback fetches differently
        // across releases. Do not keep broad third-party media/raw blocks scoped to
        // YouTube pages in the static blocker, because a false positive stalls playback.
        if urlFilter == ".*" || urlFilter == ".*_ad_" {
            let resourceTypes = Set((trigger["resource-type"] as? [String]) ?? [])
            let loadTypes = Set((trigger["load-type"] as? [String]) ?? [])
            if !resourceTypes.isDisjoint(with: ["raw", "media"]) && (loadTypes.isEmpty || loadTypes.contains("third-party")) {
                return true
            }
        }

        return false
    }

    private static func isGoogleVideoPlaybackURLFilter(_ urlFilter: String) -> Bool {
        urlFilter.contains("googlevideo") && (urlFilter.contains("videoplayback") || urlFilter.contains("initplayback"))
    }

    private static func isGoogleVideoPlaybackBlockRule(_ rule: [String: Any]) -> Bool {
        guard let action = rule["action"] as? [String: Any],
              action["type"] as? String == "block",
              let trigger = rule["trigger"] as? [String: Any],
              let urlFilter = (trigger["url-filter"] as? String)?.lowercased() else {
            return false
        }
        return isGoogleVideoPlaybackURLFilter(urlFilter)
    }

    private static func isUnsafeGlobalThirdPartyRawBlock(_ rule: [String: Any]) -> Bool {
        guard let action = rule["action"] as? [String: Any],
              action["type"] as? String == "block",
              let trigger = rule["trigger"] as? [String: Any],
              trigger["url-filter"] as? String == ".*",
              let resourceTypes = trigger["resource-type"] as? [String],
              resourceTypes == ["raw"],
              let loadTypes = trigger["load-type"] as? [String],
              loadTypes == ["third-party"] else {
            return false
        }

        // These broad option-only filters are valid in uBO, but Safari often classifies
        // normal media fetches as "raw". If conversion cannot preserve the original
        // domain scope, the result blocks all third-party XHR/fetch traffic, including
        // YouTube's googlevideo playback requests.
        return Set(trigger.keys) == Set(["url-filter", "resource-type", "load-type"])
    }

    /// Finalizes Safari content blocker JSON before saving.
    /// This injects terminal allow rules for disabled sites and for fragile YouTube
    /// playback requests, and removes unsafe global raw third-party blocks produced
    /// when conversion cannot preserve option-only rule domain scope.
    private static func injectIgnoreRulesForDisabledSites(json: String, disabledSites: [String]) -> String {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = trimmed.data(using: .utf8),
              var rules = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return json
        }

        rules.removeAll { isUnsafeGlobalThirdPartyRawBlock($0) || isYouTubePlaybackBlockRule($0) || isGoogleVideoPlaybackBlockRule($0) || isBuiltInYouTubePlaybackIgnoreRule($0) }
        rules.append(contentsOf: youtubePlaybackIgnoreRules())

        for site in disabledSites {
            let trimmedSite = site.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSite.isEmpty else { continue }
            let wildcardDomain = trimmedSite.hasPrefix("*") ? trimmedSite : "*\(trimmedSite)"
            rules.append([
                "action": ["type": "ignore-previous-rules"],
                "trigger": ["url-filter": ".*", "if-domain": [wildcardDomain]]
            ])
        }

        guard let updatedData = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let updatedJSON = String(data: updatedData, encoding: .utf8) else {
            return json
        }
        return updatedJSON
    }
    
    /// Counts the number of rules in a Safari content blocker JSON string.
    ///
    /// - Parameter json: Safari content blocker JSON string.
    /// - Returns: Number of rules in the JSON array.
    private static func countRulesInJSON(_ json: String) -> Int {
        do {
            guard let jsonData = json.data(using: .utf8),
                  let rules = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                return 0
            }
            return rules.count
        } catch {
            return 0
        }
    }
    
    /// Builds the native advanced runtime from WBlockFilterCompiler JSON bundles.
    ///
    /// - Parameters:
    ///   - advancedRuleBundles: JSON-encoded WBlockFilterCompiler advanced-rule bundles.
    ///   - groupIdentifier: Group ID to use for the shared container.
    public static func buildCombinedNativeAdvancedRuntime(advancedRuleBundles: [String], groupIdentifier: String) throws {
        try measure(label: "Building native advanced runtime") {
            try NativeAdvancedRuntimeAdapter.build(
                jsonBundleSnippets: advancedRuleBundles,
                groupIdentifier: groupIdentifier
            )
        }
    }

    /// Clears the native advanced runtime.
    ///
    /// - Parameter groupIdentifier: Group ID to use for the shared container.
    public static func clearNativeAdvancedRuntime(groupIdentifier: String) throws {
        try NativeAdvancedRuntimeAdapter.clear(groupIdentifier: groupIdentifier)
    }

    public struct AdvancedRuntimePayloadCounts: Codable, Sendable, Equatable {
        public let css: Int
        public let extendedCss: Int
        public let js: Int
        public let scriptlets: Int
    }

    public struct AdvancedRuntimeLookupDebugReport: Codable, Sendable, Equatable {
        public let pageURL: String
        public let topURL: String?
        public let nativeAvailable: Bool
        public let nativeCounts: AdvancedRuntimePayloadCounts
    }

    /// Reports the installed native advanced runtime for a single URL without mutating it.
    public static func debugAdvancedRuntimeLookup(
        pageURL: URL,
        topURL: URL? = nil,
        groupIdentifier: String
    ) throws -> AdvancedRuntimeLookupDebugReport {
        let nativePayload = NativeAdvancedRuntimeAdapter.lookupPayload(
            pageURL: pageURL,
            topURL: topURL,
            groupIdentifier: groupIdentifier
        )

        return AdvancedRuntimeLookupDebugReport(
            pageURL: pageURL.absoluteString,
            topURL: topURL?.absoluteString,
            nativeAvailable: nativePayload != nil,
            nativeCounts: payloadCounts(nativePayload)
        )
    }

    private static func payloadCounts(_ payload: [String: Any]?) -> AdvancedRuntimePayloadCounts {
        AdvancedRuntimePayloadCounts(
            css: stringArray(in: payload, key: "css").count,
            extendedCss: stringArray(in: payload, key: "extendedCss").count,
            js: stringArray(in: payload, key: "js").count,
            scriptlets: scriptletEntries(in: payload).count
        )
    }

    private static func stringArray(in payload: [String: Any]?, key: String) -> [String] {
        payload?[key] as? [String] ?? []
    }

    private static func scriptletEntries(in payload: [String: Any]?) -> [String] {
        guard let scriptlets = payload?["scriptlets"] as? [[String: Any]] else { return [] }
        return scriptlets.map { scriptlet in
            let name = scriptlet["name"] as? String ?? ""
            let args = scriptlet["args"] as? [String] ?? []
            return "\(name)(\(args.joined(separator: "\u{1f}")))"
        }.sorted()
    }

    public static func buildCombinedAdvancedRuntime(combinedAdvancedRules: String, groupIdentifier: String) throws {
        guard !combinedAdvancedRules.isEmpty else { return }
        try buildCombinedNativeAdvancedRuntime(
            advancedRuleBundles: [combinedAdvancedRules],
            groupIdentifier: groupIdentifier
        )
    }

    public static func clearAdvancedRuntime(groupIdentifier: String) throws {
        try NativeAdvancedRuntimeAdapter.clear(groupIdentifier: groupIdentifier)
    }
    
}

// MARK: - Safari Content Blocker functions

extension ContentBlockerService {
    /// Converts filter rules into the Safari content blocking rules syntax.
    ///
    /// - Parameters:
    ///   - rules: Filter rules to convert.
    /// - Returns: A ConversionResult containing the converted Safari rules in JSON format
    ///           and advanced rules in text format.
    private struct ConversionResult {
        let safariRulesJSON: String
        let safariRulesCount: Int
        let advancedRulesText: String?
    }

    private static func convertRules(rules: String) throws -> ConversionResult {
        var filterRules = rules
        if !filterRules.isContiguousUTF8 {
            measure(label: "Make contiguous UTF-8") {
                filterRules.makeContiguousUTF8()
            }
        }

        let nativeResult = try measure(label: "Native conversion") {
            try NativeFilterCompilerAdapter.convert(
                rules: filterRules,
                sourceIdentifier: "combined",
                displayName: "Combined rules"
            )
        }

        if nativeResult.unsupportedRuleCount > 0 {
            os_log(.info, "Native filter conversion skipped %d unsupported rules", nativeResult.unsupportedRuleCount)
        }

        return ConversionResult(
            safariRulesJSON: nativeResult.safariRulesJSON,
            safariRulesCount: nativeResult.safariRulesCount,
            advancedRulesText: nativeResult.advancedRulesText
        )
    }

    /// Saves the blocker list file contents to the shared directory specified by the group identifier.
    ///
    /// - Parameters:
    ///   - contents: String content to write to the blocker list file.
    ///   - groupIdentifier: App group identifier for accessing the shared container.
    private static func saveBlockerListFile(contents: String, groupIdentifier: String, filename: String) {
        guard
            let appGroupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier
            )
        else {
            os_log(.error, "Failed to access the App Group container for file: %@", filename)
            return
        }

        let sharedFileURL = appGroupURL.appendingPathComponent(filename)

        do {
            guard let data = contents.data(using: .utf8) else {
                os_log(.error, "Failed to encode contents as UTF-8 for %@", filename)
                return
            }
            try data.write(to: sharedFileURL, options: .atomic)
            normalizeBlockerListFileForSafari(sharedFileURL)
            os_log(.info, "Successfully saved rules to %@", sharedFileURL.path)
        } catch {
            os_log(
                .error,
                "Failed to save %@ to the App Group container: %@",
                filename,
                error.localizedDescription
            )
        }
    }

    private static func normalizeBlockerListFileForSafari(_ url: URL) {
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        } catch {
            os_log(
                .error,
                "Failed to set Safari-readable permissions for %@: %@",
                url.path,
                error.localizedDescription
            )
        }

        #if canImport(Darwin)
        let attributesToRemove = [
            "com.apple.quarantine",
            "com.apple.provenance",
        ]
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            for attribute in attributesToRemove {
                if removexattr(path, attribute, 0) != 0, errno != ENOATTR {
                    let message = String(cString: strerror(errno))
                    os_log(
                        .error,
                        "Failed to remove extended attribute %@ from %@: %@",
                        attribute,
                        url.path,
                        message
                    )
                }
            }
        }
        #endif
    }


}
