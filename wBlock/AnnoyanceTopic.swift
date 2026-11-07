import Foundation
import wBlockCoreService

/// Topics that split the Annoyances lists into smaller cards, following the
/// groups uBlock Origin tags its own annoyance lists with. Display only:
/// categories, ordering and compilation are unchanged.
enum AnnoyanceTopic: String, CaseIterable, Sendable {
    case general, cookies, popups, social, other

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
        filter.isCustom ? .other : topicByName[filter.name] ?? .other
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
/// on the lists it names.
enum AnnoyanceChoice: String, CaseIterable, Identifiable, Sendable {
    case cookies, popups, banners, social, chat, general, ai

    var id: String { rawValue }

    /// Cookie notices are the one choice onboarding preselects.
    static let recommended: Set<AnnoyanceChoice> = [.cookies]

    /// A localization key.
    var title: String {
        switch self {
        case .cookies: "Cookie Notices"
        case .popups: "Pop-ups"
        case .banners: "Banners"
        case .social: "Social"
        case .chat: "Chat"
        case .general: "General"
        case .ai: "Anti-AI"
        }
    }

    var subtitle: String {
        switch self {
        case .cookies: String(localized: "Hides cookie consent banners and pop-ups.")
        case .popups: String(localized: "Hides newsletter sign-ups and requests to show notifications.")
        case .banners: String(localized: "Hides banners that push a site's mobile app.")
        case .social: String(localized: "Hides share buttons and social media widgets.")
        case .chat: String(localized: "Hides live chat and support widgets.")
        case .general: String(localized: "Hides overlays, promotions, and other distractions.")
        case .ai: String(localized: "Hides AI features and AI-generated content.")
        }
    }

    var filterNames: [String] {
        switch self {
        case .cookies: ["uBlock filters – Cookie Notices", "EasyList – Cookie Notices"]
        case .popups: ["EasyList – Newsletter Notices", "EasyList – Notifications"]
        case .banners: ["AdGuard Mobile App Banners"]
        case .social: ["EasyList – Social Widgets"]
        case .chat: ["EasyList – Chat Widgets"]
        case .general: ["uBlock filters – Annoyances", "EasyList – Other Annoyances"]
        case .ai: ["Stevo's AI Blocklist"]
        }
    }

    /// The built-in lists `choices` turn on.
    static func filters(for choices: Set<AnnoyanceChoice>, in filters: [FilterList]) -> [FilterList] {
        let names = Set(choices.flatMap(\.filterNames))
        return filters.filter { !$0.isCustom && names.contains($0.name) }
    }

    /// Choices whose lists are all on.
    static func choices(enabledIn filters: [FilterList]) -> Set<AnnoyanceChoice> {
        let enabled = Set(filters.filter { !$0.isCustom && $0.isSelected }.map(\.name))
        return Set(allCases.filter { Set($0.filterNames).isSubset(of: enabled) })
    }
}
