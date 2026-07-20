//
//  WebExtensionRequestHandler.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 11/04/2025.
//

internal import FilterEngine
import Foundation
#if os(macOS)
import AppKit
#endif
import SafariServices
import os.log

/// WebExtensionRequestHandler processes requests from Safari Web Extensions and provides
/// content blocking configuration for web pages.
///
/// This handler receives requests from the extension's background page, looks up the
/// appropriate blocking rules for the requested URL, and returns the configuration
/// back to the extension.
public enum WebExtensionRequestHandler {
    private static let sharedWebExtensionLogFilename = "web_extension.log"

    // Reused for shared-log timestamps. Requests can be handled on concurrent
    // threads, so formatting is serialized behind a lock.
    private static let sharedLogDateFormatter = ISO8601DateFormatter()
    private static let sharedLogDateFormatterLock = NSLock()

    private static func sharedLogTimestamp() -> String {
        sharedLogDateFormatterLock.lock()
        defer { sharedLogDateFormatterLock.unlock() }
        return sharedLogDateFormatter.string(from: Date())
    }

    private static func emptyRulesPayload() -> [String: Any] {
        [
            "css": [],
            "extendedCss": [],
            "js": [],
            "scriptlets": [],
            "userScripts": [],
            "engineTimestamp": 0
        ]
    }

    @MainActor
    private static func currentDisabledSites() async -> [String] {
        await ProtobufDataManager.shared.waitUntilLoaded()
        _ = await ProtobufDataManager.shared.refreshFromDiskIfModified()
        return ProtobufDataManager.shared.disabledSites
    }

    /// Normalized union used exclusively for content filtering and RemoveParam.
    @MainActor
    private static func currentFilterDisabledSites() async -> [String] {
        await ProtobufDataManager.shared.waitUntilLoaded()
        _ = await ProtobufDataManager.shared.refreshFromDiskIfModified()
        return DisabledSitesNormalizer.effectiveFilterDisabledDomains(
            master: ProtobufDataManager.shared.disabledSites,
            filterOnly: ProtobufDataManager.shared.filterDisabledSites
        )
    }

