import Foundation
import wBlockCoreService

@main
struct BasicModeTests {
    static func main() {
        testAppModeDefaultsAndSeeding()
        testAnnoyanceChoiceOrdering()
        testBasicBundleDerivationAndStates()
        testBasicBundlePartlyOnSnapshotIdentityAndReset()
        testBasicBundleUnownedActiveAndDirty()
        testRegionalLanguageMultiLanguageGroupToggle()
        testSafariHealthPriorityOrder()
        testSafariHealthHysteresisAndTransientNil()
        print("PASS — BasicMode, BasicBundle, and SafariHealth tests")
    }

    private static func testAppModeDefaultsAndSeeding() {
        let suiteName = "wblock.test.appmode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Fresh install seeds to .basic (Standard)
        let seededFresh = AppMode.seedIfNeeded(hasCompletedOnboarding: false, hasCustomContent: false, defaults: defaults)
        precondition(seededFresh == .basic, "Fresh install must seed to .basic")
        precondition(defaults.string(forKey: AppMode.storageKey) == "basic")

        // Stock 3.x upgrader with no custom lists/scripts seeds to .basic (Standard)
        defaults.removeObject(forKey: AppMode.storageKey)
        let seededStockUpgrader = AppMode.seedIfNeeded(hasCompletedOnboarding: true, hasCustomContent: false, defaults: defaults)
        precondition(seededStockUpgrader == .basic, "Stock upgrader without custom content must seed to .basic")
        precondition(defaults.string(forKey: AppMode.storageKey) == "basic")

        // Existing install with custom lists or scripts seeds to .advanced
        defaults.removeObject(forKey: AppMode.storageKey)
        let seededPowerUpgrader = AppMode.seedIfNeeded(hasCompletedOnboarding: true, hasCustomContent: true, defaults: defaults)
        precondition(seededPowerUpgrader == .advanced, "Existing install with custom content must seed to .advanced")
        precondition(defaults.string(forKey: AppMode.storageKey) == "advanced")

        // Explicit choice wins even when onboarding/custom flags differ
        defaults.set(AppMode.basic.rawValue, forKey: AppMode.storageKey)
        precondition(
            AppMode.seedIfNeeded(hasCompletedOnboarding: true, hasCustomContent: true, defaults: defaults) == .basic,
            "seedIfNeeded must preserve existing stored choice"
        )
    }

    private static func testAnnoyanceChoiceOrdering() {
        precondition(
            AnnoyanceChoice.allCases == [.cookies, .popups, .banners, .social, .chat, .general, .ai],
            "Cookie Notices must lead AnnoyanceChoice.allCases"
        )
    }

    private static func testBasicBundleDerivationAndStates() {
        let loader = FilterListLoader()
        var lists = loader.getDefaultFilterLists()

        // Core bundles start .on with default recommended lists
        for core in CoreProtectionBundle.allCases {
            let bundle = BasicBundle.core(core)
            precondition(
                bundle.state(in: lists) == .on,
                "Default catalog should put core bundle \(core.rawValue) in .on state"
            )
        }

        // Security recommended member is strictly uBlock filters – Badware risks
        let securityMembers = BasicBundle.core(.security).memberFilters(in: lists).map(\.name)
        precondition(securityMembers == ["uBlock filters – Badware risks"], "Security members mismatch: \(securityMembers)")

        // Turning off one recommended Ads list puts Ads into .partlyOn
        if let idx = lists.firstIndex(where: { $0.name == "EasyList" }) {
            lists[idx].isSelected = false
        }
        precondition(BasicBundle.core(.ads).state(in: lists) == .partlyOn, "Subset of Ads members must be .partlyOn")

        // Turning off all Ads lists puts Ads into .off
        for idx in lists.indices where !lists[idx].isCustom && lists[idx].category == .ads {
            lists[idx].isSelected = false
        }
        precondition(BasicBundle.core(.ads).state(in: lists) == .off, "Empty Ads selection must be .off")

        // Enabling a non-recommended built-in list (AdGuard Base Filter) makes Ads .partlyOn
        if let idx = lists.firstIndex(where: { $0.name == "AdGuard Base Filter" }) {
            lists[idx].isSelected = true
        }
        precondition(BasicBundle.core(.ads).state(in: lists) == .partlyOn, "Non-recommended built-in Ads list must be .partlyOn")

        // Annoyances start .off in default catalog
        for choice in AnnoyanceChoice.allCases {
            precondition(
                BasicBundle.annoyance(choice).state(in: lists) == .off,
                "Annoyance \(choice.rawValue) should start .off"
            )
        }

        // Enabling only one of Cookie Notices' two lists makes it .partlyOn
        if let idx = lists.firstIndex(where: { $0.name == "AdGuard Cookie Notices" }) {
            lists[idx].isSelected = true
        }
        precondition(BasicBundle.annoyance(.cookies).state(in: lists) == .partlyOn, "One of two Cookie lists must be .partlyOn")

        // Enabling both makes it .on
        if let idx = lists.firstIndex(where: { $0.name == "uBlock filters – Cookie Notices" }) {
            lists[idx].isSelected = true
        }
        precondition(BasicBundle.annoyance(.cookies).state(in: lists) == .on, "Both Cookie lists must be .on")
    }

