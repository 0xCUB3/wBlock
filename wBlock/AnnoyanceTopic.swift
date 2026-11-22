import Foundation
import wBlockCoreService

/// Topics that split the Annoyances lists into smaller cards, following the
/// groups uBlock Origin tags its own annoyance lists with. Display only:
/// categories, ordering and compilation are unchanged.
enum AnnoyanceTopic: String, CaseIterable, Identifiable, Sendable {
    case general, cookies, popups, social, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .cookies: "Cookie Notices"
        case .popups: "Pop-ups & Banners"
        case .social: "Social & Chat"
        case .other: "Other"
        }
    }

    private static let topicByName: [String: AnnoyanceTopic] = [
        "uBlock filters – Annoyances": .general,
        "EasyList – Other Annoyances": .general,
        "AdGuard Other Annoyances": .general,
        "uBlock filters – Cookie Notices": .cookies,
        "EasyList – Cookie Notices": .cookies,
        "AdGuard Cookie Notices": .cookies,
        "AdGuard Popups": .popups,
        "AdGuard Mobile App Banners": .popups,
        "EasyList – Newsletter Notices": .popups,
        "EasyList – Notifications": .popups,
        "EasyList – Social Widgets": .social,
        "AdGuard Social Media Filter": .social,
        "EasyList – Chat Widgets": .social,
        "AdGuard Widgets": .social,
    ]

    static func topic(for filter: FilterList) -> AnnoyanceTopic {
        if filter.isCustom {
            return filter.annoyanceTopic.flatMap(AnnoyanceTopic.init(rawValue:)) ?? .other
        }
        return topicByName[filter.name] ?? .other
    }

    /// Persisted value for a custom list's subcategory; nil means Other or non-Annoyances.
    static func storedValue(_ topic: AnnoyanceTopic, category: FilterListCategory) -> String? {
        category == .annoyances && topic != .other ? topic.rawValue : nil
    }

    /// `filters` split by topic in topic order, each keeping its given order.
    /// Empty topics are left out.
    static func groups(_ filters: [FilterList]) -> [(topic: AnnoyanceTopic, filters: [FilterList])] {
        let grouped = Dictionary(grouping: filters, by: topic(for:))
        return allCases.compactMap { topic in grouped[topic].map { (topic, $0) } }
    }
}

/// What onboarding and Annoyances Info offer in place of the whole list of
/// annoyance lists, none of which is on by default (#1087). Each choice turns
/// on the lists it names. All built-in annoyance choices use AdGuard's lists
/// (plus uBO's for Cookie Notices and General), which are updated far more
/// often than EasyList's (#1112).
enum AnnoyanceChoice: String, CaseIterable, Identifiable, Sendable {
    case general, cookies, popups, banners, social, chat, ai

    var id: String { rawValue }

    /// What onboarding preselects (#1091). Cookie Notices only, as in 3.2.3:
    /// AdGuard Other Annoyances hides Google's AI Overview (Dalsu, Discord).
    static let recommended: Set<AnnoyanceChoice> = [.cookies]

    /// A localization key.
    var title: String {
        switch self {
        case .cookies: "Cookie Notices"
        case .popups: "Pop-ups"
        case .banners: "Mobile App Banners"
        case .social: "Social"
        case .chat: "Chat"
        case .general: "General"
        case .ai: "Anti-AI"
        }
    }

    var subtitle: String {
        switch self {
        case .cookies: String(localized: "Hides cookie consent banners and pop-ups.")
        case .popups: String(localized: "Hides pop-ups, newsletter prompts, and notification requests.")
        case .banners: String(localized: "Hides banners that push a site's mobile app.")
        case .social: String(localized: "Hides share buttons and social media widgets.")
        case .chat: String(localized: "Hides live chat and support widgets.")
        case .general: String(localized: "Hides overlays, promotions, and other distractions.")
        case .ai: String(localized: "Hides AI features and AI-generated content.")
        }
    }

    var filterNames: [String] {
        switch self {
        case .cookies: ["uBlock filters – Cookie Notices", "AdGuard Cookie Notices"]
        case .popups: ["AdGuard Popups"]
        case .banners: ["AdGuard Mobile App Banners"]
        case .social: ["AdGuard Social Media Filter"]
        case .chat: ["AdGuard Widgets"]
        case .general: ["uBlock filters – Annoyances", "AdGuard Other Annoyances"]
        case .ai: ["Stevo's AI Blocklist"]
        }
    }

    /// The built-in lists `choices` turn on.
    static func filters(for choices: Set<AnnoyanceChoice>, in filters: [FilterList]) -> [FilterList] {
        let names = Set(choices.flatMap(\.filterNames))
        return filters.filter { !$0.isCustom && names.contains($0.name) }
    }

    /// General was on by default in the 4.0 alphas. It goes off once where
    /// all its lists are on (AppFilterManager.applyOnce). uBlock filters –
    /// Annoyances is new in 4.0, so a 3.2.3 install that ran AdGuard Other
    /// Annoyances keeps it.
    static func turningOffGeneral(_ lists: [FilterList]) -> [FilterList] {
        guard choices(enabledIn: lists).contains(.general) else { return lists }
        let names = Set(general.filterNames)
        return lists.map { list in
            var list = list
            if !list.isCustom && names.contains(list.name) { list.isSelected = false }
            return list
        }
    }

    /// Choices whose lists are all on.
    static func choices(enabledIn filters: [FilterList]) -> Set<AnnoyanceChoice> {
        let enabled = Set(filters.filter { !$0.isCustom && $0.isSelected }.map(\.name))
        return Set(allCases.filter { Set($0.filterNames).isSubset(of: enabled) })
    }
}
