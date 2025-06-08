#!/usr/bin/env swift

import Foundation

// Copy the SIMPLIFIED UserScript matching logic for testing
func matchesPattern(pattern: String, url: String) -> Bool {
    print("🔍 Testing pattern: '\(pattern)' against URL: '\(url)'")
    
    // Validate URL format
    guard URL(string: url) != nil else {
        print("❌ Invalid URL format")
        return false
    }
    
    // Simple and robust pattern matching approach
    // Convert the userscript @match pattern to a regex pattern
    var regexPattern = NSRegularExpression.escapedPattern(for: pattern)
    print("📝 Escaped pattern: \(regexPattern)")
    
    // Now selectively unescape the wildcards we want to handle
    regexPattern = regexPattern.replacingOccurrences(of: "\\*:\\/\\/", with: "(https?|ftp)://")
    print("📝 After scheme: \(regexPattern)")
    
    regexPattern = regexPattern.replacingOccurrences(of: "\\*\\.", with: "([^./]*\\.)?")
    print("📝 After subdomain: \(regexPattern)")
    
    regexPattern = regexPattern.replacingOccurrences(of: "\\/\\*", with: "/.*")
    print("📝 After path wildcard: \(regexPattern)")
    
    regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
    print("📝 After remaining wildcards: \(regexPattern)")
    
    // Anchor the pattern to match the entire URL
    regexPattern = "^" + regexPattern + "$"
    print("📝 Final regex: \(regexPattern)")
    
    do {
        let regex = try NSRegularExpression(pattern: regexPattern, options: [])
        let range = NSRange(location: 0, length: url.utf16.count)
        let match = regex.firstMatch(in: url, options: [], range: range) != nil
        print(match ? "✅ Match found!" : "❌ No match")
        return match
    } catch {
        print("❌ Regex compilation failed: \(error)")
        return false
    }
}

// Test with YouTube URLs
let pattern = "*://*.youtube.com/*"
let testUrls = [
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "https://youtube.com/watch?v=dQw4w9WgXcQ",
    "http://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
    "https://music.youtube.com/watch?v=dQw4w9WgXcQ"
]

print("Testing SIMPLIFIED YouTube pattern matching:")
print("============================================")

for url in testUrls {
    let result = matchesPattern(pattern: pattern, url: url)
    print("Result: \(result)")
    print()
}
