//
//  SafariWebExtensionHandler.swift
//  wBlock Scripts (iOS)
//
//  Created by Alexander Skula on 5/23/25.
//

import Foundation

public class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    public func beginRequest(with context: NSExtensionContext) {
        // This extension is DNR-only (no native messaging).
        context.completeRequest(returningItems: [])
    }
}
