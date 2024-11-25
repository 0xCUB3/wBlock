//
//  ContentBlockerEngineWrapper.swift
//  wBlock Origin
//
//  Created by Alexander Skula on 7/18/24.
//

import ContentBlockerEngine
import Foundation
import os.log

actor ContentBlockerEngineWrapper {
    static let shared = ContentBlockerEngineWrapper()
    private let logger = Logger(subsystem: "app.0xcube.wBlock.wBlockScripts", category: "ContentBlocker")
    private var contentBlockerEngine: ContentBlockerEngine

    private init() {
        do {
            let emptyRules = "[]"
            self.contentBlockerEngine = try ContentBlockerEngine(emptyRules)

            if let json = try? FileStorage.shared.loadJSON(filename: "advancedBlocking.json") {
                self.contentBlockerEngine = try ContentBlockerEngine(json)
                logger.debug("Successfully loaded advanced blocking rules")
            } else {
                logger.warning("Using empty rules - failed to load advanced blocking rules")
            }
        } catch {
            logger.error("Failed to initialize content blocker: \(error.localizedDescription)")
            // Fallback to empty rules
            self.contentBlockerEngine = try! ContentBlockerEngine("[]")
        }
    }

    func getData(url: URL) throws -> String {
        do {
            return try self.contentBlockerEngine.getData(url: url)
        } catch {
            logger.error("Failed to get data for URL \(url): \(error.localizedDescription)")
            throw error
        }
    }
}
