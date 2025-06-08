#!/usr/bin/env swift

import Foundation

// Test URL pattern matching
func testPatternMatching() {
    let testCases = [
        // (pattern, url, expected)
        ("*://*.youtube.com/*", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", true),
        ("*://*.youtube.com/*", "https://youtube.com/", true),
        ("*://*.youtube.com/*", "https://m.youtube.com/watch", true),
        ("*://*.youtube.com/*", "https://music.youtube.com/", true), // Note: this would be excluded separately
        ("*://*.youtube.com/*", "https://www.google.com/", false),
        ("https://example.com/*", "https://example.com/path", true),
        ("https://example.com/*", "http://example.com/path", false),
        ("*://example.com/path/*", "https://example.com/path/to/file", true),
    ]
    
    print("Testing URL pattern matching...")
    
    for (pattern, url, expected) in testCases {
        let result = matchesPattern(pattern: pattern, url: url)
        let status = result == expected ? "✅ PASS" : "❌ FAIL"
        print("\(status): '\(pattern)' vs '\(url)' -> \(result) (expected: \(expected))")
        
        if result != expected {
            print("  Generated regex: \(generateRegexPattern(from: pattern))")
        }
    }
}

func generateRegexPattern(from pattern: String) -> String {
    // Convert match pattern to regex
    var regexPattern = pattern
    
    // Handle scheme wildcard (*://)
    regexPattern = regexPattern.replacingOccurrences(of: "*://", with: "https?://")
    
    // Handle subdomain wildcard (*.) - must come before general wildcard
    regexPattern = regexPattern.replacingOccurrences(of: "*.", with: "([^.]*\\.)?")
    
    // Handle path wildcard specifically for "/*" at the end
    regexPattern = regexPattern.replacingOccurrences(of: "/*", with: "/.*")
    
    // Handle remaining wildcards
    regexPattern = regexPattern.replacingOccurrences(of: "*", with: ".*")
    
    // Escape periods in domain names but preserve regex patterns
    let components = regexPattern.components(separatedBy: "://")
    if components.count == 2 {
        let scheme = components[0]
        let rest = components[1]
        
        // Split by the first slash to separate host from path
        let hostPathComponents = rest.components(separatedBy: "/")
        if hostPathComponents.count >= 1 {
            let host = hostPathComponents[0]
            let path = hostPathComponents.dropFirst().joined(separator: "/")
            
            // Escape literal dots in the host part, but preserve regex wildcards
            let escapedHost = host
                .replacingOccurrences(of: "\\.", with: "__ESCAPED_DOT__") // Protect already escaped dots
                .replacingOccurrences(of: "([^.]*\\.)?", with: "__WILDCARD_SUBDOMAIN__") // Protect wildcard pattern
                .replacingOccurrences(of: ".", with: "\\.")                            // Escape literal dots
                .replacingOccurrences(of: "__WILDCARD_SUBDOMAIN__", with: "([^.]*\\.)?") // Restore wildcard pattern
                .replacingOccurrences(of: "__ESCAPED_DOT__", with: "\\.")              // Restore escaped dots
            
            regexPattern = scheme + "://" + escapedHost
            if !path.isEmpty {
                regexPattern += "/" + path
            }
        }
    }
    
    // Anchor the pattern to match the entire URL
    regexPattern = "^" + regexPattern + "$"
    
    return regexPattern
}

func matchesPattern(pattern: String, url: String) -> Bool {
    // Validate URL format
    guard URL(string: url) != nil else {
        return false
    }
    
    let regexPattern = generateRegexPattern(from: pattern)
    
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

testPatternMatching()
