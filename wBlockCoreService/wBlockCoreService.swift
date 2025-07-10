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
    ) -> Result<Void, Error> {
        os_log(.info, "Start reloading the content blocker")

        let result = measure(label: "Reload safari") {
            reloadContentBlockerSynchronously(withIdentifier: identifier)
        }

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
    /// - Returns: A tuple containing the number of Safari content blocker rules generated 
    ///           and the advanced rules text (if any).
    public static func convertFilter(rules: String, groupIdentifier: String, targetRulesFilename: String) -> (safariRulesCount: Int, advancedRulesText: String?) {
        // Check if we can use fast path for disabled sites only changes
        let disabledSites = getDisabledSites(groupIdentifier: groupIdentifier)
        
        // Try to use cached conversion result if rules haven't changed
        let cacheKey = getCacheKey(for: rules)
        let cachedResult = cacheQueue.sync { conversionCache[cacheKey] }
        
        let result: ConversionResult
        if let cached = cachedResult {
            os_log(.info, "Using cached conversion result for %@", targetRulesFilename)
            result = cached
        } else {
            os_log(.info, "Converting rules for %@ (cache miss)", targetRulesFilename)
            result = convertRules(rules: rules) // Convert AdGuard rules to Safari JSON
            
            // Cache the result for future use
            cacheQueue.async(flags: .barrier) {
                conversionCache[cacheKey] = result
            }
        }
        
        // Always inject ignore rules for current disabled sites
        let finalJSON = injectIgnoreRulesForDisabledSites(json: result.safariRulesJSON, disabledSites: disabledSites)

        measure(label: "Saving content blocking rules file \(targetRulesFilename)") {
            saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)
        }
        
        // Count rules from final JSON for accurate reporting
        let finalRuleCount = countRulesInJSON(finalJSON)
        
        // Return both the count and advanced rules text for the caller to handle engine building
        return (safariRulesCount: finalRuleCount, advancedRulesText: result.advancedRulesText)
    }
    
    /// Fast update for disabled sites changes only - skips SafariConverterLib conversion
    /// Reads existing JSON files and re-injects ignore rules without full conversion
    ///
    /// - Parameters:
    ///   - groupIdentifier: Group ID to use for the shared container
    ///   - targetRulesFilename: Target filename for the rules file
    /// - Returns: A tuple containing the number of Safari content blocker rules and advanced rules text
    public static func fastUpdateDisabledSites(groupIdentifier: String, targetRulesFilename: String) -> (safariRulesCount: Int, advancedRulesText: String?) {
        let disabledSites = getDisabledSites(groupIdentifier: groupIdentifier)
        
        // Try to read existing file
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            os_log(.error, "Failed to access App Group container for fast update")
            return (safariRulesCount: 0, advancedRulesText: nil)
        }
        
        let fileURL = containerURL.appendingPathComponent(targetRulesFilename)
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let existingJSON = try? String(contentsOf: fileURL, encoding: .utf8) else {
            os_log(.info, "No existing file found for fast update, will use empty rules")
            // Create minimal rules with just ignore rules
            let emptyJSON = "[]"
            let finalJSON = injectIgnoreRulesForDisabledSites(json: emptyJSON, disabledSites: disabledSites)
            
            measure(label: "Fast saving content blocking rules file \(targetRulesFilename)") {
                saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)
            }
            
            return (safariRulesCount: countRulesInJSON(finalJSON), advancedRulesText: nil)
        }
        
        // Remove existing ignore rules and inject new ones
        let baseJSON = removeIgnoreRulesForDisabledSites(json: existingJSON)
        let finalJSON = injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: disabledSites)
        
        measure(label: "Fast updating content blocking rules file \(targetRulesFilename)") {
            saveBlockerListFile(contents: finalJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)
        }
        
        let finalRuleCount = countRulesInJSON(finalJSON)
        os_log(.info, "Fast updated %@ with %d rules for %d disabled sites", targetRulesFilename, finalRuleCount, disabledSites.count)
        
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
    
    /// Injects Safari content blocker ignore-previous-rules for disabled sites into existing JSON.
    /// This uses Safari's native ignore-previous-rules action to whitelist disabled sites.
    ///
    /// - Parameters:
    ///   - json: Existing Safari content blocker JSON string.
    ///   - disabledSites: Array of site hostnames to whitelist.
    /// - Returns: Modified JSON string with ignore rules injected.
    private static func injectIgnoreRulesForDisabledSites(json: String, disabledSites: [String]) -> String {
        guard !disabledSites.isEmpty else { return json }
        
        do {
            // Parse existing JSON
            guard let jsonData = json.data(using: .utf8),
                  let existingRules = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                os_log(.error, "Failed to parse existing content blocker JSON for disabled sites injection")
                return json
            }
            
            var modifiedRules = existingRules
            
            // Add ignore-previous-rules for each disabled site
            // This rule tells Safari to ignore all previous blocking rules for the specified domains
            for site in disabledSites {
                let ignoreRule: [String: Any] = [
                    "action": [
                        "type": "ignore-previous-rules"
                    ],
                    "trigger": [
                        "url-filter": ".*",
                        "if-domain": [site, "*." + site] // Include both domain and all subdomains
                    ]
                ]
                modifiedRules.append(ignoreRule)
            }
            
            // Convert back to JSON
            let modifiedJsonData = try JSONSerialization.data(withJSONObject: modifiedRules, options: [])
            if let modifiedJsonString = String(data: modifiedJsonData, encoding: .utf8) {
                os_log(.info, "Successfully injected ignore-previous-rules for %d disabled sites", disabledSites.count)
                return modifiedJsonString
            }
        } catch {
            os_log(.error, "Error injecting ignore rules for disabled sites: %@", error.localizedDescription)
        }
        
        return json // Return original JSON if injection fails
    }
    
    /// Removes existing ignore-previous-rules for disabled sites from JSON.
    /// This is used for fast updates to clean slate before re-injecting rules.
    ///
    /// - Parameter json: Existing Safari content blocker JSON string.
    /// - Returns: JSON string with ignore rules removed.
    private static func removeIgnoreRulesForDisabledSites(json: String) -> String {
        do {
            guard let jsonData = json.data(using: .utf8),
                  let existingRules = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                os_log(.error, "Failed to parse JSON for ignore rules removal")
                return json
            }
            
            // Filter out rules that are ignore-previous-rules (our disabled sites rules)
            let filteredRules = existingRules.filter { rule in
                if let action = rule["action"] as? [String: Any],
                   let type = action["type"] as? String,
                   type == "ignore-previous-rules" {
                    return false // Remove ignore rules
                }
                return true // Keep other rules
            }
            
            // Convert back to JSON
            let updatedData = try JSONSerialization.data(withJSONObject: filteredRules, options: [])
            return String(data: updatedData, encoding: .utf8) ?? json
            
        } catch {
            os_log(.error, "Error removing ignore rules: %@", error.localizedDescription)
            return json
        }
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

        let lines = filterRules.components(separatedBy: "\n")

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

    /// Provides a synchronous wrapper over SFContentBlockerManager.reloadContentBlocker.
    ///
    /// - Parameters:
    ///   - identifier: Bundle ID of the content blocker extension to reload.
    /// - Returns: A Result indicating success or containing an error if the reload failed.
    private static func reloadContentBlockerSynchronously(
        withIdentifier identifier: String
    ) -> Result<Void, Error> {
        // Create a semaphore with an initial count of 0
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, Error> = .success(())

        SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { error in
            if let error = error {
                result = .failure(error)
            } else {
                result = .success(())
            }
            // Signal the semaphore to unblock
            semaphore.signal()
        }

        // Block the thread until the semaphore is signaled
        semaphore.wait()
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
            try contents.data(using: .utf8)?.write(to: sharedFileURL)
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
