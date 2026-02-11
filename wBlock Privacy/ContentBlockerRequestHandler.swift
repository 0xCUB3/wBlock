//
//  ContentBlockerRequestHandler.swift
//  wBlock Privacy
//
//  Created by Alexander Skula on 5/23/25.
//

import Foundation
import wBlockCoreService
import os.log

public class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    public func beginRequest(with context: NSExtensionContext) {
        #if os(iOS)
        let platform: Platform = .iOS
        #else
        let platform: Platform = .macOS
        #endif

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "Unknown"
        guard let targetInfo = ContentBlockerTargetManager.shared.targetInfo(forBundleIdentifier: bundleIdentifier, platform: platform) else {
            os_log(.fault, "CRITICAL: Could not find ContentBlockerTargetInfo for bundleIdentifier '%@' on platform '%@'.", bundleIdentifier, String(describing: platform))
            // Fallback to sending empty rules
            let emptyRules = "[]"; let item = NSExtensionItem(); item.attachments = [NSItemProvider(item: emptyRules.data(using: .utf8) as NSData?, typeIdentifier: kUTTypeJSON as String)]; context.completeRequest(returningItems: [item]);
            return
        }

        ContentBlockerExtensionRequestHandler.handleRequest(
            with: context,
            groupIdentifier: GroupIdentifier.shared.value,
            rulesFilenameInAppGroup: targetInfo.rulesFilename
        )
    }
}
