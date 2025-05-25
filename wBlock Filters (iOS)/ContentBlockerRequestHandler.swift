//
//  ContentBlockerRequestHandler.swift
//  wBlock Filters (iOS)
//
//  Created by Alexander Skula on 5/23/25.
//

import Foundation
import wBlockCoreService

public class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    public func beginRequest(with context: NSExtensionContext) {
        ContentBlockerExtensionRequestHandler.handleRequest(
            with: context,
            groupIdentifier: GroupIdentifier.shared.value
        )
    }
}
