import Foundation
import SwiftUI
import wBlockCoreService

/// Core Protection instrument bundles shown in Basic mode's 3-up trio.
/// Members are derived directly from `FilterListLoader.recommendedFilterNames`
/// split by category so there is never a duplicate filter table.
enum CoreProtectionBundle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case ads
    case privacy
    case security

    var id: String { rawValue }

    var category: FilterListCategory {
        switch self {
        case .ads: .ads
        case .privacy: .privacy
        case .security: .security
        }
    }

    /// Keep the real category name ("Privacy", not a synonym) so Basic and
    /// Advanced never give two names to one thing.
    var titleKey: String {
        switch self {
        case .ads: "Ads"
        case .privacy: "Privacy"
        case .security: "Security"
        }
    }

    var localizedTitle: String {
        NSLocalizedString(titleKey, comment: "Core protection bundle title")
    }

    var subtitle: String {
        switch self {
        case .ads:
            NSLocalizedString("Blocks most ads on websites and videos.", comment: "Ads core bundle description")
        case .privacy:
            NSLocalizedString("Stops most trackers that follow you around the web and strips tracking from links.", comment: "Privacy core bundle description")
        case .security:
            NSLocalizedString("Blocks sites known to carry malware, scams, and phishing attempts.", comment: "Security core bundle description")
        }
    }

    var examples: [String] {
        switch self {
        case .ads:
            [
                NSLocalizedString("Stops online ads from bothering you", comment: "Ads example 1"),
                NSLocalizedString("Prevents sneaky hidden ads", comment: "Ads example 2"),
                NSLocalizedString("Removes annoying banner ads", comment: "Ads example 3"),
            ]
        case .privacy:
            [
                NSLocalizedString("Keeps your info safe from trackers", comment: "Privacy example 1"),
                NSLocalizedString("Blocks websites from spying on you", comment: "Privacy example 2"),
                NSLocalizedString("Limits how much is tracked about you", comment: "Privacy example 3"),
            ]
        case .security:
            [
                NSLocalizedString("Guards against dangerous website tricks", comment: "Security example 1"),
                NSLocalizedString("Shields your device from bad sites", comment: "Security example 2"),
                NSLocalizedString("Reduces the risk of nasty surprises online", comment: "Security example 3"),
            ]
        }
    }

    /// Shield glyphs are reserved strictly for the Hero medallion.
    var symbolName: String {
        switch self {
        case .ads: "nosign"
        case .privacy: "eye.slash.fill"
        case .security: "lock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ads: Color(red: 0.90, green: 0.27, blue: 0.27)
        case .privacy: Color(red: 0.20, green: 0.49, blue: 0.96)
        case .security: Color(red: 0.35, green: 0.34, blue: 0.84)
        }
    }
}

/// Visual metadata for `AnnoyanceChoice` rows in Basic mode and Onboarding.
extension AnnoyanceChoice {
    var symbolName: String {
        switch self {
        case .cookies: "doc.plaintext.fill"
        case .popups: "macwindow.badge.plus"
        case .banners: "iphone"
        case .social: "bubble.left.and.bubble.right.fill"
        case .chat: "message.fill"
        case .general: "sparkles.rectangle.stack.fill"
        case .ai: "cpu.fill"
        }
    }

    var tint: Color {
        switch self {
        case .cookies: Color(red: 0.93, green: 0.54, blue: 0.14)
        case .popups: Color(red: 0.91, green: 0.29, blue: 0.49)
        case .banners: Color(red: 0.15, green: 0.67, blue: 0.66)
        case .social: Color(red: 0.62, green: 0.36, blue: 0.88)
        case .chat: Color(red: 0.15, green: 0.62, blue: 0.89)
        case .general: Color(red: 0.48, green: 0.50, blue: 0.55)
        case .ai: Color(red: 0.45, green: 0.39, blue: 0.90)
        }
    }

