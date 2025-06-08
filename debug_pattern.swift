#!/usr/bin/env swift

import Foundation

func debugPatternMatching() {
    let pattern = "*://*.youtube.com/*"
    let urls = [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/",
        "https://m.youtube.com/watch",
        "https://music.youtube.com/"
    ]
    
    print("Pattern: \(pattern)")
    print("Step-by-step transformation:")
    
    var regexPattern = pattern
    print("1. Original: \(regexPattern)")
    
    // Handle scheme wildcard (*://)
    regexPattern = regexPattern.replacingOccurrences(of: "*://", with: "https?://")
    print("2. After scheme: \(regexPattern)")
    
    // Handle subdomain wildcard (*.)
    regexPattern = regexPattern.replacingOccurrences(of: "*.", with: "([^/]*\\.)?")
    print("3. After subdomain: \(regexPattern)")
    
    // Handle path wildcard
    regexPattern = regexPattern.replacingOccurrences(of: "/*", with: "/.*")
    print("4. After path: \(regexPattern)")
    
    // Escape dots - be very careful here
    let components = regexPattern.components(separatedBy: "://")
    if components.count == 2 {
        let scheme = components[0]
        let hostAndPath = components[1]
        
        // Find where the host ends (first slash or end of string)
        let slashIndex = hostAndPath.firstIndex(of: "/") ?? hostAndPath.endIndex
        let host = String(hostAndPath[..<slashIndex])
        let path = String(hostAndPath[slashIndex...])
        
        print("5. Host part: '\(host)'")
        print("   Path part: '\(path)'")
        
        // Only escape dots that are NOT part of our regex patterns
        let escapedHost = host
            .replacingOccurrences(of: "([^/]*\\.)?", with: "__SUBDOMAIN_PATTERN__")
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "__SUBDOMAIN_PATTERN__", with: "([^/]*\\.)?")
        
        print("6. Escaped host: '\(escapedHost)'")
        
        regexPattern = scheme + "://" + escapedHost + path
    }
    
    print("7. Final regex: \(regexPattern)")
    
    // Test against URLs
    for url in urls {
        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [])
            let range = NSRange(location: 0, length: url.utf16.count)
            let matches = regex.firstMatch(in: url, options: [], range: range) != nil
            print("  \(url) -> \(matches)")
        } catch {
            print("  \(url) -> ERROR: \(error)")
        }
    }
}

debugPatternMatching()
