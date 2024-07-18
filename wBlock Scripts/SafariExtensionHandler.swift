//  SafariExtensionHandler.swift
//  wBlock Scripts
//
//  Created by Alexander Skula on 7/18/24.
//

import ContentBlockerEngine
import SafariServices

class SafariExtensionHandler: SFSafariExtensionHandler {

    override func messageReceived(
        withName messageName: String, from page: SFSafariPage,
        userInfo: [String: Any]?
    ) {
        page.getPropertiesWithCompletionHandler { properties in
            if let url = properties?.url?.absoluteString {
                print("Received message \(messageName) from page: \(url)")
            }
        }

        // Content script requests scripts and css for current page
        if messageName == "getAdvancedBlockingData" {
            if let url = userInfo?["url"] as? String {
                let pageUrl = URL(string: url)!
                Task {
                    let data: [String: Any]? = [
                        "url": url,
                        "data": await ContentBlockerEngineWrapper.shared.getData(url: pageUrl),
                        "verbose": true,
                    ]
                    page.dispatchMessageToScript(withName: "advancedBlockingData", userInfo: data)
                    print("Attempted to inject script into: \(url)")
                }
            } else {
                print("Empty url passed with the message")
            }
        }
    }

    override func toolbarItemClicked(in window: SFSafariWindow) {
        print("The extension's toolbar item was clicked")
    }

    override func validateToolbarItem(
        in window: SFSafariWindow,
        validationHandler: @escaping ((Bool, String) -> Void)
    ) {
        validationHandler(true, "")
    }

    override func popoverViewController() -> SFSafariExtensionViewController {
        return SafariExtensionViewController.shared
    }
}
