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
                // Check disabled sites list with subdomain support
                let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
                let disabled = defaults?.stringArray(forKey: "disabledSites") ?? []
                
                // Check if this host or any parent domain is disabled
                let isDisabled = isHostDisabled(host: host, disabledSites: disabled)
                
                os_log(.info, "SafariExtensionHandler: Host '%@' disabled check: %{BOOL}d (disabled sites: %@)", host, isDisabled, disabled.joined(separator: ", "))
                
                if isDisabled {
                    // Send empty rules so content blocker does nothing
                    let emptyPayload: [String: Any] = [
                        "requestId": requestId,
                        "payload": ["css": [], "extendedCss": [], "js": [], "scriptlets": [], "userScripts": []],
                        "requestedAt": requestedAt,
                        "verbose": false
                    ]
                    os_log(.info, "SafariExtensionHandler: Sending empty payload for disabled host: %@", host)
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
            
            // Check if site is disabled before processing userscripts
            if let url = URL(string: urlString), let host = url.host {
                let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
                let disabled = defaults?.stringArray(forKey: "disabledSites") ?? []
                let isDisabled = isHostDisabled(host: host, disabledSites: disabled)
                
                os_log(.info, "SafariExtensionHandler: UserScripts - Host '%@' disabled check: %{BOOL}d", host, isDisabled)
                
                if isDisabled {
                    // Send empty userscripts array for disabled sites
                    let emptyResponse: [String: Any] = [
                        "requestId": requestId,
                        "userScripts": [],
                        "verbose": false
                    ]
                    os_log(.info, "SafariExtensionHandler: Sending empty userscripts for disabled host: %@", host)
                    page.dispatchMessageToScript(withName: "requestUserScripts", userInfo: emptyResponse)
                    return
                }
            }
            
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
        case "zapperController":
            // Handle element zapper messages
            guard let action = userInfo?["action"] as? String else {
                os_log(.error, "SafariExtensionHandler: zapperController message missing action")
                return
            }
            
            os_log(.info, "SafariExtensionHandler: Processing zapperController action: %@", action)
            
            switch action {
            case "saveRule":
                if let hostname = userInfo?["hostname"] as? String,
                   let selector = userInfo?["selector"] as? String {
                    os_log(.info, "SafariExtensionHandler: Attempting to save zapper rule for %@ with selector: %@", hostname, selector)
                    saveZapperRule(hostname: hostname, selector: selector)
                    os_log(.info, "SafariExtensionHandler: Saved zapper rule for %@: %@", hostname, selector)
                    
                    // Immediately verify the rule was saved by loading it back
                    let savedRules = loadZapperRules(for: hostname)
                    os_log(.info, "SafariExtensionHandler: Verification - hostname %@ now has %d total rules: %@", hostname, savedRules.count, savedRules.joined(separator: ", "))
                } else {
                    os_log(.error, "SafariExtensionHandler: saveRule missing required parameters - hostname: %@, selector: %@", 
                           userInfo?["hostname"] as? String ?? "nil", 
                           userInfo?["selector"] as? String ?? "nil")
                }
                
            case "removeRule":
                if let hostname = userInfo?["hostname"] as? String,
                   let selector = userInfo?["selector"] as? String {
                    removeZapperRule(hostname: hostname, selector: selector)
                    os_log(.info, "SafariExtensionHandler: Removed zapper rule for %@: %@", hostname, selector)
                }
                
            case "loadRules":
                if let hostname = userInfo?["hostname"] as? String {
                    let rules = loadZapperRules(for: hostname)
                    let response: [String: Any] = [
                        "action": "loadRulesResponse",
                        "rules": rules
                    ]
                    page.dispatchMessageToScript(withName: "zapperController", userInfo: response)
                    os_log(.info, "SafariExtensionHandler: Loaded %d zapper rules for %@", rules.count, hostname)
                }
                
            case "activateZapper":
                // Inject the zapper content script
                injectZapper(into: page)
                os_log(.info, "SafariExtensionHandler: Activated element zapper")
                
            default:
                os_log(.info, "SafariExtensionHandler: Unknown zapperController action: %@", action)
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
    
    /// Checks if a host is disabled, including subdomain matching.
    /// For example, if "reddit.com" is disabled, this will return true for both "reddit.com" and "www.reddit.com"
    ///
    /// - Parameters:
    ///   - host: The hostname to check
    ///   - disabledSites: Array of disabled site hostnames
    /// - Returns: True if the host or any parent domain is disabled
    private func isHostDisabled(host: String, disabledSites: [String]) -> Bool {
        // Check for exact match first
        if disabledSites.contains(host) {
            return true
        }
        
        // Check if any disabled site is a parent domain of this host
        for disabledSite in disabledSites {
            if host == disabledSite || host.hasSuffix("." + disabledSite) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Element Zapper Methods
    
    private func injectZapper(into page: SFSafariPage) {
        guard let zapperHTMLPath = Bundle.main.path(forResource: "element-zapper", ofType: "html"),
              let zapperJSPath = Bundle.main.path(forResource: "element-zapper", ofType: "js") else {
            os_log(.error, "Zapper resource files not found in bundle.")
            return
        }
        
        do {
            let zapperHTML = try String(contentsOfFile: zapperHTMLPath, encoding: .utf8)
            let zapperJS = try String(contentsOfFile: zapperJSPath, encoding: .utf8)
            
            let message: [String: Any] = [
                "action": "injectZapper",
                "html": zapperHTML,
                "js": zapperJS
            ]
            
            page.dispatchMessageToScript(withName: "wblockAdvanced", userInfo: message)
            os_log(.info, "Successfully dispatched zapper HTML and JS to the content script.")
        } catch {
            os_log(.error, "Error reading zapper files: %@", error.localizedDescription)
        }
    }
    
    /// Saves a CSS selector rule for the element zapper for a specific hostname
    ///
    /// - Parameters:
    ///   - hostname: The hostname to save the rule for
    ///   - selector: The CSS selector to hide elements matching this pattern
    private func saveZapperRule(hostname: String, selector: String) {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
        os_log(.info, "SafariExtensionHandler: saveZapperRule - Using UserDefaults suite: %@", GroupIdentifier.shared.value)
        
        // Get existing rules for this hostname
        let key = "zapperRules_\(hostname)"
        var existingRules = defaults?.stringArray(forKey: key) ?? []
        os_log(.info, "SafariExtensionHandler: saveZapperRule - Found %d existing rules for key '%@': %@", existingRules.count, key, existingRules.joined(separator: ", "))
        
        // Add new rule if it doesn't already exist
        if !existingRules.contains(selector) {
            existingRules.append(selector)
            defaults?.set(existingRules, forKey: key)
            defaults?.synchronize() // Force sync to disk
            os_log(.info, "SafariExtensionHandler: Successfully saved zapper rule for %@: %@ (total rules: %d)", hostname, selector, existingRules.count)
            
            // Verify the save worked
            let verifyRules = defaults?.stringArray(forKey: key) ?? []
            os_log(.info, "SafariExtensionHandler: Verification read back %d rules: %@", verifyRules.count, verifyRules.joined(separator: ", "))
        } else {
            os_log(.info, "SafariExtensionHandler: Zapper rule already exists for %@: %@", hostname, selector)
        }
    }
    
    /// Loads all CSS selector rules for the element zapper for a specific hostname
    ///
    /// - Parameters:
    ///   - hostname: The hostname to load rules for
    /// - Returns: Array of CSS selectors for this hostname
    private func loadZapperRules(for hostname: String) -> [String] {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
        let key = "zapperRules_\(hostname)"
        let rules = defaults?.stringArray(forKey: key) ?? []
        
        os_log(.info, "SafariExtensionHandler: loadZapperRules - Loading rules for hostname '%@' with key '%@'", hostname, key)
        os_log(.info, "SafariExtensionHandler: loadZapperRules - Found %d rules: %@", rules.count, rules.joined(separator: ", "))
        
        return rules
    }
    
    /// Removes a specific zapper rule for a hostname
    ///
    /// - Parameters:
    ///   - hostname: The hostname to remove the rule from
    ///   - selector: The CSS selector to remove
    private func removeZapperRule(hostname: String, selector: String) {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
        let key = "zapperRules_\(hostname)"
        var existingRules = defaults?.stringArray(forKey: key) ?? []
        
        if let index = existingRules.firstIndex(of: selector) {
            existingRules.remove(at: index)
            defaults?.set(existingRules, forKey: key)
            os_log(.info, "SafariExtensionHandler: Removed zapper rule for %@: %@", hostname, selector)
        }
    }
    
    /// Gets all hostnames that have zapper rules
    ///
    /// - Returns: Array of hostnames with saved zapper rules
    private func getAllZapperHostnames() -> [String] {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
        guard let allKeys = defaults?.dictionaryRepresentation().keys else {
            return []
        }
        
        let zapperHostnames = allKeys.compactMap { key -> String? in
            if key.hasPrefix("zapperRules_") {
                return String(key.dropFirst("zapperRules_".count))
            }
            return nil
        }
        
        return Array(zapperHostnames)
    }
}
