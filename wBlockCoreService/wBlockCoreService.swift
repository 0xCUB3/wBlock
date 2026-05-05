//
//  wBlockCoreService.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 5/23/25.
//

internal import ContentBlockerConverter
internal import FilterEngine
import CryptoKit
import Foundation
import SafariServices
internal import ZIPFoundation
import os.log

/// ContentBlockerService provides functionality to convert AdGuard rules to Safari content blocking format
/// and manage content blocker extensions.
public enum ContentBlockerService {
    /// Version marker for built-in compatibility rules that are appended to
    /// every conversion. Bump this when changing `embeddedCompatibilityRules`
    /// so cached base JSON gets invalidated.
    private static let embeddedCompatibilityRulesVersion = "2"

    /// Minimal built-in rules that improve blocking of common dynamic ad script
    /// patterns and dynamic ad containers across filter sets.
    ///
    /// YouTube rules use trusted-replace-fetch-response for pre-parse string
    /// replacement (faster than json-prune-fetch-response which works post-parse).
    /// Sourced from uAssets, translated to AdGuard syntax.
    private static let embeddedCompatibilityRules = """
/js/widget/ads.js$script
/js/pagead.js$script
/widget/pagead.js$script
##.adbox.banner_ads.adsbox
www.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '"adPlacements"', '"no_ads"', 'player?')
www.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '"adSlots"', '"no_ads"', 'player?')
www.youtube.com#%#//scriptlet('set-constant', 'ytInitialPlayerResponse.playerAds', 'undefined')
www.youtube.com#%#//scriptlet('set-constant', 'ytInitialPlayerResponse.adPlacements', 'undefined')
www.youtube.com#%#//scriptlet('set-constant', 'playerResponse.adPlacements', 'undefined')
"""

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

