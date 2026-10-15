import Foundation

/// Ad and tracking hosts that the default lists only block by path. Blocking
/// them as third parties leaves their own sites and dashboards working.
/// Hosts that real pages depend on (Facebook login, YouTube video, JW Player,
/// chat and signup widgets) are left out on purpose.
public enum BuiltInBlockRules {
    static let hosts = [
        "adtech.yahooinc.com", "advertising-api-eu.amazon.com", "advertising.apple.com",
        "advertising.yahoo.com", "advertising.yandex.ru", "ads-api.tiktok.com", "ads-sg.tiktok.com",
        "ads.huawei.com", "ads.microsoft.com", "ads.vk.com", "ads.x.com", "analytics.twitter.com",
        "analytics.x.com", "app.posthog.com", "appmetrica.yandex.ru", "business-api.tiktok.com",
        "c.bing.com", "eu.posthog.com", "fingerprintjs.com", "g.jwpsrv.com", "gemini.yahoo.com",
        "log.fc.yahoo.com", "mads-eu.amazon.com", "metrika.yandex.ru", "mineralt.io",
        "ngfts.lge.com", "pangleglobal.com", "pixel.quora.com", "qevents.quora.com",
        "rudderstack.com", "smartclip.com", "snap.licdn.com", "snowplowanalytics.com",
        "tagmanager.google.com", "tr.facebook.com", "udc.yahoo.com", "udcm.yahoo.com",
        "xp.apple.com",
    ]

    public static let text = hosts.map { "||\($0)^$third-party" }.joined(separator: "\n")

    /// Extra source rules for the Custom slot: these rules while any list is
    /// on, plus the element zapper's rules.
    public static func extraRulesText(filtersEnabled: Bool, zapperRulesText: String?) -> String? {
        let parts = [filtersEnabled ? text : nil, zapperRulesText].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