    private static func testBasicBundlePartlyOnSnapshotIdentityAndReset() {
        var lists = FilterListLoader().getDefaultFilterLists()
        let adsBundle = BasicBundle.core(.ads)

        // Create a custom partly-on selection: EasyList + AdGuard Base Filter only
        for idx in lists.indices where !lists[idx].isCustom && lists[idx].category == .ads {
            lists[idx].isSelected = (lists[idx].name == "EasyList" || lists[idx].name == "AdGuard Base Filter")
        }
        let originalSelected = Set(lists.filter(\.isSelected).map(\.id))
        precondition(adsBundle.state(in: lists) == .partlyOn)

        var memory = BasicBundleToggleMemory()

        // Toggle OFF -> snapshots the exact partlyOn set
        let offChanges = memory.selectionChanges(for: adsBundle, turnOn: false, in: lists)
        apply(offChanges, to: &lists)
        precondition(adsBundle.state(in: lists) == .off, "Toggling partlyOn bundle off must yield .off")
        precondition(memory.hasSnapshot(for: adsBundle), "Snapshot must be recorded when turning off a partlyOn bundle")

        // Toggle ON -> restores exact original set (off -> on is identity)
        let onChanges = memory.selectionChanges(for: adsBundle, turnOn: true, in: lists)
        apply(onChanges, to: &lists)
        let restoredSelected = Set(lists.filter(\.isSelected).map(\.id))
        precondition(restoredSelected == originalSelected, "off -> on on a partlyOn bundle must be an exact identity")
        precondition(adsBundle.state(in: lists) == .partlyOn)

        // Reset to Recommended -> normalizes to recommended members and clears snapshot
        let resetChanges = memory.resetToRecommendedChanges(for: adsBundle, in: lists)
        apply(resetChanges, to: &lists)
        precondition(adsBundle.state(in: lists) == .on, "Reset to Recommended must normalize bundle to .on")
        precondition(!memory.hasSnapshot(for: adsBundle))
    }

