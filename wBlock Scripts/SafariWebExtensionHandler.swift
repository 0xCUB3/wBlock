//
//  SafariWebExtensionHandler.swift
//  wBlock Scripts
//
//  Created by Alexander Skula on 3/17/26.
//

import wBlockCoreService
import Foundation

public class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    public func beginRequest(with context: NSExtensionContext) {
        WebExtensionRequestHandler.beginRequest(with: context)
    }
}
