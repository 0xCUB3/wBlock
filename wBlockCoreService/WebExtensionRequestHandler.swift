//
//  WebExtensionRequestHandler.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 11/04/2025.
//

internal import FilterEngine
import SafariServices
import os.log

/// WebExtensionRequestHandler processes requests from Safari Web Extensions and provides
/// content blocking configuration for web pages.
///
/// This handler receives requests from the extension's background page, looks up the
/// appropriate blocking rules for the requested URL, and returns the configuration
/// back to the extension.
public enum WebExtensionRequestHandler {
    private static func normalizeHost(_ host: String) -> String {
        host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func isHostDisabled(host: String, disabledSites: [String]) -> Bool {
        let normalizedHost = normalizeHost(host)
        if normalizedHost.isEmpty { return false }
        for site in disabledSites {
            let disabled = normalizeHost(site)
            if disabled.isEmpty { continue }
            if normalizedHost == disabled { return true }
            if normalizedHost.hasSuffix("." + disabled) { return true }
        }
        return false
    }

    private static func emptyRulesPayload() -> [String: Any] {
        [
            "css": [],
            "extendedCss": [],
            "js": [],
            "scriptlets": [],
            "userScripts": []
        ]
    }

    private static func extractResourceNames(from userScriptContent: String) -> [String] {
        // Only parse the metadata header block to avoid scanning huge script bodies.
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
                // Format: // @resource <name> <url>
                let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 3 {
                    let name = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { names.append(name) }
                }
            }
        }

