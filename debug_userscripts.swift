#!/usr/bin/env swift

import Foundation

struct UserScript: Codable {
    let id: UUID
    var name: String
    var url: URL?
    var isEnabled: Bool
    var description: String
    var version: String
    var matches: [String]
    var excludeMatches: [String]
    var includes: [String]
    var excludes: [String]
    var runAt: String
    var injectInto: String
    var grant: [String]
    var isLocal: Bool
    var updateURL: String?
    var downloadURL: String?
    var content: String
}

let sharedContainerIdentifier = "group.skula.wBlock"
let userScriptsKey = "userScripts"

guard let groupUserDefaults = UserDefaults(suiteName: sharedContainerIdentifier) else {
    print("Failed to access app group UserDefaults")
    exit(1)
}

guard let data = groupUserDefaults.data(forKey: userScriptsKey) else {
    print("No userScripts found in UserDefaults")
    exit(0)
}

print("Found userScripts data: \(data.count) bytes")

do {
    let userScripts = try JSONDecoder().decode([UserScript].self, from: data)
    print("Decoded \(userScripts.count) userscripts:")
    
    for (index, script) in userScripts.enumerated() {
        print("\n--- Script \(index + 1) ---")
        print("ID: \(script.id)")
        print("Name: \(script.name)")
        print("Enabled: \(script.isEnabled)")
        print("URL: \(script.url?.absoluteString ?? "nil")")
        print("Matches: \(script.matches)")
        print("Includes: \(script.includes)")
        print("Excludes: \(script.excludes)")
        print("ExcludeMatches: \(script.excludeMatches)")
        print("RunAt: \(script.runAt)")
        print("Content length: \(script.content.count)")
        
        // Test URL matching
        let testUrls = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com/",
            "https://m.youtube.com/",
            "https://www.google.com/"
        ]
        
        print("URL matching tests:")
        for testUrl in testUrls {
            let matches = script.matches(url: testUrl)
            print("  \(testUrl): \(matches)")
        }
    }
} catch {
    print("Failed to decode userScripts: \(error)")
}

extension UserScript {
    func matches(url: String) -> Bool {
        // Check @match patterns
        for pattern in matches {
            if matchesPattern(pattern: pattern, url: url) {
                // Check exclude patterns
                for excludePattern in excludeMatches {
                    if matchesPattern(pattern: excludePattern, url: url) {
                        return false
                    }
                }
                return true
            }
        }
        
        // Check @include patterns
        for pattern in includes {
            if matchesIncludePattern(pattern: pattern, url: url) {
                // Check exclude patterns
                for excludePattern in excludes {
                    if matchesIncludePattern(pattern: excludePattern, url: url) {
                        return false
                    }
                }
                return true
            }
        }
        
        return false
    }
    
    private func matchesPattern(pattern: String, url: String) -> Bool {
        // Handle @match patterns which follow a specific format: <scheme>://<host><path>
        // Examples: 
        // "*://*.youtube.com/*" should match "https://www.youtube.com/watch?v=..."
        // "https://example.com/*" should match "https://example.com/path"
        
        // Validate URL format
        guard URL(string: url) != nil else {
            return false
        }
        
        // Convert match pattern to regex
        var regexPattern = pattern
        
        // Handle scheme wildcard (*://)
        regexPattern = regexPattern.replacingOccurrences(of: "*://", with: "https?://")
        
        // Handle subdomain wildcard (*.)
        regexPattern = regexPattern.replacingOccurrences(of: "*.", with: "(.*\\.)?")
        
        // Handle path wildcard (*)
        regexPattern = regexPattern.replacingOccurrences(of: "/*", with: "/.*")
        regexPattern = regexPattern.replacingOccurrences(of: "*", with: ".*")
        
        // Escape periods in domain names but not in regex we just created
        let components = regexPattern.components(separatedBy: "://")
        if components.count == 2 {
            let scheme = components[0]
            let rest = components[1]
            
            // Split by the first slash to separate host from path
            let hostPathComponents = rest.components(separatedBy: "/")
            if hostPathComponents.count >= 1 {
                let host = hostPathComponents[0]
                let path = hostPathComponents.dropFirst().joined(separator: "/")
                
                // Only escape dots in the host part that aren't part of regex wildcards
                let escapedHost = host
                    .replacingOccurrences(of: "\\.", with: "__DOT__") // Protect already escaped dots
                    .replacingOccurrences(of: ".", with: "\\.")       // Escape literal dots
                    .replacingOccurrences(of: "__DOT__", with: "\\.")  // Restore escaped dots
                
                regexPattern = scheme + "://" + escapedHost
                if !path.isEmpty {
                    regexPattern += "/" + path
                }
            }
        }
        
        // Anchor the pattern to match the entire URL
        regexPattern = "^" + regexPattern + "$"
        
        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [])
            let range = NSRange(location: 0, length: url.utf16.count)
            return regex.firstMatch(in: url, options: [], range: range) != nil
        } catch {
            // If regex compilation fails, fall back to simple string matching
            print("Regex compilation failed for pattern: \(pattern), error: \(error)")
            return false
        }
    }
    
    private func matchesIncludePattern(pattern: String, url: String) -> Bool {
        // Basic include pattern implementation (supports * wildcards)
        let regexPattern = pattern
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: ".", with: "\\.")
        
        if let regex = try? NSRegularExpression(pattern: regexPattern) {
            let range = NSRange(location: 0, length: url.utf16.count)
            return regex.firstMatch(in: url, options: [], range: range) != nil
        }
        
        return false
    }
}
