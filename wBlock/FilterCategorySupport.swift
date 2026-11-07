import Foundation
import wBlockCoreService

enum FilterCategorySupport {
    /// Only categories whose choices aren't obvious explain themselves: Regional
    /// picks languages, and Annoyances mixes lists from three projects, none
    /// on by default. Every other category has no info button (#1087).
    static func descriptionKey(for category: FilterListCategory) -> String? {
        switch category {
        case .annoyances: "Removes cookie notices, pop-ups, banners, and other distracting elements."
        case .foreign: "Lists for websites and languages of specific regions."
        default: nil
        }
    }
}
