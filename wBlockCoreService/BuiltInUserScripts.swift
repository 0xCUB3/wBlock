import Foundation

public enum BuiltInUserScriptTier: String, Sendable {
    case featured
    case automatic
    case advancedOnly
}

public enum BuiltInUserScriptBasicGroup: String, CaseIterable, Identifiable, Sendable {
    case video
    case reading

    public var id: String { rawValue }
}

struct BuiltInUserScriptDefinition {
    let name: String
    let url: String
    let isEnabledByDefault: Bool
    let description: String
    let languages: [String]
    let displayRole: BuiltInUserScriptDisplayRole?
    let isBeta: Bool
    /// Shown before the script is downloaded and kept afterwards (#1106).
    let author: String
    let homepage: String
    let tier: BuiltInUserScriptTier
    let basicGroup: BuiltInUserScriptBasicGroup?

    init(
        name: String,
        url: String,
        isEnabledByDefault: Bool,
        description: String = "Default userscript",
        languages: [String] = [],
        displayRole: BuiltInUserScriptDisplayRole? = nil,
        isBeta: Bool = false,
        author: String,
        homepage: String,
        tier: BuiltInUserScriptTier = .advancedOnly,
        basicGroup: BuiltInUserScriptBasicGroup? = nil
    ) {
        self.name = name
        self.url = url
        self.isEnabledByDefault = isEnabledByDefault
        self.description = description
        self.languages = languages.map { $0.lowercased() }
        self.displayRole = displayRole
        self.isBeta = isBeta
        self.author = author
        self.homepage = homepage
        self.tier = tier
        self.basicGroup = basicGroup
    }
}

enum BuiltInUserScripts {
    static let popupBlockerName = "AdGuard Popup Blocker"
    static let popupBlockerStableURL =
        "https://userscripts.adtidy.org/release/popup-blocker/2.5/popupblocker.user.js"
    static let adGuardExtraURL =
        "https://userscripts.adtidy.org/release/adguard-extra/1.0/adguard-extra.user.js"
    static let adGuardExtraHostManifestURL =
        "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/manifests/adguard-extra-hosts.json"
    static let tinyShieldURL =
        "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/tinyShield.user.js"
    static let tinyShieldDescription =
        "Lets ad blockers quickly resist Ad-Shield, which reinserts ads on matching sites after filter lists hide them."
    static let retiredYouTubeAdBlockURL =
        "https://raw.githubusercontent.com/SysAdminDoc/YoutubeAdblock/main/YoutubeAdblock.user.js"

    static let tubeCleanerURL = "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/tube-cleaner/dist/tube-cleaner.user.js"
    static let deArrowURL = DeArrowPreference.scriptURL
    static let deArrowDescription = "Blocks clickbait titles and thumbnails on YouTube and replaces them with accurate ones from the DeArrow community."
    static let playerCleanerURL = "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/player-cleaner/dist/player-cleaner.user.js"
    static let darkReaderURL = DarkReaderAppearancePreference.scriptURL
    static let darkReaderDescription =
        "Makes websites dark by restyling their colors, from the Dark Reader project. Some sites may look off, since it doesn't include Dark Reader's site fixes."
    static let disableAMPURL = "https://userscripts.adtidy.org/release/disable-amp/1.0/disable-amp.user.js"
    static let disableAMPDescription = "Opens the publisher's regular page instead of its AMP version, from the AdGuard project."
    static let tubeCleanerDescription =
        "Blocks YouTube's ads and web player and plays videos in Safari's native player, with chapters, picture-in-picture, background playback, and audio-only mode. Includes SponsorBlock, which skips sponsored segments."
    static let playerCleanerDescription =
        "Blocks third-party video players on other sites and plays videos with Safari's native controls, adding auto PiP, background playback, subtitles, chapters, and Now Playing info."