    private static func testBasicBundleUnownedActiveAndDirty() {
        var lists = FilterListLoader().getDefaultFilterLists()
        precondition(BasicBundle.unownedActiveFilters(in: lists).isEmpty, "Default recommended lists must have no unowned active lists")

        // Turn on a Multipurpose list, an Experimental list, and a custom list
        if let idx = lists.firstIndex(where: { $0.category == .multipurpose }) {
            lists[idx].isSelected = true
        }
        if let idx = lists.firstIndex(where: { $0.category == .experimental }) {
            lists[idx].isSelected = true
        }
        var custom = FilterList(
            id: UUID(),
            name: "My Custom List",
            url: URL(string: "https://example.com/custom.txt")!,
            category: .custom,
            isSelected: true
        )
        custom.isCustom = true
        var customAds = FilterList(
            id: UUID(),
            name: "My Custom Ad List",
            url: URL(string: "https://example.com/custom-ads.txt")!,
            category: .ads,
            isSelected: true
        )
        customAds.isCustom = true
        lists.append(contentsOf: [custom, customAds])

        let unowned = BasicBundle.unownedActiveFilters(in: lists)
        precondition(unowned.count == 3, "Expected 3 unowned active lists, got \(unowned.count)")
        precondition(unowned.contains { $0.id == custom.id }, "Custom list in Other must surface in Also on")
        precondition(!unowned.contains { $0.id == customAds.id }, "Custom list in Ads must stay in Ads scoped lists instead of duplicating in Also on")
        precondition(BasicBundle.core(.ads).scopedFilters(in: lists).contains { $0.id == customAds.id }, "Custom list in Ads must appear in Ads scoped lists")

        // Bypass Paywalls Clean Filter is owned by the Extras toggle while BPC script is on,
        // and surfaces under "Also on" only if enabled standalone without the script.
        if let bpcIdx = lists.firstIndex(where: BasicBundle.isPairedBypassPaywallsFilter) {
            lists[bpcIdx].isSelected = true
            let withoutScript = BasicBundle.unownedActiveFilters(in: lists, isBypassPaywallsCleanEnabled: false)
            precondition(withoutScript.contains { $0.id == lists[bpcIdx].id }, "Standalone BPC filter must appear in Also on")
            let withScript = BasicBundle.unownedActiveFilters(in: lists, isBypassPaywallsCleanEnabled: true)
            precondition(!withScript.contains { $0.id == lists[bpcIdx].id }, "BPC filter owned by Extras toggle must stay out of Also on")
            lists[bpcIdx].isSelected = false
        }

        // Mobile App Banners is omitted on macOS, so if enabled (e.g. synced from iOS),
        // it must surface truthfully under "Also on" on macOS while remaining owned on iOS.
        precondition(AnnoyanceChoice.basicPrimaryChoices(includeMobileAppBanners: true) == [.cookies, .popups, .banners])
        precondition(AnnoyanceChoice.basicPrimaryChoices(includeMobileAppBanners: false) == [.cookies, .popups])
        precondition(AnnoyanceChoice.basicStricterChoices == [.social, .chat, .general, .ai])
        if let bannerIdx = lists.firstIndex(where: { !$0.isCustom && $0.name == "AdGuard Mobile App Banners" }) {
            lists[bannerIdx].isSelected = true
            let iosUnowned = BasicBundle.unownedActiveFilters(in: lists, includesMobileAppBannersBundle: true)
            precondition(!iosUnowned.contains { $0.id == lists[bannerIdx].id }, "Mobile App Banners must be owned on iOS")
            let macUnowned = BasicBundle.unownedActiveFilters(in: lists, includesMobileAppBannersBundle: false)
            precondition(macUnowned.contains { $0.id == lists[bannerIdx].id }, "Mobile App Banners must surface in Also on on macOS when synced on")
            lists[bannerIdx].isSelected = false
        }

        // Dirty tracking
        let baseline = Set(lists.filter(\.isSelected).map(\.id))
        precondition(!BasicBundle.core(.privacy).isDirty(in: lists, appliedSelectedIDs: baseline))
        if let idx = lists.firstIndex(where: { $0.name == "EasyPrivacy" }) {
            lists[idx].isSelected = false
        }
        precondition(BasicBundle.core(.privacy).isDirty(in: lists, appliedSelectedIDs: baseline))
        precondition(!BasicBundle.core(.ads).isDirty(in: lists, appliedSelectedIDs: baseline))
    }

    private static func testRegionalLanguageMultiLanguageGroupToggle() {
        let czechSlovak = FilterList(
            id: UUID(),
            name: "EasyList Czech and Slovak",
            url: URL(string: "https://example.com/cs-sk.txt")!,
            category: .foreign,
            isSelected: true,
            languages: ["cs", "sk"]
        )
        let japanese = FilterList(
            id: UUID(),
            name: "AdGuard Japanese Filter",
            url: URL(string: "https://example.com/ja.txt")!,
            category: .foreign,
            isSelected: true,
            languages: ["ja"]
        )
        let lists = [czechSlovak, japanese]

        // Selecting Czech alone must not auto-check Slovak in the picker
        let activeForCzech = BasicBundle.activeRegionalLanguageCodes(in: lists, storedCodes: ["cs", "ja"])
        precondition(activeForCzech == ["cs", "ja"], "Single language from multi-language list must not pull in siblings")

        // Unchecking Czech removes Czech cleanly
        let afterRemovingCzech = BasicBundle.updatedStoredRegionalLanguageCodes(
            previousVisible: activeForCzech,
            newVisible: ["ja"],
            storedCodes: ["cs", "ja"],
            in: lists
        )
        precondition(afterRemovingCzech == ["ja"], "Unchecking Czech must leave only Japanese")

        // Synced/untracked multi-language list shows its languages, and unchecking one removes the whole group without touching other languages
        let activeSynced = BasicBundle.activeRegionalLanguageCodes(in: lists, storedCodes: [])
        precondition(activeSynced == ["cs", "sk", "ja"])
        let afterRemovingSyncedCzech = BasicBundle.updatedStoredRegionalLanguageCodes(
            previousVisible: activeSynced,
            newVisible: ["sk", "ja"],
            storedCodes: [],
            in: lists
        )
        precondition(afterRemovingSyncedCzech == ["ja"], "Unchecking one code from an untracked multi-language list must disable its group while preserving unrelated languages")
    }

