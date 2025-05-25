//
//  ContentBlockerExtensionRequestHandler.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 10/12/2024.
//

import os.log
import Foundation

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
    public static func handleRequest(with context: NSExtensionContext, groupIdentifier: String) {
        os_log(.info, "Start loading the content blocker")

        // Get the shared container URL using the provided group identifier
        guard
            let appGroupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier
            )
        else {
            context.cancelRequest(
                withError: createError(code: 1001, message: "Failed to access App Group container.")
            )
            return
        }

        // Construct the path to the shared blocker list file
        let sharedFileURL = appGroupURL.appendingPathComponent(Constants.SAFARI_BLOCKER_FILE_NAME)

        // Determine which blocker list file to use
        var blockerListFileURL = sharedFileURL
        if !FileManager.default.fileExists(atPath: sharedFileURL.path) {
            os_log(.info, "No blocker list file found. Using the default one.")

            // Fall back to the default blocker list included in the bundle
            guard
                let defaultURL = Bundle.main.url(forResource: "blockerList", withExtension: "json")
            else {
                context.cancelRequest(
                    withError: createError(
                        code: 1002,
                        message: "Failed to find default blocker list."
                    )
                )
                return
            }
            blockerListFileURL = defaultURL
        }

        // Create an attachment with the blocker list file
        guard let attachment = NSItemProvider(contentsOf: blockerListFileURL) else {
            context.cancelRequest(
                withError: createError(code: 1003, message: "Failed to create attachment.")
            )
            return
        }

        // Prepare and complete the extension request with the blocker list
        let item = NSExtensionItem()
        item.attachments = [attachment]

        context.completeRequest(
            returningItems: [item]
        ) { _ in
            os_log(.info, "Finished loading the content blocker")
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
