//
//  ContentBlockerExtensionRequestHandler.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 10/12/2024.
//

import os.log
import Foundation
import UniformTypeIdentifiers

/// Implements Safari content blocker extension logic.
/// This handler is responsible for loading content blocking rules from the
/// shared container and providing them to Safari extensions.
///
/// The rules are loaded from a shared location that is accessible by both the main app
/// and the content blocker extension. If no custom rules are found, it falls back to
/// the default blocker list included in the extension bundle.
public enum ContentBlockerExtensionRequestHandler {
    /// Handles content blocking extension request for rules.
    ///
    /// This method loads the content blocker rules JSON file from the shared container
    /// and attaches it to the extension context to be used by Safari.
    ///
    /// - Parameters:
    ///   - context: The extension context that initiated the request.
    ///   - groupIdentifier: The app group identifier used to access the shared container.
    public static func handleRequest(with context: NSExtensionContext, groupIdentifier: String, rulesFilenameInAppGroup: String) {
        os_log(.info, "ContentBlockerExtensionRequestHandler: Starting request")
        os_log(.info, "  - Group ID: %@", groupIdentifier)
        os_log(.info, "  - Target rules file: %@", rulesFilenameInAppGroup)
        os_log(.info, "  - Bundle ID: %@", Bundle.main.bundleIdentifier ?? "Unknown")
        
        #if os(iOS)
        os_log(.info, "  - Platform: iOS")
        #else
        os_log(.info, "  - Platform: macOS")
        #endif

        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            os_log(.error, "CRITICAL: Failed to access App Group container for group: %@", groupIdentifier)
            context.cancelRequest(withError: createError(code: 1001, message: "Failed to access App Group container."))
            return
        }
        
        os_log(.info, "  - App Group URL: %@", appGroupURL.path)

        let sharedFileURL = appGroupURL.appendingPathComponent(rulesFilenameInAppGroup)
        var rulesToLoadURL: URL?

        if FileManager.default.fileExists(atPath: sharedFileURL.path) {
            rulesToLoadURL = sharedFileURL
            // Get file size for debugging
            if let attributes = try? FileManager.default.attributesOfItem(atPath: sharedFileURL.path),
               let fileSize = attributes[.size] as? Int64 {
                os_log(.info, "Found rules in app group: %@ (size: %lld bytes)", sharedFileURL.path, fileSize)
            } else {
                os_log(.info, "Found rules in app group: %@", sharedFileURL.path)
            }
        } else {
            os_log(.info, "Rules file %@ not found in app group at path: %@", rulesFilenameInAppGroup, sharedFileURL.path)
            os_log(.info, "Falling back to bundled blockerList.json.")
            // Each extension should have its own "blockerList.json" as a fallback.
            // The name "blockerList.json" is hardcoded in many of your ContentBlockerRequestHandler.swift files already.
            if let bundledFallbackURL = Bundle.main.url(forResource: "blockerList", withExtension: "json") {
                rulesToLoadURL = bundledFallbackURL
                os_log(.info, "Using bundled fallback: %@", bundledFallbackURL.path)
            } else {
                os_log(.error, "FATAL: Bundled blockerList.json also not found for extension trying to load rules for %@.", rulesFilenameInAppGroup)
                let emptyRules = "[]"
                let item = NSExtensionItem()
                item.attachments = [NSItemProvider(item: emptyRules.data(using: .utf8) as NSData?, typeIdentifier: UTType.json.identifier as String)]
                context.completeRequest(returningItems: [item]) { _ in
                    os_log(.info, "Finished loading EMPTY content blocker due to missing files for originally sought: %@", rulesFilenameInAppGroup)
                }
                return
            }
        }

        guard let finalURL = rulesToLoadURL, let attachment = NSItemProvider(contentsOf: finalURL) else {
            os_log(.error, "Failed to create attachment from URL: %@", rulesToLoadURL?.path ?? "nil URL")
            let emptyRules = "[]"
            let item = NSExtensionItem()
            item.attachments = [NSItemProvider(item: emptyRules.data(using: .utf8) as NSData?, typeIdentifier: UTType.json.identifier as String)]
            context.completeRequest(returningItems: [item]) { _ in
                os_log(.info, "Finished loading EMPTY content blocker due to attachment failure for: %@", rulesFilenameInAppGroup)
            }
            return
        }

        let item = NSExtensionItem()
        item.attachments = [attachment]
        context.completeRequest(returningItems: [item]) { _ in
            os_log(.info, "Successfully completed request for content blocker rules from %@ (originally sought %@)", finalURL.path, rulesFilenameInAppGroup)
        }
    }

    /// Creates an NSError with the specified code and message.
    ///
    /// - Parameters:
    ///   - code: The error code.
    ///   - message: The error message.
    /// - Returns: An NSError object with the specified parameters.
    private static func createError(code: Int, message: String) -> NSError {
        return NSError(
            domain: "skula.wBlock",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
