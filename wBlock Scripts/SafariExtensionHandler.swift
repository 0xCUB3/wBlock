//  SafariExtensionHandler.swift
//  wBlock Scripts
//
//  Created by Alexander Skula on 7/18/24.
//

import ContentBlockerEngine
import SafariServices
import os.log

class SafariExtensionHandler: SFSafariExtensionHandler {
    private let logger = Logger(subsystem: "app.0xcube.wBlock.wBlockScripts", category: "ExtensionHandler")

    override func messageReceived(
        withName messageName: String,
        from page: SFSafariPage,
        userInfo: [String: Any]?
    ) {
        guard messageName == "getAdvancedBlockingData",
              let url = userInfo?["url"] as? String,
              let pageUrl = URL(string: url) else {
            logger.error("Invalid message or URL received")
            return
        }

        page.getPropertiesWithCompletionHandler { [weak self] properties in
            guard let self = self else { return }
            if let pageUrlString = properties?.url?.absoluteString {
                self.logger.debug("Received message \(messageName) from page: \(pageUrlString)")
            }
        }

        Task {
            do {
                let blockingData = try await ContentBlockerEngineWrapper.shared.getData(url: pageUrl)
                let responseData: [String: Any] = [
                    "url": url,
                    "data": blockingData,
                    "verbose": true
                ]
                page.dispatchMessageToScript(withName: "advancedBlockingData", userInfo: responseData)
                logger.debug("Successfully injected script into: \(url)")
            } catch {
                logger.error("Failed to inject script: \(error.localizedDescription)")
            }
        }
    }

    override func toolbarItemClicked(in window: SFSafariWindow) {
        logger.debug("Toolbar item clicked")
    }

    override func validateToolbarItem(
        in window: SFSafariWindow,
        validationHandler: @escaping ((Bool, String) -> Void)
    ) {
        validationHandler(true, "")
    }

    override func popoverViewController() -> SFSafariExtensionViewController {
        SafariExtensionViewController.shared
    }
}