    var examples: [String] {
        switch self {
        case .cookies:
            [
                NSLocalizedString("Hides annoying cookie choice banners", comment: "Cookies example 1"),
                NSLocalizedString("Skips those \"We use cookies\" pop-ups", comment: "Cookies example 2"),
                NSLocalizedString("Lets you avoid cookie consent clicks", comment: "Cookies example 3"),
            ]
        case .popups:
            [
                NSLocalizedString("Stops those sudden window pop-ups", comment: "Popups example 1"),
                NSLocalizedString("Hides newsletter and promo pop-ups", comment: "Popups example 2"),
                NSLocalizedString("Blocks site notification prompts", comment: "Popups example 3"),
            ]
        case .banners:
            [
                NSLocalizedString("Removes the \"Install app\" pushy banners", comment: "Banners example 1"),
                NSLocalizedString("Hides those irritating download prompts", comment: "Banners example 2"),
                NSLocalizedString("Stops sites from forcing you to get apps", comment: "Banners example 3"),
            ]
        case .social:
            [
                NSLocalizedString("Takes off social media buttons", comment: "Social example 1"),
                NSLocalizedString("Erases \"Like\" and share icons on sites", comment: "Social example 2"),
                NSLocalizedString("Removes those distracting social links", comment: "Social example 3"),
            ]
        case .chat:
            [
                NSLocalizedString("Skips those intrusive chat windows", comment: "Chat example 1"),
                NSLocalizedString("Hides chat invitations on sites", comment: "Chat example 2"),
                NSLocalizedString("Removes pushy \"Talk to us\" pop-ups", comment: "Chat example 3"),
            ]
        case .general:
            [
                NSLocalizedString("Makes web pages cleaner and neater", comment: "General annoyances example 1"),
                NSLocalizedString("Removes distracting elements from sites", comment: "General annoyances example 2"),
                NSLocalizedString("Helps pages look less cluttered", comment: "General annoyances example 3"),
            ]
        case .ai:
            [
                NSLocalizedString("Hides AI summaries on search pages", comment: "AI example 1"),
                NSLocalizedString("Hides AI chat and assistant buttons on sites", comment: "AI example 2"),
                NSLocalizedString("Removes AI sidebars and widgets", comment: "AI example 3"),
            ]
        }
    }

    /// Primary everyday annoyances shown directly in Standard Filters and Onboarding.
    static func basicPrimaryChoices(includeMobileAppBanners: Bool = defaultIncludesMobileAppBanners) -> [AnnoyanceChoice] {
        includeMobileAppBanners ? [.cookies, .popups, .banners] : [.cookies, .popups]
    }

    /// Opinionated / stricter annoyance bundles housed behind the expandable
    /// "Stricter Blocking" row in Standard Filters.
    static let basicStricterChoices: [AnnoyanceChoice] = [.social, .chat, .general, .ai]

    static var defaultIncludesMobileAppBanners: Bool {
        true
    }

    /// Legacy EasyList names that swap into this choice, derived from `FilterListLoader`
    /// so there is no second hardcoded table.
    var legacyEquivalentFilterNames: Set<String> {
        var names = Set<String>()
        let targets = Set(filterNames)
        for (oldName, newName) in FilterListLoader.adGuardAnnoyanceSwaps where targets.contains(newName) {
            names.insert(oldName)
        }
        for (oldName, newNames) in FilterListLoader.adGuardTopicAnnoyanceSwaps where !targets.isDisjoint(with: newNames) {
            names.insert(oldName)
        }
        return names
    }
}

/// Derived activation state for a Basic mode bundle. Never persisted.
enum BasicBundleState: Equatable, Sendable {
    case off
    case on
    case partlyOn

    var accessibilityLabel: String {
        switch self {
        case .off: NSLocalizedString("Off", comment: "Bundle state")
        case .on: NSLocalizedString("On", comment: "Bundle state")
        case .partlyOn: NSLocalizedString("Custom", comment: "Bundle state")
        }
    }
}

