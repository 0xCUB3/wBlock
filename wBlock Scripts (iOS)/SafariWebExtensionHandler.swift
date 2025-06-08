//
//  SafariWebExtensionHandler.swift
//  wBlock Scripts (iOS)
//
//  Created by Alexander Skula on 5/23/25.
//

import wBlockCoreService
import Foundation

public class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    public func beginRequest(with context: NSExtensionContext) {
        WebExtensionRequestHandler.beginRequest(with: context)
    }
}
