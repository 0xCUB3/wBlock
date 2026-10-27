import SwiftUI
import wBlockCoreService

struct RiskyFilterEnable {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let enable: () -> Void

    init?(
        filter: FilterList,
        defaults: UserDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard,
        enable: @escaping () -> Void
    ) {
        guard !filter.isCustom else { return nil }
        let acknowledgedKey: String?
        if filter.name == "HaGeZi Multi Pro Mini" {
            let key = "wBlock.hasAcknowledgedHaGeZiWarning"
            guard !defaults.bool(forKey: key) else { return nil }
            acknowledgedKey = key
            title = "Enable HaGeZi Multi Pro Mini?"
            message = "HaGeZi Multi Pro Mini is better suited to a DNS blocker than Safari. Its many domain rules can consume a large share of Safari’s limited rule capacity, leaving less room for browser-focused filters, and may break websites by blocking services they need. We recommend leaving it off and using wBlock’s recommended filter lists instead."
        } else if filter.category == .experimental {
            acknowledgedKey = nil
            title = "Enable Experimental Filter?"
            message = "Experimental filters test new rules before they reach the main lists and can break websites. Enable them only if you’re comfortable finding and reporting breakage."
        } else {
            return nil
        }
        self.enable = {
            if let acknowledgedKey { defaults.set(true, forKey: acknowledgedKey) }
            enable()
        }
    }
}