    /// Processes an extension request and provides content blocking configuration.
    ///
    /// This method extracts the URL from the request, looks up the appropriate blocking
    /// rules using WebExtension, and returns the configuration back to the extension.
    ///
    /// - Parameters:
    ///   - context: The extension context containing the request from the extension.
    public static func beginRequest(with context: NSExtensionContext) {
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
            case "getPageUserScripts":
                handleGetPageUserScriptsRequest(message: message!, context: context)
                return
            case "getUserScriptResourceChunk":
                handleUserScriptChunkRequest(message: message!, context: context, kind: .resource)
                return
            case "setUserScriptStorageValue":
                handleSetUserScriptStorageValue(message: message!, context: context)
                return
            case "deleteUserScriptStorageValue":
                handleDeleteUserScriptStorageValue(message: message!, context: context)
                return
            case "setUserScriptSiteDisabledState":
                handleSetUserScriptSiteDisabledState(message: message!, context: context)
                return
            case "gmXmlhttpRequestNative", "gmXmlhttpRequest":
                handleNativeGMXmlhttpRequest(message: message!, context: context)
                return
            case "getBlockingPausedState":
                handleGetBlockingPausedState(context: context)
                return
            case "getSiteDisabledState":
                handleGetSiteDisabledState(message: message!, context: context)
                return
            case "setSiteDisabledState":
                handleSetSiteDisabledState(message: message!, context: context)
                return
            case "getRemoveParamDNRRules":
                handleGetRemoveParamDNRRules(message: message!, context: context)
                return
            case "syncZapperRules":
                handleSyncZapperRules(message: message!, context: context)
                return
            case "getZapperRules":
                handleGetZapperRules(message: message!, context: context)
                return
            case "setSiteZapperDisabled":
                handleSetSiteZapperDisabled(message: message!, context: context)
                return
            case "openContainingApp":
                handleOpenContainingApp(context: context)
                return
            case "logExtensionDiagnostic":
                handleLogExtensionDiagnostic(message: message!, context: context)
                return
            default:
                break
            }
        }

        let payload = message?["payload"] as? [String: Any] ?? [:]
        if let urlString = payload["url"] as? String {
            if let url = URL(string: urlString) {
                // Respect global pause and per-site disable immediately for advanced rules.
                Task { @MainActor in
                    if BlockingPauseStore.isPaused() {
                        message?["payload"] = emptyRulesPayload()
                    } else {
                        let disabledSites = await currentDisabledSites()
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
        payload["engineTimestamp"] = configuration.engineTimestamp

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
            let disabledSites = await currentDisabledSites()
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
            var list = await currentDisabledSites()
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

            // Regenerate RemoveParam DNR rules detached from the response: they are read
            // on demand from disk by handleGetRemoveParamDNRRules, so a brief staleness
            // window is harmless and removing it from the toggle's critical path keeps
            // the popup under its timeout even on profiles with many selected filters.
            let selectedFilters = ProtobufDataManager.shared.getFilterLists().filter { $0.isSelected }
            let effectiveDisabledSites = await currentFilterDisabledSites()
            Task.detached(priority: .utility) {
                do {
                    _ = try RemoveParamDNRRuleGenerator.saveRules(
                        for: selectedFilters,
                        disabledSites: effectiveDisabledSites,
                        groupIdentifier: GroupIdentifier.shared.value
                    )
                } catch {
                    os_log(.error, "Failed to refresh removeparam DNR rules for disabled site change: %@", error.localizedDescription)
                }
            }

            // Apply the change immediately by fast-updating the existing blocker JSON
            // and reloading each relevant content blocker target for the current platform.
            #if os(macOS)
            let platform: Platform = .macOS
            #else
            let platform: Platform = .iOS
            #endif

            let applyStart = Date()
            let summary = await Task.detached(priority: .userInitiated) {
                await applyDisabledSitesFastPath(disabledSites: effectiveDisabledSites, platform: platform)
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

    private static func handleGetBlockingPausedState(context: NSExtensionContext) {
        let response = createResponse(with: ["paused": BlockingPauseStore.isPaused()])
        context.completeRequest(returningItems: [response])
    }

    private static func handleGetRemoveParamDNRRules(message: [String: Any?], context: NSExtensionContext) {
        let offset = message["offset"] as? Int ?? 0
        let limit = message["limit"] as? Int ?? 250
        let payload: [String: Any]
        if BlockingPauseStore.isPaused() {
            payload = RemoveParamDNRRuleGenerator.emptyRulesPayload(offset: offset, limit: limit)
        } else {
            payload = RemoveParamDNRRuleGenerator.loadRulesPayload(
                groupIdentifier: GroupIdentifier.shared.value,
                offset: offset,
                limit: limit
            )
        }
        let response = createResponse(with: payload.mapValues { Optional($0) })
        context.completeRequest(returningItems: [response])
    }

    private static func handleOpenContainingApp(context: NSExtensionContext) {
        let opened: Bool
        let error: String?

        #if os(macOS)
        opened = NSWorkspace.shared.open(URL(string: "wblockapp://open")!)
        error = opened ? nil : "Failed to open the app"
        #else
        opened = false
        error = "Unavailable on iOS"
        #endif

        let response = createResponse(with: [
            "opened": opened,
            "error": error
        ])
        context.completeRequest(returningItems: [response])
    }

    private static func shouldIgnoreExtensionDiagnostic(_ fields: [String: String]) -> Bool {
        fields["event"] == "support_decision"
            && fields["source"] == "background"
            && fields["outcome"] == "unsupported"
            && fields["reason"] == "missing_url"
    }


    private static func handleLogExtensionDiagnostic(message: [String: Any?], context: NSExtensionContext) {
        let rawFields = message["fields"] as? [String: Any]
        let fields = rawFields?.reduce(into: [String: String]()) { partial, entry in
            partial[entry.key] = String(describing: entry.value)
        } ?? [:]
        guard !shouldIgnoreExtensionDiagnostic(fields) else {
            let response = createResponse(with: ["ok": true])
            context.completeRequest(returningItems: [response])
            return
        }

        if !fields.isEmpty {
            appendSharedWebExtensionDiagnostic(fields)
            os_log(.info, "Web extension diagnostic: %@", fields.description)
        }

        let response = createResponse(with: ["ok": true])
        context.completeRequest(returningItems: [response])
    }

    private static func appendSharedWebExtensionDiagnostic(_ fields: [String: String]) {
        let payload = fields
            .map { key, value in
                let normalized = value.replacingOccurrences(of: " ", with: "_")
                return "\(key)=\(normalized)"
            }
            .sorted()
            .joined(separator: " ")
        appendSharedWebExtensionLog("diagnostic \(payload)")
    }

    private static func appendSharedWebExtensionLog(_ line: String) {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            return
        }

        let logURL = base.appendingPathComponent(sharedWebExtensionLogFilename)
        let timestamp = sharedLogTimestamp()
        let fullLine = "[\(timestamp)] \(line)\n"

        guard let data = fullLine.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: logURL.path) {
            do {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                try? data.write(to: logURL, options: .atomic)
            }
        } else {
            try? data.write(to: logURL)
        }
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
        var updateFailures = 0
        for target in targets {
            do {
                let updateResult = try ContentBlockerService.fastUpdateDisabledSites(
                    groupIdentifier: groupID,
                    targetRulesFilename: target.rulesFilename,
                    disabledSites: disabledSites
                )
                if updateResult.safariRulesCount > 0 {
                    targetsToReload.append(target)
                }
            } catch {
                updateFailures += 1
            }
        }

        let skippedTargets = max(targets.count - targetsToReload.count - updateFailures, 0)
        guard !targetsToReload.isEmpty else {
            return (reloadedTargets: 0, skippedTargets: skippedTargets, failedTargets: updateFailures)
        }

        let results = await reloadTargetsWithRetry(targetsToReload)
        return (
            reloadedTargets: results.reloadedTargets,
            skippedTargets: skippedTargets,
            failedTargets: results.failedTargets + updateFailures
        )
    }

    private static func reloadTargetsWithRetry(_ targets: [ContentBlockerTargetInfo]) async -> (
        reloadedTargets: Int,
        failedTargets: Int
    ) {
        // Safari reloads distinct content blocker identifiers independently, so reload
        // them concurrently instead of serially. Behind the popup's 5s toggle timeout
        // a sequential loop (`for target in targets { await ... }`) was the dominant
        // cost and the reason Disable-on-this-site intermittently reported failure on
        // profiles with several selected filter lists.
        await withTaskGroup(of: Bool.self) { group in
            for target in targets {
                group.addTask {
                    await ContentBlockerService.reloadWithRetry(identifier: target.bundleIdentifier).success
                }
            }
            var reloadedTargets = 0
            var failedTargets = 0
            for await success in group {
                if success {
                    reloadedTargets += 1
                } else {
                    failedTargets += 1
                }
            }
            return (reloadedTargets: reloadedTargets, failedTargets: failedTargets)
        }
    }

    /// Returns enabled userscripts for a URL. By default this uses lightweight descriptors,
    /// but callers can request hydrated payloads to avoid repeated native chunk messages.
    private static func handleGetUserScriptsRequest(message: [String: Any?], context: NSExtensionContext) {
        // While blocking is globally paused, serve no userscripts so the paused state also
        // suppresses userscript/userstyle injection — not just the declarative blockers.
        if BlockingPauseStore.isPaused() {
            let response = createResponse(with: ["userScripts": []])
            context.completeRequest(returningItems: [response])
            return
        }

        guard let urlString = message["url"] as? String else {
            let response = createResponse(with: ["userScripts": []])
            context.completeRequest(returningItems: [response])
            return
        }

        let includeContent = message["includeContent"] as? Bool == true
        let maxInlineContentBytes = message["maxInlineContentBytes"] as? Int ?? Int.max
        Task { @MainActor in
            let disabledSites = await currentDisabledSites()
            if let url = URL(string: urlString) {
                if HostMatcher.isHostDisabled(host: url.host ?? "", disabledSites: disabledSites) {
                    let response = createResponse(with: ["userScripts": []])
                    context.completeRequest(returningItems: [response])
                    return
                }
            }

            let userScriptManager = UserScriptManager.shared
            await userScriptManager.waitUntilReady()
            let userScripts = userScriptManager.getEnabledUserScriptsForURL(urlString)

            var userScriptDescriptors: [[String: Any]] = []
            userScriptDescriptors.reserveCapacity(userScripts.count)

            // Inlining content in this single response lets the injector run a script
            // without extra native round-trips. That timing matters most for
            // `document-start` scripts (for example anti-adblock shims), which must
            // execute before the page's own code. The payload uses executable userscript
            // content with the metadata block removed; matching and UI metadata stay on
            // the native side.
            let documentStartInlineCap = max(maxInlineContentBytes, Self.documentStartInlineContentCap)
            var remainingInlineBudget = Self.totalInlineResponseBudget

            // Process timing-critical scripts first so they win the inline budget, but emit
            // descriptors in the original order the manager returned.
            let inlineOrder = userScripts.indices.sorted { lhs, rhs in
                let lhsStart = userScripts[lhs].runAt == "document-start"
                let rhsStart = userScripts[rhs].runAt == "document-start"
                if lhsStart != rhsStart { return lhsStart }
                return lhs < rhs
            }

            var descriptorsByIndex = [Int: [String: Any]](minimumCapacity: userScripts.count)

            for index in inlineOrder {
                let script = userScripts[index]

                if script.isUserStyle {
                    // Userstyles inline the effective CSS for this URL up front; there is
                    // no GM machinery, no resources, and no namespace to ship. Oversized
                    // payloads hydrate through the chunk path, which recomputes the same
                    // effective CSS from the page URL.
                    guard let css = UserStyleSupport.effectiveCSS(forContent: script.content, url: urlString) else {
                        continue
                    }
                    var descriptor: [String: Any] = [
                        "id": script.id.uuidString,
                        "kind": "style",
                        "name": script.name,
                        "version": script.version,
                        "description": script.description,
                        "runAt": "document-start",
                        "noframes": false,
                        "updateURL": script.updateURL ?? "",
                        "downloadURL": script.downloadURL ?? ""
                    ]
                    if includeContent {
                        let cssBytes = css.utf8.count
                        if cssBytes <= documentStartInlineCap, cssBytes <= remainingInlineBudget {
                            descriptor["content"] = css
                            remainingInlineBudget -= cssBytes
                        }
                    }
                    descriptorsByIndex[index] = descriptor
                    continue
                }

                // Prefer cached resource names, but fall back to parsing metadata so scripts
                // installed before resource caching still request the right dependencies.
                let resourceNames =
                    !script.resourceContents.isEmpty
                    ? Array(script.resourceContents.keys).sorted()
                    : UserScriptMetadataParser.extractResourceNames(from: script.content)
                let storageSnapshot = await UserScriptStorageManager.shared.snapshot(for: script.id.uuidString)
                let hasUnsafeWindowGrant = script.grant.contains {
                    $0.caseInsensitiveCompare("unsafeWindow") == .orderedSame
                }
                let injectInto = (script.injectInto == "auto" && hasUnsafeWindowGrant) ? "page" : script.injectInto
                let namespace = UserScriptMetadataParser.extractValue(for: "namespace", from: script.content) ?? ""

                var descriptor: [String: Any] = [
                    "id": script.id.uuidString,
                    "name": script.name,
                    "namespace": namespace,
                    "version": script.version,
                    "description": script.description,
                    "runAt": script.runAt,
                    "noframes": script.noframes,
                    "injectInto": injectInto,
                    "updateURL": script.updateURL ?? "",
                    "downloadURL": script.downloadURL ?? "",
                    "resourceNames": resourceNames,
                    "storageSnapshot": storageSnapshot
                ]
                if includeContent, !script.content.isEmpty {
                    let executableContent = script.executableContent
                    let inlinePayloadBytes = executableContent.utf8.count
                        + script.resourceContents.values.reduce(0) { $0 + $1.utf8.count }
                    let perScriptCap = script.runAt == "document-start"
                        ? documentStartInlineCap
                        : maxInlineContentBytes
                    if inlinePayloadBytes <= perScriptCap, inlinePayloadBytes <= remainingInlineBudget {
                        descriptor["content"] = executableContent
                        if !script.resourceContents.isEmpty {
                            descriptor["resources"] = script.resourceContents
                        }
                        remainingInlineBudget -= inlinePayloadBytes
                    }
                }

                descriptorsByIndex[index] = descriptor
            }

            for index in userScripts.indices {
                if let descriptor = descriptorsByIndex[index] {
                    userScriptDescriptors.append(descriptor)
                }
            }

            let response = createResponse(with: ["userScripts": userScriptDescriptors])
            context.completeRequest(returningItems: [response])
        }
    }

    /// Per-script inline allowance for `document-start` userscripts. Timing-critical
    /// scripts should arrive in the first response; scripts that still exceed this
    /// after metadata stripping fall back to chunked hydration.
    private static let documentStartInlineContentCap = 4 * 1024 * 1024

    /// Ceiling for the total inlined payload in a single `getUserScripts` response.
    /// This prevents multiple large matching scripts from producing an oversized
    /// native-messaging response.
    private static let totalInlineResponseBudget = 16 * 1024 * 1024

    private static func handleGetPageUserScriptsRequest(message: [String: Any?], context: NSExtensionContext) {
        // Mirrors the pause check above so the page‑level userscript listing also reports none.
        if BlockingPauseStore.isPaused() {
            let response = createResponse(with: ["userScripts": []])
            context.completeRequest(returningItems: [response])
            return
        }

        guard let urlString = message["url"] as? String else {
            let response = createResponse(with: ["userScripts": []])
            context.completeRequest(returningItems: [response])
            return
        }

        Task { @MainActor in
            let disabledSites = await currentDisabledSites()
            if let url = URL(string: urlString),
               HostMatcher.isHostDisabled(host: url.host ?? "", disabledSites: disabledSites)
            {
                let response = createResponse(with: ["userScripts": []])
                context.completeRequest(returningItems: [response])
                return
            }

            let manager = UserScriptManager.shared
            await manager.waitUntilReady()
            let pageScripts = manager.pageUserScripts(for: urlString)
            let descriptors = pageScripts.map { item -> [String: Any] in
                [
                    "id": item.script.id.uuidString,
                    "kind": item.script.isUserStyle ? "style" : "script",
                    "name": item.script.name,
                    "version": item.script.version,
                    "description": item.script.description,
                    "disabledForSite": item.disabledForSite,
                    "running": !item.disabledForSite
                ]
            }

            let response = createResponse(with: ["userScripts": descriptors])
            context.completeRequest(returningItems: [response])
        }
    }

    private static func handleSetUserScriptSiteDisabledState(message: [String: Any?], context: NSExtensionContext) {
        guard let scriptIDString = message["scriptId"] as? String,
              let scriptID = UUID(uuidString: scriptIDString),
              let host = message["host"] as? String
        else {
            let response = createResponse(with: ["ok": false, "error": "Missing userscript site setting payload"])
            context.completeRequest(returningItems: [response])
            return
        }

        let disabled = message["disabled"] as? Bool ?? false
        Task { @MainActor in
            let manager = UserScriptManager.shared
            await manager.waitUntilReady()
            let ok = await manager.setUserScript(
                withId: scriptID,
                disabledOnHost: host,
                disabled: disabled
            )
            let response = createResponse(with: ok
                ? ["ok": true]
                : ["ok": false, "error": "Userscript not found"])
            context.completeRequest(returningItems: [response])
        }
    }

    private static func handleSetUserScriptStorageValue(message: [String: Any?], context: NSExtensionContext) {
        guard let scriptID = message["scriptId"] as? String,
              let key = message["key"] as? String,
              let rawValue = message["rawValue"] as? String
        else {
            let response = createResponse(with: ["ok": false, "error": "Missing userscript storage payload"])
            context.completeRequest(returningItems: [response])
            return
        }

        Task {
            let result = await UserScriptStorageManager.shared.setSerializedValue(rawValue, forKey: key, scriptID: scriptID)
            let response = createResponse(with: result.ok
                ? ["ok": true]
                : ["ok": false, "error": result.error ?? "Failed to persist userscript storage"] )
            context.completeRequest(returningItems: [response])
        }
    }

    private static func handleDeleteUserScriptStorageValue(message: [String: Any?], context: NSExtensionContext) {
        guard let scriptID = message["scriptId"] as? String,
              let key = message["key"] as? String
        else {
            let response = createResponse(with: ["ok": false, "error": "Missing userscript storage payload"])
            context.completeRequest(returningItems: [response])
            return
        }

        Task {
            let result = await UserScriptStorageManager.shared.deleteValue(forKey: key, scriptID: scriptID)
            let response = createResponse(with: result.ok
                ? ["ok": true]
                : ["ok": false, "error": result.error ?? "Failed to persist userscript storage"] )
            context.completeRequest(returningItems: [response])
        }
    }

    private static func handleNativeGMXmlhttpRequest(message: [String: Any?], context: NSExtensionContext) {
        guard let urlString = message["url"] as? String,
              let url = URL(string: urlString)
        else {
            let response = createResponse(with: ["error": "Missing or invalid URL"])
            context.completeRequest(returningItems: [response])
            return
        }

        let method = ((message["method"] as? String) ?? "GET")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let headers = (message["headers"] as? [String: Any])?.reduce(into: [String: String]()) { partial, entry in
            partial[entry.key] = String(describing: entry.value)
        } ?? [:]
        let body = message["body"] as? String
        let anonymous = message["anonymous"] as? Bool ?? false
        let responseType = ((message["responseType"] as? String) ?? "text")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let overrideMimeType = (message["overrideMimeType"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let timeoutMilliseconds = message["timeout"] as? Double
            ?? (message["timeout"] as? Int).map(Double.init)
            ?? 0

        Task {
            let result = await performNativeGMXmlhttpRequest(
                url: url,
                method: method.isEmpty ? "GET" : method,
                headers: headers,
                body: body,
                anonymous: anonymous,
                responseType: responseType,
                overrideMimeType: overrideMimeType,
                timeoutMilliseconds: timeoutMilliseconds
            )
            let response = createResponse(with: result)
            context.completeRequest(returningItems: [response])
        }
    }

    private static func performNativeGMXmlhttpRequest(
        url: URL,
        method: String,
        headers: [String: String],
        body: String?,
        anonymous: Bool,
        responseType: String,
        overrideMimeType: String?,
        timeoutMilliseconds: Double
    ) async -> [String: Any?] {
        let timeoutSeconds = timeoutMilliseconds > 0 ? max(timeoutMilliseconds / 1000, 0.1) : 30
        let configuration = anonymous ? URLSessionConfiguration.ephemeral : URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = max(timeoutSeconds, 60)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        if anonymous {
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
        }

        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutSeconds)
        request.httpMethod = method
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body, !body.isEmpty, method != "GET", method != "HEAD" {
            request.httpBody = Data(body.utf8)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ["error": "Invalid HTTP response"]
            }

            let responseHeaders = httpResponse.allHeaderFields
                .compactMap { entry -> String? in
                    guard let key = entry.key as? String else { return nil }
                    return "\(key): \(String(describing: entry.value))"
                }
                .joined(separator: "\r\n")
            let isBinaryResponse = nativeGMXmlhttpResponseIsBinary(responseType)
            let responseText = isBinaryResponse ? "" : decodeNativeGMXmlhttpResponseText(data, overrideMimeType: overrideMimeType, response: httpResponse)
            let responseLength = data.count
            let expectedLength = httpResponse.expectedContentLength
            let responseTotal = expectedLength > 0 ? expectedLength : Int64(responseLength)

            return [
                "status": httpResponse.statusCode,
                "statusText": HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                "responseHeaders": responseHeaders,
                "responseText": responseText,
                "response": nativeGMXmlhttpResponseObject(data: data, responseText: responseText, responseType: responseType),
                "responseBase64": isBinaryResponse ? data.base64EncodedString() : nil,
                "responseMimeType": httpResponse.mimeType ?? "",
                "responseLength": responseLength,
                "responseTotal": responseTotal,
                "finalUrl": httpResponse.url?.absoluteString ?? url.absoluteString
            ]
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    private static func nativeGMXmlhttpResponseObject(
        data: Data,
        responseText: String,
        responseType: String
    ) -> Any? {
        if responseType == "json" {
            return try? JSONSerialization.jsonObject(with: data, options: [])
        }
        if nativeGMXmlhttpResponseIsBinary(responseType) {
            return nil
        }
        return responseText
    }

    private static func nativeGMXmlhttpResponseIsBinary(_ responseType: String) -> Bool {
        responseType == "blob" || responseType == "arraybuffer"
    }

    private static func decodeNativeGMXmlhttpResponseText(
        _ data: Data,
        overrideMimeType: String?,
        response: HTTPURLResponse
    ) -> String {
        let charset = charsetName(from: overrideMimeType)
            ?? charsetName(from: response.value(forHTTPHeaderField: "Content-Type"))
        if let charset, let encoding = stringEncoding(forCharset: charset),
           let decoded = String(data: data, encoding: encoding) {
            return decoded
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func charsetName(from contentType: String?) -> String? {
        guard let contentType else { return nil }
        return contentType
            .split(separator: ";")
            .compactMap { part -> String? in
                let pieces = part.split(separator: "=", maxSplits: 1)
                guard pieces.count == 2,
                      pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare("charset") == .orderedSame
                else { return nil }
                return pieces[1]
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            }
            .first
    }

    private static func stringEncoding(forCharset charset: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        if cfEncoding != kCFStringEncodingInvalidId {
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        }

        switch charset.lowercased() {
        case "latin1", "latin-1":
            return .isoLatin1
        default:
            return nil
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
            let disabled = ProtobufDataManager.shared.isZapperDisabled(forHost: hostname)
            let response = createResponse(with: ["ok": true, "rules": rules, "disabled": disabled])
            context.completeRequest(returningItems: [response])
        }
    }

    private static func handleSetSiteZapperDisabled(message: [String: Any?], context: NSExtensionContext) {
        let hostname = (message["hostname"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !hostname.isEmpty else {
            let response = createResponse(with: ["ok": false, "error": "Missing hostname"])
            context.completeRequest(returningItems: [response])
            return
        }

        let disabled = message["disabled"] as? Bool ?? false
        Task { @MainActor in
            await ProtobufDataManager.shared.waitUntilLoaded()
            _ = await ProtobufDataManager.shared.refreshFromDiskIfModified(forceRead: true)
            await ProtobufDataManager.shared.setZapperRulesDisabled(disabled, forHost: hostname)
            let response = createResponse(with: [
                "ok": true,
                "disabled": ProtobufDataManager.shared.isZapperDisabled(forHost: hostname),
            ])
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
        let chunkSize = message["chunkSize"] as? Int ?? 512 * 1024

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
                if script.isUserStyle, let pageURL = message["url"] as? String, !pageURL.isEmpty {
                    // Style chunks carry the same effective CSS the inline path would
                    // have produced for this page; recomputation is deterministic.
                    text = UserStyleSupport.effectiveCSS(forContent: script.content, url: pageURL)
                } else {
                    text = script.executableContent
                }
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
