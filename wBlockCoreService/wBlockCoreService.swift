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

public enum ContentBlockerService {

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

    public static func exportConversionResult(rules: String) -> Data? {
        // Use the new public convertRules which returns a tuple
        let resultTuple = convertRules(rules: rules)

        var safariRulesJSON = resultTuple.safariRulesJSON // Already a String
        let advancedRulesText = resultTuple.advancedRulesText // Already a String?

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

        return createZipArchive(
            safariRulesJSON: safariRulesJSON,
            advancedRulesText: advancedRulesText
        )
    }

    public static func reloadContentBlocker(
        withIdentifier identifier: String
    ) -> Result<Void, Error> {
        os_log(.info, "Start reloading content blocker: %{public}s", identifier)
        let result = measure(label: "Reload safari \(identifier)") {
            reloadContentBlockerSynchronously(withIdentifier: identifier)
        }
        switch result {
        case .success:
            os_log(.info, "Content blocker %{public}s reloaded successfully.", identifier)
        case .failure(let error):
            os_log(.error, "Failed to reload content blocker %{public}s: %@", identifier, error.localizedDescription)
        }
        return result
    }

    public static func saveContentBlocker(jsonRules: String, groupIdentifier: String, fileName: String) -> Int {
        os_log(.info, "Saving content blocker rules to %{public}s", fileName)
        do {
            guard let jsonData = jsonRules.data(using: .utf8) else {
                os_log(.error, "Failed to convert string to bytes for %{public}s", fileName)
                return 0
            }
            let rules = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]]
            let ruleCount = rules?.count ?? 0
            measure(label: "Saving file: \(fileName)") {
                saveBlockerListFile(contents: jsonRules, groupIdentifier: groupIdentifier, fileName: fileName)
            }
            os_log(.info, "Successfully saved %{public}s with %d rules.", fileName, ruleCount)
            return ruleCount
        } catch {
            os_log(.error, "Failed to decode/save content blocker JSON for %{public}s: %@", fileName, error.localizedDescription)
            return 0
        }
    }

    // This function might still be used if you have a global "default" conversion path.
    // It now correctly calls the new saveContentBlocker.
    public static func convertFilter(rules: String, groupIdentifier: String) -> Int {
        let resultTuple = convertRules(rules: rules) // Calls the public version returning a tuple

        let savedRuleCount = saveContentBlocker(
            jsonRules: resultTuple.safariRulesJSON,
            groupIdentifier: groupIdentifier,
            fileName: Constants.SAFARI_BLOCKER_FILE_NAME // Ensure Constants.SAFARI_BLOCKER_FILE_NAME is defined
        )

        if let advancedRulesText = resultTuple.advancedRulesText {
            measure(label: "Building and saving engine for global rules") {
                do {
                    let webExtension = try WebExtension.shared(groupID: groupIdentifier)
                    _ = try webExtension.buildFilterEngine(rules: advancedRulesText)
                } catch {
                    os_log(.error, "Failed to build and save the filtering engine for global rules: %@", error.localizedDescription)
                }
            }
        }
        return savedRuleCount
    }

    // MODIFIED: Return type is now a tuple of public types
    /// Converts AdGuard rules and returns the results as a tuple of public types.
    ///
    /// - Parameters:
    ///   - rules: AdGuard rules to convert.
    /// - Returns: A tuple containing `safariRulesJSON` (String), `advancedRulesText` (String?),
    ///            `safariRulesCount` (Int), and `advancedRulesCount` (Int).
    public static func convertRules(rules: String) -> (safariRulesJSON: String, advancedRulesText: String?, safariRulesCount: Int, advancedRulesCount: Int) {
        let internalConversionResult = performInternalConversion(rules: rules)
        return (
            safariRulesJSON: internalConversionResult.safariRulesJSON,
            advancedRulesText: internalConversionResult.advancedRulesText,
            safariRulesCount: internalConversionResult.safariRulesCount,
            advancedRulesCount: internalConversionResult.advancedRulesCount
        )
    }

    // This function performs the actual conversion using the internal `ConversionResult` type.
    // It's marked `fileprivate` to be accessible only within this file.
    fileprivate static func performInternalConversion(rules: String) -> ConversionResult {
        var filterRules = rules
        if !filterRules.isContiguousUTF8 {
            measure(label: "Make contigious UTF-8") {
                filterRules.makeContiguousUTF8()
            }
        }
        let lines = filterRules.components(separatedBy: .newlines)
        let result = measure(label: "Conversion") {
            ContentBlockerConverter().convertArray(
                rules: lines,
                safariVersion: SafariVersion(18.1),
                advancedBlocking: true,
                maxJsonSizeBytes: nil,
                progress: nil
            )
        }
        return result
    }

    private static func reloadContentBlockerSynchronously(
        withIdentifier identifier: String
    ) -> Result<Void, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, Error> = .success(())
        SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { error in
            if let error = error {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    private static func saveBlockerListFile(contents: String, groupIdentifier: String, fileName: String) {
        guard
            let appGroupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier
            )
        else {
            os_log(.error, "Failed to access the App Group container for file %{public}s", fileName)
            return
        }
        let sharedFileURL = appGroupURL.appendingPathComponent(fileName)
        do {
            try contents.data(using: .utf8)?.write(to: sharedFileURL)
            os_log(.info, "Successfully wrote to %{public}s in App Group.", sharedFileURL.lastPathComponent)
        } catch {
            os_log(.error, "Failed to save %{public}s to the App Group container: %@", fileName, error.localizedDescription)
        }
    }

    private static func createZipArchive(
        safariRulesJSON: String,
        advancedRulesText: String?
    ) -> Data? {
        guard let contentBlockerData = safariRulesJSON.data(using: .utf8) else {
            fatalError("Failed to convert string to bytes")
        }
        let advancedData = advancedRulesText?.data(using: .utf8)
        do {
            let archive = try Archive(accessMode: .create)
            try archive.addEntry(
                with: "content-blocker.json",
                type: .file,
                uncompressedSize: Int64(contentBlockerData.count),
                bufferSize: 4096
            ) { position, size -> Data in
                return contentBlockerData.subdata(in: Data.Index(position)..<Data.Index(position) + size)
            }
            if let advancedData = advancedData {
                try archive.addEntry(
                    with: "advanced-rules.txt",
                    type: .file,
                    uncompressedSize: Int64(advancedData.count),
                    bufferSize: 4096
                ) { position, size -> Data in
                    return advancedData.subdata(in: Data.Index(position)..<Data.Index(position) + size)
                }
            }
            return archive.data
        } catch {
            os_log(.error, "Error while creating a ZIP archive with rules: %@", error.localizedDescription)
            return nil
        }
    }
}
