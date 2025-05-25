//
//  ContentBlockerRequestHandler.swift
//  wBlock Annoyances
//
//  Created by Alexander Skula on 5/25/25.
//

import Foundation
import wBlockCoreService
import os.log

public class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    // --- CONFIGURE THESE FOR EACH EXTENSION ---
    private let myPrimaryCategory: wBlockCoreService.FilterListCategory = .annoyances
    private let mySecondaryCategory: wBlockCoreService.FilterListCategory? = nil
    private let myPlatform = Platform.macOS
    // --- END CONFIGURATION ---

    public func beginRequest(with context: NSExtensionContext) {
        // Try primary category first
        var targetInfo = ContentBlockerTargetManager.shared.targetInfo(forCategory: myPrimaryCategory, platform: myPlatform)

        // If not found and there's a secondary category, try that (for combined extensions)
        if targetInfo == nil, let secondary = mySecondaryCategory {
            targetInfo = ContentBlockerTargetManager.shared.targetInfo(forCategory: secondary, platform: myPlatform)
        }
        
        guard let finalTargetInfo = targetInfo else {
            os_log(.fault, "CRITICAL: Could not find ContentBlockerTargetInfo for primaryCategory '%@' (secondary: '%@') on platform '%@'. Extension Bundle: %@",
                   myPrimaryCategory.rawValue,
                   mySecondaryCategory?.rawValue ?? "N/A",
                   String(describing: myPlatform),
                   Bundle.main.bundleIdentifier ?? "Unknown")
            // Fallback to sending empty rules
            let emptyRules = "[]"; let item = NSExtensionItem(); item.attachments = [NSItemProvider(item: emptyRules.data(using: .utf8) as NSData?, typeIdentifier: kUTTypeJSON as String)]; context.completeRequest(returningItems: [item]);
            return
        }

        ContentBlockerExtensionRequestHandler.handleRequest(
            with: context,
            groupIdentifier: GroupIdentifier.shared.value,
            rulesFilenameInAppGroup: finalTargetInfo.rulesFilename
        )
    }
}
