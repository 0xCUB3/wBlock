#!/usr/bin/env swift

import Foundation

// Test the final pattern matching logic
func matchesPattern(pattern: String, url: String) -> Bool {
    guard URL(string: url) != nil else {
        return false
    }
    
    var regexPattern = NSRegularExpression.escapedPattern(for: pattern)
    regexPattern = regexPattern.replacingOccurrences(of: "\\*:\\/\\/", with: "(https?|ftp)://")
    regexPattern = regexPattern.replacingOccurrences(of: "\\*\\.", with: "([^/]*\\.)?")
    regexPattern = regexPattern.replacingOccurrences(of: "\\/\\*", with: "/.*")
    regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
    regexPattern = "^" + regexPattern + "$"
    
    do {
        let regex = try NSRegularExpression(pattern: regexPattern, options: [])
        let range = NSRange(location: 0, length: url.utf16.count)
        return regex.firstMatch(in: url, options: [], range: range) != nil
    } catch {
        print("❌ Regex error: \(error)")
        return false
    }
}

// Test various patterns and URLs
let tests = [
    // YouTube tests
    ("*://*.youtube.com/*", "https://www.youtube.com/watch?v=123", true),
    ("*://*.youtube.com/*", "https://youtube.com/watch?v=123", true),
    ("*://*.youtube.com/*", "https://m.youtube.com/watch?v=123", true),
    ("*://*.youtube.com/*", "https://example.com/watch?v=123", false),
    
    // Other patterns
    ("https://example.com/*", "https://example.com/path", true),
    ("https://example.com/*", "http://example.com/path", false),
    ("*://example.com/*", "https://example.com/path", true),
    ("*://example.com/*", "http://example.com/path", true),
    
    // Subdomain tests
    ("*://*.example.com/*", "https://sub.example.com/path", true),
    ("*://*.example.com/*", "https://example.com/path", true),
    ("*://*.example.com/*", "https://deep.sub.example.com/path", true),
]

print("Testing comprehensive pattern matching:")
print("======================================")

var passed = 0
var failed = 0

for (pattern, url, expected) in tests {
    let result = matchesPattern(pattern: pattern, url: url)
    let status = result == expected ? "✅ PASS" : "❌ FAIL"
    print("\(status): '\(pattern)' vs '\(url)' -> \(result) (expected: \(expected))")
    
    if result == expected {
        passed += 1
    } else {
        failed += 1
    }
}

print("\nResults: \(passed) passed, \(failed) failed")
