//
//  FileStorage.swift
//  wBlock
//
//  Created by Alexander Skula on 11/25/24.
//

import Foundation

class FileStorage {
    static let shared = FileStorage()
    
    private let groupIdentifier = AppConstants.appGroupIdentifier
    
    private init() {}

    func getContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    func saveJSON(_ jsonString: String, filename: String) throws {
        guard let containerURL = getContainerURL() else {
            throw NSError(domain: "FileStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access app group container"])
        }

        let fileURL = containerURL.appendingPathComponent(filename)
        try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func loadJSON(filename: String) throws -> String {
        guard let containerURL = getContainerURL() else {
            throw NSError(domain: "FileStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access app group container"])
        }

        let fileURL = containerURL.appendingPathComponent(filename)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