/// Unified identifier and pure derivation engine for Basic mode bundles.
enum BasicBundle: Hashable, Identifiable, Sendable {
    case core(CoreProtectionBundle)
    case annoyance(AnnoyanceChoice)

    var id: String {
        switch self {
        case .core(let core): "core.\(core.rawValue)"
        case .annoyance(let choice): "annoyance.\(choice.rawValue)"
        }
    }

    static var allCases: [BasicBundle] {
        CoreProtectionBundle.allCases.map(Self.core) + AnnoyanceChoice.allCases.map(Self.annoyance)
    }

    var titleKey: String {
        switch self {
        case .core(let core): core.titleKey
        case .annoyance(let choice): choice.title
        }
    }

    var localizedTitle: String {
        NSLocalizedString(titleKey, comment: "Basic bundle title")
    }

    var subtitle: String {
        switch self {
        case .core(let core): core.subtitle
        case .annoyance(let choice): choice.subtitle
        }
    }

    var examples: [String] {
        switch self {
        case .core(let core): core.examples
        case .annoyance(let choice): choice.examples
        }
    }

    var symbolName: String {
        switch self {
        case .core(let core): core.symbolName
        case .annoyance(let choice): choice.symbolName
        }
    }

    var tint: Color {
        switch self {
        case .core(let core): core.tint
        case .annoyance(let choice): choice.tint
        }
    }

    var category: FilterListCategory {
        switch self {
        case .core(let core): core.category
        case .annoyance: .annoyances
        }
    }

    /// Built-in lists owned by this bundle.
    func ownedFilters(
        in filters: [FilterList],
        recommendedNames: Set<String> = FilterListLoader.recommendedFilterNames
    ) -> [FilterList] {
        switch self {
        case .core(let core):
            return filters.filter { !$0.isCustom && $0.category == core.category }
        case .annoyance(let choice):
            let names = Set(choice.filterNames).union(choice.legacyEquivalentFilterNames)
            return filters.filter { !$0.isCustom && $0.category == .annoyances && names.contains($0.name) }
        }
    }

    /// Built-in lists that turning this bundle ON (fresh / reset) enables.
    func memberFilters(
        in filters: [FilterList],
        recommendedNames: Set<String> = FilterListLoader.recommendedFilterNames
    ) -> [FilterList] {
        switch self {
        case .core(let core):
            return filters.filter {
                !$0.isCustom && $0.category == core.category && recommendedNames.contains($0.name)
            }
        case .annoyance(let choice):
            let names = Set(choice.filterNames)
            return filters.filter { !$0.isCustom && $0.category == .annoyances && names.contains($0.name) }
        }
    }

    /// Derives `.off`, `.on`, or `.partlyOn` directly from `filters`.
    func state(
        in filters: [FilterList],
        recommendedNames: Set<String> = FilterListLoader.recommendedFilterNames
    ) -> BasicBundleState {
        let owned = ownedFilters(in: filters, recommendedNames: recommendedNames)
        let selectedOwnedIDs = Set(owned.filter(\.isSelected).map(\.id))
        if selectedOwnedIDs.isEmpty {
            return .off
        }
        let memberIDs = Set(memberFilters(in: filters, recommendedNames: recommendedNames).map(\.id))
        if !memberIDs.isEmpty && selectedOwnedIDs == memberIDs {
            return .on
        }
        return .partlyOn
    }

    /// Lists shown in this bundle's scoped "All N lists" sheet.
    /// Core bundles include custom lists placed in that category so they live
    /// in their category instead of being duplicated under "Also on".
    func scopedFilters(
        in filters: [FilterList],
        recommendedNames: Set<String> = FilterListLoader.recommendedFilterNames
    ) -> [FilterList] {
        switch self {
        case .core(let core):
            return filters.filter { $0.category == core.category }
        case .annoyance(let choice):
            let owned = ownedFilters(in: filters, recommendedNames: recommendedNames)
            if !owned.isEmpty { return owned }
            return filters.filter { !$0.isCustom && $0.category == .annoyances && choice.filterNames.contains($0.name) }
        }
    }

