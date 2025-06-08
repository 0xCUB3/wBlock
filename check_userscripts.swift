#!/usr/bin/env swift

import Foundation

let userScriptManager = UserDefaults(suiteName: "group.skula.wBlock") ?? UserDefaults.standard

print("🔍 Checking UserDefaults for userScripts...")

// Check for userScripts
if let data = userScriptManager.data(forKey: "userScripts") {
    print("Found userScripts data: \(data.count) bytes")
    
    do {
        // Try to decode as proper UserScript array
        let decoder = JSONDecoder()
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        print("JSON structure: \(jsonObject)")
    } catch {
        print("Error decoding JSON: \(error)")
        // Try as string to see raw content
        if let str = String(data: data, encoding: .utf8) {
            print("Raw data: \(str)")
        }
    }
} else {
    print("No userScripts data found")
}

// List all keys
let allKeys = Array(userScriptManager.dictionaryRepresentation().keys)
print("All UserDefaults keys: \(allKeys)")
