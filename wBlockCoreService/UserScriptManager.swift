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
    @Published public var showingDuplicatesAlert = false
    @Published public var duplicatesMessage = ""
    @Published public var pendingDuplicatesToRemove: [UserScript] = []
    @Published public var hasCompletedInitialSetup = false
    
    private let userScriptsKey = "userScripts"
    private let initialSetupCompletedKey = "userScriptsInitialSetupCompleted"
    private let sharedContainerIdentifier = "group.skula.wBlock"
    private let dataManager = ProtobufDataManager.shared
    private let logger = Logger(subsystem: "com.skula.wBlock", category: "UserScriptManager")
    private var cancellables = Set<AnyCancellable>()
    
    // Configured URLSession for better resource management
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 0, diskPath: nil) // 2MB memory, no disk cache
        return URLSession(configuration: config)
    }()
    
    // MARK: - Singleton
    public static let shared = UserScriptManager()
    
    private let defaultUserScripts: [(name: String, url: String)] = [
        ("Return YouTube Dislike", "https://raw.githubusercontent.com/Anarios/return-youtube-dislike/main/Extensions/UserScript/Return%20Youtube%20Dislike.user.js"),
        ("Bypass Paywalls Clean", "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=userscript%2Fbpc.en.user.js"),
        ("YouTube Classic", "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/greasemonkey/youtube-classic.user.js"),
        ("AdGuard Extra", "https://userscripts.adtidy.org/release/adguard-extra/1.0/adguard-extra.user.js")
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
        logger.info("✅ Using ProtobufDataManager for userscript persistence")
        
        // Initialize userscripts after data manager finishes loading saved data
        Task { @MainActor in
            // Wait until ProtobufDataManager has loaded existing data
            while dataManager.isLoading {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            // Load existing scripts
            self.userScripts = dataManager.getUserScripts()
            logger.info("🔧 Loaded \(self.userScripts.count) userscripts from ProtobufDataManager")

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
    
    /// Simple and reliable duplicate detection - only finds truly duplicate scripts
    private func detectDuplicateUserScripts() -> [(older: UserScript, newer: UserScript)] {
        guard userScripts.count > 1 else { return [] }
        
        logger.info("🔍 Simple duplicate detection among \(self.userScripts.count) scripts...")
        
        var duplicates: [(older: UserScript, newer: UserScript)] = []
        
        // Compare each script with every other script
        for i in 0..<userScripts.count {
            for j in (i+1)..<userScripts.count {
                let script1 = userScripts[i]
                let script2 = userScripts[j]
                
                // Check if they're duplicates by URL (exact match)
                if let url1 = script1.url?.absoluteString,
                   let url2 = script2.url?.absoluteString,
                   !url1.isEmpty && !url2.isEmpty && url1 == url2 {
                    
                    logger.info("🔍 URL DUPLICATE: '\(script1.name)' vs '\(script2.name)' (URL: \(url1))")
                    
                    // Keep the enabled one, or the first one if both have same status
                    if script2.isEnabled && !script1.isEnabled {
                        duplicates.append((older: script1, newer: script2))
                    } else {
                        duplicates.append((older: script2, newer: script1))
                    }
                    continue
                }
                
                // Check if they're duplicates by name (simple case-insensitive match)
                let name1 = script1.name.lowercased().trimmingCharacters(in: .whitespaces)
                let name2 = script2.name.lowercased().trimmingCharacters(in: .whitespaces)
                
                if name1 == name2 {
                    logger.info("🔍 NAME DUPLICATE: '\(script1.name)' (v\(script1.version)) vs '\(script2.name)' (v\(script2.version))")
                    
                    // Keep the one with the newer version
                    let script1Version = parseVersionNumber(script1.version)
                    let script2Version = parseVersionNumber(script2.version)
                    
                    if script2Version > script1Version {
                        logger.info("🔍 Keeping '\(script2.name)' (v\(script2.version)) over '\(script1.name)' (v\(script1.version)) - newer version")
                        duplicates.append((older: script1, newer: script2))
                    } else if script1Version > script2Version {
                        logger.info("🔍 Keeping '\(script1.name)' (v\(script1.version)) over '\(script2.name)' (v\(script2.version)) - newer version")
                        duplicates.append((older: script2, newer: script1))
                    } else {
                        // Same version or can't parse - keep the enabled one, or the first one
                        if script2.isEnabled && !script1.isEnabled {
                            logger.info("🔍 Same version - keeping enabled '\(script2.name)' over disabled '\(script1.name)'")
                            duplicates.append((older: script1, newer: script2))
                        } else {
                            logger.info("🔍 Same version - keeping first '\(script1.name)' over '\(script2.name)'")
                            duplicates.append((older: script2, newer: script1))
                        }
                    }
                }
            }
        }
        
        logger.info("🔍 Found \(duplicates.count) duplicate pairs")
        return duplicates
    }
    
    /// Parse version string to a comparable number (e.g., "2.3.1" -> 20301)
    private func parseVersionNumber(_ version: String) -> Int {
        let cleanVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanVersion.isEmpty else { return 0 }
        
        // Extract numeric parts from version string
        let components = cleanVersion.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
            .compactMap { Int($0) }
        
        guard !components.isEmpty else { return 0 }
        
        // Convert to comparable number: major*10000 + minor*100 + patch
        var versionNumber = 0
        for (index, component) in components.prefix(3).enumerated() {
            let multiplier = [10000, 100, 1][index]
            versionNumber += component * multiplier
        }
        
        logger.info("🔍 Parsed version '\(version)' -> \(versionNumber)")
        return versionNumber
    }
    
    /// Simple removal of duplicate userscripts
    private func removeDuplicateUserScripts(_ duplicatesToRemove: [UserScript]) async {
        guard !duplicatesToRemove.isEmpty else { return }
        
        logger.info("🗑️ Removing \(duplicatesToRemove.count) duplicate userscripts...")
        
        // Get IDs of scripts to remove
        let idsToRemove = Set(duplicatesToRemove.map { $0.id })
        logger.info("🗑️ Scripts to remove by ID: \(idsToRemove)")
        
        // Remove files first
        for script in duplicatesToRemove {
            removeUserScriptFile(script)
            logger.info("🗑️ Removed file for: '\(script.name)' (ID: \(script.id))")
        }
        
        // Filter out the scripts to remove from the array
        let originalCount = userScripts.count
        userScripts = userScripts.filter { script in
            let shouldKeep = !idsToRemove.contains(script.id)
            if !shouldKeep {
                logger.info("🗑️ Filtering out script: '\(script.name)' (ID: \(script.id))")
            }
            return shouldKeep
        }
        
        logger.info("🗑️ Array size changed from \(originalCount) to \(self.userScripts.count)")
        
        // Save to protobuf immediately and await completion
        logger.info("💾 About to save \(self.userScripts.count) scripts to protobuf...")
        await dataManager.updateUserScripts(userScripts)
        logger.info("💾 Successfully saved \(self.userScripts.count) userscripts to ProtobufDataManager")
        
        // Verify the save worked by checking what's in protobuf
        let savedScripts = dataManager.getUserScripts()
        logger.info("💾 Verification: protobuf now contains \(savedScripts.count) scripts")
        
        // Log the IDs of remaining scripts for debugging
        for script in userScripts {
            logger.info("💾 Remaining in memory: '\(script.name)' (ID: \(script.id))")
        }
        for script in savedScripts {
            logger.info("💾 Saved in protobuf: '\(script.name)' (ID: \(script.id))")
        }
    }
    
    /// Compares two scripts to determine which one to keep during duplicate removal
    /// Returns true if current script should be kept, false if existing script should be kept
    private func compareScriptsForDuplicateRemoval(current: UserScript, existing: UserScript) -> Bool {
        // HIGHEST PRIORITY: Prefer enabled scripts over disabled ones
        // This prevents user-enabled scripts from being replaced by disabled defaults
        if current.isEnabled && !existing.isEnabled {
            logger.info("🔄 Keeping enabled script '\(current.name)' over disabled '\(existing.name)'")
            return true
        }
        if !current.isEnabled && existing.isEnabled {
            logger.info("🔄 Keeping enabled script '\(existing.name)' over disabled '\(current.name)'")
            return false
        }
        
        // Prefer scripts with content over empty ones
        if current.isDownloaded && !existing.isDownloaded {
            return true
        }
        if !current.isDownloaded && existing.isDownloaded {
            return false
        }
        
        // If both have lastUpdated dates, prefer the more recent one
        if let currentDate = current.lastUpdated, let existingDate = existing.lastUpdated {
            return currentDate > existingDate
        }
        
        // Prefer the one with a lastUpdated date
        if current.lastUpdated != nil && existing.lastUpdated == nil {
            return true
        }
        if current.lastUpdated == nil && existing.lastUpdated != nil {
            return false
        }
        
        // Prefer remote scripts (with URL) over local ones
        if current.url != nil && existing.url == nil {
            return true
        }
        if current.url == nil && existing.url != nil {
            return false
        }
        
        // If all else is equal, keep the current one (later in the array)
        return true
    }
    
    /// Checks for duplicates and presents confirmation dialog to user
    private func checkForDuplicatesAndAskForConfirmation() {
        let duplicatePairs = detectDuplicateUserScripts()
        
        if !duplicatePairs.isEmpty {
            let duplicatesToRemove = duplicatePairs.map { $0.older }
            pendingDuplicatesToRemove = duplicatesToRemove
            
            let duplicateNames = duplicatePairs.map { pair in
                "• '\(pair.older.name)' (keeping '\(pair.newer.name)')"
            }.joined(separator: "\n")
            
            duplicatesMessage = "Found \(duplicatePairs.count) duplicate userscript(s):\n\n\(duplicateNames)\n\nWould you like to remove the older versions?"
            
            // Use a small delay to ensure UI is ready to show the alert
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showingDuplicatesAlert = true
                self.logger.info("📋 Showing duplicate removal confirmation dialog")
            }
            
            logger.info("📋 Asking user to confirm removal of \(duplicatesToRemove.count) duplicate userscripts")
        } else {
            logger.info("✅ No duplicate userscripts found")
        }
    }
    
    /// Remove the file associated with a userscript from ALL possible locations to prevent resurrection
    private func removeUserScriptFile(_ userScript: UserScript) {
        let fileName = "\(userScript.id.uuidString).user.js"
        var totalRemoved = 0
        
        // Remove from ALL possible directory locations to prevent resurrection
        [groupScriptsDirectoryURL, fallbackScriptsDirectoryURL].compactMap { $0 }.forEach { dirURL in
            let fileURL = dirURL.appendingPathComponent(fileName)
            let locationName = dirURL.path.contains("Group Containers") ? "group container" : "application support"
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    totalRemoved += 1
                    logger.info("🗑️ Successfully removed file from \(locationName): \(fileURL.path)")
                } catch {
                    logger.error("❌ Failed to remove file from \(locationName) \(fileURL.path): \(error)")
                }
            } else {
                logger.info("ℹ️ File not found in \(locationName): \(fileURL.path)")
            }
        }
        
        if totalRemoved == 0 {
            logger.warning("⚠️ No files were found to remove for userscript: \(userScript.name) (ID: \(userScript.id))")
        } else {
            logger.info("✅ Completely removed \(totalRemoved) file(s) for userscript: \(userScript.name) - no resurrection possible")
        }
    }
    
    private func setup() {
        logger.info("🔧 Setting up UserScriptManager...")
        checkAndCreateUserScriptsFolder()
        loadUserScripts()
        logger.info("✅ UserScriptManager initialized with \(self.userScripts.count) userscript(s)")
        statusDescription = "Initialized with \(userScripts.count) userscript(s)."
    }
    
    /// Returns the directory URL for storing userscripts, using the shared app group container if available, otherwise falling back to Application Support.
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
        logger.error("❌ Failed to determine userscripts directory")
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
        
        // Check if this is the first time setup
        hasCompletedInitialSetup = UserDefaults.standard.bool(forKey: initialSetupCompletedKey)
        logger.info("🔧 Initial setup completed: \(self.hasCompletedInitialSetup)")
        
        // Always check for missing default scripts first
        checkAndAddMissingDefaultScripts()
        
        // Always check for duplicates - simplified approach
        checkForDuplicatesAndAskForConfirmation()
        
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
        
        var hasAddedNew = false
        
        for defaultScript in defaultUserScripts {
            logger.info("🔍 Checking default script: '\(defaultScript.name)'")
            
            // Simple check - does this URL already exist?
            let existsByURL = userScripts.contains { script in
                script.url?.absoluteString == defaultScript.url
            }
            
            if !existsByURL {
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
            let (data, _) = try await urlSession.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            await MainActor.run {
                if index < userScripts.count {
                    userScripts[index].content = content
                    userScripts[index].parseMetadata()
                    userScripts[index].lastUpdated = Date()
                    
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
                logger.info("💾 Wrote userscript to: \(fileURL.path)")
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
            let (data, _) = try await urlSession.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            await MainActor.run {
                var newUserScript = UserScript(name: url.lastPathComponent.replacingOccurrences(of: ".user.js", with: ""), url: url, content: content)
                newUserScript.parseMetadata()
                newUserScript.isEnabled = true
                newUserScript.lastUpdated = Date()
                
                // Check if script already exists
                if let existingIndex = userScripts.firstIndex(where: { $0.url == url }) {
                    userScripts[existingIndex] = newUserScript
                    statusDescription = "Updated userscript: \(newUserScript.name)"
                } else {
                    userScripts.append(newUserScript)
                    statusDescription = "Added userscript: \(newUserScript.name)"
                }
                
                _ = writeUserScriptContent(newUserScript)
                
                // Check for duplicates after adding a script
                checkForDuplicatesAndAskForConfirmation()
                
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

    /// Sets the enabled state for a userscript explicitly (idempotent)
    public func setUserScript(_ userScript: UserScript, isEnabled: Bool) async {
        if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
            guard userScripts[index].isEnabled != isEnabled else { return }
            userScripts[index].isEnabled = isEnabled
            statusDescription = isEnabled ? "Enabled \(userScript.name)" : "Disabled \(userScript.name)"
            logger.info("💾 Persisting userscript setEnabled for \(userScript.name): \(isEnabled)")
            await dataManager.updateUserScripts(self.userScripts)
            logger.info("💾 Userscripts saved after setEnabled")
        }
    }

    /// Batch apply enabled state using a set of IDs (single persistence write)
    public func setEnabledScripts(withIDs enabledIDs: Set<UUID>) async {
        var changed = false
        for i in userScripts.indices {
            let shouldEnable = enabledIDs.contains(userScripts[i].id)
            if userScripts[i].isEnabled != shouldEnable {
                userScripts[i].isEnabled = shouldEnable
                changed = true
            }
        }
        if changed {
            logger.info("💾 Persisting batch userscript enable states for \(enabledIDs.count) scripts")
            await dataManager.updateUserScripts(self.userScripts)
            logger.info("💾 Userscripts saved after batch setEnabled")
        } else {
            logger.info("ℹ️ No userscript enable state changes to persist (batch)")
        }
    }
    
    public func removeUserScript(_ userScript: UserScript) {
        if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
            // Remove file
            removeUserScriptFile(userScript)
            
            // Remove from memory
            userScripts.remove(at: index)
            saveUserScripts()
            statusDescription = "Removed \(userScript.name)"
            
            logger.info("🗑️ Removed userscript: '\(userScript.name)'")
        }
    }
    
    public func updateUserScript(_ userScript: UserScript) async {
        guard let url = userScript.url else { return }
        
        await MainActor.run {
            isLoading = true
            statusDescription = "Updating \(userScript.name)..."
        }
        
        do {
            let (data, _) = try await urlSession.data(from: url)
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
                    userScripts[index].lastUpdated = Date()
                    
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
            let (data, _) = try await urlSession.data(from: url)
            let content = String(data: data, encoding: .utf8) ?? ""
            
            await MainActor.run {
                if let index = userScripts.firstIndex(where: { $0.id == userScript.id }) {
                    userScripts[index].content = content
                    userScripts[index].parseMetadata()
                    userScripts[index].isEnabled = true
                    userScripts[index].isLocal = false
                    userScripts[index].lastUpdated = Date()
                    
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
    
    /// Manually triggers duplicate userscript removal and cleanup
    public func cleanupDuplicateUserScripts() {
        logger.info("🧹 Manual cleanup of duplicate userscripts requested")
        // Force duplicate detection even during initial setup when manually requested
        checkForDuplicatesAndAskForConfirmation()
    }
    
    /// Confirms removal of pending duplicate userscripts
    public func confirmDuplicateRemoval() {
        let count = pendingDuplicatesToRemove.count
        let scriptNames = pendingDuplicatesToRemove.map { $0.name }.joined(separator: ", ")
        
        logger.info("✅ User confirmed removal of \(count) duplicate userscripts: \(scriptNames)")
        
        Task { @MainActor in
            await removeDuplicateUserScripts(pendingDuplicatesToRemove)
            
            // Clear pending state
            pendingDuplicatesToRemove = []
            showingDuplicatesAlert = false
            statusDescription = "Removed \(count) duplicate userscript\(count == 1 ? "" : "s")"
            
            logger.info("🎉 Duplicate removal completed successfully")
        }
    }
    
    /// Cancels removal of pending duplicate userscripts
    public func cancelDuplicateRemoval() {
        logger.info("❌ User cancelled removal of duplicate userscripts")
        pendingDuplicatesToRemove = []
        showingDuplicatesAlert = false
        statusDescription = "Duplicate removal cancelled"
    }
    
    /// Marks the initial setup as complete and enables duplicate detection
    public func markInitialSetupComplete() {
        logger.info("✅ Marking initial setup as complete")
        hasCompletedInitialSetup = true
        UserDefaults.standard.set(true, forKey: initialSetupCompletedKey)
        
        // Now that setup is complete, check for duplicates
        checkForDuplicatesAndAskForConfirmation()
    }
    
    /// Resets initial setup state (for testing or fresh starts)
    public func resetInitialSetupState() {
        logger.info("🔄 Resetting initial setup state")
        hasCompletedInitialSetup = false
        UserDefaults.standard.removeObject(forKey: initialSetupCompletedKey)
    }
    
    /// Debug method to simulate fresh install behavior
    public func simulateFreshInstall() {
        logger.info("🧪 Simulating fresh install for testing")
        
        // Reset initial setup state
        resetInitialSetupState()
        
        // Clear all existing userscripts to simulate fresh install
        userScripts.removeAll()
        
        // Re-run setup as if it's the first time
        setup()
        
        logger.info("🧪 Fresh install simulation complete")
    }
    
    /// Force duplicate detection for testing/debugging
    public func forceDuplicateDetection() {
        logger.info("🧪 Force duplicate detection requested")
        checkForDuplicatesAndAskForConfirmation()
    }
    
}
