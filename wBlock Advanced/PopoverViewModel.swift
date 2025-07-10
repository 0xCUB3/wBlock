import Foundation
import Combine
import SafariServices
import wBlockCoreService
import os.log

/// ViewModel for PopoverView, managing state and persistence
@MainActor
public class PopoverViewModel: ObservableObject {
    @Published public var blockedCount: Int = 0
    @Published public var isDisabled: Bool = false {
        didSet { saveDisabledState() }
    }
    @Published public var host: String = ""
    @Published public var zapperRules: [String] = []
    @Published public var showingZapperRules: Bool = false

    private let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)

    /// Load current site host and disabled state
    public func loadState() {
        SFSafariApplication.getActiveWindow { window in
            window?.getActiveTab { tab in
                tab?.getActivePage { optionalPage in
                    guard let page = optionalPage else { return }
                    page.getPropertiesWithCompletionHandler() { properties in
                        guard let props = properties,
                              let url = props.url,
                              let host = url.host else { return }
                        Task { @MainActor in
                            self.host = host
                            let list = self.defaults?.stringArray(forKey: "disabledSites") ?? []
                            self.isDisabled = list.contains(host)
                            self.loadZapperRules() // Load zapper rules when state is loaded
                            os_log(.info, "PopoverViewModel: Loaded state for host '%@', isDisabled: %{BOOL}d, disabled sites: %@", host, self.isDisabled, list.joined(separator: ", "))
                        }
                    }
                }
            }
        }
    }

    /// Save toggled disabled state for current host
    public func saveDisabledState() {
        guard !host.isEmpty else { return }
        var list = defaults?.stringArray(forKey: "disabledSites") ?? []
        if isDisabled {
            if !list.contains(host) { list.append(host) }
        } else {
            list.removeAll { $0 == host }
        }
        defaults?.setValue(list, forKey: "disabledSites")
        
        // The main app will automatically detect this change via UserDefaults observer
        // and rebuild/reload all content blockers with the updated allowlist rules
        os_log(.info, "PopoverViewModel: Updated disabled sites list for host: %@, isDisabled: %{BOOL}d, final list: %@", host, isDisabled, list.joined(separator: ", "))
    }
    
    /// Activate the element zapper on the current page
    public func activateElementZapper() {
        os_log(.info, "PopoverViewModel: Activating element zapper")
        
        SFSafariApplication.getActiveWindow { window in
            window?.getActiveTab { tab in
                tab?.getActivePage { optionalPage in
                    guard let page = optionalPage else {
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
                    DispatchQueue.main.async {
                        if let windowController = NSApp.keyWindow?.windowController {
                            windowController.close()
                        }
                    }
                }
            }
        }
    }
    
    /// Load zapper rules for the current host
    public func loadZapperRules() {
        guard !host.isEmpty else { return }
        let key = "zapperRules_\(host)"
        zapperRules = defaults?.stringArray(forKey: key) ?? []
        os_log(.info, "PopoverViewModel: Loaded %d zapper rules for host: %@", zapperRules.count, host)
    }
    
    /// Delete a specific zapper rule
    public func deleteZapperRule(_ rule: String) {
        guard !host.isEmpty else { return }
        let key = "zapperRules_\(host)"
        var rules = defaults?.stringArray(forKey: key) ?? []
        rules.removeAll { $0 == rule }
        defaults?.setValue(rules, forKey: key)
        defaults?.synchronize()
        
        // Update local state
        zapperRules = rules
        
        os_log(.info, "PopoverViewModel: Deleted zapper rule '%@' for host: %@, remaining: %d", rule, host, rules.count)
    }
    
    /// Delete all zapper rules for the current host
    public func deleteAllZapperRules() {
        guard !host.isEmpty else { return }
        let key = "zapperRules_\(host)"
        defaults?.removeObject(forKey: key)
        defaults?.synchronize()
        
        // Update local state
        zapperRules = []
        
        os_log(.info, "PopoverViewModel: Deleted all zapper rules for host: %@", host)
    }
    
    /// Toggle the visibility of zapper rules section
    public func toggleZapperRules() {
        showingZapperRules.toggle()
        if showingZapperRules {
            loadZapperRules()
        }
    }
}