    private static func testSafariHealthPriorityOrder() {
        let now = Date()

        // 1. All blockers off beats everything (even paused, rule limit, applying, failed)
        let s1 = SafariHealthResolver.resolve(SafariHealthInput(
            hasReadExtensions: true,
            blockerStates: [false, false, false, false, false],
            scriptsEnabled: false,
            isScriptsStateKnowable: true,
            isWelded: false,
            pausedComponents: .all,
            hasHitRuleLimit: true,
            isApplying: true,
            hasFailed: true,
            failedDuringUpdate: true,
            lastUpdatedDate: now
        ))
        precondition(s1 == .allBlockersOff && s1.action == .openSafariSettings)

        // 2. Some blockers off beats scripts off, paused, etc.
        let s2 = SafariHealthResolver.resolve(SafariHealthInput(
            hasReadExtensions: true,
            blockerStates: [true, true, false, true, true],
            scriptsEnabled: false,
            isScriptsStateKnowable: true,
            isWelded: false,
            pausedComponents: .all,
            hasHitRuleLimit: true,
            isApplying: true,
            hasFailed: true,
            failedDuringUpdate: false,
            lastUpdatedDate: now
        ))
        precondition(s2 == .someBlockersOff)

        // 3. Scripts extension off beats paused
        let s3 = SafariHealthResolver.resolve(SafariHealthInput(
            hasReadExtensions: true,
            blockerStates: [true, true, true, true, true],
            scriptsEnabled: false,
            isScriptsStateKnowable: true,
            isWelded: false,
            pausedComponents: .all,
            hasHitRuleLimit: true,
            isApplying: true,
            hasFailed: true,
            failedDuringUpdate: false,
            lastUpdatedDate: now
        ))
        precondition(s3 == .scriptsExtensionOff)

        // 4. Paused (full vs partial) beats rule limit
        let s4Full = SafariHealthResolver.resolve(SafariHealthInput(
            hasReadExtensions: true,
            blockerStates: [true, true, true, true, true],
            scriptsEnabled: true,
            isScriptsStateKnowable: true,
            isWelded: true,
            pausedComponents: .all,
            hasHitRuleLimit: true,
            isApplying: true,
            hasFailed: true,
            failedDuringUpdate: false,
            lastUpdatedDate: now
        ))
        precondition(s4Full == .paused(partial: false) && s4Full.action == .resume)

        let s4Partial = SafariHealthResolver.resolve(SafariHealthInput(
            hasReadExtensions: true,
            blockerStates: [true, true, true, true, true],
            scriptsEnabled: true,
            isScriptsStateKnowable: true,
            isWelded: true,
            pausedComponents: [.filters],
            hasHitRuleLimit: true,
            isApplying: true,
            hasFailed: true,
            failedDuringUpdate: false,
            lastUpdatedDate: now
        ))
        precondition(s4Partial == .paused(partial: true))

        // 5. Rule limit hit beats applying & failed
        let s5 = SafariHealthResolver.resolve(SafariHealthInput(
            hasReadExtensions: true,
            blockerStates: [true, true, true, true, true],
            scriptsEnabled: true,
            isScriptsStateKnowable: true,
            isWelded: true,
            pausedComponents: [],
            hasHitRuleLimit: true,
            isApplying: true,
            hasFailed: true,
            failedDuringUpdate: false,
            lastUpdatedDate: now
        ))
        precondition(s5 == .ruleLimitHit && s5.action == .reviewRuleLimit)

        // 6. Applying beats failed
        let s6 = SafariHealthResolver.resolve(SafariHealthInput(
            hasReadExtensions: true,
            blockerStates: [true, true, true, true, true],
            scriptsEnabled: true,
            isScriptsStateKnowable: true,
            isWelded: true,
            pausedComponents: [],
            hasHitRuleLimit: false,
            isApplying: true,
            hasFailed: true,
            failedDuringUpdate: false,
            lastUpdatedDate: now
        ))
        precondition(s6 == .applying && s6.action == nil)

        // 7. Failed beats protected
        let s7 = SafariHealthResolver.resolve(SafariHealthInput(
            hasReadExtensions: true,
            blockerStates: [true, true, true, true, true],
            scriptsEnabled: true,
            isScriptsStateKnowable: true,
            isWelded: true,
            pausedComponents: [],
            hasHitRuleLimit: false,
            isApplying: false,
            hasFailed: true,
            failedDuringUpdate: false,
            lastUpdatedDate: now
        ))
        precondition(s7 == .failed(isUpdate: false) && s7.action == .tryAgain)

        // 8. Protected
        let s8 = SafariHealthResolver.resolve(SafariHealthInput(
            hasReadExtensions: true,
            blockerStates: [true, true, true, true, true],
            scriptsEnabled: true,
            isScriptsStateKnowable: true,
            isWelded: true,
            pausedComponents: [],
            hasHitRuleLimit: false,
            isApplying: false,
            hasFailed: false,
            failedDuringUpdate: false,
            lastUpdatedDate: now
        ))
        precondition(s8 == .protected(lastUpdated: now) && s8.action == nil)
    }

