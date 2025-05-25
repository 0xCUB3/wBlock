//
//  ContentBlockerExtensionRequestHandler.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 10/12/2024.
//

import os.log
import Foundation

public enum ContentBlockerExtensionRequestHandler {
    public static func handleRequest(with context: NSExtensionContext, groupIdentifier: String, specificBlockerListFileName: String) {
        os_log(.info, "Loading content blocker rules for file: %{public}s", specificBlockerListFileName)

        guard
            let appGroupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier
            )
        else {
            let errorMsg = "Failed to access App Group container."
            os_log(.error, "%{public}s", errorMsg)
            context.cancelRequest(
                withError: createError(code: 1001, message: errorMsg)
            )
            return
        }

        let sharedFileURL = appGroupURL.appendingPathComponent(specificBlockerListFileName)
        var blockerListFileURL = sharedFileURL

        if !FileManager.default.fileExists(atPath: sharedFileURL.path) {
            os_log(.info, "Shared file %{public}s not found. Trying bundle fallback.", specificBlockerListFileName)
            // Fallback to a file with the same specific name in the extension's bundle
            // The bundle's forResource name should not include the .json extension.
            let resourceName = specificBlockerListFileName.hasSuffix(".json") ? String(specificBlockerListFileName.dropLast(5)) : specificBlockerListFileName
            
            if let bundleURL = Bundle.main.url(forResource: resourceName, withExtension: "json") {
                 os_log(.info, "Found %{public}s in bundle. Using it as fallback.", specificBlockerListFileName)
                blockerListFileURL = bundleURL
            } else {
                 // As a last resort, try the default "blockerList.json" from bundle if specific one not found
                 if let defaultBundleURL = Bundle.main.url(forResource: "blockerList", withExtension: "json") {
                     os_log(.default, "Specific file %{public}s not found in bundle. Falling back to default 'blockerList.json' in bundle.", specificBlockerListFileName)
                    blockerListFileURL = defaultBundleURL
                 } else {
                    let errorMsg = "Failed to find %{public}s in shared container or bundle, and default 'blockerList.json' not in bundle."
                    os_log(.error, "%{public}s", String(format: errorMsg, specificBlockerListFileName))
                    context.cancelRequest(
                        withError: createError(code: 1002, message: String(format: errorMsg, specificBlockerListFileName))
                    )
                    return
                 }
            }
        }


        guard let attachment = NSItemProvider(contentsOf: blockerListFileURL) else {
            let errorMsg = "Failed to create attachment from %{public}s."
            os_log(.error, "%{public}s", String(format: errorMsg, blockerListFileURL.path))
            context.cancelRequest(
                withError: createError(code: 1003, message: String(format: errorMsg, blockerListFileURL.path))
            )
            return
        }

        let item = NSExtensionItem()
        item.attachments = [attachment]

        context.completeRequest(
            returningItems: [item]
        ) { _ in
            os_log(.info, "Finished loading content blocker with rules from %{public}s", blockerListFileURL.lastPathComponent)
        }
    }

    private static func createError(code: Int, message: String) -> NSError {
        return NSError(
            domain: "skula.wBlock.ContentBlockerExtensionRequestHandler",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
