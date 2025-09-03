//
//  ContentBlockerRequestHandler.swift
//  wBlock Foreign & Experimental
//
//  Created by Alexander Skula on 9/3/25.
//

#if os(iOS)
import UIKit
import MobileCoreServices
#endif
import wBlockCoreService
import os.log
import UniformTypeIdentifiers

public class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    // --- CONFIGURE THESE FOR EACH EXTENSION ---
    private let myPrimaryCategory: wBlockCoreService.FilterListCategory = .ads
    #if os(iOS)
    private let myPlatform = Platform.iOS
    #else
    private let myPlatform = Platform.macOS
    #endif
    // --- END CONFIGURATION ---

    public func beginRequest(with context: NSExtensionContext) {
        guard let targetInfo = ContentBlockerTargetManager.shared.targetInfo(forCategory: myPrimaryCategory, platform: myPlatform) else {
            os_log(.fault, "CRITICAL: Could not find ContentBlockerTargetInfo for primaryCategory '%@' on platform '%@'. Extension Bundle: %@",
                   myPrimaryCategory.rawValue,
                   String(describing: myPlatform),
                   Bundle.main.bundleIdentifier ?? "Unknown")
            // Fallback to sending empty rules
            let emptyRules = "[]"; let item = NSExtensionItem(); item.attachments = [NSItemProvider(item: emptyRules.data(using: .utf8) as NSData?, typeIdentifier: UTType.json.identifier)]; context.completeRequest(returningItems: [item]);
            return
        }

        ContentBlockerExtensionRequestHandler.handleRequest(
            with: context,
            groupIdentifier: GroupIdentifier.shared.value,
            rulesFilenameInAppGroup: targetInfo.rulesFilename
        )
    }
}

