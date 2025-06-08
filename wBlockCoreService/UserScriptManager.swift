//
//  UserScriptManager.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 6/7/25.
//

import Foundation
import Combine
import os.log

@MainActor
public class UserScriptManager: ObservableObject {
    @Published public var userScripts: [UserScript] = []
    @Published public var isLoading: Bool = false
    @Published public var statusDescription: String = "Ready."
    @Published public var hasError: Bool = false
    @Published public var errorMessage: String = ""
    @Published public var showingUpdateSuccessAlert = false
    @Published public var showingUpdateErrorAlert = false
    @Published public var updateAlertMessage = ""
    
    private let userScriptsKey = "userScripts"
    private let sharedContainerIdentifier = "group.skula.wBlock"
    private let groupUserDefaults: UserDefaults
    private let logger = Logger(subsystem: "com.skula.wBlock", category: "UserScriptManager")
    
    private let defaultUserScripts: [(name: String, url: String)] = [
        ("Return YouTube Dislike", "https://raw.githubusercontent.com/Anarios/return-youtube-dislike/main/Extensions/UserScript/Return%20Youtube%20Dislike.user.js"),
        ("Bypass Paywalls Clean", "https://raw.githubusercontent.com/0xCUB3/Website/refs/heads/main/content/bpc.en.user.js"),
        ("YouTube Classic", "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/greasemonkey/youtube-classic.user.js")
    ]
    
    public init() {
        logger.info("🔧 UserScriptManager initializing...")
        
        // Test UserDefaults access
        logger.info("🔧 Testing UserDefaults access...")
        
        // Standard UserDefaults
        let standardDefaults = UserDefaults.standard
        standardDefaults.set("test", forKey: "wblock-test")
        let standardTest = standardDefaults.string(forKey: "wblock-test")
        logger.info("🔧 Standard UserDefaults test: \(standardTest ?? "nil")")
        
        // Group UserDefaults
        self.groupUserDefaults = UserDefaults(suiteName: sharedContainerIdentifier) ?? UserDefaults.standard
        if UserDefaults(suiteName: sharedContainerIdentifier) != nil {
            logger.info("✅ Successfully created group UserDefaults for: \(self.sharedContainerIdentifier)")
        } else {
            logger.error("❌ Failed to create group UserDefaults for: \(self.sharedContainerIdentifier), falling back to standard")
        }
        
        groupUserDefaults.set("test", forKey: "wblock-group-test")
        let groupTest = groupUserDefaults.string(forKey: "wblock-group-test")
        logger.info("🔧 Group UserDefaults test: \(groupTest ?? "nil")")
        
        // Check if userScripts key exists
        let existingData = groupUserDefaults.data(forKey: userScriptsKey)
        logger.info("🔧 Existing userScripts data: \(existingData?.count ?? 0) bytes")
        
        // List all keys in group UserDefaults
        let allKeys = Array(groupUserDefaults.dictionaryRepresentation().keys)
        logger.info("🔧 All keys in group UserDefaults: \(allKeys)")
        
        logger.info("🔧 UserScriptManager container: \(self.sharedContainerIdentifier)")
        setup()
    }
    
    private func setup() {
        logger.info("🔧 Setting up UserScriptManager...")
        checkAndCreateUserScriptsFolder()
        loadUserScripts()
        logger.info("✅ UserScriptManager initialized with \(self.userScripts.count) userscript(s)")
        statusDescription = "Initialized with \(userScripts.count) userscript(s)."
    }
    
    private func checkAndCreateUserScriptsFolder() {
        guard let containerURL = getSharedContainerURL() else {
            logger.error("❌ Failed to get shared container URL")
            return
        }
        
        let userScriptsURL = containerURL.appendingPathComponent("userscripts")
        logger.info("📁 Checking userscripts folder at: \(userScriptsURL.path)")
        
        if !FileManager.default.fileExists(atPath: userScriptsURL.path) {
            do {
                try FileManager.default.createDirectory(at: userScriptsURL, withIntermediateDirectories: true, attributes: nil)
                logger.info("✅ Created userscripts directory")
            } catch {
                logger.error("❌ Error creating userscripts directory: \(error)")
                print("Error creating userscripts directory: \(error)")
            }
        } else {
            logger.info("✅ Userscripts directory already exists")
        }
    }
    
