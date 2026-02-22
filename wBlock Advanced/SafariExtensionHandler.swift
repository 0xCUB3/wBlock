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
    private static func extractResourceNames(from userScriptContent: String) -> [String] {
        var names: [String] = []
        var inMetadata = false

        for line in userScriptContent.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "// ==UserScript==" {
                inMetadata = true
                continue
            }
            if trimmed == "// ==/UserScript==" { break }
            if !inMetadata { continue }

            if trimmed.hasPrefix("// @resource") {
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 3 {
                    let name = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { names.append(name) }
                }
            }
        }

        return Array(Set(names)).sorted()
    }
    
    @MainActor
    private func getOrCreateUserScriptManager() -> UserScriptManager { // New helper method
        return UserScriptManager.shared
    }
    
    /// MainActor-isolated accessor for the userscript manager
    @MainActor
    private var userScriptManager: UserScriptManager { // Accessor now uses the helper
        return getOrCreateUserScriptManager()
    }

    @MainActor
    private func refreshSharedDataIfNeeded() async {
        await ProtobufDataManager.shared.waitUntilLoaded()
        _ = await ProtobufDataManager.shared.refreshFromDiskIfModified()
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
        // Opportunistic background filter auto-update - force if overdue
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            if status.isOverdue && !status.isRunning {
                await SharedAutoUpdateManager.shared.forceNextUpdate()
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "AdvancedExtensionMessage", force: true)
            } else {
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "AdvancedExtensionMessage")
            }
        }
        os_log(.info, "SafariExtensionHandler: Received message '%@' with userInfo: %@", messageName, String(describing: userInfo))
        
        switch messageName {
        case "requestRules":
            // Retrieve the URL string from the incoming message.
            let requestId = userInfo?["requestId"] as? String ?? ""
            let urlString = userInfo?["url"] as? String ?? ""
            let topUrlString = userInfo?["topUrl"] as? String
            let requestedAt = userInfo?["requestedAt"] as? Int ?? 0

            os_log(.info, "SafariExtensionHandler: Processing requestRules for URL: %@", urlString)

            Task {
                await refreshSharedDataIfNeeded()
                let disabled = await ProtobufDataManager.shared.disabledSites
                
                // Convert the string into a URL. If valid, attempt to look up its
                // configuration or honor per-site disable.
                if let url = URL(string: urlString), let host = url.host {
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
                            await MainActor.run {
                                let manager = userScriptManager
                                os_log(.info, "SafariExtensionHandler: Getting userscripts for URL: %@", urlString)
                                let userScripts = manager.getEnabledUserScriptsForURL(urlString)
                                os_log(.info, "SafariExtensionHandler: Found %d userscripts for URL: %@", userScripts.count, urlString)
                                
                                let userScriptPayload = userScripts.map { script in
                                    os_log(.info, "SafariExtensionHandler: Including userscript: %@", script.name)
                                    return [
                                        "name": script.name,
                                        "content": script.content,
                                        "runAt": script.runAt,
                                        "noframes": script.noframes,
                                        "resources": script.resourceContents,
                                        "injectInto": script.injectInto
                                    ] as [String: Any]
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
            }
        case "requestUserScripts", "getUserScripts":
            // Handle userscript list requests
            let responseMessageName = messageName
            let requestId = userInfo?["requestId"] as? String ?? ""
            let urlString = userInfo?["url"] as? String ?? ""

            os_log(.info, "SafariExtensionHandler: Processing %@ for URL: %@", responseMessageName, urlString)

            Task {
                await refreshSharedDataIfNeeded()
                let disabled = await ProtobufDataManager.shared.disabledSites

                // Check if site is disabled before processing userscripts
                if let url = URL(string: urlString), let host = url.host {
                    let isDisabled = isHostDisabled(host: host, disabledSites: disabled)

                    os_log(.info, "SafariExtensionHandler: UserScripts - Host '%@' disabled check: %{BOOL}d", host, isDisabled)

                    if isDisabled {
                        let emptyResponse: [String: Any] = [
                            "requestId": requestId,
                            "userScripts": []
                        ]
                        os_log(.info, "SafariExtensionHandler: Sending empty userscripts for disabled host: %@", host)
                        page.dispatchMessageToScript(withName: responseMessageName, userInfo: emptyResponse)
                        return
                    }
                }

                await MainActor.run {
                    let manager = userScriptManager
                    os_log(.info, "SafariExtensionHandler: Getting userscripts for URL: %@", urlString)
                    let userScripts = manager.getEnabledUserScriptsForURL(urlString)
                    os_log(.info, "SafariExtensionHandler: Found %d userscripts for URL: %@", userScripts.count, urlString)

                    let userScriptDescriptors: [[String: Any]] = userScripts.map { script in
                        os_log(.info, "SafariExtensionHandler: Including userscript descriptor: %@", script.name)
                        let resourceNames =
                            !script.resourceContents.isEmpty
                            ? Array(script.resourceContents.keys).sorted()
                            : Self.extractResourceNames(from: script.content)
                        return [
                            "id": script.id.uuidString,
                            "name": script.name,
                            "version": script.version,
                            "description": script.description,
                            "runAt": script.runAt,
                            "noframes": script.noframes,
                            "injectInto": script.injectInto,
                            "resourceNames": resourceNames
                        ]
                    }

                    let responseUserInfo: [String: Any] = [
                        "requestId": requestId,
                        "userScripts": userScriptDescriptors
                    ]

                    os_log(.info, "SafariExtensionHandler: Dispatching response for %@ with %d scripts", responseMessageName, userScriptDescriptors.count)
                    page.dispatchMessageToScript(withName: responseMessageName, userInfo: responseUserInfo)
                }
            }
        case "getUserScriptContentChunk", "getUserScriptResourceChunk":
            let responseMessageName = messageName
            let requestId = userInfo?["requestId"] as? String ?? ""
            let scriptIdString = userInfo?["scriptId"] as? String ?? ""
            let chunkIndex = userInfo?["chunkIndex"] as? Int ?? 0
            let chunkSize = userInfo?["chunkSize"] as? Int ?? 256 * 1024
            let resourceName = userInfo?["resourceName"] as? String

            guard let scriptId = UUID(uuidString: scriptIdString), chunkIndex >= 0, chunkSize > 0 else {
                let errorResponse: [String: Any] = [
                    "requestId": requestId,
                    "error": "Missing or invalid parameters"
                ]
                page.dispatchMessageToScript(withName: responseMessageName, userInfo: errorResponse)
                return
            }

            if responseMessageName == "getUserScriptResourceChunk" && (resourceName == nil || resourceName?.isEmpty == true) {
                let errorResponse: [String: Any] = [
                    "requestId": requestId,
                    "error": "Missing resourceName"
                ]
                page.dispatchMessageToScript(withName: responseMessageName, userInfo: errorResponse)
                return
            }

            Task { @MainActor in
                let manager = userScriptManager
                guard let script = manager.userScript(withId: scriptId) else {
                    let errorResponse: [String: Any] = [
                        "requestId": requestId,
                        "scriptId": scriptIdString,
                        "error": "Userscript not found"
                    ]
                    page.dispatchMessageToScript(withName: responseMessageName, userInfo: errorResponse)
                    return
                }

                let text: String?
                if responseMessageName == "getUserScriptContentChunk" {
                    text = script.content
                } else {
                    text = await manager.ensureResourceContent(forScriptId: scriptId, resourceName: resourceName!)
                }

                guard let text, !text.isEmpty else {
                    var errorResponse: [String: Any] = [
                        "requestId": requestId,
                        "scriptId": scriptIdString,
                        "error": "Requested content not available"
                    ]
                    if let resourceName { errorResponse["resourceName"] = resourceName }
                    page.dispatchMessageToScript(withName: responseMessageName, userInfo: errorResponse)
                    return
                }

                let data = Data(text.utf8)
                let totalChunks = Int(ceil(Double(data.count) / Double(chunkSize)))
                guard totalChunks > 0, chunkIndex < totalChunks else {
                    var errorResponse: [String: Any] = [
                        "requestId": requestId,
                        "scriptId": scriptIdString,
                        "error": "chunkIndex out of range",
                        "totalChunks": totalChunks
                    ]
                    if let resourceName { errorResponse["resourceName"] = resourceName }
                    page.dispatchMessageToScript(withName: responseMessageName, userInfo: errorResponse)
                    return
                }

                let start = chunkIndex * chunkSize
                let end = min(start + chunkSize, data.count)
                let chunkData = data.subdata(in: start..<end)

                var response: [String: Any] = [
                    "requestId": requestId,
                    "scriptId": scriptIdString,
                    "chunkIndex": chunkIndex,
                    "totalChunks": totalChunks,
                    "chunk": chunkData.base64EncodedString()
                ]
                if let resourceName { response["resourceName"] = resourceName }
                page.dispatchMessageToScript(withName: responseMessageName, userInfo: response)
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
                    Task { @MainActor in
                        await refreshSharedDataIfNeeded()
                        await ProtobufDataManager.shared.addZapperRule(selector, forHost: hostname)
                        let savedRules = ProtobufDataManager.shared.getZapperRules(forHost: hostname)
                        os_log(.info, "SafariExtensionHandler: Saved zapper rule for %@: %@ (total: %d)", hostname, selector, savedRules.count)
                    }
                } else {
                    os_log(.error, "SafariExtensionHandler: saveRule missing required parameters - hostname: %@, selector: %@",
                           userInfo?["hostname"] as? String ?? "nil",
                           userInfo?["selector"] as? String ?? "nil")
                }

            case "removeRule":
                if let hostname = userInfo?["hostname"] as? String,
                   let selector = userInfo?["selector"] as? String {
                    Task { @MainActor in
                        await refreshSharedDataIfNeeded()
                        await ProtobufDataManager.shared.deleteZapperRule(selector, forHost: hostname)
                        os_log(.info, "SafariExtensionHandler: Removed zapper rule for %@: %@", hostname, selector)
                    }
                }

            case "loadRules":
                if let hostname = userInfo?["hostname"] as? String {
                    Task { @MainActor in
                        await refreshSharedDataIfNeeded()
                        let rules = ProtobufDataManager.shared.getZapperRules(forHost: hostname)
                        let response: [String: Any] = [
                            "action": "loadRulesResponse",
                            "rules": rules
                        ]
                        page.dispatchMessageToScript(withName: "zapperController", userInfo: response)
                        os_log(.info, "SafariExtensionHandler: Loaded %d zapper rules for %@", rules.count, hostname)
                    }
                }

            case "activateZapper":
                // The zapper is activated directly from script.js now
                os_log(.info, "SafariExtensionHandler: Received activateZapper (handled by script.js)")

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
        // Secondary trigger path - check if overdue
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            if status.isOverdue && !status.isRunning {
                await SharedAutoUpdateManager.shared.forceNextUpdate()
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BlockedResourceEvent", force: true)
            } else {
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "BlockedResourceEvent")
            }
        }
        // Use an asynchronous task to update the blocking counter.
        Task {
            // Update the blocked count and then refresh the toolbar badge
            await ToolbarData.shared.trackBlocked(on: page, urls: urls)
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
            // Reset blocked count and then refresh the toolbar badge
            await ToolbarData.shared.resetBlocked(on: page)
        }
        // Navigation trigger - check if overdue
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            if status.isOverdue && !status.isRunning {
                await SharedAutoUpdateManager.shared.forceNextUpdate()
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "Navigation", force: true)
            } else {
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "Navigation")
            }
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
            await refreshSharedDataIfNeeded()

            // Check if badge counter is enabled (read from Protobuf)
            let isBadgeCounterEnabled = await ProtobufDataManager.shared.isBadgeCounterEnabled

            if !isBadgeCounterEnabled {
                // Badge is disabled, show empty string
                validationHandler(true, "")
            } else {
                // Retrieve the total number of blocked resources on the active tab.
                let blockedCount = await ToolbarData.shared.getBlockedOnActiveTab(in: window)
                // Determine the badge text based on the count.
                let badgeText = blockedCount == 0 ? "" : String(blockedCount)
                validationHandler(true, badgeText)
            }
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
            let blockedRequests = await ToolbarData.shared.getBlockedURLsOnActiveTab(in: window)
            await SafariExtensionViewController.shared.updateBlockedRequests(blockedRequests)
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
    
}
