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
    private let dataManager = ProtobufDataManager.shared
    private let logger = Logger(subsystem: "com.skula.wBlock", category: "UserScriptManager")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Singleton
    public static let shared = UserScriptManager()
    
    private let defaultUserScripts: [(name: String, url: String)] = [
        ("Return YouTube Dislike", "https://raw.githubusercontent.com/Anarios/return-youtube-dislike/main/Extensions/UserScript/Return%20Youtube%20Dislike.user.js"),
        ("Bypass Paywalls Clean", "https://raw.githubusercontent.com/0xCUB3/Website/refs/heads/main/content/bpc.en.user.js"),
        ("YouTube Classic", "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/greasemonkey/youtube-classic.user.js")
    ]
    
    private init() {
        logger.info("🔧 UserScriptManager initializing...")
        
        // Test UserDefaults access
        logger.info("🔧 Testing UserDefaults access...")
        
        // Standard UserDefaults
        let standardDefaults = UserDefaults.standard
        standardDefaults.set("test", forKey: "wblock-test")
        let standardTest = standardDefaults.string(forKey: "wblock-test")
        logger.info("🔧 Standard UserDefaults test: \(standardTest ?? "nil")")
        
        // Using ProtobufDataManager for data persistence
        logger.info("✅ Using ProtobufDataManager for user script persistence")
        
        // Initialize user scripts after data manager finishes loading saved data
        Task { @MainActor in
            // Wait until ProtobufDataManager has loaded existing data
            while dataManager.isLoading {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            // Load existing scripts
            self.userScripts = dataManager.getUserScripts()
            logger.info("🔧 Loaded \(self.userScripts.count) user scripts from ProtobufDataManager")

            // Initial setup (folders, defaults, downloads)
            self.setup()

            // Observe dataManager for future changes
            dataManager.$appData
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.syncFromDataManager()
                    }
                }
                .store(in: &cancellables)
            logger.info("✅ UserScriptManager data sync observer setup complete")
        }
    }
    
    private func syncFromDataManager() {
        let newUserScripts = dataManager.getUserScripts()
        logger.info("🔄 Syncing userscripts from data manager: \(newUserScripts.count) scripts")
        
        // Update content from stored files
        var updatedScripts = newUserScripts
        for i in 0..<updatedScripts.count {
            if let content = readUserScriptContent(updatedScripts[i]) {
                updatedScripts[i].content = content
            }
        }
        
        // If data manager has no scripts but we have defaults, don't sync from empty data manager
        if newUserScripts.isEmpty && !userScripts.isEmpty {
            logger.info("🔄 Data manager is empty but we have userscripts - skipping sync to preserve defaults")
            return
        }
        
        // Only update if the scripts have actually changed to avoid unnecessary UI updates
        if !areUserScriptsEqual(userScripts, updatedScripts) {
            userScripts = updatedScripts
            logger.info("✅ Updated userscripts from data manager")
        }
    }
    
    private func areUserScriptsEqual(_ scripts1: [UserScript], _ scripts2: [UserScript]) -> Bool {
        guard scripts1.count == scripts2.count else { return false }
        
        for i in 0..<scripts1.count {
            let script1 = scripts1[i]
            let script2 = scripts2[i]
            
            if script1.id != script2.id ||
               script1.isEnabled != script2.isEnabled ||
               script1.name != script2.name ||
               script1.version != script2.version ||
               script1.content != script2.content {
                return false
            }
        }
        
        return true
    }
    
    private func setup() {
        logger.info("🔧 Setting up UserScriptManager...")
        checkAndCreateUserScriptsFolder()
        loadUserScripts()
        logger.info("✅ UserScriptManager initialized with \(self.userScripts.count) userscript(s)")
        statusDescription = "Initialized with \(userScripts.count) userscript(s)."
    }
    
    /// Returns the directory URL for storing user scripts, using the shared app group container if available, otherwise falling back to Application Support.
    // MARK: - Scripts Directory Locations
    /// URL for group container scripts directory, if available
    private var groupScriptsDirectoryURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier)?
            .appendingPathComponent("userscripts")
    }
    /// URL for fallback scripts directory in Application Support
    private var fallbackScriptsDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("wBlock").appendingPathComponent("userscripts")
    }
    /// Returns appropriate scripts directory, preferring group container
    private func getUserScriptsDirectoryURL() -> URL? {
        if let groupURL = groupScriptsDirectoryURL {
            return groupURL
        }
        if let fallbackURL = fallbackScriptsDirectoryURL {
            return fallbackURL
        }
        logger.error("❌ Failed to determine user scripts directory")
        return nil
    }
    
    private func checkAndCreateUserScriptsFolder() {
        // Ensure both group and fallback directories exist
        [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.forEach { dirURL in
            logger.info("📁 Ensuring userscripts folder at: \(dirURL.path)")
            if !FileManager.default.fileExists(atPath: dirURL.path) {
                do {
                    try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
                    logger.info("✅ Created userscripts directory at: \(dirURL.path)")
                } catch {
                    logger.error("❌ Error creating userscripts directory at \(dirURL.path): \(error)")
                }
            } else {
                logger.info("✅ Userscripts directory already exists at: \(dirURL.path)")
            }
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
        logger.info("📖 Loading userscripts from ProtobufDataManager...")
        userScripts = dataManager.getUserScripts()
        logger.info("📖 Loaded \(self.userScripts.count) userscripts from ProtobufDataManager")
        
        // Always check for missing default scripts, regardless of whether we have existing scripts
        checkAndAddMissingDefaultScripts()
        
        if userScripts.isEmpty {
            logger.info("📖 No userscripts found after default check, loading defaults")
            loadDefaultUserScripts()
        } else {
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
        }
    }
    
    private func checkAndAddMissingDefaultScripts() {
        logger.info("🔍 Checking for missing default userscripts...")
        logger.info("🔍 Current userscripts count: \(self.userScripts.count)")
        logger.info("🔍 Default userscripts count: \(self.defaultUserScripts.count)")
        
        for script in userScripts {
            logger.info("🔍 Existing script: '\(script.name)' from URL: \(script.url?.absoluteString ?? "nil")")
        }
        
        var hasAddedNew = false
        
        for defaultScript in defaultUserScripts {
            logger.info("🔍 Checking default script: '\(defaultScript.name)' with URL: \(defaultScript.url)")
            
            // Check if this default script already exists
            let exists = userScripts.contains { script in
                let nameMatch = script.name == defaultScript.name
                let urlMatch = script.url?.absoluteString == defaultScript.url
                logger.info("🔍   Comparing with existing script '\(script.name)': nameMatch=\(nameMatch), urlMatch=\(urlMatch)")
                return nameMatch || urlMatch
            }
            
            if !exists {
                logger.info("➕ Adding missing default script: \(defaultScript.name)")
                guard let url = URL(string: defaultScript.url) else { 
                    logger.error("❌ Invalid URL for default script: \(defaultScript.url)")
                    continue 
                }
                
                var newUserScript = UserScript(name: defaultScript.name, url: url, content: "")
                newUserScript.isEnabled = false
                newUserScript.isLocal = false
                newUserScript.description = "Default userscript - downloading..."
                newUserScript.version = "Downloading..."
                
                userScripts.append(newUserScript)
                hasAddedNew = true
                logger.info("✅ Added default script: \(defaultScript.name)")
            } else {
                logger.info("✅ Default script already exists: \(defaultScript.name)")
            }
        }
        
        if hasAddedNew {
            logger.info("💾 Saving \(self.userScripts.count) userscripts after adding defaults")
            saveUserScripts()
            
            // Start downloading missing scripts in the background
            Task {
                await downloadMissingDefaultScripts()
            }
        } else {
            logger.info("ℹ️ No missing default scripts to add")
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
            logger.info("💾 About to save \(self.userScripts.count) default userscript placeholders")
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
        Task { @MainActor in
            logger.info("💾 Saving \(self.userScripts.count) userscripts to ProtobufDataManager")
            await dataManager.updateUserScripts(userScripts)
            logger.info("💾 Successfully saved \(self.userScripts.count) userscripts to ProtobufDataManager")
        }
    }
    
    private func readUserScriptContent(_ userScript: UserScript) -> String? {
        // Try fallback directory first (files may exist here initially)
        if let fallbackURL = fallbackScriptsDirectoryURL {
            let fileURL = fallbackURL.appendingPathComponent("\(userScript.id.uuidString).user.js")
            if FileManager.default.fileExists(atPath: fileURL.path), let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                // Migrate to group directory if available
                if let groupURL = groupScriptsDirectoryURL {
                    let destURL = groupURL.appendingPathComponent(fileURL.lastPathComponent)
                    try? FileManager.default.copyItem(at: fileURL, to: destURL)
                }
                return content
            }
        }
        // Then try group directory
        if let groupURL = groupScriptsDirectoryURL {
            let fileURL = groupURL.appendingPathComponent("\(userScript.id.uuidString).user.js")
            if FileManager.default.fileExists(atPath: fileURL.path), let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                return content
            }
        }
        return nil
    }
    
    private func writeUserScriptContent(_ userScript: UserScript) -> Bool {
        var success = false
        let fileName = "\(userScript.id.uuidString).user.js"
        [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.forEach { dirURL in
            let fileURL = dirURL.appendingPathComponent(fileName)
            do {
                try userScript.content.write(to: fileURL, atomically: true, encoding: .utf8)
                success = true
                logger.info("💾 Wrote user script to: \(fileURL.path)")
            } catch {
                logger.error("❌ Failed to write script to \(fileURL.path): \(error)")
            }
        }
        return success
    }
    
    private func userScriptFileExists(_ userScript: UserScript) -> Bool {
        let fileName = "\(userScript.id.uuidString).user.js"
        return [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.contains { dirURL in
            let filePath = dirURL.appendingPathComponent(fileName).path
            return FileManager.default.fileExists(atPath: filePath)
        }
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
    
    public func toggleUserScript(_ userScript: UserScript) async {
        // Toggle the enabled state and persist immediately
        if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
            userScripts[index].isEnabled.toggle()
            statusDescription = userScripts[index].isEnabled ? "Enabled \(userScript.name)" : "Disabled \(userScript.name)"
            // Persist the change synchronously
            logger.info("💾 Persisting userscript toggle for \(userScript.name): \(self.userScripts[index].isEnabled)")
            await dataManager.updateUserScripts(self.userScripts)
            logger.info("💾 Userscripts saved after toggle")
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
