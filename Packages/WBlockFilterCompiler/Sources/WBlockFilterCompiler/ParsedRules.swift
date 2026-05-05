import Foundation

enum ParsedRule: Equatable {
    case comment
    case preprocessor
    case network(NetworkRule)
    case cosmetic(CosmeticRule)
    case cosmeticException(CosmeticRule)
    case unsupported(UnsupportedReason)
}

struct NetworkRule: Equatable {
    var source: SourceLine
    var isException: Bool
    var action: NetworkAction
    var pattern: String
    var resourceTypes: Set<SafariResourceType>
    var loadType: SafariLoadType?
    var ifDomains: [String]
    var unlessDomains: [String]
    var toDomains: [String]
    var denyAllowDomains: [String]
    var removeParameters: [String]
    var urlSkipSteps: String?
    var uriTransform: String?
    var redirectResource: String?
    var matchCase: Bool
    var important: Bool
    var isBadfilter: Bool
    var canonicalIdentity: String
}

struct CosmeticRule: Equatable {
    var source: SourceLine
    var selector: String
    var ifDomains: [String]
    var unlessDomains: [String]
}

enum SafariResourceType: String, CaseIterable, Encodable, Hashable {
    case document
    case image
    case styleSheet = "style-sheet"
    case script
    case font
    case raw
    case svgDocument = "svg-document"
    case media
    case popup
}

enum SafariLoadType: String, Encodable, Hashable {
    case firstParty = "first-party"
    case thirdParty = "third-party"
}

enum NetworkAction: Equatable {
    case block
    case blockCookies
    case makeHTTPS
}

extension NetworkRule {
    var requiresAdvancedURLHandling: Bool {
        !removeParameters.isEmpty || urlSkipSteps != nil || uriTransform != nil || redirectResource != nil
    }
}
