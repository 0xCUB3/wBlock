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
    ///
    /// - Parameters:
    ///   - rules: AdGuard rules to be converted.
    ///   - groupIdentifier: Group ID to use for the shared container where
    ///                      the file will be saved.
    /// - Returns: The number of Safari content blocker rules generated from the conversion.
    public static func convertFilter(rules: String, groupIdentifier: String, targetRulesFilename: String) -> Int {
        let result = convertRules(rules: rules) // convertRules remains private and unchanged

        measure(label: "Saving content blocking rules file \(targetRulesFilename)") {
            saveBlockerListFile(contents: result.safariRulesJSON, groupIdentifier: groupIdentifier, filename: targetRulesFilename)
        }
        // advancedRulesText handling remains as is, assuming it's for a single WebExtension or not category-specific yet.
        if let advancedRulesText = result.advancedRulesText, !advancedRulesText.isEmpty {
             measure(label: "Building and saving engine (global for now)") {
                 do {
                     let webExtension = try WebExtension.shared(groupID: groupIdentifier)
                     _ = try webExtension.buildFilterEngine(rules: advancedRulesText)
                 } catch {
                     os_log(
                         .error,
                         "Failed to build and save the global filtering engine: %@",
                         error.localizedDescription
                     )
                 }
             }
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
