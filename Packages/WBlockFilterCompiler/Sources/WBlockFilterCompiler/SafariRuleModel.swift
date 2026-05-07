import Foundation

struct SafariContentBlockerRule: Encodable, Equatable {
    var action: SafariAction
    var trigger: SafariTrigger
}

struct SafariAction: Encodable, Equatable {
    var type: SafariActionType
    var selector: String?

    enum CodingKeys: String, CodingKey {
        case type
        case selector
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(selector, forKey: .selector)
    }
}

enum SafariActionType: String, Encodable {
    case block
    case blockCookies = "block-cookies"
    case cssDisplayNone = "css-display-none"
    case ignorePreviousRules = "ignore-previous-rules"
    case makeHTTPS = "make-https"
}

struct SafariTrigger: Encodable, Equatable {
    var urlFilter: String
    var urlFilterIsCaseSensitive: Bool?
    var resourceType: [SafariResourceType]?
    var loadType: [SafariLoadType]?
    var ifDomain: [String]?
    var unlessDomain: [String]?

    enum CodingKeys: String, CodingKey {
        case urlFilter = "url-filter"
        case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
        case resourceType = "resource-type"
        case loadType = "load-type"
        case ifDomain = "if-domain"
        case unlessDomain = "unless-domain"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(urlFilter, forKey: .urlFilter)
        try container.encodeIfPresent(urlFilterIsCaseSensitive, forKey: .urlFilterIsCaseSensitive)
        try container.encodeIfPresent(resourceType?.sorted { $0.rawValue < $1.rawValue }, forKey: .resourceType)
        try container.encodeIfPresent(loadType?.sorted { $0.rawValue < $1.rawValue }, forKey: .loadType)
        try container.encodeIfPresent(ifDomain?.sorted(), forKey: .ifDomain)
        try container.encodeIfPresent(unlessDomain?.sorted(), forKey: .unlessDomain)
    }
}

enum SafariRuleWriter {
    static func write(_ rules: [SafariContentBlockerRule]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(rules)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
