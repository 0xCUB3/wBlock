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