    private static func testSafariHealthHysteresisAndTransientNil() {
        var h = SafariExtensionHysteresis()

        // First read degraded -> not welded
        h.record(blockerStates: [true, true, false, true, true], rawScriptsEnabled: true, isScriptsStateKnowable: true)
        precondition(!h.isWelded, "Degraded initial read must not weld")

        // All on -> welds immediately
        h.record(blockerStates: [true, true, true, true, true], rawScriptsEnabled: true, isScriptsStateKnowable: true)
        precondition(h.isWelded, "All-on must weld immediately")

        // Transient nil scripts read keeps last known true -> stays welded
        h.record(blockerStates: [true, true, true, true, true], rawScriptsEnabled: nil, isScriptsStateKnowable: true)
        precondition(h.isWelded && h.effectiveScriptsEnabled == true, "Transient nil must keep last known scripts state")

        // First off read while welded -> STILL welded (anti-flicker hysteresis)
        h.record(blockerStates: [true, true, false, true, true], rawScriptsEnabled: true, isScriptsStateKnowable: true)
        precondition(h.isWelded, "Single off read must NOT un-weld")

        // Recovery resets counter -> stays welded
        h.record(blockerStates: [true, true, true, true, true], rawScriptsEnabled: true, isScriptsStateKnowable: true)
        precondition(h.isWelded && h.consecutiveOffReads == 0)

        // Two consecutive off reads -> un-welds!
        h.record(blockerStates: [true, true, false, true, true], rawScriptsEnabled: true, isScriptsStateKnowable: true)
        precondition(h.isWelded, "First of two off reads must stay welded")
        precondition(h.isAwaitingOffConfirmation, "First off read while welded must request confirmation poll")
        h.record(blockerStates: [true, true, false, true, true], rawScriptsEnabled: true, isScriptsStateKnowable: true)
        precondition(!h.isWelded, "Second consecutive off read must un-weld")
        precondition(!h.isAwaitingOffConfirmation, "Once un-welded, confirmation state clears")

        // OS where scripts state is not knowable (iOS < 26.2): welds on 5/5 blockers alone
        var iosLegacy = SafariExtensionHysteresis()
        iosLegacy.record(blockerStates: [true, true, true, true, true], rawScriptsEnabled: nil, isScriptsStateKnowable: false)
        precondition(iosLegacy.isWelded, "iOS < 26.2 must weld on 5/5 blockers with nil scripts state")
    }

    private static func apply(_ changes: [(id: UUID, selected: Bool)], to lists: inout [FilterList]) {
        for change in changes {
            if let idx = lists.firstIndex(where: { $0.id == change.id }) {
                lists[idx].isSelected = change.selected
            }
        }
    }
}