    private func getSharedContainerURL() -> URL? {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier)
        if let url = url {
            logger.info("📁 Shared container URL: \(url.path)")
        } else {
            logger.error("❌ Failed to get shared container URL for: \(self.sharedContainerIdentifier)")
        }
        return url
    }
    
    private func loadUserScripts() {
        logger.info("📖 Loading userscripts from UserDefaults...")
        
        if let data = groupUserDefaults.data(forKey: userScriptsKey) {
            logger.info("📖 Found userscripts data in UserDefaults (\(data.count) bytes)")
            
            do {
                let savedUserScripts: [UserScript] = try JSONDecoder().decode([UserScript].self, from: data)
                logger.info("📖 Decoded \(savedUserScripts.count) userscripts from storage")
                
                userScripts = savedUserScripts
                
                // Update content from stored files
                for i in 0..<userScripts.count {
                    let script = userScripts[i]
                    logger.info("📖 Loading content for script: \(script.name) (ID: \(script.id))")
                    logger.info("📖 Script enabled: \(script.isEnabled), matches: \(script.matches)")
                    
                    if let content = readUserScriptContent(userScripts[i]) {
                        userScripts[i].content = content
                        logger.info("✅ Loaded content for \(script.name) (\(content.count) characters)")
                    } else {
                        logger.warning("⚠️ Failed to load content for \(script.name)")
                    }
                }
                
                // Check if we need to add any missing default scripts
                checkAndAddMissingDefaultScripts()
                
            } catch {
                logger.error("❌ Failed to decode userscripts: \(error)")
            }
        } else {
            logger.info("📖 No userscripts found in UserDefaults")
            // Load default userscripts for first-time users
            loadDefaultUserScripts()
        }
    }
    
    private func checkAndAddMissingDefaultScripts() {
        logger.info("🔍 Checking for missing default userscripts...")
        
        var hasAddedNew = false
        
        for defaultScript in defaultUserScripts {
            // Check if this default script already exists
            let exists = userScripts.contains { script in
                script.name == defaultScript.name || script.url?.absoluteString == defaultScript.url
            }
            
            if !exists {
                logger.info("➕ Adding missing default script: \(defaultScript.name)")
                guard let url = URL(string: defaultScript.url) else { continue }
                
                var newUserScript = UserScript(name: defaultScript.name, url: url, content: "")
                newUserScript.isEnabled = false
                newUserScript.isLocal = false
                newUserScript.description = "Default userscript - downloading..."
                newUserScript.version = "Downloading..."
                
                userScripts.append(newUserScript)
                hasAddedNew = true
            }
        }
        
        if hasAddedNew {
            saveUserScripts()
            
            // Start downloading missing scripts in the background
            Task {
                await downloadMissingDefaultScripts()
            }
        } else {
            // Check if any existing default scripts need to be downloaded
            Task {
                await downloadMissingDefaultScripts()
            }
        }
    }
    
    private func downloadMissingDefaultScripts() async {
        logger.info("📥 Checking and downloading missing default userscripts...")
        
        for i in 0..<userScripts.count {
            let script = userScripts[i]
            
            // Check if this is a default script that needs downloading
            let isDefaultScript = defaultUserScripts.contains { defaultScript in
                script.name == defaultScript.name || script.url?.absoluteString == defaultScript.url
            }
            
            if isDefaultScript && !script.isLocal && script.content.isEmpty, let url = script.url {
                await downloadUserScriptInBackground(at: i, from: url)
            }
        }
        
        await MainActor.run {
            logger.info("✅ Finished checking default userscripts")
        }
    }
    
    private func loadDefaultUserScripts() {
        logger.info("🎯 Loading default userscripts for first-time setup...")
        
        for defaultScript in defaultUserScripts {
            guard let url = URL(string: defaultScript.url) else {
                logger.error("❌ Invalid URL for default userscript: \(defaultScript.url)")
                continue
            }
            
            var newUserScript = UserScript(name: defaultScript.name, url: url, content: "")
            newUserScript.isEnabled = false // Default to disabled
            newUserScript.isLocal = false // Mark as remote
            
            // Add placeholder metadata so they show up in the list
            newUserScript.description = "Default userscript - downloading..."
            newUserScript.version = "Downloading..."
            
            userScripts.append(newUserScript)
            logger.info("✅ Added default userscript placeholder: \(defaultScript.name)")
        }
        
        if !userScripts.isEmpty {
            saveUserScripts()
            logger.info("💾 Saved \(self.userScripts.count) default userscript placeholders")
            
            // Start downloading default scripts in the background
            Task {
                await downloadDefaultUserScripts()
            }
        }
    }
    
    private func downloadDefaultUserScripts() async {
        logger.info("📥 Starting background download of default userscripts...")
        
        for i in 0..<userScripts.count {
            let script = userScripts[i]
            
            // Only download if it's a default script and not yet downloaded
            if !script.isLocal && script.content.isEmpty, let url = script.url {
                await downloadUserScriptInBackground(at: i, from: url)
            }
        }
        
        await MainActor.run {
            logger.info("✅ Finished downloading default userscripts")
            statusDescription = "Default userscripts ready"
        }
    }
    
    private func downloadUserScriptInBackground(at index: Int, from url: URL) async {
        logger.info("📥 Downloading userscript from: \(url)")
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            await MainActor.run {
                if index < userScripts.count {
                    userScripts[index].content = content
                    userScripts[index].parseMetadata()
                    
                    // Update description and version from metadata, but keep disabled
                    if userScripts[index].description.isEmpty || userScripts[index].description == "Default userscript - downloading..." {
                        userScripts[index].description = userScripts[index].description.isEmpty ? "Ready to enable" : userScripts[index].description
                    }
                    
                    if userScripts[index].version == "Downloading..." {
                        userScripts[index].version = userScripts[index].version.isEmpty ? "Downloaded" : userScripts[index].version
                    }
                    
                    _ = writeUserScriptContent(userScripts[index])
                    saveUserScripts()
                    
                    logger.info("✅ Downloaded and saved: \(self.userScripts[index].name)")
                }
            }
        } catch {
            await MainActor.run {
                if index < userScripts.count {
                    userScripts[index].description = "Download failed - tap to retry"
                    userScripts[index].version = "Error"
                    saveUserScripts()
                }
                logger.error("❌ Failed to download \(self.userScripts[index].name): \(error)")
            }
        }
    }
    
    private func saveUserScripts() {
        do {
            let data = try JSONEncoder().encode(userScripts)
            groupUserDefaults.set(data, forKey: userScriptsKey)
            logger.info("💾 Saved \(self.userScripts.count) userscripts to UserDefaults (\(data.count) bytes)")
            
            // Force synchronization
            let success = groupUserDefaults.synchronize()
            logger.info("💾 UserDefaults synchronize result: \(success)")
        } catch {
            logger.error("❌ Failed to encode userscripts for saving: \(error)")
        }
    }
    
    private func readUserScriptContent(_ userScript: UserScript) -> String? {
        guard let containerURL = getSharedContainerURL() else { return nil }
        
        let userScriptsURL = containerURL.appendingPathComponent("userscripts")
        let fileURL = userScriptsURL.appendingPathComponent("\(userScript.id.uuidString).user.js")
        
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }
    
    private func writeUserScriptContent(_ userScript: UserScript) -> Bool {
        guard let containerURL = getSharedContainerURL() else { return false }
        
        let userScriptsURL = containerURL.appendingPathComponent("userscripts")
        let fileURL = userScriptsURL.appendingPathComponent("\(userScript.id.uuidString).user.js")
        
        do {
            try userScript.content.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
            return true
        } catch {
            return false
        }
    }
    
    private func userScriptFileExists(_ userScript: UserScript) -> Bool {
        guard let containerURL = getSharedContainerURL() else { return false }
        
        let userScriptsURL = containerURL.appendingPathComponent("userscripts")
        let fileURL = userScriptsURL.appendingPathComponent("\(userScript.id.uuidString).user.js")
        
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    // MARK: - Public Methods
    
    public func addUserScript(from url: URL) async {
        await MainActor.run {
            isLoading = true
            statusDescription = "Downloading userscript..."
            hasError = false
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            await MainActor.run {
                var newUserScript = UserScript(name: url.lastPathComponent.replacingOccurrences(of: ".user.js", with: ""), url: url, content: content)
                newUserScript.parseMetadata()
                newUserScript.isEnabled = true
                
                // Check if script already exists
                if let existingIndex = userScripts.firstIndex(where: { $0.url == url }) {
                    userScripts[existingIndex] = newUserScript
                    statusDescription = "Updated userscript: \(newUserScript.name)"
                } else {
                    userScripts.append(newUserScript)
                    statusDescription = "Added userscript: \(newUserScript.name)"
                }
                
                _ = writeUserScriptContent(newUserScript)
                saveUserScripts()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                hasError = true
                errorMessage = "Failed to download userscript: \(error.localizedDescription)"
                statusDescription = "Download failed"
                isLoading = false
            }
        }
    }
    
    public func toggleUserScript(_ userScript: UserScript) {
        if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
            userScripts[index].isEnabled.toggle()
            saveUserScripts()
            statusDescription = userScripts[index].isEnabled ? "Enabled \(userScript.name)" : "Disabled \(userScript.name)"
        }
    }
    
    public func removeUserScript(_ userScript: UserScript) {
        if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
            // Remove file
            if let containerURL = getSharedContainerURL() {
                let userScriptsURL = containerURL.appendingPathComponent("userscripts")
                let fileURL = userScriptsURL.appendingPathComponent("\(userScript.id.uuidString).user.js")
                try? FileManager.default.removeItem(at: fileURL)
            }
            
            userScripts.remove(at: index)
            saveUserScripts()
            statusDescription = "Removed \(userScript.name)"
        }
    }
    
    public func updateUserScript(_ userScript: UserScript) async {
        guard let url = userScript.url else { return }
        
        await MainActor.run {
            isLoading = true
            statusDescription = "Updating \(userScript.name)..."
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            await MainActor.run {
                if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
                    var tempUserScript = UserScript(name: userScript.name, content: content)
                    tempUserScript.parseMetadata()
                    
                    userScripts[index].content = tempUserScript.content
                    userScripts[index].description = tempUserScript.description
                    userScripts[index].version = tempUserScript.version
                    userScripts[index].matches = tempUserScript.matches
                    userScripts[index].excludeMatches = tempUserScript.excludeMatches
                    userScripts[index].includes = tempUserScript.includes
                    userScripts[index].excludes = tempUserScript.excludes
                    userScripts[index].runAt = tempUserScript.runAt
                    userScripts[index].injectInto = tempUserScript.injectInto
                    userScripts[index].grant = tempUserScript.grant
                    userScripts[index].updateURL = tempUserScript.updateURL
                    userScripts[index].downloadURL = tempUserScript.downloadURL
                    
                    _ = writeUserScriptContent(userScripts[index])
                    saveUserScripts()
                    statusDescription = "Updated \(userScript.name)"
                    updateAlertMessage = "\(userScript.name) has been successfully updated."
                    showingUpdateSuccessAlert = true
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                hasError = true
                errorMessage = "Failed to update userscript: \(error.localizedDescription)"
                statusDescription = "Update failed"
                updateAlertMessage = "Failed to update \(userScript.name): \(error.localizedDescription)"
                showingUpdateErrorAlert = true
                isLoading = false
            }
        }
    }
    
    public func downloadAndEnableUserScript(_ userScript: UserScript) async {
        guard let url = userScript.url else { return }
        
        await MainActor.run {
            isLoading = true
            statusDescription = "Downloading \(userScript.name)..."
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            await MainActor.run {
                if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
                    userScripts[index].content = content
                    userScripts[index].parseMetadata()
                    userScripts[index].isEnabled = true
                    userScripts[index].isLocal = false
                    
                    _ = writeUserScriptContent(userScripts[index])
                    saveUserScripts()
                    statusDescription = "Downloaded and enabled \(userScript.name)"
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                hasError = true
                errorMessage = "Failed to download userscript: \(error.localizedDescription)"
                statusDescription = "Download failed"
                isLoading = false
            }
        }
    }
    
    public func getEnabledUserScriptsForURL(_ url: String) -> [UserScript] {
        logger.info("🎯 Getting enabled userscripts for URL: \(url)")
        logger.info("🎯 Total userscripts: \(self.userScripts.count)")
        
        let enabledScripts = userScripts.filter { $0.isEnabled }
        logger.info("🎯 Enabled userscripts: \(enabledScripts.count)")
        
        for script in enabledScripts {
            logger.info("🎯 Checking script: \(script.name)")
            logger.info("🎯   - Matches: \(script.matches)")
            logger.info("🎯   - Includes: \(script.includes)")
            logger.info("🎯   - Excludes: \(script.excludes)")
            logger.info("🎯   - ExcludeMatches: \(script.excludeMatches)")
            
            let matches = script.matches(url: url)
            logger.info("🎯   - Does it match? \(matches)")
            if !matches && script.matches.count > 0 {
                // Add detailed debugging for failed matches
                logger.info("🔍 Debugging match failure for pattern: \(script.matches[0])")
                for pattern in script.matches {
                    logger.info("🔍   Testing pattern '\(pattern)' against '\(url)'")
                }
            }
        }
        
        let matchingScripts = enabledScripts.filter { $0.matches(url: url) }
        logger.info("🎯 Final matching scripts: \(matchingScripts.count)")
        
        for script in matchingScripts {
            logger.info("✅ Matched script: \(script.name)")
        }
        
        return matchingScripts
    }
}
