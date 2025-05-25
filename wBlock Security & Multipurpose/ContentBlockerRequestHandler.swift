//
//  ContentBlockerRequestHandler.swift
//  wBlock Security & Multipurpose
//
//  Created by Alexander Skula on 5/25/25.
//

import Foundation
import wBlockCoreService

public class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {

    private func getSpecificJsonFileName() -> String {
        // Derive filename from CFBundleName (which is usually $(PRODUCT_NAME))
        // e.g., "wBlock Custom (iOS)" -> "wBlock_Custom_iOS_rules.json"
        let productName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ?? "default_rules_for_unknown_product"
        
        // Sanitize the product name to create a valid filename component
        var sanitizedProductName = productName
        sanitizedProductName = sanitizedProductName.replacingOccurrences(of: " ", with: "_")
        sanitizedProductName = sanitizedProductName.replacingOccurrences(of: "(", with: "")
        sanitizedProductName = sanitizedProductName.replacingOccurrences(of: ")", with: "")
        sanitizedProductName = sanitizedProductName.replacingOccurrences(of: "&", with: "And")

        return "\(sanitizedProductName)_rules.json"
    }

    public func beginRequest(with context: NSExtensionContext) {
        let fileName = getSpecificJsonFileName()
        ContentBlockerExtensionRequestHandler.handleRequest(
            with: context,
            groupIdentifier: GroupIdentifier.shared.value,
            specificBlockerListFileName: fileName
        )
    }
}
