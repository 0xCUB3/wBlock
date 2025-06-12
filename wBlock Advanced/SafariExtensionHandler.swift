//
//  SafariExtensionHandler.swift
//  wBlock Advanced
//
//  Created by Alexander Skula on 5/23/25.
//

import FilterEngine
import SafariServices
import wBlockCoreService
import os.log

/// SafariExtensionHandler is responsible for communicating between the Safari
/// web page and the extension's native code. It handles incoming messages from
/// content scripts, dispatches configuration rules, and manages content
/// blocking events.
public class SafariExtensionHandler: SFSafariExtensionHandler {
    
    private var _userScriptManager: UserScriptManager? // Replaces the lazy var

    @MainActor
    private func getOrCreateUserScriptManager() -> UserScriptManager { // New helper method
        if _userScriptManager == nil {
            // UserScriptManager() is now called within a @MainActor function
            _userScriptManager = UserScriptManager()
        }
        return _userScriptManager!
    }
    
    /// MainActor-isolated accessor for the userscript manager
    @MainActor
    private var userScriptManager: UserScriptManager { // Accessor now uses the helper
        return getOrCreateUserScriptManager()
    }

    /// Handles incoming messages from a web page.
    ///
    /// This method is invoked when the content script dispatches a message.
    /// It currently supports the "requestRules" message to supply configuration
    /// rules (CSS, JS, and scriptlets) to the web page.
    ///
    /// - Parameters:
    ///   - messageName: The name of the message (e.g., "requestRules").
    ///   - page: The Safari page that sent the message.
    ///   - userInfo: A dictionary with additional information associated with
    ///     the message.
    public override func messageReceived(
        withName messageName: String,
        from page: SFSafariPage,
        userInfo: [String: Any]?
    ) {
        os_log(.info, "SafariExtensionHandler: Received message '%@' with userInfo: %@", messageName, String(describing: userInfo))
        
        switch messageName {
        case "requestRules":
            // Retrieve the URL string from the incoming message.
            let requestId = userInfo?["requestId"] as? String ?? ""
            let urlString = userInfo?["url"] as? String ?? ""
            let topUrlString = userInfo?["topUrl"] as? String
            let requestedAt = userInfo?["requestedAt"] as? Int ?? 0

            os_log(.info, "SafariExtensionHandler: Processing requestRules for URL: %@", urlString)

            // Convert the string into a URL. If valid, attempt to look up its
            // configuration or honor per-site disable.
            if let url = URL(string: urlString), let host = url.host {
                // Check disabled sites list
                let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
                let disabled = defaults?.stringArray(forKey: "disabledSites") ?? []
                if disabled.contains(host) {
                    // Send empty rules so content blocker does nothing
                    let emptyPayload: [String: Any] = [
                        "requestId": requestId,
                        "payload": ["css": [], "extendedCss": [], "js": [], "scriptlets": []],
                        "requestedAt": requestedAt,
                        "verbose": false
                    ]
                    page.dispatchMessageToScript(withName: "requestRules", userInfo: emptyPayload)
                    return
                }
                // Otherwise proceed normally
                do {
                    let webExtension = try WebExtension.shared(
                        groupID: GroupIdentifier.shared.value
                    )

                    var topUrl: URL?
                    if let topUrlString = topUrlString {
                        topUrl = URL(string: topUrlString)
                    }

                    if let conf = webExtension.lookup(pageUrl: url, topUrl: topUrl) {
                        // Convert the configuration into a payload (dictionary
                        // format) consumable by the content script.
                        var payload = convertToPayload(conf)
                        
                        // Add userscripts to the payload
                        Task { @MainActor in
                            let manager = userScriptManager
                            os_log(.info, "SafariExtensionHandler: Getting userscripts for URL: %@", urlString)
                            let userScripts = manager.getEnabledUserScriptsForURL(urlString)
                            os_log(.info, "SafariExtensionHandler: Found %d userscripts for URL: %@", userScripts.count, urlString)
                            
                            let userScriptPayload = userScripts.map { script in
                                os_log(.info, "SafariExtensionHandler: Including userscript: %@", script.name)
                                return [
                                    "name": script.name,
                                    "content": script.content,
                                    "runAt": script.runAt
                                ]
                            }
                            
                            payload["userScripts"] = userScriptPayload
                            os_log(.info, "SafariExtensionHandler: Final payload includes %d userscripts", userScriptPayload.count)
                            
                            // Dispatch the payload back to the web page under the same
                            // message name.
                            let responseUserInfo: [String: Any] = [
                                "requestId": requestId,
                                "payload": payload,
                                "requestedAt": requestedAt,
                                // Enable verbose logging in the content script.
                                // In the real app `verbose` flag should only be true
                                // for debugging purposes.
                                "verbose": true,
                            ]

                            os_log(.info, "SafariExtensionHandler: Dispatching response for requestRules with payload")
                            page.dispatchMessageToScript(
                                withName: "requestRules",
                                userInfo: responseUserInfo
                            )
                        }
                    } else {
                        os_log(.info, "SafariExtensionHandler: No configuration found for URL: %@", urlString)
                    }
                } catch {
                    os_log(
                        .error,
                        "Failed to get WebExtension instance: %@",
                        error.localizedDescription
                    )
                }
            } else {
                os_log(.error, "SafariExtensionHandler: Invalid URL string: %@", urlString)
            }
        case "requestUserScripts":
            // Handle standalone userscript requests
            let requestId = userInfo?["requestId"] as? String ?? ""
            let urlString = userInfo?["url"] as? String ?? ""
            
            os_log(.info, "SafariExtensionHandler: Processing requestUserScripts for URL: %@", urlString)
            
            Task { @MainActor in
                let manager = userScriptManager
                os_log(.info, "SafariExtensionHandler: Getting userscripts for URL: %@", urlString)
                let userScripts = manager.getEnabledUserScriptsForURL(urlString)
                os_log(.info, "SafariExtensionHandler: Found %d userscripts for URL: %@", userScripts.count, urlString)
                
                let userScriptPayload = userScripts.map { script in
                    os_log(.info, "SafariExtensionHandler: Including userscript: %@", script.name)
                    return [
                        "name": script.name,
                        "content": script.content,
                        "runAt": script.runAt
                    ]
                }
                
                let responseUserInfo: [String: Any] = [
                    "requestId": requestId,
                    "userScripts": userScriptPayload
                ]
                
                os_log(.info, "SafariExtensionHandler: Dispatching response for requestUserScripts with %d scripts", userScriptPayload.count)
                page.dispatchMessageToScript(
                    withName: "requestUserScripts",
                    userInfo: responseUserInfo
                )
            }
        default:
            // For any unknown message, no action is taken.
            os_log(.info, "SafariExtensionHandler: Unknown message name: %@", messageName)
            return
        }
    }