    static let definitions: [BuiltInUserScriptDefinition] = [
        BuiltInUserScriptDefinition(
            name: "Tube Cleaner",
            url: tubeCleanerURL,
            isEnabledByDefault: false,
            description: tubeCleanerDescription,
            displayRole: .functionality,
            isBeta: true,
            author: "wBlock",
            homepage: "https://github.com/0xCUB3/wBlock-userscripts",
            tier: .featured,
            basicGroup: .video
        ),
        BuiltInUserScriptDefinition(
            name: "DeArrow",
            url: deArrowURL,
            isEnabledByDefault: false,
            description: deArrowDescription,
            displayRole: .functionality,
            isBeta: true,
            author: "wBlock",
            homepage: "https://dearrow.ajay.app/",
            tier: .featured,
            basicGroup: .video
        ),
        BuiltInUserScriptDefinition(
            name: "Player Cleaner",
            url: playerCleanerURL,
            isEnabledByDefault: false,
            description: playerCleanerDescription,
            displayRole: .functionality,
            isBeta: true,
            author: "wBlock",
            homepage: "https://github.com/0xCUB3/wBlock-userscripts",
            tier: .featured,
            basicGroup: .video
        ),
        BuiltInUserScriptDefinition(
            name: "Dark Reader",
            url: darkReaderURL,
            isEnabledByDefault: false,
            description: darkReaderDescription,
            displayRole: .functionality,
            isBeta: true,
            author: "Dark Reader Ltd. and wBlock",
            homepage: "https://darkreader.org/",
            tier: .featured,
            basicGroup: .reading
        ),
        // Content blockers can't redirect, so AMP pages need AdGuard's script (#1095).
        BuiltInUserScriptDefinition(
            name: "Disable AMP",
            url: disableAMPURL,
            isEnabledByDefault: false,
            description: disableAMPDescription,
            displayRole: .functionality,
            author: "AdGuard",
            homepage: "https://adguard.com/",
            tier: .featured,
            basicGroup: .reading
        ),
        BuiltInUserScriptDefinition(
            name: "Return YouTube Dislike",
            url: "https://raw.githubusercontent.com/Anarios/return-youtube-dislike/main/Extensions/UserScript/Return%20Youtube%20Dislike.user.js",
            isEnabledByDefault: false,
            displayRole: .functionality,
            author: "Anarios & JRWR",
            homepage: "https://www.returnyoutubedislike.com/",
            tier: .featured,
            basicGroup: .video
        ),
        BuiltInUserScriptDefinition(
            name: "Bypass Paywalls Clean",
            url: "https://greasyfork.org/scripts/542351-bypass-paywalls-clean-en/code/Bypass%20Paywalls%20Clean%20(EN).user.js",
            isEnabledByDefault: false,
            languages: ["en"],
            displayRole: .functionality,
            author: "magnolia1234",
            homepage: "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters",
            tier: .featured,
            basicGroup: .reading
        ),
        BuiltInUserScriptDefinition(
            name: "AdGuard Extra",
            url: adGuardExtraURL,
            isEnabledByDefault: false,
            description: "Blocks Twitch ads and handles complicated anti-adblock cases, from the AdGuard project. It slows page loads.",
            displayRole: .functionality,
            author: "AdGuard",
            homepage: "https://adguard.com/",
            tier: .advancedOnly
        ),
        BuiltInUserScriptDefinition(
            name: "TwitchAdSolutions (vaft)",
            url: "https://raw.githubusercontent.com/ryanbr/TwitchAdSolutions/master/vaft/vaft.user.js",
            isEnabledByDefault: false,
            description: "Blocks Twitch ads with the vaft script from TwitchAdSolutions.",
            displayRole: .blocking,
            author: "ryanbr (Fanboy)",
            homepage: "https://github.com/ryanbr/TwitchAdSolutions",
            tier: .featured,
            basicGroup: .video
        ),
        BuiltInUserScriptDefinition(
            name: "tinyShield",
            url: tinyShieldURL,
            isEnabledByDefault: true,
            description: tinyShieldDescription,
            displayRole: .blocking,
            author: "PiQuark6046 and contributors",
            homepage: "https://github.com/FilteringDev/tinyShield",
            tier: .automatic
        ),
        BuiltInUserScriptDefinition(
            name: popupBlockerName,
            url: popupBlockerStableURL,
            isEnabledByDefault: false,
            description: "Blocks pop-up and pop-under windows that pages open when you click, from the AdGuard project.",
            displayRole: .blocking,
            author: "AdGuard",
            homepage: "https://popupblocker.adguard.com/release/v1",
            tier: .advancedOnly
        ),
    ]

    static let protectedURLs = Set(definitions.map(\.url))
    static let displayRoleByURL = Dictionary(uniqueKeysWithValues: definitions.compactMap { definition in
        definition.displayRole.map { (definition.url, $0) }
    })
    static let isBetaByURL = Dictionary(
        uniqueKeysWithValues: definitions.filter(\.isBeta).map { ($0.url, true) }
    )
    static let languagesByURL = Dictionary(
        uniqueKeysWithValues: definitions.map { ($0.url, $0.languages) }
    )
    static let isEnabledByDefaultByURL = Dictionary(
        uniqueKeysWithValues: definitions.map { ($0.url, $0.isEnabledByDefault) }
    )
    static let tierByURL = Dictionary(
        uniqueKeysWithValues: definitions.map { ($0.url, $0.tier) }
    )
    static let basicGroupByURL = Dictionary(uniqueKeysWithValues: definitions.compactMap { definition in
        definition.basicGroup.map { (definition.url, $0) }
    })
    static let bypassPaywallsCleanURL =
        "https://greasyfork.org/scripts/542351-bypass-paywalls-clean-en/code/Bypass%20Paywalls%20Clean%20(EN).user.js"

    static func definition(for url: URL?) -> BuiltInUserScriptDefinition? {
        guard let source = url?.absoluteString else { return nil }
        return definitions.first { $0.url == source }
    }

    /// Catalog credits, so a built-in shows its author and homepage before it
    /// is downloaded and after a reload from the store, which keeps only edits.
    static func applyCredits(_ definition: BuiltInUserScriptDefinition? = nil, to script: inout UserScript) {
        guard let definition = definition ?? self.definition(for: script.url) else { return }
        script.author = script.metadataAuthorOverride ?? definition.author
        script.homepage = script.metadataHomepageOverride ?? definition.homepage
    }

    /// Catalog keys keep curated metadata localizable; uncataloged descriptions use the header.
    @discardableResult
    static func applyDisplayMetadata(to script: inout UserScript) -> Bool {
        guard let definition = definition(for: script.url) else { return false }
        let previousName = script.name
        let previousDescription = script.description
        let previousAuthor = script.author
        let previousHomepage = script.homepage
        script.name = definition.name
        if definition.description != "Default userscript" {
            script.description = definition.description
        }
        applyCredits(definition, to: &script)
        return script.name != previousName || script.description != previousDescription
            || script.author != previousAuthor || script.homepage != previousHomepage
    }
}
