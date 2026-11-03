import SwiftUI
import wBlockCoreService

struct RiskyFilterEnable {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let enable: () -> Void

    init?(filter: FilterList, enable: @escaping () -> Void) {
        guard !filter.isCustom, filter.category == .experimental else { return nil }
        title = "Enable Experimental Filter?"
        message = "Experimental filters test new rules before they reach the main lists and can break websites. Enable them only if you’re comfortable finding and reporting breakage."
        self.enable = enable
    }
}
