//
//  ContentBlockerRequestHandler.swift
//  wBlock Extension
//
//  Created by Alexander Skula on 7/17/24.
//

import Foundation

class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        do {
            // Get the URL for blockerList.json using FileStorage
            guard let fileURL = FileStorage.shared.getContainerURL()?.appendingPathComponent("blockerList.json") else {
                print("Failed to get shared container URL")
                context.completeRequest(returningItems: nil, completionHandler: nil)
                return
            }

            // Check if file exists
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("blockerList.json does not exist at path: \(fileURL.path)")
                context.completeRequest(returningItems: nil, completionHandler: nil)
                return
            }

            // Create attachment directly from file URL, just like before
            let attachment = NSItemProvider(contentsOf: fileURL)!

            let item = NSExtensionItem()
            item.attachments = [attachment]

            context.completeRequest(returningItems: [item], completionHandler: nil)

        } catch {
            print("Error in content blocker: \(error)")
            context.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
