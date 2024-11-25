//
//  ContentBlockerEngineWrapper.swift
//  wBlock Origin
//
//  Created by Alexander Skula on 7/18/24.
//

import ContentBlockerEngine
import Foundation

class ContentBlockerEngineWrapper {
    private var contentBlockerEngine: ContentBlockerEngine
    nonisolated(unsafe) static let shared = ContentBlockerEngineWrapper()

    init() {
        // Initialize with empty rules first
        self.contentBlockerEngine = try! ContentBlockerEngine("[]")

        do {
            let json = try FileStorage.shared.loadJSON(filename: "advancedBlocking.json")
            self.contentBlockerEngine = try ContentBlockerEngine(json)
        } catch {
            print("Error loading advanced blocking rules: \(error)")
            // Keep the empty rules if loading fails
        }
    }

    public func getData(url: URL) -> String {
        return try! self.contentBlockerEngine.getData(url: url)
    }
}
