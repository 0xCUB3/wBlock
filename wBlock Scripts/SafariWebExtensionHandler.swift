//
//  SafariWebExtensionHandler.swift
//  wBlock Scripts
//
//  Created by Alexander Skula on 3/11/25.
//

import OSLog
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    static let logger = Logger(subsystem: "com.0xcube.wBlock.wBlock-Scripts", category: "SafariWebExtensionHandler")
    let engine = try? ContentBlockerEngineWrapper(appGroupID: "DNP7DGUB7B.wBlock")

    //    func beginRequest(with context: NSExtensionContext) {
    //        guard let item = context.inputItems.first as? NSExtensionItem,
    //            let userInfo = item.userInfo as? [String: Any],
    //            let message = userInfo[SFExtensionMessageKey]
    //        else {
    //            context.completeRequest(returningItems: nil, completionHandler: nil)
    //            return
    //        }
    //
    //        if let profileIdentifier = userInfo[SFExtensionProfileKey] as? UUID {
    //            // Perform profile specific tasks.
    //        } else {
    //            // Perform normal browsing tasks.
    //        }
    //
    //        // Prepare a response
    //        let response = NSExtensionItem()
    //        response.userInfo = [SFExtensionMessageKey: ["response": "Hello from Swift! You said: \(message)"]]
    //
    //        // Send the response back to JavaScript
    //        context.completeRequest(returningItems: [response], completionHandler: nil)
    //    }

    func beginRequest(with context: NSExtensionContext) {
        guard let message = context.inputItems.first as? NSExtensionItem,
            let userInfo = message.userInfo?[SFExtensionMessageKey] as? [String: Any]
        else {
            sendErrorResponse(on: context, message: "Invalid request")
            return
        }

        SafariWebExtensionHandler.logger.info("Received native message: \(userInfo.description, privacy: .public)")

        guard let action = userInfo["action"] as? String else {
            sendErrorResponse(on: context, message: "Missing action in request")
            return
        }

        switch action {
        case "getAdvancedBlockingData":
            handleBlockingDataRequest(context, userInfo: userInfo)
        default:
            sendErrorResponse(on: context, message: "Unknown action")
        }
    }

    private func handleBlockingDataRequest(_ context: NSExtensionContext, userInfo: [String: Any]) {
        guard let urlString = userInfo["url"] as? String,
            let url = URL(string: urlString)
        else {
            sendErrorResponse(on: context, message: "Invalid URL")
            return
        }

        do {
            guard let data = try engine?.getBlockingData(for: url) else {
                sendErrorResponse(on: context, message: "Error fetching blocking data")
                return
            }
            if data.utf8.count > 32_768 {
                sendChunkedResponse(context, url: urlString)
            } else {
                sendSingleResponse(on: context, data: data, url: urlString)
            }
        } catch {
            sendErrorResponse(on: context, message: "Error getting blocking data: \(error)")
        }
    }

    private func sendChunkedResponse(_ context: NSExtensionContext, url: String) {
        do {
            guard let reader = try engine?.makeChunkedReader() else {
                sendErrorResponse(on: context, message: "Error making chunked reader")
                return
            }

            let response = NSExtensionItem()
            var message: [String: Any] = [
                "url": url,
                "chunked": true,
                "more": true,
            ]

            if let chunk = reader.nextChunk() {
                message["data"] = chunk
                message["more"] = reader.progress < 1.0
            }

            response.userInfo = [SFExtensionMessageKey: message]
            complete(context: context, with: response)

        } catch {
            sendErrorResponse(on: context, message: "Error in chunked response: \(error)")
        }
    }

    private func sendSingleResponse(on context: NSExtensionContext, data: String, url: String) {
        let response = NSExtensionItem()
        response.userInfo = [
            SFExtensionMessageKey: [
                "url": url,
                "data": data,
                "chunked": false,
            ]
        ]
        complete(context: context, with: response)
    }

    private func sendErrorResponse(on context: NSExtensionContext, message: String) {
        SafariWebExtensionHandler.logger.error("\(message)")
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["error": message]]
        complete(context: context, with: response)
    }

    private func complete(context: NSExtensionContext, with item: NSExtensionItem) {
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
