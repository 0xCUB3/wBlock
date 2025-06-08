#!/usr/bin/env swift

import Foundation

// Test UserDefaults app group access
let sharedContainerIdentifier = "group.skula.wBlock"

print("Testing UserDefaults app group access...")
print("Container identifier: \(sharedContainerIdentifier)")

// Check standard UserDefaults
let standardDefaults = UserDefaults.standard
standardDefaults.set("test-value", forKey: "test-key")
let standardResult = standardDefaults.string(forKey: "test-key")
print("Standard UserDefaults: \(standardResult ?? "nil")")

// Check group UserDefaults
if let groupDefaults = UserDefaults(suiteName: sharedContainerIdentifier) {
    print("✅ Successfully created group UserDefaults")
    
    // Test basic read/write
    groupDefaults.set("group-test-value", forKey: "test-key")
    let groupResult = groupDefaults.string(forKey: "test-key")
    print("Group UserDefaults write/read test: \(groupResult ?? "nil")")
    
    // Check for userScripts
    let userScriptsData = groupDefaults.data(forKey: "userScripts")
    print("UserScripts data: \(userScriptsData?.count ?? 0) bytes")
    
    // List all keys
    let allKeys = Array(groupDefaults.dictionaryRepresentation().keys).sorted()
    print("All keys in group UserDefaults (\(allKeys.count) total):")
    for key in allKeys.prefix(10) {
        print("  - \(key)")
    }
    if allKeys.count > 10 {
        print("  ... and \(allKeys.count - 10) more")
    }
    
    // Check if specific app group files exist
    if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier) {
        print("Container URL: \(containerURL.path)")
        
        let prefsPath = containerURL.appendingPathComponent("Library/Preferences/\(sharedContainerIdentifier).plist")
        let prefsExists = FileManager.default.fileExists(atPath: prefsPath.path)
        print("Preferences file exists: \(prefsExists)")
        
        if prefsExists {
            // Try to read the plist directly
            if let plistData = try? Data(contentsOf: prefsPath),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
                print("Direct plist read successful, keys: \(Array(plist.keys).sorted())")
                
                if let userScriptsValue = plist["userScripts"] {
                    print("UserScripts value type: \(type(of: userScriptsValue))")
                    if let data = userScriptsValue as? Data {
                        print("UserScripts data size: \(data.count) bytes")
                        
                        // Try to decode as JSON to see the structure
                        do {
                            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                                print("Successfully decoded as JSON array with \(json.count) items")
                                
                                for (index, item) in json.enumerated() {
                                    print("  Script \(index + 1):")
                                    if let name = item["name"] as? String {
                                        print("    Name: \(name)")
                                    }
                                    if let isEnabled = item["isEnabled"] as? Bool {
                                        print("    Enabled: \(isEnabled)")
                                    }
                                    if let matches = item["matches"] as? [String] {
                                        print("    Matches: \(matches)")
                                    }
                                    if let url = item["url"] as? String {
                                        print("    URL: \(url)")
                                    }
                                }
                            } else {
                                print("Failed to decode as JSON array")
                            }
                        } catch {
                            print("JSON decode error: \(error)")
                        }
                    }
                }
            }
        }
    } else {
        print("❌ Failed to get container URL")
    }
    
} else {
    print("❌ Failed to create group UserDefaults")
}
