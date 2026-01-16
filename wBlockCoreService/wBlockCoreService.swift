//
//  wBlockCoreService.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 5/23/25.
//

internal import ContentBlockerConverter
internal import FilterEngine
import Foundation
import SafariServices
internal import ZIPFoundation
import os.log

/// ContentBlockerService provides functionality to convert AdGuard rules to Safari content blocking format
/// and manage content blocker extensions.
public enum ContentBlockerService {
    
    // MARK: - Performance Optimization Cache
    
    /// Cache for conversion results to avoid redundant SafariConverterLib calls
    private static var conversionCache: [String: ConversionResult] = [:]
    private static let maxConversionCacheEntries: Int = 8
    private static let cacheQueue = DispatchQueue(label: "conversion-cache", attributes: .concurrent)
    
    /// Clears the conversion cache to free memory
    public static func clearConversionCache() {
        cacheQueue.async(flags: .barrier) {
            conversionCache.removeAll()
        }
    }
    
    /// Gets cache key for rules to enable caching
    private static func getCacheKey(for rules: String) -> String {
        return String(rules.hash)
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

    /// Reloads the Safari content blocker extension with the specified identifier.
    ///
    /// - Parameters:
    ///   - identifier: Bundle ID of the content blocker extension to reload.
    /// - Returns: A Result indicating success or containing an error if the reload failed.
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
        // Check if we can use fast path for disabled sites only changes
        let sitesToUse = disabledSites ?? getDisabledSites(groupIdentifier: groupIdentifier)
        
        // Try to use cached conversion result if rules haven't changed
        let cacheKey = getCacheKey(for: rules)
        let cachedResult = cacheQueue.sync { conversionCache[cacheKey] }
        
        let result: ConversionResult
        let isCacheMiss: Bool
        if let cached = cachedResult {
            os_log(.info, "Using cached conversion result for %@", targetRulesFilename)
            result = cached
            isCacheMiss = false
        } else {
            os_log(.info, "Converting rules for %@ (cache miss)", targetRulesFilename)
            result = convertRules(rules: rules) // Convert AdGuard rules to Safari JSON
            isCacheMiss = true
            
            // Cache the result for future use
            cacheQueue.async(flags: .barrier) {
                conversionCache[cacheKey] = result
                if conversionCache.count > maxConversionCacheEntries {
                    conversionCache.removeAll(keepingCapacity: true)
                    conversionCache[cacheKey] = result
                }
            }
        }

        // Persist the raw (non-disabled-site) JSON once per conversion so fast disabled-site updates
        // don't need to parse/strip "ignore-previous-rules" (which is also used by filter exceptions).
        if isCacheMiss {
            let baseFilename = baseRulesFilename(for: targetRulesFilename)
            let baseCountFilename = baseRulesCountFilename(for: targetRulesFilename)
            saveBlockerListFile(contents: result.safariRulesJSON, groupIdentifier: groupIdentifier, filename: baseFilename)
            saveBlockerListFile(contents: String(result.safariRulesCount), groupIdentifier: groupIdentifier, filename: baseCountFilename)
        }

        // Inject ignore rules for current disabled sites (string-based to avoid massive JSONSerialization overhead)
        let finalJSON = injectIgnoreRulesForDisabledSites(json: result.safariRulesJSON, disabledSites: sitesToUse)

        saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)

        // Rule count is the converter's base count plus 1 ignore rule per disabled site.
        let finalRuleCount = result.safariRulesCount + sitesToUse.count
        
        // Return both the count and advanced rules text for the caller to handle engine building
        return (safariRulesCount: finalRuleCount, advancedRulesText: result.advancedRulesText)
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
        
        let baseFilename = baseRulesFilename(for: targetRulesFilename)
        let baseCountFilename = baseRulesCountFilename(for: targetRulesFilename)

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

    private static func baseRulesFilename(for targetRulesFilename: String) -> String {
        if targetRulesFilename.lowercased().hasSuffix(".json") {
            let stem = targetRulesFilename.dropLast(5)
            return "\(stem).base.json"
        }
        return "\(targetRulesFilename).base"
    }

    private static func baseRulesCountFilename(for targetRulesFilename: String) -> String {
        "\(baseRulesFilename(for: targetRulesFilename)).count"
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
    
    /// Builds the filter engine with combined advanced rules from all filter groups.
    ///
    /// - Parameters:
    ///   - combinedAdvancedRules: Combined advanced rules text from all filter groups.
    ///   - groupIdentifier: Group ID to use for the shared container.
    public static func buildCombinedFilterEngine(combinedAdvancedRules: String, groupIdentifier: String) {
        guard !combinedAdvancedRules.isEmpty else {
            os_log(.info, "No advanced rules to build filter engine with")
            return
        }
        
        measure(label: "Building combined filter engine") {
            do {
                let webExtension = try WebExtension.shared(groupID: groupIdentifier)
                _ = try webExtension.buildFilterEngine(rules: combinedAdvancedRules)
                os_log(.info, "Successfully built combined filter engine with %d characters of advanced rules", combinedAdvancedRules.count)
            } catch {
                os_log(
                    .error,
                    "Failed to build combined filtering engine: %@",
                    error.localizedDescription
                )
            }
        }
    }
    
    /// Clears the filter engine by building it with empty rules.
    ///
    /// - Parameters:
    ///   - groupIdentifier: Group ID to use for the shared container.
    public static func clearFilterEngine(groupIdentifier: String) {
        measure(label: "Clearing filter engine") {
            do {
                let webExtension = try WebExtension.shared(groupID: groupIdentifier)
                _ = try webExtension.buildFilterEngine(rules: "")
                os_log(.info, "Successfully cleared filter engine")
            } catch {
                os_log(
                    .error,
                    "Failed to clear filtering engine: %@",
                    error.localizedDescription
                )
            }
        }
    }
    
    /// Backward compatibility function that builds the filter engine immediately (legacy behavior).
    /// This function is deprecated and should not be used for new code.
    ///
    /// - Parameters:
    ///   - rules: AdGuard rules to be converted.
    ///   - groupIdentifier: Group ID to use for the shared container.
    ///   - targetRulesFilename: Target filename for the rules.
    /// - Returns: The number of Safari content blocker rules generated from the conversion.
    @available(*, deprecated, message: "Use convertFilter(rules:groupIdentifier:targetRulesFilename:) -> (safariRulesCount: Int, advancedRulesText: String?) and buildCombinedFilterEngine instead")
    public static func convertFilterLegacy(rules: String, groupIdentifier: String, targetRulesFilename: String) -> Int {
        let result = convertFilter(rules: rules, groupIdentifier: groupIdentifier, targetRulesFilename: targetRulesFilename)
        
        // Legacy behavior - build engine immediately if there are advanced rules
        if let advancedRulesText = result.advancedRulesText, !advancedRulesText.isEmpty {
            buildCombinedFilterEngine(combinedAdvancedRules: advancedRulesText, groupIdentifier: groupIdentifier)
        }
        
        return result.safariRulesCount
    }
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
            // In theory, this cannot happen.
            fatalError("Failed to convert string to bytes")
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
