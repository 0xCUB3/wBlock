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
        let requiredPart: String = "group.app.0xcube.wBlock"
        let advancedBlockingURL: URL? = FileManager.default
            .containerURL(
                forSecurityApplicationGroupIdentifier: requiredPart)?.appending(
                path: "advancedBlocking.json",
                directoryHint: URL.DirectoryHint.notDirectory
            )
        let json: String = try! String(
            contentsOf: advancedBlockingURL!,
            encoding: .utf8
        )
        self.contentBlockerEngine = try! ContentBlockerEngine(json)
    }

    public func getData(url: URL) -> String {
        return try! self.contentBlockerEngine.getData(url: url)
    }
}