    /// Concise differentiating note for a filter list inside Standard mode's
    /// inline bundle list dropdown. Returns `nil` when the bundle header and
    /// examples already cover what the list does.
    static func concisePeekNote(for filter: FilterList) -> String? {
        if filter.isCustom {
            let trimmed = filter.localizedDisplayDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        switch filter.name {
        case "uBlock filters – Ads", "AdGuard Base Filter", "EasyPrivacy":
            return NSLocalizedString("Works alongside EasyList.", comment: "Concise bundle list note")
        case "AdGuard Mobile Filter":
            return NSLocalizedString("Recommended for iPhone.", comment: "Concise bundle list note")
        case "uBlock filters – Quick fixes":
            return NSLocalizedString("Fixes sites broken by other lists.", comment: "Concise bundle list note")
        case "uBlock filters – Unbreak":
            return NSLocalizedString("Keeps sites working when other lists break them.", comment: "Concise bundle list note")
        case "uBlock filters – Privacy":
            return NSLocalizedString("Also removes tracking parameters from URLs.", comment: "Concise bundle list note")
        case "AdGuard URL Tracking Protection Filter":
            return NSLocalizedString("Removes tracking parameters from URLs.", comment: "Concise bundle list note")
        case "Actually Legitimate URL Shortener Tool":
            return NSLocalizedString("Cleans unneeded parameters from links.", comment: "Concise bundle list note")
        case "wBlock Ad and Tracking Hosts":
            return NSLocalizedString("Catches hosts other lists miss.", comment: "Concise bundle list note")
        case "Block Outsider Intrusion into LAN":
            return NSLocalizedString("Stops public sites from reaching your local network.", comment: "Concise bundle list note")
        case "Phishing URL Blocklist":
            return NSLocalizedString("Blocks phishing pages.", comment: "Concise bundle list note")
        case "Dandelion Sprout's Anti-Malware List":
            return NSLocalizedString("Blocks malware redirects and scams.", comment: "Concise bundle list note")
        case "uBlock filters – Cookie Notices", "uBlock filters – Annoyances":
            return NSLocalizedString("Works alongside AdGuard or EasyList.", comment: "Concise bundle list note")
        case "EasyList – Newsletter Notices":
            return NSLocalizedString("Hides newsletter sign-up prompts.", comment: "Concise bundle list note")
        case "EasyList – Notifications":
            return NSLocalizedString("Hides notification prompts.", comment: "Concise bundle list note")
        default:
            return nil
        }
    }

    /// True iff any filter surfaced under this bundle differs from `appliedSelectedIDs`.
    func isDirty(
        in filters: [FilterList],
        appliedSelectedIDs: Set<UUID>,
        recommendedNames: Set<String> = FilterListLoader.recommendedFilterNames
    ) -> Bool {
        let scoped = scopedFilters(in: filters, recommendedNames: recommendedNames)
        return scoped.contains { $0.isSelected != appliedSelectedIDs.contains($0.id) }
    }

    /// Built-in filter paired with the Bypass Paywalls Clean extra.
    static func isPairedBypassPaywallsFilter(_ filter: FilterList) -> Bool {
        guard !filter.isCustom else { return false }
        let candidates = ["Bypass Paywalls Clean Filter", "Bypass Paywalls Filter", "Bypass Paywalls"]
        return candidates.contains(where: { filter.name.localizedCaseInsensitiveContains($0) })
    }

    /// Every selected list that no Basic bundle shown on this platform, no
    /// built-in Regional language filter, and no paired Extras toggle owns
    /// (custom lists, Multipurpose, Experimental, standalone Bypass Paywalls
    /// Clean Filter when its Extras script is off, and Mobile App Banners on
    /// macOS if synced from iOS).
    static func unownedActiveFilters(
        in filters: [FilterList],
        recommendedNames: Set<String> = FilterListLoader.recommendedFilterNames,
        isBypassPaywallsCleanEnabled: Bool = false,
        includesMobileAppBannersBundle: Bool = AnnoyanceChoice.defaultIncludesMobileAppBanners
    ) -> [FilterList] {
        let ownedIDs = ownedFilterIDs(
            in: filters,
            recommendedNames: recommendedNames,
            isBypassPaywallsCleanEnabled: isBypassPaywallsCleanEnabled,
            includesMobileAppBannersBundle: includesMobileAppBannersBundle
        )
        return filters.filter { $0.isSelected && !ownedIDs.contains($0.id) }
    }

    /// True iff any built-in Regional list differs from `appliedSelectedIDs`.
    static func isLanguagesDirty(in filters: [FilterList], appliedSelectedIDs: Set<UUID>) -> Bool {
        filters.contains { !$0.isCustom && $0.category == .foreign && ($0.isSelected != appliedSelectedIDs.contains($0.id)) }
    }

    /// Derives the checked language codes for Standard mode's Languages picker
    /// from the live selected `.foreign` filters without expanding single-choice
    /// selections into sibling languages of shared multi-language lists.
    static func activeRegionalLanguageCodes(
        in filters: [FilterList],
        storedCodes: Set<String>
    ) -> Set<String> {
        let foreignSelected = filters.filter { !$0.isCustom && $0.category == .foreign && $0.isSelected }
        guard !foreignSelected.isEmpty else { return [] }

        let normalizedStored = Set(storedCodes.map(RegionalLanguageOption.canonicalCode))
        var active = Set<String>()

        for filter in foreignSelected {
            let filterCodes = Set(filter.languages.map(RegionalLanguageOption.canonicalCode))
            let matchedStored = filterCodes.intersection(normalizedStored)
            if !matchedStored.isEmpty {
                active.formUnion(matchedStored)
            } else {
                active.formUnion(filterCodes)
            }
        }
        return active
    }

    /// Computes the next stored language codes after a toggle in the Languages
    /// picker so unchecking any language from an externally-enabled multi-language
    /// list disables that list cleanly instead of getting re-pinned by siblings.
    static func updatedStoredRegionalLanguageCodes(
        previousVisible: Set<String>,
        newVisible: Set<String>,
        storedCodes: Set<String>,
        in filters: [FilterList]
    ) -> Set<String> {
        let normalizedStored = Set(storedCodes.map(RegionalLanguageOption.canonicalCode))
        let removed = previousVisible.subtracting(newVisible)
        let added = newVisible.subtracting(previousVisible)

        var next = normalizedStored.intersection(previousVisible)
        next.formUnion(added)
        next.subtract(removed)

        let foreignSelected = filters.filter { !$0.isCustom && $0.category == .foreign && $0.isSelected }
        for filter in foreignSelected {
            let filterCodes = Set(filter.languages.map(RegionalLanguageOption.canonicalCode))
            guard filterCodes.isDisjoint(with: normalizedStored) else { continue }
            if filterCodes.isDisjoint(with: removed) {
                next.formUnion(filterCodes.intersection(newVisible))
            }
        }
        return next
    }

    /// True iff any unowned list differs from `appliedSelectedIDs`.
    static func isUnownedDirty(
        in filters: [FilterList],
        appliedSelectedIDs: Set<UUID>,
        recommendedNames: Set<String> = FilterListLoader.recommendedFilterNames,
        isBypassPaywallsCleanEnabled: Bool = false,
        includesMobileAppBannersBundle: Bool = AnnoyanceChoice.defaultIncludesMobileAppBanners
    ) -> Bool {
        let ownedIDs = ownedFilterIDs(
            in: filters,
            recommendedNames: recommendedNames,
            isBypassPaywallsCleanEnabled: isBypassPaywallsCleanEnabled,
            includesMobileAppBannersBundle: includesMobileAppBannersBundle
        )
        return filters.contains { !ownedIDs.contains($0.id) && ($0.isSelected != appliedSelectedIDs.contains($0.id)) }
    }

    private static func ownedFilterIDs(
        in filters: [FilterList],
        recommendedNames: Set<String>,
        isBypassPaywallsCleanEnabled: Bool,
        includesMobileAppBannersBundle: Bool
    ) -> Set<UUID> {
        var ownedIDs = Set<UUID>()
        for bundle in allCases {
            if !includesMobileAppBannersBundle, case .annoyance(.banners) = bundle {
                continue
            }
            ownedIDs.formUnion(bundle.scopedFilters(in: filters, recommendedNames: recommendedNames).map(\.id))
        }
        for filter in filters where !filter.isCustom && filter.category == .foreign {
            ownedIDs.insert(filter.id)
        }
        if isBypassPaywallsCleanEnabled {
            for filter in filters where isPairedBypassPaywallsFilter(filter) {
                ownedIDs.insert(filter.id)
            }
        }
        return ownedIDs
    }
}

/// In-memory snapshot memory so turning a `.partlyOn` bundle off and back on
/// is an exact identity. Only Reset to Recommended normalizes to `members(b)`.
struct BasicBundleToggleMemory: Sendable {
    private var snapshots: [String: Set<UUID>] = [:]

