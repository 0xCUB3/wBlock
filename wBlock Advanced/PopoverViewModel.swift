import Foundation
import Combine
import SafariServices
import wBlockCoreService

/// ViewModel for PopoverView, managing state and persistence
@MainActor
public class PopoverViewModel: ObservableObject {
    @Published public var blockedCount: Int = 0
    @Published public var isDisabled: Bool = false {
        didSet { saveDisabledState() }
    }
    @Published public var host: String = ""

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
                        }
                    }
                }
            }
        }
    }

    /// Save toggled disabled state for current host
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
        // Reload the content blocker to apply change
        // Reload the content blocker so the updated disabledSites takes effect
        if let extID = Bundle.main.bundleIdentifier {
            SFContentBlockerManager.reloadContentBlocker(withIdentifier: extID) { error in
                if let error = error {
                    print("Failed to reload content blocker: \(error.localizedDescription)")
                }
            }
        }
    }
}
