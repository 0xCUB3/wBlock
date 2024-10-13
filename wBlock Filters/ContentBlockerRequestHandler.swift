//
//  ContentBlockerRequestHandler.swift
//  wBlock Extension
//
//  Created by Alexander Skula on 7/17/24.
//

import Foundation

class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let sharedContainerIdentifier = "group.app.0xcube.wBlock"
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier) else {
            print("Failed to get shared container URL")
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
        let blockerListURL = containerURL.appendingPathComponent("blockerList.json")
        
        guard FileManager.default.fileExists(atPath: blockerListURL.path) else {
            print("blockerList.json does not exist at path: \(blockerListURL.path)")
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
        let attachment = NSItemProvider(contentsOf: blockerListURL)!
        
        let item = NSExtensionItem()
        item.attachments = [attachment]
        
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