        return Array(Set(names)).sorted()
    }
    /// Processes an extension request and provides content blocking configuration.
    ///
    /// This method extracts the URL from the request, looks up the appropriate blocking
    /// rules using WebExtension, and returns the configuration back to the extension.
    ///
    /// - Parameters:
    ///   - context: The extension context containing the request from the extension.
    public static func beginRequest(with context: NSExtensionContext) {
        // Fire-and-forget auto-update - force if overdue
        Task {
            let status = await SharedAutoUpdateManager.shared.nextScheduleStatus()
            if status.isOverdue && !status.isRunning {
                await SharedAutoUpdateManager.shared.forceNextUpdate()
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "ScriptsWebExtensionRequest", force: true)
            } else {
                await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(trigger: "ScriptsWebExtensionRequest")
            }
        }
        let request = context.inputItems.first as? NSExtensionItem

        var message = getMessage(from: request)

        if message == nil {
            context.completeRequest(returningItems: [])

            return
        }

        let nativeStart = Int64(Date().timeIntervalSince1970 * 1000)
        
        // Check if this is a userscript-related request
        if let action = message?["action"] as? String {
            switch action {
            case "requestRules":
                break
            case "getUserScripts":
                handleGetUserScriptsRequest(message: message!, context: context)
                return
            case "getUserScriptContentChunk":
                handleUserScriptChunkRequest(message: message!, context: context, kind: .content)
                return
            case "getUserScriptResourceChunk":
                handleUserScriptChunkRequest(message: message!, context: context, kind: .resource)
                return
            case "getSiteDisabledState":
                handleGetSiteDisabledState(message: message!, context: context)
                return
            case "setSiteDisabledState":
                handleSetSiteDisabledState(message: message!, context: context)
                return
            case "getBadgeCounterState":
                handleGetBadgeCounterState(context: context)
                return
            case "zapperController":
                handleZapperControllerRequest(message: message!, context: context)
                return
            default:
                break
            }
        }

        let payload = message?["payload"] as? [String: Any] ?? [:]
        if let urlString = payload["url"] as? String {
            if let url = URL(string: urlString) {
                // Respect per-site disable immediately for both content blockers and scripts.
                Task { @MainActor in
                    await ProtobufDataManager.shared.waitUntilLoaded()
                    let disabledSites = ProtobufDataManager.shared.disabledSites
                    let disabled = isHostDisabled(host: url.host ?? "", disabledSites: disabledSites)

                    if disabled {
                        message?["payload"] = emptyRulesPayload()
                    } else {
                        do {
                            let webExtension = try WebExtension.shared(
                                groupID: GroupIdentifier.shared.value
                            )

                            var topUrl: URL?
                            if let topUrlString = payload["topUrl"] as? String {
                                topUrl = URL(string: topUrlString)
                            }

                            if let configuration = webExtension.lookup(pageUrl: url, topUrl: topUrl) {
                                message?["payload"] = convertToPayload(configuration)
                            }
                        } catch {
                            os_log(
                                .error,
                                "Failed to get WebExtension instance: %@",
                                error.localizedDescription
                            )
                        }
                    }

                    if var trace = message?["trace"] as? [String: Int64] {
                        trace["nativeStart"] = nativeStart
                        trace["nativeEnd"] = Int64(Date().timeIntervalSince1970 * 1000)
                        message?["trace"] = trace
                    }

                    // Enable verbose logging in the content script only in debug builds
                    #if DEBUG
                    message?["verbose"] = true
                    #else
                    message?["verbose"] = false
                    #endif

                    if let safeMessage = message {
                        let response = createResponse(with: safeMessage)
                        context.completeRequest(returningItems: [response], completionHandler: nil)
                    } else {
                        context.completeRequest(returningItems: [], completionHandler: nil)
                    }
                }
                return
            }
        }

        if var trace = message?["trace"] as? [String: Int64] {
            trace["nativeStart"] = nativeStart
            trace["nativeEnd"] = Int64(Date().timeIntervalSince1970 * 1000)
            message?["trace"] = trace  // Reassign the modified dictionary back
        }

        // Enable verbose logging in the content script only in debug builds
        #if DEBUG
        message?["verbose"] = true
        #else
        message?["verbose"] = false
        #endif

        if let safeMessage = message {
            let response = createResponse(with: safeMessage)
            context.completeRequest(returningItems: [response], completionHandler: nil)
        } else {
            context.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    /// Converts a WebExtension.Configuration object to a dictionary payload.
    ///
    /// - Parameters:
    ///   - configuration: The WebExtension.Configuration object to convert.
    /// - Returns: A dictionary containing CSS, extended CSS, JS, and scriptlets
    ///           that should be applied to the web page.
    private static func convertToPayload(
        _ configuration: WebExtension.Configuration
    ) -> [String: Any] {
        var payload: [String: Any] = [:]
        payload["css"] = configuration.css
        payload["extendedCss"] = configuration.extendedCss
        payload["js"] = configuration.js

        var scriptlets: [[String: Any]] = []
        for scriptlet in configuration.scriptlets {
            var scriptletData: [String: Any] = [:]
            scriptletData["name"] = scriptlet.name
            scriptletData["args"] = scriptlet.args
            scriptlets.append(scriptletData)
        }

        payload["scriptlets"] = scriptlets

        return payload
    }

    /// Creates an NSExtensionItem response with the provided JSON payload.
    ///
    /// - Parameters:
    ///   - json: The JSON payload to include in the response.
    /// - Returns: An NSExtensionItem containing the response message.
    private static func createResponse(with json: [String: Any?]) -> NSExtensionItem {
        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: json]
        } else {
            response.userInfo = ["message": json]
        }

        return response
    }

    /// Extracts the message from an extension request.
    ///
    /// This method handles different Safari versions by using the appropriate
    /// keys for accessing the message and profile information.
    ///
    /// - Parameters:
    ///   - request: The NSExtensionItem containing the request from the extension.
    /// - Returns: The message dictionary or nil if no valid message was found.
    private static func getMessage(from request: NSExtensionItem?) -> [String: Any?]? {
        if request == nil {
            return nil
        }

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        os_log(
            .info,
            "Received message from browser.runtime.sendNativeMessage: %@ (profile: %@)",
            String(describing: message),
            profile?.uuidString ?? "none"
        )

        if message is [String: Any?] {
            return message as? [String: Any?]
        }

        return nil
    }

    private enum UserScriptChunkKind {
        case content
        case resource
    }

    private static func handleGetSiteDisabledState(message: [String: Any?], context: NSExtensionContext) {
        let host = normalizeHost((message["host"] as? String) ?? "")
        if host.isEmpty {
            let response = createResponse(with: ["disabled": false])
            context.completeRequest(returningItems: [response])
            return
        }

        Task { @MainActor in
            await ProtobufDataManager.shared.waitUntilLoaded()
            let disabledSites = ProtobufDataManager.shared.disabledSites
            let disabled = isHostDisabled(host: host, disabledSites: disabledSites)
            let response = createResponse(with: ["disabled": disabled])
            context.completeRequest(returningItems: [response])
        }
    }

    private static func handleSetSiteDisabledState(message: [String: Any?], context: NSExtensionContext) {
        let host = normalizeHost((message["host"] as? String) ?? "")
        let disabled = message["disabled"] as? Bool ?? false

        guard !host.isEmpty else {
            let response = createResponse(with: ["disabled": false, "error": "Missing host"])
            context.completeRequest(returningItems: [response])
            return
        }

        Task { @MainActor in
            await ProtobufDataManager.shared.waitUntilLoaded()

            var list = ProtobufDataManager.shared.disabledSites
            if disabled {
                if !list.contains(host) { list.append(host) }
            } else {
                // If a parent domain is disabled, remove it as well so the current host is active.
                let normalizedHost = normalizeHost(host)
                list.removeAll { entry in
                    let normalizedEntry = normalizeHost(entry)
                    if normalizedEntry.isEmpty { return true }
                    if normalizedEntry == normalizedHost { return true }
                    return normalizedHost.hasSuffix("." + normalizedEntry)
                }
            }

            await ProtobufDataManager.shared.setWhitelistedDomains(list)

            // Apply the change immediately by fast-updating the existing blocker JSON
            // and reloading each content blocker target for the current platform.
            #if os(macOS)
            let platform: Platform = .macOS
            #else
            let platform: Platform = .iOS
            #endif

            let groupID = GroupIdentifier.shared.value
            let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: platform)
            for target in targets {
                _ = ContentBlockerService.fastUpdateDisabledSites(
                    groupIdentifier: groupID,
                    targetRulesFilename: target.rulesFilename,
                    disabledSites: list
                )
                _ = await ContentBlockerService.reloadContentBlocker(withIdentifier: target.bundleIdentifier)
            }

            let response = createResponse(with: ["disabled": disabled])
            context.completeRequest(returningItems: [response])
        }
    }

    private static func handleGetBadgeCounterState(context: NSExtensionContext) {
        Task { @MainActor in
            await ProtobufDataManager.shared.waitUntilLoaded()
            let enabled = ProtobufDataManager.shared.isBadgeCounterEnabled
            let response = createResponse(with: ["enabled": enabled])
            context.completeRequest(returningItems: [response])
        }
    }

    /// Returns enabled userscripts for a URL, but without inlining potentially huge `content`/`resources`.
    private static func handleGetUserScriptsRequest(message: [String: Any?], context: NSExtensionContext) {
        guard let urlString = message["url"] as? String else {
            let response = createResponse(with: ["userScripts": []])
            context.completeRequest(returningItems: [response])
            return
        }

        Task { @MainActor in
            await ProtobufDataManager.shared.waitUntilLoaded()
            if let url = URL(string: urlString) {
                let disabledSites = ProtobufDataManager.shared.disabledSites
                if isHostDisabled(host: url.host ?? "", disabledSites: disabledSites) {
                    let response = createResponse(with: ["userScripts": []])
                    context.completeRequest(returningItems: [response])
                    return
                }
            }

            let userScriptManager = UserScriptManager.shared
            await userScriptManager.waitUntilReady()
            let userScripts = userScriptManager.getEnabledUserScriptsForURL(urlString)

            let userScriptDescriptors: [[String: Any]] = userScripts.map { script in
                // Prefer cached resource names, but fall back to parsing metadata so scripts
                // installed before resource caching still request the right dependencies.
                let resourceNames =
                    !script.resourceContents.isEmpty
                    ? Array(script.resourceContents.keys).sorted()
                    : extractResourceNames(from: script.content)
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

            let response = createResponse(with: ["userScripts": userScriptDescriptors])
            context.completeRequest(returningItems: [response])
        }
    }

    private static func handleUserScriptChunkRequest(
        message: [String: Any?],
        context: NSExtensionContext,
        kind: UserScriptChunkKind
    ) {
        guard let scriptIdString = message["scriptId"] as? String, let scriptId = UUID(uuidString: scriptIdString) else {
            let response = createResponse(with: ["error": "Missing or invalid scriptId"])
            context.completeRequest(returningItems: [response])
            return
        }

        let chunkIndex = message["chunkIndex"] as? Int ?? 0
        let chunkSize = message["chunkSize"] as? Int ?? 256 * 1024

        if chunkIndex < 0 || chunkSize <= 0 {
            let response = createResponse(with: ["error": "Invalid chunkIndex/chunkSize"])
            context.completeRequest(returningItems: [response])
            return
        }

        let resourceName: String?
        switch kind {
        case .content:
            resourceName = nil
        case .resource:
            resourceName = message["resourceName"] as? String
            if resourceName == nil || resourceName?.isEmpty == true {
                let response = createResponse(with: ["error": "Missing resourceName"])
                context.completeRequest(returningItems: [response])
                return
            }
        }

        Task { @MainActor in
            let manager = UserScriptManager.shared
            await manager.waitUntilReady()
            guard let script = manager.userScript(withId: scriptId) else {
                let response = createResponse(with: ["error": "Userscript not found"])
                context.completeRequest(returningItems: [response])
                return
            }

            let text: String?
            switch kind {
            case .content:
                text = script.content
            case .resource:
                // Lazily populate missing resources for scripts installed before caching existed.
                text = await manager.ensureResourceContent(forScriptId: scriptId, resourceName: resourceName!)
            }

            guard let text, !text.isEmpty else {
                let response = createResponse(with: ["error": "Requested content not available"])
                context.completeRequest(returningItems: [response])
                return
            }

            let data = Data(text.utf8)
            let totalChunks = Int(ceil(Double(data.count) / Double(chunkSize)))
            guard totalChunks > 0, chunkIndex < totalChunks else {
                let response = createResponse(with: ["error": "chunkIndex out of range", "totalChunks": totalChunks])
                context.completeRequest(returningItems: [response])
                return
            }

            let start = chunkIndex * chunkSize
            let end = min(start + chunkSize, data.count)
            let chunkData = data.subdata(in: start..<end)

            var responsePayload: [String: Any] = [
                "scriptId": scriptId.uuidString,
                "chunkIndex": chunkIndex,
                "totalChunks": totalChunks,
                "chunk": chunkData.base64EncodedString()
            ]
            if let resourceName {
                responsePayload["resourceName"] = resourceName
            }

            let response = createResponse(with: responsePayload)
            context.completeRequest(returningItems: [response])
        }
    }

    private static func handleZapperControllerRequest(message: [String: Any?], context: NSExtensionContext) {
        let payload = message["payload"] as? [String: Any] ?? [:]
        let action = payload["action"] as? String ?? ""

        switch action {
        case "saveRule":
            guard
                let hostname = (payload["hostname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !hostname.isEmpty,
                let selector = (payload["selector"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !selector.isEmpty
            else {
                let response = createResponse(with: ["error": "Missing hostname/selector"])
                context.completeRequest(returningItems: [response])
                return
            }

            saveZapperRule(hostname: hostname, selector: selector)
            let response = createResponse(with: ["ok": true])
            context.completeRequest(returningItems: [response])

        case "removeRule":
            guard
                let hostname = (payload["hostname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !hostname.isEmpty,
                let selector = (payload["selector"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !selector.isEmpty
            else {
                let response = createResponse(with: ["error": "Missing hostname/selector"])
                context.completeRequest(returningItems: [response])
                return
            }

            removeZapperRule(hostname: hostname, selector: selector)
            let response = createResponse(with: ["ok": true])
            context.completeRequest(returningItems: [response])

        case "loadRules":
            guard
                let hostname = (payload["hostname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !hostname.isEmpty
            else {
                let response = createResponse(with: ["action": "loadRulesResponse", "rules": []])
                context.completeRequest(returningItems: [response])
                return
            }

            let rules = loadZapperRules(for: hostname)
            let response = createResponse(with: [
                "action": "loadRulesResponse",
                "rules": rules,
            ])
            context.completeRequest(returningItems: [response])

        default:
            let response = createResponse(with: ["error": "Unknown zapper action"])
            context.completeRequest(returningItems: [response])
        }
    }

    private static func saveZapperRule(hostname: String, selector: String) {
        guard let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) else { return }
        let key = "zapperRules_\(hostname)"
        var existingRules = defaults.stringArray(forKey: key) ?? []
        if existingRules.contains(selector) == false {
            existingRules.append(selector)
            defaults.set(existingRules, forKey: key)
            defaults.synchronize()
        }
    }

    private static func loadZapperRules(for hostname: String) -> [String] {
        guard let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) else { return [] }
        let key = "zapperRules_\(hostname)"
        return defaults.stringArray(forKey: key) ?? []
    }

    private static func removeZapperRule(hostname: String, selector: String) {
        guard let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) else { return }
        let key = "zapperRules_\(hostname)"
        var existingRules = defaults.stringArray(forKey: key) ?? []
        existingRules.removeAll { $0 == selector }
        defaults.set(existingRules, forKey: key)
        defaults.synchronize()
    }
}
