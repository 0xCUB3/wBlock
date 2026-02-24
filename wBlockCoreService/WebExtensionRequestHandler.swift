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
    private static func emptyRulesPayload() -> [String: Any] {
        [
            "css": [],
            "extendedCss": [],
            "js": [],
            "scriptlets": [],
            "userScripts": []
        ]
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
            case "syncZapperRules":
                handleSyncZapperRules(message: message!, context: context)
                return
            case "getZapperRules":
                handleGetZapperRules(message: message!, context: context)
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
                    let disabled = HostMatcher.isHostDisabled(host: url.host ?? "", disabledSites: disabledSites)

                    if disabled {
                        message?["payload"] = emptyRulesPayload()
                    } else {
                        do {
                            var topUrl: URL?
                            if let topUrlString = payload["topUrl"] as? String {
                                topUrl = URL(string: topUrlString)
                            }

                            let configuration: WebExtension.Configuration? = try WebExtensionGate.shared.withLock {
                                let webExtension = try WebExtension.shared(
                                    groupID: GroupIdentifier.shared.value
                                )
                                return webExtension.lookup(pageUrl: url, topUrl: topUrl)
                            }

                            if let configuration {
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
        let host = (message["host"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if host.isEmpty {
            let response = createResponse(with: ["disabled": false])
            context.completeRequest(returningItems: [response])
            return
        }

        Task { @MainActor in
            await ProtobufDataManager.shared.waitUntilLoaded()
            let disabledSites = ProtobufDataManager.shared.disabledSites
            let disabled = HostMatcher.isHostDisabled(host: host, disabledSites: disabledSites)
            let response = createResponse(with: ["disabled": disabled])
            context.completeRequest(returningItems: [response])
        }
    }

    private static func handleSetSiteDisabledState(message: [String: Any?], context: NSExtensionContext) {
        let host = (message["host"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let disabled = message["disabled"] as? Bool ?? false

        guard !host.isEmpty else {
            let response = createResponse(with: ["disabled": false, "error": "Missing host"])
            context.completeRequest(returningItems: [response])
            return
        }

        Task { @MainActor in
            await ProtobufDataManager.shared.waitUntilLoaded()

            var list = ProtobufDataManager.shared.disabledSites
            let previousList = list
            if disabled {
                if !list.contains(host) { list.append(host) }
            } else {
                // If a parent domain is disabled, remove it as well so the current host is active.
                let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                list.removeAll { entry in
                    let normalizedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if normalizedEntry.isEmpty { return true }
                    if normalizedEntry == normalizedHost { return true }
                    return normalizedHost.hasSuffix("." + normalizedEntry)
                }
            }

            // No-op writes/reloads are expensive; skip if nothing actually changed.
            guard list != previousList else {
                let effectiveDisabled = HostMatcher.isHostDisabled(host: host, disabledSites: list)
                let response = createResponse(with: [
                    "disabled": effectiveDisabled,
                    "changed": false,
                    "reloadDurationMs": 0,
                    "reloadedTargets": 0,
                    "skippedTargets": 0,
                    "failedTargets": 0
                ])
                context.completeRequest(returningItems: [response])
                return
            }

            await ProtobufDataManager.shared.setWhitelistedDomains(list)

            // Apply the change immediately by fast-updating the existing blocker JSON
            // and reloading each relevant content blocker target for the current platform.
            #if os(macOS)
            let platform: Platform = .macOS
            #else
            let platform: Platform = .iOS
            #endif

            let applyStart = Date()
            let summary = await Task.detached(priority: .userInitiated) {
                await applyDisabledSitesFastPath(disabledSites: list, platform: platform)
            }.value
            let applyDurationMs = Int(Date().timeIntervalSince(applyStart) * 1000)

            let response = createResponse(with: [
                "disabled": disabled,
                "changed": true,
                "reloadDurationMs": applyDurationMs,
                "reloadedTargets": summary.reloadedTargets,
                "skippedTargets": summary.skippedTargets,
                "failedTargets": summary.failedTargets
            ])
            context.completeRequest(returningItems: [response])
        }
    }

    private static func reloadContentBlockerWithRetry(identifier: String, maxRetries: Int = 5) async -> Bool {
        for attempt in 1...maxRetries {
            let result = await ContentBlockerService.reloadContentBlocker(withIdentifier: identifier)
            if case .success = result {
                return true
            }

            if attempt < maxRetries {
                // WKErrorDomain error 6 is often transient immediately after writing JSON files.
                let delayMs = min(200 * attempt, 1500)
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
        }
        return false
    }

    private static func applyDisabledSitesFastPath(disabledSites: [String], platform: Platform) async -> (
        reloadedTargets: Int,
        skippedTargets: Int,
        failedTargets: Int
    ) {
        let groupID = GroupIdentifier.shared.value
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: platform)

        // Update JSON for all targets, then only reload targets that actually have rules.
        var targetsToReload: [ContentBlockerTargetInfo] = []
        for target in targets {
            let updateResult = ContentBlockerService.fastUpdateDisabledSites(
                groupIdentifier: groupID,
                targetRulesFilename: target.rulesFilename,
                disabledSites: disabledSites
            )
            if updateResult.safariRulesCount > 0 {
                targetsToReload.append(target)
            }
        }

        let skippedTargets = max(targets.count - targetsToReload.count, 0)
        guard !targetsToReload.isEmpty else {
            return (reloadedTargets: 0, skippedTargets: skippedTargets, failedTargets: 0)
        }

        let results = await reloadTargetsWithRetry(targetsToReload)
        return (
            reloadedTargets: results.reloadedTargets,
            skippedTargets: skippedTargets,
            failedTargets: results.failedTargets
        )
    }

    private static func reloadTargetsWithRetry(_ targets: [ContentBlockerTargetInfo]) async -> (
        reloadedTargets: Int,
        failedTargets: Int
    ) {
        #if os(macOS)
        let maxConcurrent = 3
        #else
        let maxConcurrent = 1
        #endif

        var iterator = targets.makeIterator()
        var outcomes: [Bool] = []

        await withTaskGroup(of: Bool.self) { group in
            func enqueueNext() {
                guard let nextTarget = iterator.next() else { return }
                group.addTask {
                    await reloadContentBlockerWithRetry(identifier: nextTarget.bundleIdentifier)
                }
            }

            for _ in 0..<min(maxConcurrent, targets.count) {
                enqueueNext()
            }

            while let success = await group.next() {
                outcomes.append(success)
                enqueueNext()
            }
        }

        let reloadedTargets = outcomes.filter { $0 }.count
        let failedTargets = outcomes.count - reloadedTargets
        return (reloadedTargets: reloadedTargets, failedTargets: failedTargets)
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
                if HostMatcher.isHostDisabled(host: url.host ?? "", disabledSites: disabledSites) {
                    let response = createResponse(with: ["userScripts": []])
                    context.completeRequest(returningItems: [response])
                    return
                }
            }

            let userScriptManager = UserScriptManager.shared
            let userScripts = userScriptManager.getEnabledUserScriptsForURL(urlString)

            let userScriptDescriptors: [[String: Any]] = userScripts.map { script in
                // Prefer cached resource names, but fall back to parsing metadata so scripts
                // installed before resource caching still request the right dependencies.
                let resourceNames =
                    !script.resourceContents.isEmpty
                    ? Array(script.resourceContents.keys).sorted()
                    : UserScriptMetadataParser.extractResourceNames(from: script.content)
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

    private static func handleSyncZapperRules(message: [String: Any?], context: NSExtensionContext) {
        let hostname = (message["hostname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !hostname.isEmpty else {
            let response = createResponse(with: ["ok": false, "error": "Missing hostname"])
            context.completeRequest(returningItems: [response])
            return
        }

        Task { @MainActor in
            await ProtobufDataManager.shared.waitUntilLoaded()
            _ = await ProtobufDataManager.shared.refreshFromDiskIfModified(forceRead: true)

            // Consume any rules deleted from the app since last sync
            let pendingDeletions = await ProtobufDataManager.shared.consumeZapperPendingDeletions(forHost: hostname)
            let deletionSet = Set(pendingDeletions)

            if let rules = message["rules"] as? [String] {
                let filtered = rules
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !deletionSet.contains($0) }
                if filtered.isEmpty {
                    await ProtobufDataManager.shared.deleteAllZapperRules(forHost: hostname)
                } else {
                    await ProtobufDataManager.shared.setZapperRules(forHost: hostname, rules: filtered)
                }
                let response = createResponse(with: ["ok": true, "rules": filtered])
                context.completeRequest(returningItems: [response])
            } else {
                await ProtobufDataManager.shared.deleteAllZapperRules(forHost: hostname)
                let response = createResponse(with: ["ok": true, "rules": [String]()])
                context.completeRequest(returningItems: [response])
            }
        }
    }

    private static func handleGetZapperRules(message: [String: Any?], context: NSExtensionContext) {
        let hostname = (message["hostname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !hostname.isEmpty else {
            let response = createResponse(with: ["ok": false, "error": "Missing hostname", "rules": [String]()])
            context.completeRequest(returningItems: [response])
            return
        }

        Task { @MainActor in
            await ProtobufDataManager.shared.waitUntilLoaded()
            _ = await ProtobufDataManager.shared.refreshFromDiskIfModified(forceRead: true)
            let rules = ProtobufDataManager.shared.getZapperRules(forHost: hostname)
            let response = createResponse(with: ["ok": true, "rules": rules])
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
}
