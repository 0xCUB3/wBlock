import Foundation
import Combine
import SafariServices
import wBlockCoreService
import os.log

/// ViewModel for PopoverView, managing state and persistence
@MainActor
public class PopoverViewModel: ObservableObject {
    @Published public var blockedCount: Int = 0
    @Published public var blockedRequests: [String] = []
    @Published public var showingBlockedRequests: Bool = false
    @Published public var isDisabled: Bool = false {
        didSet {
            guard !isLoading, oldValue != isDisabled else { return }
            saveDisabledState()
        }
    }
    @Published public var host: String = ""
    @Published public var zapperRules: [String] = []
    @Published public var showingZapperRules: Bool = false

    private var isLoading: Bool = false

    private func isHostDisabled(host: String, disabledSites: [String]) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedHost.isEmpty { return false }
        for site in disabledSites {
            let disabled = site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if disabled.isEmpty { continue }
            if normalizedHost == disabled { return true }
            if normalizedHost.hasSuffix("." + disabled) { return true }
        }
        return false
    }

    /// Load current site host and disabled state
    public func loadState() async {
        isLoading = true
        do {
            guard let window = await SFSafariApplication.activeWindow(),
                  let tab = await window.activeTab(),
                  let page = await tab.activePage(),
                  let properties = await page.properties(),
                  let url = properties.url,
                  let host = url.host else {
                os_log(.info, "PopoverViewModel: Could not determine active host.")
                self.host = "Unknown"
                isLoading = false
                return
            }
            
            self.host = host
            // Reload data to ensure we have the latest
            await ProtobufDataManager.shared.waitUntilLoaded()
            _ = await ProtobufDataManager.shared.refreshFromDiskIfModified(forceRead: true)
            let list = ProtobufDataManager.shared.disabledSites
            self.isDisabled = isHostDisabled(host: host, disabledSites: list)
            
            // Load zapper rules after host is set
            await self.loadZapperRules()
            
            // Load blocked requests log for the active tab
            self.blockedRequests = await ToolbarData.shared.getBlockedURLsOnActiveTab(in: window)
            
            os_log(.info, "PopoverViewModel: Loaded state for host '%@', isDisabled: %{BOOL}d, disabled sites: %@", host, self.isDisabled, list.joined(separator: ", "))
        }
        isLoading = false
    }

    /// Save toggled disabled state for current host
    public func saveDisabledState() {
        guard !host.isEmpty else { return }
        
        Task {
            // Ensure we have the latest data before modifying
            await ProtobufDataManager.shared.waitUntilLoaded()
            var list = ProtobufDataManager.shared.disabledSites
            
            if isDisabled {
                if !list.contains(host) { list.append(host) }
            } else {
                // If a parent domain is disabled, we should remove it as well to make the current site active.
                let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                list.removeAll { entry in
                    let normalizedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if normalizedEntry.isEmpty { return true }
                    if normalizedEntry == normalizedHost { return true }
                    return normalizedHost.hasSuffix("." + normalizedEntry)
                }
            }
            
            await ProtobufDataManager.shared.setWhitelistedDomains(list)
            
            // The main app will automatically detect this change via ProtobufDataManager observer
            // and rebuild/reload all content blockers with the updated allowlist rules
            os_log(.info, "PopoverViewModel: Updated disabled sites list for host: %@, isDisabled: %{BOOL}d, final list: %@", host, isDisabled, list.joined(separator: ", "))

            // Apply to the active page immediately.
            await reloadCurrentPage()
        }
    }
    
    /// Activate the element zapper on the current page
    public func activateElementZapper() async {
        os_log(.info, "PopoverViewModel: Activating element zapper")
        
        do {
            guard let window = await SFSafariApplication.activeWindow(),
                  let tab = await window.activeTab(),
                  let page = await tab.activePage() else {
                os_log(.error, "PopoverViewModel: Failed to get active page for element zapper")
                return
            }
            
            // Send activation message to the page
            let message: [String: Any] = [
                "action": "activateZapper"
            ]
            
            page.dispatchMessageToScript(withName: "zapperController", userInfo: message)
            os_log(.info, "PopoverViewModel: Sent element zapper activation message")
            
            // Dismiss the popover after activating the zapper
            if let windowController = NSApp.keyWindow?.windowController {
                windowController.close()
            }
        }
    }
    
    /// Load zapper rules for the current host
    public func loadZapperRules() async {
        guard !host.isEmpty else {
            os_log(.info, "PopoverViewModel: Cannot load zapper rules - host is empty")
            return
        }
        await ProtobufDataManager.shared.waitUntilLoaded()
        _ = await ProtobufDataManager.shared.refreshFromDiskIfModified(forceRead: true)
        zapperRules = ProtobufDataManager.shared.getZapperRules(forHost: host)

        os_log(.info, "PopoverViewModel: Loaded %d zapper rules for host: %@", zapperRules.count, host)
    }

    /// Delete a specific zapper rule
    public func deleteZapperRule(_ rule: String) {
        guard !host.isEmpty else { return }

        Task {
            await ProtobufDataManager.shared.deleteZapperRule(rule, forHost: host)
        }

        // Update local state
        zapperRules.removeAll { $0 == rule }

        os_log(.info, "PopoverViewModel: Deleted zapper rule '%@' for host: %@, remaining: %d", rule, host, zapperRules.count)

        // Reload the page to apply changes
        Task {
            await reloadCurrentPage()
        }
    }

    /// Delete all zapper rules for the current host
    public func deleteAllZapperRules() {
        guard !host.isEmpty else { return }

        Task {
            await ProtobufDataManager.shared.deleteAllZapperRules(forHost: host)
        }

        // Update local state
        zapperRules = []

        os_log(.info, "PopoverViewModel: Deleted all zapper rules for host: %@", host)

        // Reload the page to apply changes
        Task {
            await reloadCurrentPage()
        }
    }
    
    /// Reload the current page
    private func reloadCurrentPage() async {
        do {
            guard let window = await SFSafariApplication.activeWindow(),
                  let tab = await window.activeTab(),
                  let page = await tab.activePage() else {
                os_log(.error, "PopoverViewModel: Failed to get active page for reload")
                return
            }
            
            await page.reload()
            os_log(.info, "PopoverViewModel: Reloaded current page after rule deletion")
        }
    }
    
    /// Toggle the visibility of zapper rules section
    public func toggleZapperRules() {
        showingZapperRules.toggle()
        if showingZapperRules {
            // Always reload rules when expanding to ensure fresh data
            Task {
                await loadZapperRules()
                os_log(.info, "PopoverViewModel: Toggled zapper rules visibility to %{BOOL}d, reloaded %d rules", showingZapperRules, zapperRules.count)
            }
        }
    }
    
    /// Toggle the visibility of blocked requests section
    public func toggleBlockedRequests() {
        showingBlockedRequests.toggle()
        if showingBlockedRequests {
            Task {
                await refreshBlockedRequests()
            }
        }
    }
    
    /// Refresh blocked requests log for the active tab
    public func refreshBlockedRequests() async {
        guard let window = await SFSafariApplication.activeWindow() else { return }
        blockedRequests = await ToolbarData.shared.getBlockedURLsOnActiveTab(in: window)
    }
}