    /// Converts AdGuard rules and exports them as a ZIP archive.
    ///
    /// - Parameters:
    ///   - rules: AdGuard syntax rules to be converted.
    /// - Returns: Data object containing a ZIP archive with Safari content blocker JSON and advanced rules,
    ///           or nil if the archive creation fails.
    public static func exportConversionResult(rules: String) -> Data? {
        let result = convertRules(rules: rules)

        // We'll use a variable so we can modify the JSON string
        var safariRulesJSON = result.safariRulesJSON
        let advancedRulesText = result.advancedRulesText

        // Attempt to pretty-print the JSON
        if let data = safariRulesJSON.data(using: .utf8),
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.prettyPrinted]
            ),
            let prettyString = String(data: prettyData, encoding: .utf8)
        {
            safariRulesJSON = prettyString
        }

        // Pass the newly formatted JSON string to the ZIP creation
        return createZipArchive(
            safariRulesJSON: safariRulesJSON,
            advancedRulesText: advancedRulesText
        )
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
            if error.localizedDescription.contains("WKErrorDomain error 6") {
                os_log(
                    .error,
                    "Failed to reload content blocker, could not access blocker list file: %@",
                    error.localizedDescription
                )
            } else {
                os_log(
                    .error,
                    "Failed to reload content blocker: %@",
                    error.localizedDescription
                )
            }
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

    /// Converts AdGuard rules to Safari content blocker format and saves them to the shared container.
    /// This version includes per-site disable functionality by injecting ignore-previous-rules for disabled sites.
    ///
    /// - Parameters:
    ///   - rules: AdGuard rules to be converted.
    ///   - groupIdentifier: Group ID to use for the shared container where
    ///                      the file will be saved.
    ///   - targetRulesFilename: Target filename for the rules file.
    ///   - disabledSites: Optional list of disabled sites. If nil, attempts to read from legacy UserDefaults.
    /// - Returns: A tuple containing the number of Safari content blocker rules generated 
    ///           and the advanced rules text (if any).
    public static func convertFilter(rules: String, groupIdentifier: String, targetRulesFilename: String, disabledSites: [String]? = nil) -> (safariRulesCount: Int, advancedRulesText: String?) {
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
        let baseCountURL = containerURL.appendingPathComponent(baseCountFilename)
        let baseHashURL = containerURL.appendingPathComponent(baseHashFilename)
        let advancedURL = containerURL.appendingPathComponent(advancedFilename)

        if let cachedHash = try? String(contentsOf: baseHashURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            cachedHash == rulesSHA256Hex,
            FileManager.default.fileExists(atPath: baseURL.path),
            let baseJSON = try? String(contentsOf: baseURL, encoding: .utf8)
        {
            let baseCount = (try? String(contentsOf: baseCountURL, encoding: .utf8))
                .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? countRulesInJSON(baseJSON)

            let finalJSON = injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sitesToUse)
            saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

            let advancedText =
                (try? String(contentsOf: advancedURL, encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }

            return (safariRulesCount: baseCount + sitesToUse.count, advancedRulesText: advancedText)
        }

        let effectiveRules = combinedRulesWithEmbeddedCompatibility(rules)
        let result = convertRules(rules: effectiveRules)

        saveBlockerListFile(contents: result.safariRulesJSON, groupIdentifier: groupIdentifier, filename: baseFilename)
        saveBlockerListFile(contents: String(result.safariRulesCount), groupIdentifier: groupIdentifier, filename: baseCountFilename)
        saveBlockerListFile(contents: rulesSHA256Hex, groupIdentifier: groupIdentifier, filename: baseHashFilename)
        saveBlockerListFile(contents: result.advancedRulesText ?? "", groupIdentifier: groupIdentifier, filename: advancedFilename)

        let finalJSON = injectIgnoreRulesForDisabledSites(json: result.safariRulesJSON, disabledSites: sitesToUse)
        saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

        return (safariRulesCount: result.safariRulesCount + sitesToUse.count, advancedRulesText: result.advancedRulesText)
    }

    /// Converts rules from a file, with a persistent on-disk cache keyed by the caller-provided SHA256.
    /// This avoids re-running SafariConverterLib when the combined rules for a target haven't changed.
    public static func convertFilterFromFile(
        rulesFileURL: URL,
        rulesSHA256Hex: String,
        groupIdentifier: String,
        targetRulesFilename: String,
        disabledSites: [String]? = nil
    ) -> (safariRulesCount: Int, advancedRulesText: String?) {
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
        let baseCountURL = containerURL.appendingPathComponent(baseCountFilename)
        let baseHashURL = containerURL.appendingPathComponent(baseHashFilename)
        let advancedURL = containerURL.appendingPathComponent(advancedFilename)

        if let cachedHash = try? String(contentsOf: baseHashURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            cachedHash == effectiveRulesHash,
            FileManager.default.fileExists(atPath: baseURL.path),
            let baseJSON = try? String(contentsOf: baseURL, encoding: .utf8)
        {
            let baseCount = (try? String(contentsOf: baseCountURL, encoding: .utf8))
                .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? countRulesInJSON(baseJSON)

            let finalJSON = injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sitesToUse)
            saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

            let advancedText =
                (try? String(contentsOf: advancedURL, encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }

            return (safariRulesCount: baseCount + sitesToUse.count, advancedRulesText: advancedText)
        }

        // Cache miss: read rules file and run conversion.
        let combinedRules = (try? String(contentsOf: rulesFileURL, encoding: .utf8)) ?? ""
        let effectiveRules = combinedRulesWithEmbeddedCompatibility(combinedRules)
        let result = convertRules(rules: effectiveRules)

        saveBlockerListFile(contents: result.safariRulesJSON, groupIdentifier: groupIdentifier, filename: baseFilename)
        saveBlockerListFile(contents: String(result.safariRulesCount), groupIdentifier: groupIdentifier, filename: baseCountFilename)
        saveBlockerListFile(contents: effectiveRulesHash, groupIdentifier: groupIdentifier, filename: baseHashFilename)
        saveBlockerListFile(contents: result.advancedRulesText ?? "", groupIdentifier: groupIdentifier, filename: advancedFilename)

        let finalJSON = injectIgnoreRulesForDisabledSites(json: result.safariRulesJSON, disabledSites: sitesToUse)
        saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

        return (safariRulesCount: result.safariRulesCount + sitesToUse.count, advancedRulesText: result.advancedRulesText)
    }
    
    /// Experimental native conversion path. This is intentionally not used by the default
    /// app pipeline yet; it exists so internal builds and tests can exercise the modular
    /// WBlockFilterCompiler package without touching SafariConverterLib-backed caches.
    public static func convertFilterNativeExperimentalFromFile(
        rulesFileURL: URL,
        groupIdentifier: String,
        targetRulesFilename: String,
        disabledSites: [String]? = nil
    ) -> (safariRulesCount: Int, advancedRulesText: String?, unsupportedRuleCount: Int) {
        let rules = (try? String(contentsOf: rulesFileURL, encoding: .utf8)) ?? ""
        return convertFilterNativeExperimental(
            rules: rules,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetRulesFilename,
            disabledSites: disabledSites
        )
    }

    public static func convertFilterNativeExperimental(
        rules: String,
        groupIdentifier: String,
        targetRulesFilename: String,
        disabledSites: [String]? = nil
    ) -> (safariRulesCount: Int, advancedRulesText: String?, unsupportedRuleCount: Int) {
        let sitesToUse = disabledSites ?? getDisabledSites(groupIdentifier: groupIdentifier)
        let effectiveRules = combinedRulesWithEmbeddedCompatibility(rules)

        do {
            let result = try NativeFilterCompilerAdapter.convert(
                rules: effectiveRules,
                sourceIdentifier: targetRulesFilename,
                displayName: targetRulesFilename
            )
            let finalJSON = injectIgnoreRulesForDisabledSites(
                json: result.safariRulesJSON,
                disabledSites: sitesToUse
            )
            saveBlockerListFile(
                contents: finalJSON,
                groupIdentifier: groupIdentifier,
                filename: targetRulesFilename
            )
            os_log(
                .info,
                "Native experimental conversion for %@ emitted %d Safari rules and %d unsupported rules",
                targetRulesFilename,
                result.safariRulesCount,
                result.unsupportedRuleCount
            )
            return (
                safariRulesCount: result.safariRulesCount + sitesToUse.count,
                advancedRulesText: result.advancedRulesText,
                unsupportedRuleCount: result.unsupportedRuleCount
            )
        } catch {
            os_log(
                .error,
                "Native experimental conversion failed for %@: %@",
                targetRulesFilename,
                error.localizedDescription
            )
            return (safariRulesCount: 0, advancedRulesText: nil, unsupportedRuleCount: 0)
        }
    }

    /// Fast update for disabled sites changes only - skips SafariConverterLib conversion
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
        let baseCountURL = containerURL.appendingPathComponent(baseCountFilename)
        if FileManager.default.fileExists(atPath: baseURL.path),
           let baseJSON = try? String(contentsOf: baseURL, encoding: .utf8) {
            let finalJSON = injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sitesToUse)
            saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

            let baseCount = (try? String(contentsOf: baseCountURL, encoding: .utf8))
                .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
            let finalRuleCount = baseCount + sitesToUse.count

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

        let finalRuleCount = derived.baseRuleCount + sitesToUse.count
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
    
    /// Injects Safari content blocker ignore-previous-rules for disabled sites into existing JSON.
    /// This uses Safari's native ignore-previous-rules action to whitelist disabled sites.
    ///
    /// - Parameters:
    ///   - json: Existing Safari content blocker JSON string.
    ///   - disabledSites: Array of site hostnames to whitelist.
    /// - Returns: Modified JSON string with ignore rules injected.
    private static func injectIgnoreRulesForDisabledSites(json: String, disabledSites: [String]) -> String {
        guard !disabledSites.isEmpty else { return json }
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let openBracket = trimmed.firstIndex(of: "["),
              let closeBracket = trimmed.lastIndex(of: "]"),
              openBracket < closeBracket else {
            return json
        }

        let ignoreRules = disabledSites.map { disabledSiteIgnoreRuleJSON(for: $0) }.joined(separator: ",")
        guard !ignoreRules.isEmpty else { return trimmed }

        let inner = trimmed[trimmed.index(after: openBracket)..<closeBracket]
        if inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[\(ignoreRules)]"
        }

        return String(trimmed[..<closeBracket]) + "," + ignoreRules + "]"
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
    
    /// Builds the experimental native advanced runtime from WBlockFilterCompiler JSON bundles.
    /// This does not replace SafariConverterLib's FilterEngine in the default pipeline yet.
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

    /// Clears the experimental native advanced runtime.
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
        public let legacyAvailable: Bool
        public let nativeCounts: AdvancedRuntimePayloadCounts
        public let legacyCounts: AdvancedRuntimePayloadCounts
        public let missingInNative: [String: [String]]
        public let extraInNative: [String: [String]]
    }

    /// Compares the installed native advanced runtime against the installed SafariConverterLib engine
    /// for a single URL. This is a debug/parity harness and does not mutate either runtime.
    public static func debugCompareAdvancedRuntimeLookup(
        pageURL: URL,
        topURL: URL? = nil,
        groupIdentifier: String
    ) throws -> AdvancedRuntimeLookupDebugReport {
        let nativePayload = NativeAdvancedRuntimeAdapter.lookupPayload(
            pageURL: pageURL,
            topURL: topURL,
            groupIdentifier: groupIdentifier
        )

        let legacyConfiguration: WebExtension.Configuration? = try WebExtensionGate.shared.withLock {
            let webExtension = try WebExtension.shared(groupID: groupIdentifier)
            return webExtension.lookup(pageUrl: pageURL, topUrl: topURL)
        }
        let legacyPayload = legacyConfiguration.map(payloadFromLegacyConfiguration)

        let categories = ["css", "extendedCss", "js", "scriptlets"]
        var missingInNative: [String: [String]] = [:]
        var extraInNative: [String: [String]] = [:]
        for category in categories {
            let nativeEntries = Set(canonicalEntries(in: nativePayload, category: category))
            let legacyEntries = Set(canonicalEntries(in: legacyPayload, category: category))
            let missing = legacyEntries.subtracting(nativeEntries).sorted()
            let extra = nativeEntries.subtracting(legacyEntries).sorted()
            if !missing.isEmpty { missingInNative[category] = missing }
            if !extra.isEmpty { extraInNative[category] = extra }
        }

        return AdvancedRuntimeLookupDebugReport(
            pageURL: pageURL.absoluteString,
            topURL: topURL?.absoluteString,
            nativeAvailable: nativePayload != nil,
            legacyAvailable: legacyPayload != nil,
            nativeCounts: payloadCounts(nativePayload),
            legacyCounts: payloadCounts(legacyPayload),
            missingInNative: missingInNative,
            extraInNative: extraInNative
        )
    }

    private static func payloadFromLegacyConfiguration(_ configuration: WebExtension.Configuration) -> [String: Any] {
        [
            "css": configuration.css,
            "extendedCss": configuration.extendedCss,
            "js": configuration.js,
            "scriptlets": configuration.scriptlets.map { scriptlet in
                ["name": scriptlet.name, "args": scriptlet.args]
            },
            "engineTimestamp": configuration.engineTimestamp,
        ]
    }

    private static func payloadCounts(_ payload: [String: Any]?) -> AdvancedRuntimePayloadCounts {
        AdvancedRuntimePayloadCounts(
            css: stringArray(in: payload, key: "css").count,
            extendedCss: stringArray(in: payload, key: "extendedCss").count,
            js: stringArray(in: payload, key: "js").count,
            scriptlets: scriptletEntries(in: payload).count
        )
    }

    private static func canonicalEntries(in payload: [String: Any]?, category: String) -> [String] {
        if category == "scriptlets" {
            return scriptletEntries(in: payload)
        }
        return stringArray(in: payload, key: category).sorted()
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

    /// Builds the filter engine with combined advanced rules from all filter groups.
    ///
    /// - Parameters:
    ///   - combinedAdvancedRules: Combined advanced rules text from all filter groups.
    ///   - groupIdentifier: Group ID to use for the shared container.
    public static func buildCombinedFilterEngine(combinedAdvancedRules: String, groupIdentifier: String) throws {
        guard !combinedAdvancedRules.isEmpty else {
            os_log(.info, "No advanced rules to build filter engine with")
            return
        }

        try measure(label: "Building combined filter engine") {
            #if os(iOS)
            try buildFilterEngineWithoutAdvisoryLock(
                rules: combinedAdvancedRules,
                groupIdentifier: groupIdentifier
            )
            #else
            try WebExtensionGate.shared.withLock {
                let webExtension = try WebExtension.shared(groupID: groupIdentifier)
                _ = try webExtension.buildFilterEngine(rules: combinedAdvancedRules)
            }
            #endif
            os_log(
                .info,
                "Successfully built combined filter engine with %d characters of advanced rules",
                combinedAdvancedRules.count
            )
        }
    }

    /// Clears SafariConverterLib's legacy filter engine without removing the native runtime.
    /// Used by the experimental native path so stale legacy rules are not used as fallback.
    ///
    /// - Parameter groupIdentifier: Group ID to use for the shared container.
    public static func clearLegacyFilterEngine(groupIdentifier: String) throws {
        try measure(label: "Clearing legacy filter engine") {
            #if os(iOS)
            try buildFilterEngineWithoutAdvisoryLock(rules: "", groupIdentifier: groupIdentifier)
            #else
            try WebExtensionGate.shared.withLock {
                let webExtension = try WebExtension.shared(groupID: groupIdentifier)
                _ = try webExtension.buildFilterEngine(rules: "")
            }
            #endif
            os_log(.info, "Successfully cleared legacy filter engine")
        }
    }

    /// Clears the filter engine by building it with empty rules.
    ///
    /// - Parameters:
    ///   - groupIdentifier: Group ID to use for the shared container.
    public static func clearFilterEngine(groupIdentifier: String) throws {
        try measure(label: "Clearing filter engine") {
            try clearLegacyFilterEngine(groupIdentifier: groupIdentifier)
            try? NativeAdvancedRuntimeAdapter.clear(groupIdentifier: groupIdentifier)
            os_log(.info, "Successfully cleared filter engine")
        }
    }

    #if os(iOS)
    private static func buildFilterEngineWithoutAdvisoryLock(
        rules: String,
        groupIdentifier: String
    ) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw WebExtension.WebExtensionError.containerURLNotFound(groupID: groupIdentifier)
        }

        let baseURL = containerURL.appendingPathComponent(Schema.BASE_DIR, isDirectory: true)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var buildResult: Result<Void, Error>?

        coordinator.coordinate(writingItemAt: baseURL, options: [], error: &coordinationError) { _ in
            buildResult = Result {
                try buildFilterEngineFiles(rules: rules, baseURL: baseURL)
            }
        }

        if let buildResult {
            try buildResult.get()
            return
        }

        if let coordinationError {
            throw coordinationError
        }

        throw WebExtension.WebExtensionError.buildEngineFailed(
            underlyingError: CocoaError(.fileWriteUnknown)
        )
    }

    private static func buildFilterEngineFiles(rules: String, baseURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let temporaryDirectory = baseURL.appendingPathComponent(
            "engine-rebuild-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let temporaryRulesBinURL = temporaryDirectory.appendingPathComponent(Schema.FILTER_RULE_STORAGE_FILE_NAME)
        let temporaryEngineURL = temporaryDirectory.appendingPathComponent(Schema.FILTER_ENGINE_INDEX_FILE_NAME)
        let temporaryRulesTextURL = temporaryDirectory.appendingPathComponent(Schema.RULES_FILE_NAME)
        let temporaryMetaURL = temporaryDirectory.appendingPathComponent(Schema.ENGINE_META_FILE_NAME)

        let storage = try FilterRuleStorage(
            from: rules.components(separatedBy: "\n"),
            for: SafariVersion.autodetect(),
            fileURL: temporaryRulesBinURL
        )
        let engine = try FilterEngine(storage: storage)
        try engine.write(to: temporaryEngineURL)
        try rules.write(to: temporaryRulesTextURL, atomically: true, encoding: .utf8)

        let meta = EngineMeta(timestamp: Date().timeIntervalSince1970, schemaVersion: Int32(Schema.VERSION))
        try meta.toData().write(to: temporaryMetaURL, options: .atomic)

        try publishEngineFiles(
            temporaryRulesBinURL: temporaryRulesBinURL,
            temporaryEngineURL: temporaryEngineURL,
            temporaryRulesTextURL: temporaryRulesTextURL,
            temporaryMetaURL: temporaryMetaURL,
            baseURL: baseURL
        )

        let migrationMarkerURL = baseURL.appendingPathComponent(Schema.MIGRATION_MARKER_FILE_NAME)
        if fileManager.fileExists(atPath: migrationMarkerURL.path) {
            try? fileManager.removeItem(at: migrationMarkerURL)
        }
    }

    private static func publishEngineFiles(
        temporaryRulesBinURL: URL,
        temporaryEngineURL: URL,
        temporaryRulesTextURL: URL,
        temporaryMetaURL: URL,
        baseURL: URL
    ) throws {
        let lockURL = baseURL.appendingPathComponent(Schema.LOCK_FILE_NAME)
        guard let fileLock = FileLock(filePath: lockURL.path) else {
            throw WebExtension.WebExtensionError.buildEngineFailed(
                underlyingError: CocoaError(.fileWriteUnknown)
            )
        }

        guard fileLock.lock(before: Date().addingTimeInterval(2)) else {
            throw WebExtension.WebExtensionError.buildEngineFailed(
                underlyingError: CocoaError(.fileWriteUnknown)
            )
        }
        defer { _ = fileLock.unlock() }

        let existingMetaURL = baseURL.appendingPathComponent(Schema.ENGINE_META_FILE_NAME)
        if FileManager.default.fileExists(atPath: existingMetaURL.path) {
            try FileManager.default.removeItem(at: existingMetaURL)
        }

        try replaceEngineFile(temporaryRulesBinURL, in: baseURL, named: Schema.FILTER_RULE_STORAGE_FILE_NAME)
        try replaceEngineFile(temporaryEngineURL, in: baseURL, named: Schema.FILTER_ENGINE_INDEX_FILE_NAME)
        try replaceEngineFile(temporaryRulesTextURL, in: baseURL, named: Schema.RULES_FILE_NAME)
        try replaceEngineFile(temporaryMetaURL, in: baseURL, named: Schema.ENGINE_META_FILE_NAME)
    }

    private static func replaceEngineFile(_ sourceURL: URL, in baseURL: URL, named fileName: String) throws {
        let destinationURL = baseURL.appendingPathComponent(fileName)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: sourceURL)
        } else {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
    }
    #endif
    
    /// Backward compatibility function that builds the filter engine immediately (legacy behavior).
    /// This function is deprecated and should not be used for new code.
    ///
    /// - Parameters:
    ///   - rules: AdGuard rules to be converted.
    ///   - groupIdentifier: Group ID to use for the shared container.
    ///   - targetRulesFilename: Target filename for the rules.
    /// - Returns: The number of Safari content blocker rules generated from the conversion.
}

