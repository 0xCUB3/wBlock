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
        
        guard let containerDefaults = UserDefaults(suiteName: sharedContainerIdentifier),
              let blockerData = containerDefaults.data(forKey: "blockerList") else {
            print("Failed to retrieve blockerList from UserDefaults")
            let error = NSError(domain: "ContentBlocker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Blocker list not available"])
            context.cancelRequest(withError: error)
            return
        }
        
        let attachment = NSItemProvider(item: blockerData as NSSecureCoding, typeIdentifier: kUTTypeJSON as String)
        
        let item = NSExtensionItem()
        item.attachments = [attachment]
        
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