    /// Converts a WebExtension.Configuration object into a dictionary payload.
    ///
    /// The payload includes the CSS, extended CSS, JS code, and an array of
    /// scriptlet data (name and arguments), which is then sent to the content
    /// script.
    ///
    /// - Parameters:
    ///   - configuration: The configuration object with the rules and scriptlets.
    /// - Returns: A dictionary ready to be sent as the payload.
    private func convertToPayload(_ configuration: WebExtension.Configuration) -> [String: Any] {
        var payload: [String: Any] = [:]
        // Add the primary configuration components.
        payload["css"] = configuration.css
        payload["extendedCss"] = configuration.extendedCss
        payload["js"] = configuration.js

        // Prepare an array to hold dictionary representations of each scriptlet.
        var scriptlets: [[String: Any]] = []
        for scriptlet in configuration.scriptlets {
            var scriptletData: [String: Any] = [:]
            // Include the scriptlet name and arguments.
            scriptletData["name"] = scriptlet.name
            scriptletData["args"] = scriptlet.args
            scriptlets.append(scriptletData)
        }

        payload["scriptlets"] = scriptlets

        return payload
    }

    /// Called when Safari's content blocker extension blocks resource requests.
    ///
    /// This method informs the app about which resources were blocked for
    /// a particular page, allowing the toolbar data (such as a blocked count)
    /// to be updated.
    ///
    /// - Parameters:
    ///   - contentBlockerIdentifier: The identifier for the content blocker.
    ///   - urls: An array of URLs for the resources that were blocked.
    ///   - page: The Safari page where the blocks occurred.
    public override func contentBlocker(
        withIdentifier contentBlockerIdentifier: String,
        blockedResourcesWith urls: [URL],
        on page: SFSafariPage
    ) {
        // Use an asynchronous task to update the blocking counter.
        Task {
            await ToolbarData.shared.trackBlocked(on: page, count: urls.count)
        }
    }

    /// Called when the current page is about to navigate to a new URL or reload.
    ///
    /// Resets the blocked advertisements counter for the page, ensuring that
    /// counts do not persist across navigations.
    ///
    /// - Parameters:
    ///   - page: The Safari page undergoing navigation.
    ///   - url: The destination URL (if provided).
    public override func page(_ page: SFSafariPage, willNavigateTo url: URL?) {
        Task {
            await ToolbarData.shared.resetBlocked(on: page)
        }
    }

    /// Validates and updates the toolbar item (icon) in Safari.
    ///
    /// This is triggered when the toolbar item is refreshed. It retrieves the
    /// count of blocked resources from the active tab and updates the badge
    /// text accordingly.
    ///
    /// - Parameters:
    ///   - window: The Safari window containing the toolbar item.
    ///   - validationHandler: A callback that receives a boolean (validity)
    ///     and a badge text.
    public override func validateToolbarItem(
        in window: SFSafariWindow,
        validationHandler: @escaping ((Bool, String) -> Void)
    ) {
        Task {
            // Retrieve the total number of blocked resources on the active tab.
            let blockedCount = await ToolbarData.shared.getBlockedOnActiveTab(in: window)
            // Determine the badge text based on the count.
            let badgeText = blockedCount == 0 ? "" : String(blockedCount)
            validationHandler(true, badgeText)
        }
    }

    /// Returns the popover view controller for the extension.
    ///
    /// The popover view controller is displayed when the extension's toolbar item is activated.
    ///
    /// - Returns: A shared instance of SafariExtensionViewController.
    public override func popoverViewController() -> SFSafariExtensionViewController {
        return SafariExtensionViewController.shared
    }

    /// Called when the popover is about to be shown.
    ///
    /// This method retrieves the blocked requests count for the active tab and
    /// passes it to the view controller before the popover is displayed.
    ///
    /// - Parameters:
    ///   - window: The Safari window containing the toolbar item.
    public override func popoverWillShow(in window: SFSafariWindow) {
        Task {
            let blockedCount = await ToolbarData.shared.getBlockedOnActiveTab(in: window)
            await SafariExtensionViewController.shared.updateBlockedCount(blockedCount)
        }
    }
}