// MARK: - Safari Content Blocker functions

extension ContentBlockerService {
    /// Converts AdGuard rules into the Safari content blocking rules syntax.
    ///
    /// - Parameters:
    ///   - rules: AdGuard rules to convert.
    /// - Returns: A ConversionResult containing the converted Safari rules in JSON format
    ///           and advanced rules in text format.
    private static func convertRules(rules: String) -> ConversionResult {
        var filterRules = rules
        if !filterRules.isContiguousUTF8 {
            measure(label: "Make contigious UTF-8") {
                // This is super important for the conversion performance.
                // In a normal app make sure you're storing filter lists as
                // contigious UTF-8 strings.
                filterRules.makeContiguousUTF8()
            }
        }

        // Important: many filter lists use CRLF, which Swift can treat as a single `Character`.
        // Splitting on "\n" alone may fail and yield a single giant line, resulting in 0 converted rules.
        let lines = filterRules.split(whereSeparator: \.isNewline).map(String.init)

        let result = measure(label: "Conversion") {
            ContentBlockerConverter().convertArray(
                rules: lines,
                safariVersion: .autodetect(),
                advancedBlocking: true,
                maxJsonSizeBytes: nil,
                progress: nil
            )
        }

        return result
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

    /// Creates a ZIP archive containing Safari content blocker rules and advanced rules.
    ///
    /// The archive will always include "content-blocker.json" and optionally "advanced-rules.txt"
    /// if advanced rules are provided.
    ///
    /// - Parameters:
    ///   - safariRulesJSON: JSON string containing Safari content blocker rules.
    ///   - advancedRulesText: Optional text string containing advanced blocking rules.
    /// - Returns: Data object representing the ZIP archive, or nil if archive creation fails.
    private static func createZipArchive(
        safariRulesJSON: String,
        advancedRulesText: String?
    ) -> Data? {
        // 1. Prepare data from strings
        guard let contentBlockerData = safariRulesJSON.data(using: .utf8) else {
            return nil
        }
        let advancedData = advancedRulesText?.data(using: .utf8)

        do {
            // 3. Create the Archive object with ZipFoundation
            let archive = try Archive(accessMode: .create)

            // 4. Add content-blocker.json entry
            try archive.addEntry(
                with: "content-blocker.json",
                type: .file,
                uncompressedSize: Int64(contentBlockerData.count),
                bufferSize: 4
            ) { position, size -> Data in
                // This will be called until `data` is exhausted (3x in this case).
                return contentBlockerData.subdata(
                    in: Data.Index(position)..<Int(position) + size
                )
            }

            // 5. Add advanced-rules.txt if present
            if let advancedData = advancedData {
                try archive.addEntry(
                    with: "advanced-rules.txt",
                    type: .file,
                    uncompressedSize: Int64(advancedData.count),
                    bufferSize: 4
                ) { position, size -> Data in
                    // This will be called until `data` is exhausted (3x in this case).
                    return advancedData.subdata(in: Data.Index(position)..<Int(position) + size)
                }
            }

            // 6. Zip creation complete
            return archive.data
        } catch {
            os_log(
                .error,
                "Error while creating a ZIP archive with rules: %@",
                error.localizedDescription
            )

            return nil
        }
    }
}
