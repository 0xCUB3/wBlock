//
//  FileStorage.swift
//  wBlock
//
//  Created by Alexander Skula on 11/25/24.
//

import Foundation

class FileStorage {
    static let shared = FileStorage()
    private let groupIdentifier = "DNP7DGUB7B.wBlock"
    
    private lazy var cachedContainerURL: URL? = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }()
    
    private let fileManager = FileManager.default
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    
    private init() {}
    
    func getContainerURL() -> URL? {
        return cachedContainerURL
    }
    
    func saveJSON(_ jsonString: String, filename: String) throws {
        guard let containerURL = cachedContainerURL else {
            throw NSError(domain: "FileStorage",
                         code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Cannot access app group container"])
        }
        
        let fileURL = containerURL.appendingPathComponent(filename)
        
        try jsonString.write(to: fileURL,
                           atomically: true,
                           encoding: .utf8)
    }
    
    func loadJSON(filename: String) throws -> String {
        guard let containerURL = cachedContainerURL else {
            throw NSError(domain: "FileStorage",
                         code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Cannot access app group container"])
        }
        
        let fileURL = containerURL.appendingPathComponent(filename)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
    
    func clearCache() {
        // Method to clear cached URLs if needed
        if let containerURL = cachedContainerURL {
            try? fileManager.removeItem(at: containerURL)
        }
    }
}
