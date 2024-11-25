//
//  ContentBlockerRequestHandler.swift
//  wBlock Extension
//
//  Created by Alexander Skula on 7/17/24.
//

import Foundation

class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        if let fileURL = FileStorage.shared.getContainerURL()?.appendingPathComponent("blockerList.json"),
           FileManager.default.fileExists(atPath: fileURL.path),
           let attachment = NSItemProvider(contentsOf: fileURL) {
            
            let item = NSExtensionItem()
            item.attachments = [attachment]
            context.completeRequest(returningItems: [item], completionHandler: nil)
        } else {
            print("Failed to locate blockerList.json in shared container")
            context.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