    /// Computes the exact filter selection changes `(id, selected)` for toggling
    /// `bundle` to `turnOn`. Mutates snapshot memory in place.
    mutating func selectionChanges(
        for bundle: BasicBundle,
        turnOn: Bool,
        in filters: [FilterList],
        recommendedNames: Set<String> = FilterListLoader.recommendedFilterNames
    ) -> [(id: UUID, selected: Bool)] {
        let owned = bundle.ownedFilters(in: filters, recommendedNames: recommendedNames)
        let ownedIDs = Set(owned.map(\.id))
        let currentState = bundle.state(in: filters, recommendedNames: recommendedNames)

        if !turnOn {
            if currentState == .partlyOn {
                snapshots[bundle.id] = Set(owned.filter(\.isSelected).map(\.id))
            } else {
                snapshots.removeValue(forKey: bundle.id)
            }
            return owned.filter(\.isSelected).map { ($0.id, false) }
        } else {
            let targetIDs: Set<UUID>
            if let saved = snapshots.removeValue(forKey: bundle.id) {
                let valid = saved.intersection(ownedIDs)
                if !valid.isEmpty {
                    targetIDs = valid
                } else {
                    targetIDs = Set(bundle.memberFilters(in: filters, recommendedNames: recommendedNames).map(\.id))
                }
            } else {
                targetIDs = Set(bundle.memberFilters(in: filters, recommendedNames: recommendedNames).map(\.id))
            }
            return owned.compactMap { filter in
                let desired = targetIDs.contains(filter.id)
                return filter.isSelected == desired ? nil : (filter.id, desired)
            }
        }
    }

    /// Normalizes a bundle to its recommended `members` and clears any snapshot.
    mutating func resetToRecommendedChanges(
        for bundle: BasicBundle,
        in filters: [FilterList],
        recommendedNames: Set<String> = FilterListLoader.recommendedFilterNames
    ) -> [(id: UUID, selected: Bool)] {
        snapshots.removeValue(forKey: bundle.id)
        let owned = bundle.ownedFilters(in: filters, recommendedNames: recommendedNames)
        let memberIDs = Set(bundle.memberFilters(in: filters, recommendedNames: recommendedNames).map(\.id))
        return owned.compactMap { filter in
            let desired = memberIDs.contains(filter.id)
            return filter.isSelected == desired ? nil : (filter.id, desired)
        }
    }

    func hasSnapshot(for bundle: BasicBundle) -> Bool {
        snapshots[bundle.id] != nil
    }
}
