//
//  wBlockCoreService.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 5/23/25.
//

internal import WBEngine
import CryptoKit
import Foundation
import SafariServices
import os.log

private final class ContentBlockerServiceBundleMarker {}

/// ContentBlockerService provides functionality to convert AdGuard rules to Safari content blocking format
/// and manage content blocker extensions.
public enum ContentBlockerService {

public struct ContentBlockerTargetOutcome: Sendable {
    public let safariRulesCount: Int
    public let truncatedRuleCount: Int
    public let advancedRulesText: String?
    public let reusedCachedBase: Bool
    public let outputChanged: Bool
    /// Per-filter source rule lines admitted by the target's real input path
    /// after site scoping, affinity filtering, cosmetic filtering, and the same
    /// identity deduplication used before conversion. This is not a per-filter
    /// Safari JSON output count; the converter only reports target totals.
    public let admittedSourceRuleCountsByFilterID: [UUID: Int]

    public init(
        safariRulesCount: Int,
        advancedRulesText: String?,
        reusedCachedBase: Bool,
        truncatedRuleCount: Int = 0,
        admittedSourceRuleCountsByFilterID: [UUID: Int] = [:]
    ) {
        self.init(
            safariRulesCount: safariRulesCount,
            truncatedRuleCount: truncatedRuleCount,
            advancedRulesText: advancedRulesText,
            reusedCachedBase: reusedCachedBase,
            outputChanged: true,
            admittedSourceRuleCountsByFilterID: admittedSourceRuleCountsByFilterID
        )
    }

    public init(
        safariRulesCount: Int,
        truncatedRuleCount: Int = 0,
        advancedRulesText: String?,
        reusedCachedBase: Bool,
        outputChanged: Bool,
        admittedSourceRuleCountsByFilterID: [UUID: Int] = [:]
    ) {
        self.safariRulesCount = safariRulesCount
        self.truncatedRuleCount = truncatedRuleCount
        self.advancedRulesText = advancedRulesText
        self.reusedCachedBase = reusedCachedBase
        self.outputChanged = outputChanged
        self.admittedSourceRuleCountsByFilterID = admittedSourceRuleCountsByFilterID
    }
}

public struct ContentBlockerSaveResult: Sendable {
    public let ruleCount: Int
    public let outputChanged: Bool
}

private struct StoredTargetSourceRuleProvenance: Codable {
    let schemaVersion: Int
    let inputSignature: String
    let admittedSourceRuleCountsByFilterID: [String: Int]

    init(admittedSourceRuleCountsByFilterID: [UUID: Int], inputSignature: String) {
        self.schemaVersion = 1
        self.inputSignature = inputSignature
        self.admittedSourceRuleCountsByFilterID = Dictionary(
            uniqueKeysWithValues: admittedSourceRuleCountsByFilterID.map { ($0.key.uuidString, $0.value) }
        )
    }

    var decodedCounts: [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: admittedSourceRuleCountsByFilterID.compactMap { key, value in
                guard let id = UUID(uuidString: key) else { return nil }
                return (id, value)
            }
        )
    }
}

    /// A valid Safari content blocker list that performs no blocking.
    ///
    /// Some Safari versions fail to reload an extension backed by a literal empty
    /// array with WKErrorDomain error 6, so pause/clear paths use this inert rule
    /// instead of `[]`.
    public static let inertContentBlockerRulesJSON = """
    [
      {
        "trigger": { "url-filter": "^https?://wblock-pause-never-match[.]invalid/" },
        "action": { "type": "ignore-previous-rules" }
      }
    ]
    """

    public static let inertContentBlockerRuleCount = 1

    /// Safari's documented per-extension content blocker rule limit.
    public static let safariContentBlockerRuleLimit = 150_000

    /// Version marker for built-in compatibility rules that are appended to
    /// every conversion. Bump this when changing `embeddedCompatibilityRules`
    /// so cached base JSON gets invalidated.
    // 8: defuse Urban Dictionary's AdShield fallback without triggering its sentinel redirect.
    // 9: remove the Valnet sites' anti-adblock dialog (#895).
    public static let embeddedCompatibilityRulesVersion = "9"
    private static let contentBlockerOutputLockTimeout: TimeInterval = 10

    /// Built-in compatibility rules that improve blocking of common dynamic ad script
    /// patterns and dynamic ad containers across filter sets.
    ///
    /// YouTube rules use trusted response replacement for pre-parse string
    /// replacement (faster than json-prune-fetch-response which works post-parse).
    /// Sourced from uAssets, translated to AdGuard syntax. Host lists follow
    /// uAssets where it publishes them; music.youtube.com is also applied to the
    /// shared player-endpoint rules because it loads ads through the same
    /// youtubei/v1/player responses.
    ///
    /// Diagnostic-site rules are scoped to their hostnames so they do not affect
    /// normal browsing.
    private static let embeddedCompatibilityRules = """
! Common synthetic ad bait paths
/js/widget/ads.js$script
/js/pagead.js$script
/widget/pagead.js$script
##.adbox.banner_ads.adsbox

! Urban Dictionary AdShield compatibility
! Keep the loader sentinel: suppressing eval outright triggers a reporting-page redirect.
||html-load.com^$script,domain=urbandictionary.com
urbandictionary.com#%#//scriptlet('trusted-replace-argument', 'eval', '0', 'replace:/^(window[.][a-zA-Z0-9_$]+=true;)(?=[^]*Please allow ads on this site)[^]*/$1/', 'html-load.com')

! Valnet anti-adblock dialog (howtogeek.com and sister sites), from AdGuard Popups
topspeed.com,polygon.com,howtogeek.com,pocket-lint.com,cbr.com,thegamer.com,collider.com,xda-developers.com,gamerant.com,screenrant.com,makeuseof.com,androidpolice.com,fextralife.com#$?#.adblock { remove: true; }
topspeed.com,polygon.com,howtogeek.com,pocket-lint.com,cbr.com,thegamer.com,collider.com,xda-developers.com,gamerant.com,screenrant.com,makeuseof.com,androidpolice.com,fextralife.com#$#body { overflow: auto !important; }
topspeed.com,polygon.com,howtogeek.com,pocket-lint.com,cbr.com,thegamer.com,collider.com,xda-developers.com,gamerant.com,screenrant.com,makeuseof.com,androidpolice.com,fextralife.com#%#//scriptlet('prevent-fetch', 'adsbygoogle.js')

! NameMC Ad-Shield/Network N compatibility
||html-load.com^$script,domain=namemc.com
||kumo.network-n.com^$script,domain=namemc.com
||btloader.com^$script,domain=namemc.com
||securepubads.g.doubleclick.net/tag/js/gpt.js$script,domain=namemc.com
||ad-delivery.net^$domain=namemc.com
||k.streamrail.com^$domain=namemc.com
namemc.com##.ad-container
namemc.com##[id^="nn_"]
namemc.com##iframe[src*="html-load.com"]

! AdBlock Tester diagnostic bait compatibility
||ymatuhin.ru/ads/ads.js$script,domain=adblock-tester.com|checkadblock.ru
||pagead2.googlesyndication.com/pagead/js/adsbygoogle.js$script,domain=adblock-tester.com|checkadblock.ru
||an.yandex.ru/system/context.js$script,domain=adblock-tester.com|checkadblock.ru
||www.googletagmanager.com/gtag/js$script,domain=adblock-tester.com|checkadblock.ru
||static.hotjar.com/c/hotjar-$script,domain=adblock-tester.com|checkadblock.ru
||mc.yandex.ru/metrika/tag.js$script,domain=adblock-tester.com|checkadblock.ru
||js.sentry-cdn.com^$script,domain=adblock-tester.com|checkadblock.ru
||browser.sentry-cdn.com^$script,domain=adblock-tester.com|checkadblock.ru
||d2wy8f7a9ursnm.cloudfront.net/v*/bugsnag.min.js$script,domain=adblock-tester.com|checkadblock.ru
||adblock-tester.com/banners/pr_advertising_ads_banner.$domain=adblock-tester.com
||checkadblock.ru/banners/pr_advertising_ads_banner.$domain=checkadblock.ru
adblock-tester.com,checkadblock.ru##[data-ads]
adblock-tester.com,checkadblock.ru##ins.adsbygoogle
adblock-tester.com,checkadblock.ru##[id^="yandex_rtb_"]
adblock-tester.com,checkadblock.ru##img[src^="/banners/pr_advertising_ads_banner."]
adblock-tester.com,checkadblock.ru##object[data^="/banners/pr_advertising_ads_banner."]
adblock-tester.com,checkadblock.ru##embed[src^="/banners/pr_advertising_ads_banner."]

! Turtlecute diagnostic bait compatibility
/js/widget/ads.js$script,domain=adblock.turtlecute.org
/js/pagead.js$script,domain=adblock.turtlecute.org
/pagead.js$script,domain=adblock.turtlecute.org
/widget/ads.$script,domain=adblock.turtlecute.org
adblock.turtlecute.org##.adbox.banner_ads.adsbox
adblock.turtlecute.org##.textads
! Turtlecute Ads
||adtago.s3.amazonaws.com^$domain=adblock.turtlecute.org
||analyticsengine.s3.amazonaws.com^$domain=adblock.turtlecute.org
||analytics.s3.amazonaws.com^$domain=adblock.turtlecute.org
||advice-ads.s3.amazonaws.com^$domain=adblock.turtlecute.org
||pagead2.googlesyndication.com^$domain=adblock.turtlecute.org
||adservice.google.com^$domain=adblock.turtlecute.org
||pagead2.googleadservices.com^$domain=adblock.turtlecute.org
||afs.googlesyndication.com^$domain=adblock.turtlecute.org
||stats.g.doubleclick.net^$domain=adblock.turtlecute.org
||ad.doubleclick.net^$domain=adblock.turtlecute.org
||static.doubleclick.net^$domain=adblock.turtlecute.org
||m.doubleclick.net^$domain=adblock.turtlecute.org
||mediavisor.doubleclick.net^$domain=adblock.turtlecute.org
||ads30.adcolony.com^$domain=adblock.turtlecute.org
||adc3-launch.adcolony.com^$domain=adblock.turtlecute.org
||events3alt.adcolony.com^$domain=adblock.turtlecute.org
||wd.adcolony.com^$domain=adblock.turtlecute.org
||static.media.net^$domain=adblock.turtlecute.org
||media.net^$domain=adblock.turtlecute.org
||adservetx.media.net^$domain=adblock.turtlecute.org
! Turtlecute Analytics
||analytics.google.com^$domain=adblock.turtlecute.org
||click.googleanalytics.com^$domain=adblock.turtlecute.org
||google-analytics.com^$domain=adblock.turtlecute.org
||ssl.google-analytics.com^$domain=adblock.turtlecute.org
||adm.hotjar.com^$domain=adblock.turtlecute.org
||identify.hotjar.com^$domain=adblock.turtlecute.org
||insights.hotjar.com^$domain=adblock.turtlecute.org
||script.hotjar.com^$domain=adblock.turtlecute.org
||surveys.hotjar.com^$domain=adblock.turtlecute.org
||careers.hotjar.com^$domain=adblock.turtlecute.org
||events.hotjar.io^$domain=adblock.turtlecute.org
||mouseflow.com^$domain=adblock.turtlecute.org
||cdn.mouseflow.com^$domain=adblock.turtlecute.org
||o2.mouseflow.com^$domain=adblock.turtlecute.org
||gtm.mouseflow.com^$domain=adblock.turtlecute.org
||api.mouseflow.com^$domain=adblock.turtlecute.org
||tools.mouseflow.com^$domain=adblock.turtlecute.org
||cdn-test.mouseflow.com^$domain=adblock.turtlecute.org
||freshmarketer.com^$domain=adblock.turtlecute.org
||claritybt.freshmarketer.com^$domain=adblock.turtlecute.org
||fwtracks.freshmarketer.com^$domain=adblock.turtlecute.org
||luckyorange.com^$domain=adblock.turtlecute.org
||api.luckyorange.com^$domain=adblock.turtlecute.org
||realtime.luckyorange.com^$domain=adblock.turtlecute.org
||cdn.luckyorange.com^$domain=adblock.turtlecute.org
||w1.luckyorange.com^$domain=adblock.turtlecute.org
||upload.luckyorange.net^$domain=adblock.turtlecute.org
||cs.luckyorange.net^$domain=adblock.turtlecute.org
||settings.luckyorange.net^$domain=adblock.turtlecute.org
||stats.wp.com^$domain=adblock.turtlecute.org
! Turtlecute Error Trackers
||notify.bugsnag.com^$domain=adblock.turtlecute.org
||sessions.bugsnag.com^$domain=adblock.turtlecute.org
||api.bugsnag.com^$domain=adblock.turtlecute.org
||app.bugsnag.com^$domain=adblock.turtlecute.org
||browser.sentry-cdn.com^$domain=adblock.turtlecute.org
||app.getsentry.com^$domain=adblock.turtlecute.org
! Turtlecute Social Trackers
||pixel.facebook.com^$domain=adblock.turtlecute.org
||an.facebook.com^$domain=adblock.turtlecute.org
||static.ads-twitter.com^$domain=adblock.turtlecute.org
||ads-api.twitter.com^$domain=adblock.turtlecute.org
||ads.linkedin.com^$domain=adblock.turtlecute.org
||analytics.pointdrive.linkedin.com^$domain=adblock.turtlecute.org
||ads.pinterest.com^$domain=adblock.turtlecute.org
||log.pinterest.com^$domain=adblock.turtlecute.org
||trk.pinterest.com^$domain=adblock.turtlecute.org
||events.reddit.com^$domain=adblock.turtlecute.org
||events.redditmedia.com^$domain=adblock.turtlecute.org
||ads.youtube.com^$domain=adblock.turtlecute.org
||ads-api.tiktok.com^$domain=adblock.turtlecute.org
||analytics.tiktok.com^$domain=adblock.turtlecute.org
||ads-sg.tiktok.com^$domain=adblock.turtlecute.org
||analytics-sg.tiktok.com^$domain=adblock.turtlecute.org
||business-api.tiktok.com^$domain=adblock.turtlecute.org
||ads.tiktok.com^$domain=adblock.turtlecute.org
||log.byteoversea.com^$domain=adblock.turtlecute.org
! Turtlecute Mix
||ads.yahoo.com^$domain=adblock.turtlecute.org
||analytics.yahoo.com^$domain=adblock.turtlecute.org
||geo.yahoo.com^$domain=adblock.turtlecute.org
||udcm.yahoo.com^$domain=adblock.turtlecute.org
||analytics.query.yahoo.com^$domain=adblock.turtlecute.org
||partnerads.ysm.yahoo.com^$domain=adblock.turtlecute.org
||log.fc.yahoo.com^$domain=adblock.turtlecute.org
||gemini.yahoo.com^$domain=adblock.turtlecute.org
||adtech.yahooinc.com^$domain=adblock.turtlecute.org
||extmaps-api.yandex.net^$domain=adblock.turtlecute.org
||appmetrica.yandex.ru^$domain=adblock.turtlecute.org
||adfstat.yandex.ru^$domain=adblock.turtlecute.org
||metrika.yandex.ru^$domain=adblock.turtlecute.org
||offerwall.yandex.net^$domain=adblock.turtlecute.org
||adfox.yandex.ru^$domain=adblock.turtlecute.org
||auction.unityads.unity3d.com^$domain=adblock.turtlecute.org
||webview.unityads.unity3d.com^$domain=adblock.turtlecute.org
||config.unityads.unity3d.com^$domain=adblock.turtlecute.org
||adserver.unityads.unity3d.com^$domain=adblock.turtlecute.org
! Turtlecute OEMs
||iot-eu-logser.realme.com^$domain=adblock.turtlecute.org
||iot-logser.realme.com^$domain=adblock.turtlecute.org
||bdapi-ads.realmemobile.com^$domain=adblock.turtlecute.org
||bdapi-in-ads.realmemobile.com^$domain=adblock.turtlecute.org
||api.ad.xiaomi.com^$domain=adblock.turtlecute.org
||data.mistat.xiaomi.com^$domain=adblock.turtlecute.org
||data.mistat.india.xiaomi.com^$domain=adblock.turtlecute.org
||data.mistat.rus.xiaomi.com^$domain=adblock.turtlecute.org
||sdkconfig.ad.xiaomi.com^$domain=adblock.turtlecute.org
||sdkconfig.ad.intl.xiaomi.com^$domain=adblock.turtlecute.org
||tracking.rus.miui.com^$domain=adblock.turtlecute.org
||adsfs.oppomobile.com^$domain=adblock.turtlecute.org
||adx.ads.oppomobile.com^$domain=adblock.turtlecute.org
||ck.ads.oppomobile.com^$domain=adblock.turtlecute.org
||data.ads.oppomobile.com^$domain=adblock.turtlecute.org
||metrics.data.hicloud.com^$domain=adblock.turtlecute.org
||metrics2.data.hicloud.com^$domain=adblock.turtlecute.org
||grs.hicloud.com^$domain=adblock.turtlecute.org
||logservice.hicloud.com^$domain=adblock.turtlecute.org
||logservice1.hicloud.com^$domain=adblock.turtlecute.org
||logbak.hicloud.com^$domain=adblock.turtlecute.org
||click.oneplus.cn^$domain=adblock.turtlecute.org
||open.oneplus.net^$domain=adblock.turtlecute.org
||samsungads.com^$domain=adblock.turtlecute.org
||smetrics.samsung.com^$domain=adblock.turtlecute.org
||nmetrics.samsung.com^$domain=adblock.turtlecute.org
||samsung-com.112.2o7.net^$domain=adblock.turtlecute.org
||analytics-api.samsunghealthcn.com^$domain=adblock.turtlecute.org
||iadsdk.apple.com^$domain=adblock.turtlecute.org
||metrics.icloud.com^$domain=adblock.turtlecute.org
||metrics.mzstatic.com^$domain=adblock.turtlecute.org
||api-adservices.apple.com^$domain=adblock.turtlecute.org
||books-analytics-events.apple.com^$domain=adblock.turtlecute.org
||weather-analytics-events.apple.com^$domain=adblock.turtlecute.org
||notes-analytics-events.apple.com^$domain=adblock.turtlecute.org

! YouTube compatibility
www.youtube.com,music.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '"adPlacements"', '"no_ads"', 'player?')
www.youtube.com,music.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '"adSlots"', '"no_ads"', 'player?')
www.youtube.com,music.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '"adPlacements"', '"no_ads"', 'player?')
www.youtube.com,music.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '"adSlots"', '"no_ads"', 'player?')
www.youtube.com,music.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '"adPlacements"', '"no_ads"', 'get_watch?')
www.youtube.com,music.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '"adSlots"', '"no_ads"', 'get_watch?')
www.youtube.com,music.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '"adPlacements"', '"no_ads"', 'get_watch?')
www.youtube.com,music.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '"adSlots"', '"no_ads"', 'get_watch?')
m.youtube.com,music.youtube.com,tv.youtube.com,www.youtube.com,youtubekids.com,youtube-nocookie.com#%#//scriptlet('set-constant', 'ytInitialPlayerResponse.playerAds', 'undefined')
m.youtube.com,music.youtube.com,tv.youtube.com,www.youtube.com,youtubekids.com,youtube-nocookie.com#%#//scriptlet('set-constant', 'ytInitialPlayerResponse.adPlacements', 'undefined')
m.youtube.com,music.youtube.com,tv.youtube.com,www.youtube.com,youtubekids.com,youtube-nocookie.com#%#//scriptlet('set-constant', 'ytInitialPlayerResponse.adSlots', 'undefined')
m.youtube.com,music.youtube.com,tv.youtube.com,www.youtube.com,youtubekids.com,youtube-nocookie.com#%#//scriptlet('set-constant', 'playerResponse.playerAds', 'undefined')
m.youtube.com,music.youtube.com,tv.youtube.com,www.youtube.com,youtubekids.com,youtube-nocookie.com#%#//scriptlet('set-constant', 'playerResponse.adPlacements', 'undefined')
m.youtube.com,music.youtube.com,tv.youtube.com,www.youtube.com,youtubekids.com,youtube-nocookie.com#%#//scriptlet('set-constant', 'playerResponse.adSlots', 'undefined')
"""

    private static func compatibilityRulesFingerprintHex() -> String {
        let payload = "\(embeddedCompatibilityRulesVersion)\n\(embeddedCompatibilityRules)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Derives an effective conversion hash from the caller-provided rules hash
    /// plus built-in compatibility-rules fingerprint so cache keys are invalidated
    /// when embedded compatibility rules change.
    private static func effectiveRulesHashHex(
        baseRulesHashHex: String,
        cosmeticSites: CosmeticFilteringPreference.Sites = .all
    ) -> String {
        let fingerprint = compatibilityRulesFingerprintHex() + "|identity-v6|" + SafariVersionDetection.compilerIdentity
        let material = cosmeticSites.cacheMarker.map { "\(baseRulesHashHex)|\(fingerprint)|cosmetic=\($0)" }
            ?? "\(baseRulesHashHex)|\(fingerprint)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the default filter file contents from the main bundle.
    ///
    /// - Returns: The contents of the default filter list or an error message if the file cannot be read.
    public struct ReloadAttemptResult: Sendable {
        public let success: Bool
        public let skipped: Bool
        /// Safari refused the reload because the user has turned this extension
        /// off in Safari settings. The rules are already on disk and Safari loads
        /// them when the extension is enabled again, so callers must not treat
        /// this as an apply failure.
        public let disabledInSafari: Bool
        public let attempts: Int
        public let durationMs: Int
        /// Why the reload failed, in a form that can be shown in the app log.
        /// nil on success or when the reload was skipped.
        public let failureReason: String?

        public init(
            success: Bool,
            skipped: Bool = false,
            disabledInSafari: Bool = false,
            attempts: Int,
            durationMs: Int,
            failureReason: String? = nil
        ) {
            self.success = success
            self.skipped = skipped
            self.disabledInSafari = disabledInSafari
            self.attempts = attempts
            self.durationMs = durationMs
            self.failureReason = failureReason
        }
    }

    /// Stable reasons for reload failures that do not come from Safari itself.
    public enum ReloadFailureReason {
        public static let noAppGroupContainer = "App Group container is unavailable"
        public static let outputUnreadable = "Content blocker rules file could not be read"
        public static let outputChangedDuringReload = "Rules file kept changing while reloading"
        public static let markerWriteFailed = "Could not record the reload result"
        public static let anotherReloadInProgress = "Another reload for this extension was already running"
        public static let cancelled = "Reload was cancelled"
        public static let invalidArguments = "Invalid reload request"
        public static let disabledInSafari = "Extension is turned off in Safari"
    }

    private actor ReloadCoordinator {
        private struct Waiter {
            let id: UUID
            let continuation: CheckedContinuation<Bool, Never>
        }

        private var activeKeys: Set<String> = []
        private var waiters: [String: [Waiter]] = [:]

        func withGate<T: Sendable>(
            key: String,
            operation: @Sendable () async -> T
        ) async -> T? {
            guard await acquire(key) else { return nil }
            guard !Task.isCancelled else {
                release(key)
                return nil
            }
            defer { release(key) }
            return await operation()
        }

        private func acquire(_ key: String) async -> Bool {
            guard !Task.isCancelled else { return false }
            guard activeKeys.contains(key) else {
                activeKeys.insert(key)
                return true
            }

            let id = UUID()
            return await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(returning: false)
                    } else {
                        waiters[key, default: []].append(
                            Waiter(id: id, continuation: continuation)
                        )
                    }
                }
            }, onCancel: {
                Task { await self.cancelWaiter(key: key, id: id) }
            })
        }

        private func cancelWaiter(key: String, id: UUID) {
            guard var keyWaiters = waiters[key],
                  let index = keyWaiters.firstIndex(where: { $0.id == id }) else {
                return
            }
            let waiter = keyWaiters.remove(at: index)
            if keyWaiters.isEmpty {
                waiters.removeValue(forKey: key)
            } else {
                waiters[key] = keyWaiters
            }
            waiter.continuation.resume(returning: false)
        }

        private func release(_ key: String) {
            guard var keyWaiters = waiters[key], !keyWaiters.isEmpty else {
                activeKeys.remove(key)
                return
            }
            let next = keyWaiters.removeFirst()
            if keyWaiters.isEmpty {
                waiters.removeValue(forKey: key)
            } else {
                waiters[key] = keyWaiters
            }
            next.continuation.resume(returning: true)
        }
    }

    private struct ReloadMarker: Codable, Equatable {
        let schema: Int
        let outputDigest: String
        let context: ReloadContext
    }

    private struct ReloadContext: Codable, Equatable {
        let schema: Int
        let platform: String
        let osVersion: String
        let appVersion: String
        let appBuild: String
    }

    private struct ReloadSnapshot {
        let marker: ReloadMarker?
        let outputDigest: String?
        let outputIdentity: OutputIdentity?
        let context: ReloadContext
    }

    private enum ReloadMarkerWriteResult {
        case written
        case paused
        case changed
        case failed
    }

    /// Identifies one published output file. Every writer replaces the output
    /// atomically, so new bytes always get a new identity and an existing
    /// mapping keeps the bytes it was opened with.
    private struct OutputIdentity: Equatable {
        let fileNumber: Int
        let size: Int
        let modified: Date?
    }

    private static func outputIdentity(_ url: URL) -> OutputIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.intValue,
              let size = (attributes[.size] as? NSNumber)?.intValue
        else { return nil }
        return OutputIdentity(fileNumber: fileNumber, size: size, modified: attributes[.modificationDate] as? Date)
    }

    /// Maps the output without reading it. Parsing and hashing a large output
    /// takes seconds, and a process suspended while holding the output lock is
    /// killed (0xDEAD10CC), so callers take the lock only around this and
    /// identity checks, then parse after unlocking.
    private static func mapOutput(_ url: URL) -> (data: Data, identity: OutputIdentity)? {
        guard let identity = outputIdentity(url),
              let data = try? Data(contentsOf: url, options: .alwaysMapped),
              outputIdentity(url) == identity
        else { return nil }
        return (data, identity)
    }

    private static let reloadMarkerSchema = 1
    private static let reloadMarkerFileSuffix = ".reload-marker.json"
    private static let disabledSitesApplyInProgressFilename = ".disabled-sites-apply-in-progress"
    // Five total attempts can each wait reloadCompletionTimeout; retain one extra timeout as margin.
    private static let disabledSitesApplyInProgressMaximumAge: TimeInterval = reloadCompletionTimeout * 6
    private static let reloadContextAppVersionKey = "wBlock.reloadContext.appVersion"
    private static let reloadContextAppBuildKey = "wBlock.reloadContext.appBuild"
    private static let maxReloadVerificationPasses = 3
    private static let reloadCoordinator = ReloadCoordinator()

    /// Uses the containing app as the sole publisher so all app-group processes
    /// compare reload markers against the same app upgrade identity.
    private static func sharedReloadIdentity() -> (appVersion: String, appBuild: String) {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value)
        if Bundle.main.bundleIdentifier == "skula.wBlock" {
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            defaults?.set(appVersion, forKey: reloadContextAppVersionKey)
            defaults?.set(appBuild, forKey: reloadContextAppBuildKey)
            return (appVersion, appBuild)
        }
        return (
            defaults?.string(forKey: reloadContextAppVersionKey) ?? "",
            defaults?.string(forKey: reloadContextAppBuildKey) ?? ""
        )
    }

    private static var currentReloadContext: ReloadContext {
        #if os(iOS)
        let platform = "iOS"
        #else
        let platform = "macOS"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let identity = sharedReloadIdentity()
        return ReloadContext(
            schema: reloadMarkerSchema,
            platform: platform,
            osVersion: osVersion,
            appVersion: identity.appVersion,
            appBuild: identity.appBuild
        )
    }

    private static func reloadMarkerURL(
        targetRulesFilename: String,
        containerURL: URL
    ) -> URL {
        containerURL.appendingPathComponent(
            "\(targetRulesFilename)\(reloadMarkerFileSuffix)"
        )
    }

    private static func disabledSitesApplyInProgressURL(groupIdentifier: String) -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        )?.appendingPathComponent(disabledSitesApplyInProgressFilename)
    }

    /// Marks a Scripts-extension disabled-sites update as active so the containing
    /// app does not begin a concurrent reload before Safari finishes the first one.
    public static func markDisabledSitesApplyStarted(groupIdentifier: String) {
        guard let stampURL = disabledSitesApplyInProgressURL(groupIdentifier: groupIdentifier),
              let timestamp = String(Date().timeIntervalSince1970).data(using: .utf8)
        else {
            return
        }
        try? timestamp.write(to: stampURL, options: .atomic)
    }

    /// Clears the Scripts-extension disabled-sites update marker.
    public static func markDisabledSitesApplyFinished(groupIdentifier: String) {
        guard let stampURL = disabledSitesApplyInProgressURL(groupIdentifier: groupIdentifier) else {
            return
        }
        try? FileManager.default.removeItem(at: stampURL)
    }

    /// Returns whether a Scripts-extension disabled-sites update started recently.
    /// A stale or malformed stamp is ignored so a terminated extension cannot
    /// block later app-side updates indefinitely.
    public static func isDisabledSitesApplyInProgress(groupIdentifier: String) -> Bool {
        guard let stampURL = disabledSitesApplyInProgressURL(groupIdentifier: groupIdentifier),
              let data = try? Data(contentsOf: stampURL),
              let timestampString = String(data: data, encoding: .utf8),
              let timestamp = TimeInterval(timestampString.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return false
        }

        let age = Date().timeIntervalSince1970 - timestamp
        return age >= 0 && age < disabledSitesApplyInProgressMaximumAge
    }

    private static func validOutputDigest(_ data: Data?) throws -> String? {
        try Task.checkCancellation()
        guard let data,
              !data.isEmpty,
              ContentBlockerRuleArray.count(data) != nil
        else { return nil }
        return try ContentBlockerChunkedHasher.hexDigest(
            for: data,
            isCancelled: { Task.isCancelled }
        )
    }

    private static func readReloadSnapshot(
        markerURL: URL,
        outputURL: URL,
        appGroupURL: URL
    ) throws -> ReloadSnapshot {
        let (marker, output, context) = try withContentBlockerOutputLock(
            at: appGroupURL,
            targetRulesFilename: outputURL.lastPathComponent
        ) {
            let marker = (try? Data(contentsOf: markerURL)).flatMap {
                try? JSONDecoder().decode(ReloadMarker.self, from: $0)
            }
            return (marker, mapOutput(outputURL), currentReloadContext)
        }
        return ReloadSnapshot(
            marker: marker,
            outputDigest: try validOutputDigest(output?.data),
            outputIdentity: output?.identity,
            context: context
        )
    }

    private static func writeReloadMarkerIfUnchanged(
        markerURL: URL,
        outputURL: URL,
        appGroupURL: URL,
        expectedDigest: String,
        expectedIdentity: OutputIdentity?,
        expectedContext: ReloadContext,
        groupIdentifier: String
    ) throws -> ReloadMarkerWriteResult {
        try withContentBlockerOutputLock(at: appGroupURL, targetRulesFilename: outputURL.lastPathComponent) {
            if BlockingPauseStore.isContentBlockingPaused(groupIdentifier: groupIdentifier) {
                try? FileManager.default.removeItem(at: markerURL)
                return .paused
            }

            guard let expectedIdentity,
                  outputIdentity(outputURL) == expectedIdentity,
                  currentReloadContext == expectedContext
            else {
                try? FileManager.default.removeItem(at: markerURL)
                return .changed
            }

            let newMarker = ReloadMarker(
                schema: reloadMarkerSchema,
                outputDigest: expectedDigest,
                context: expectedContext
            )
            do {
                try JSONEncoder().encode(newMarker).write(to: markerURL, options: .atomic)
                return .written
            } catch {
                return .failed
            }
        }
    }

    @MainActor
    private static func contentBlockerIsEnabled(identifier: String) async -> Bool? {
        await withCheckedContinuation { continuation in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: identifier) { state, error in
                continuation.resume(returning: error == nil ? state?.isEnabled : nil)
            }
        }
    }

    private static func reloadMarkerMatches(_ snapshot: ReloadSnapshot) -> Bool {
        snapshot.marker?.schema == reloadMarkerSchema
            && snapshot.marker?.outputDigest == snapshot.outputDigest
            && snapshot.marker?.context == snapshot.context
    }

    /// Verifies output around Safari's async API without holding the output lock across an await.
    public static func reloadIfNeeded(
        identifier: String,
        targetRulesFilename: String,
        groupIdentifier: String,
        maxRetries: Int = 5
    ) async -> ReloadAttemptResult {
        let gatedResult = await reloadCoordinator.withGate(key: identifier) {
            let streak = ContentBlockerReloadPolicy.failureStreak(identifier: identifier, groupIdentifier: groupIdentifier)
            let output = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
                .appendingPathComponent(targetRulesFilename)
            let bytes = output.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            await SharedAutoUpdateManager.shared.recordOperation("reload-start", fields: [
                "target": identifier, "outputBytes": bytes.map(String.init) ?? "unknown",
                "failureStreak": String(streak),
                "recovery": String(streak >= ContentBlockerReloadPolicy.recoveryThreshold),
                "timeoutSeconds": String(streak >= ContentBlockerReloadPolicy.recoveryThreshold ? ContentBlockerReloadPolicy.recoveryTimeout : 30)
            ])
            let result = await reloadIfNeededSerially(
                identifier: identifier,
                targetRulesFilename: targetRulesFilename,
                groupIdentifier: groupIdentifier,
                maxRetries: maxRetries
            )
            ContentBlockerReloadPolicy.record(
                identifier: identifier, groupIdentifier: groupIdentifier, success: result.success,
                attempts: result.attempts, disabledInSafari: result.disabledInSafari
            )
            await SharedAutoUpdateManager.shared.recordOperation("reload-result", fields: [
                "target": identifier, "result": result.disabledInSafari ? "disabled" : result.skipped ? "skipped" : result.success ? "succeeded" : "failed",
                "attempts": String(result.attempts), "durationMs": String(result.durationMs),
                "skipped": String(result.skipped), "disabledInSafari": String(result.disabledInSafari),
                "failureStreak": String(ContentBlockerReloadPolicy.failureStreak(identifier: identifier, groupIdentifier: groupIdentifier))
            ])
            return result
        }
        guard let result = gatedResult else {
            return ReloadAttemptResult(
                success: false, attempts: 0, durationMs: 0,
                failureReason: ReloadFailureReason.anotherReloadInProgress
            )
        }
        return result
    }

    /// Rewrites the blocker output without the rules WebKit rejects
    /// (ContentBlockerRuleRepair). False when WebKit accepts the output as is,
    /// so the failure had another cause.
    private static func repairRejectedRules(outputURL: URL, containerURL: URL, targetRulesFilename: String) async -> Bool {
        guard let data = try? Data(contentsOf: outputURL),
              let repair = await ContentBlockerRuleRepair.repaired(data)
        else { return false }
        let written = (try? withContentBlockerOutputLock(at: containerURL, targetRulesFilename: targetRulesFilename) {
            // Never overwrite an output another writer replaced meanwhile.
            guard (try? Data(contentsOf: outputURL)) == data else { return false }
            try FilterArtifactStorage.write(repair.data, to: outputURL)
            return true
        }) ?? false
        if written {
            await SharedAutoUpdateManager.shared.recordOperation("reload-repair", fields: [
                "target": targetRulesFilename, "droppedRules": repair.dropped.joined(separator: " | "),
            ])
        }
        return written
    }

    private static func reloadIfNeededSerially(
        identifier: String,
        targetRulesFilename: String,
        groupIdentifier: String,
        maxRetries: Int
    ) async -> ReloadAttemptResult {
        let startTime = Date()
        let elapsedMs = { Int(Date().timeIntervalSince(startTime) * 1000) }
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return ReloadAttemptResult(
                success: false, attempts: 0, durationMs: elapsedMs(),
                failureReason: ReloadFailureReason.noAppGroupContainer
            )
        }

        let markerURL = reloadMarkerURL(
            targetRulesFilename: targetRulesFilename,
            containerURL: containerURL
        )
        let outputURL = containerURL.appendingPathComponent(targetRulesFilename)
        let invalidateMarker = {
            invalidateReloadMarker(
                groupIdentifier: groupIdentifier,
                targetRulesFilename: targetRulesFilename
            )
        }
        let recovering = ContentBlockerReloadPolicy.needsRecovery(identifier: identifier, groupIdentifier: groupIdentifier)
        if recovering {
            // Read and republish under the same output lock. Never rewrite an
            // earlier snapshot over a concurrent pause or disabled-site update.
            var rewritten = false
            if let output = mapOutput(outputURL), (try? validOutputDigest(output.data)) != nil {
                rewritten = (try? withContentBlockerOutputLock(at: containerURL, targetRulesFilename: targetRulesFilename) {
                    guard outputIdentity(outputURL) == output.identity else { return false }
                    try FilterArtifactStorage.write(output.data, to: outputURL)
                    try? FileManager.default.removeItem(at: markerURL)
                    return true
                }) ?? false
            }
            await SharedAutoUpdateManager.shared.recordOperation("reload-recovery", fields: [
                "target": identifier, "result": rewritten ? "rewritten" : "failed"
            ])
        }
        guard var snapshot = try? readReloadSnapshot(
            markerURL: markerURL,
            outputURL: outputURL,
            appGroupURL: containerURL
        ), snapshot.outputDigest != nil else {
            invalidateMarker()
            return ReloadAttemptResult(
                success: false, attempts: 0, durationMs: elapsedMs(),
                failureReason: ReloadFailureReason.outputUnreadable
            )
        }

        var totalAttempts = 0
        var mustReloadNewestOutput = false
        var repairedOutput = false
        for _ in 0..<maxReloadVerificationPasses {
            if !recovering, !mustReloadNewestOutput,
               reloadMarkerMatches(snapshot),
               !BlockingPauseStore.isContentBlockingPaused(groupIdentifier: groupIdentifier)
            {
                let enabled = await contentBlockerIsEnabled(identifier: identifier)
                guard let verified = try? readReloadSnapshot(
                    markerURL: markerURL,
                    outputURL: outputURL,
                    appGroupURL: containerURL
                ), let verifiedDigest = verified.outputDigest else {
                    invalidateMarker()
                    return ReloadAttemptResult(
                        success: false,
                        attempts: totalAttempts,
                        durationMs: elapsedMs(),
                        failureReason: ReloadFailureReason.outputUnreadable
                    )
                }
                guard verifiedDigest == snapshot.outputDigest,
                      verified.context == snapshot.context else {
                    snapshot = verified
                    mustReloadNewestOutput = true
                    continue
                }
                if enabled == true,
                   !BlockingPauseStore.isContentBlockingPaused(groupIdentifier: groupIdentifier),
                   reloadMarkerMatches(verified)
                {
                    return ReloadAttemptResult(success: true, skipped: true, attempts: 0, durationMs: elapsedMs())
                }
                snapshot = verified
            }

            guard let expectedDigest = snapshot.outputDigest else {
                return ReloadAttemptResult(
                    success: false,
                    attempts: totalAttempts,
                    durationMs: elapsedMs(),
                    failureReason: ReloadFailureReason.outputUnreadable
                )
            }

            // Do not let another caller observe a stale certification while this reload is in flight.
            invalidateMarker()

            // Safari can refuse to reload an extension the user has turned off in
            // Safari settings. Its rules are already on disk and load once the
            // extension is enabled again, so try once and report the outcome
            // distinctly instead of retrying and failing the whole apply.
            let enabledInSafari = await contentBlockerIsEnabled(identifier: identifier)
            let reload = await reloadWithRetryRaw(
                identifier: identifier,
                maxRetries: enabledInSafari == false ? 1 : maxRetries,
                timeout: recovering ? ContentBlockerReloadPolicy.recoveryTimeout : reloadCompletionTimeout
            )
            totalAttempts += reload.attempts
            // A rule this Safari's WebKit rejects fails the whole blocker. Drop
            // such rules and reload once more before reporting a failure.
            if !reload.success, enabledInSafari != false, !repairedOutput,
               await repairRejectedRules(outputURL: outputURL, containerURL: containerURL, targetRulesFilename: targetRulesFilename),
               let repaired = try? readReloadSnapshot(markerURL: markerURL, outputURL: outputURL, appGroupURL: containerURL),
               repaired.outputDigest != nil
            {
                repairedOutput = true
                snapshot = repaired
                mustReloadNewestOutput = true
                continue
            }
            guard reload.success else {
                return ReloadAttemptResult(
                    success: false,
                    disabledInSafari: enabledInSafari == false,
                    attempts: totalAttempts,
                    durationMs: elapsedMs(),
                    failureReason: enabledInSafari == false
                        ? ReloadFailureReason.disabledInSafari
                        : reload.failureReason
                )
            }

            guard let verified = try? readReloadSnapshot(
                markerURL: markerURL,
                outputURL: outputURL,
                appGroupURL: containerURL
            ), let verifiedDigest = verified.outputDigest else {
                invalidateMarker()
                return ReloadAttemptResult(
                    success: false,
                    attempts: totalAttempts,
                    durationMs: elapsedMs(),
                    failureReason: ReloadFailureReason.outputUnreadable
                )
            }
            guard verifiedDigest == expectedDigest,
                  verified.context == snapshot.context else {
                snapshot = verified
                mustReloadNewestOutput = true
                continue
            }

            switch try? writeReloadMarkerIfUnchanged(
                markerURL: markerURL,
                outputURL: outputURL,
                appGroupURL: containerURL,
                expectedDigest: expectedDigest,
                expectedIdentity: verified.outputIdentity,
                expectedContext: snapshot.context,
                groupIdentifier: groupIdentifier
            ) {
            case .some(.written), .some(.paused):
                return ReloadAttemptResult(
                    success: true,
                    attempts: totalAttempts,
                    durationMs: elapsedMs()
                )
            case .some(.changed):
                guard let changed = try? readReloadSnapshot(
                    markerURL: markerURL,
                    outputURL: outputURL,
                    appGroupURL: containerURL
                ), changed.outputDigest != nil else {
                    return ReloadAttemptResult(
                        success: false,
                        attempts: totalAttempts,
                        durationMs: elapsedMs(),
                        failureReason: ReloadFailureReason.outputUnreadable
                    )
                }
                snapshot = changed
                mustReloadNewestOutput = true
            case .some(.failed), .none:
                invalidateMarker()
                return ReloadAttemptResult(
                    success: false,
                    attempts: totalAttempts,
                    durationMs: elapsedMs(),
                    failureReason: ReloadFailureReason.markerWriteFailed
                )
            }
        }

        return ReloadAttemptResult(
            success: false,
            attempts: totalAttempts,
            durationMs: elapsedMs(),
            failureReason: ReloadFailureReason.outputChangedDuringReload
        )
    }


    /// How long to wait for Safari to answer a reload request before treating the
    /// attempt as failed. SFContentBlockerManager occasionally never invokes its
    /// completion handler (e.g. under memory pressure while compiling a large
    /// ruleset); without a watchdog the apply pipeline spins forever.
    public static let reloadCompletionTimeout: TimeInterval = 30

    /// Safari did not invoke the reload completion handler within
    /// reloadCompletionTimeout.
    public struct ReloadTimedOutError: LocalizedError, Sendable {
        public let identifier: String
        public let timeout: TimeInterval

        public init(identifier: String, timeout: TimeInterval = ContentBlockerService.reloadCompletionTimeout) {
            self.identifier = identifier
            self.timeout = timeout
        }

        public var errorDescription: String? {
            "Safari did not respond to the reload request for \(identifier) "
                + "within \(Int(timeout)) seconds."
        }
    }

    /// Guards a checked continuation against being resumed by both the reload
    /// completion handler and the watchdog timeout.
    private final class ResumeOnceGate: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if resumed { return false }
            resumed = true
            return true
        }
    }

    /// Reloads the Safari content blocker extension with the specified identifier.
    ///
    /// The wait is bounded by reloadCompletionTimeout: if Safari never calls the
    /// completion handler, the attempt fails with ReloadTimedOutError instead of
    /// hanging the caller indefinitely.
    ///
    /// - Parameters:
    ///   - identifier: Bundle ID of the content blocker extension to reload.
    /// - Returns: A Result indicating success or containing an error if the reload failed.
    @MainActor
    public static func reloadContentBlocker(
        withIdentifier identifier: String,
        timeout: TimeInterval = reloadCompletionTimeout
    ) async -> Result<Void, Error> {
        let timeout = timeout.isFinite ? max(1, min(timeout, 60)) : reloadCompletionTimeout
        os_log(.info, "Start reloading the content blocker")

        let error: Error? = await withCheckedContinuation { continuation in
            let gate = ResumeOnceGate()
            SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { error in
                guard gate.claim() else { return }
                continuation.resume(returning: error)
            }
            Task.detached {
                try? await TaskSleep.sleep(for: .seconds(timeout))
                guard gate.claim() else { return }
                continuation.resume(returning: ReloadTimedOutError(identifier: identifier, timeout: timeout))
            }
        }

        let result: Result<Void, Error> = if let error { .failure(error) } else { .success(()) }

        switch result {
        case .success:
            os_log(.info, "Content blocker reloaded successfully.")
        case .failure(let error):
            // WKErrorDomain error 6 is a common error when the content blocker
            // cannot access the blocker list file.
            if error is ReloadTimedOutError {
                os_log(
                    .error,
                    "Content blocker reload timed out waiting for Safari: %@",
                    identifier
                )
            } else if error.localizedDescription.contains("WKErrorDomain error 6") {
                os_log(
                    .error,
                    "Failed to reload content blocker, could not access blocker list file: %@",
                    error.localizedDescription
                )
            } else {
                os_log(
                    .error,
                    "Failed to reload content blocker: %@",
                    error.localizedDescription
                )
            }
        }

        return result
    }

    public static func reloadWithRetry(
        identifier: String,
        maxRetries: Int = 5,
        groupIdentifier: String? = nil,
        targetRulesFilename: String? = nil
    ) async -> ReloadAttemptResult {
        guard (groupIdentifier == nil) == (targetRulesFilename == nil) else {
            return ReloadAttemptResult(
                success: false, attempts: 0, durationMs: 0,
                failureReason: ReloadFailureReason.invalidArguments
            )
        }
        let gatedResult = await reloadCoordinator.withGate(key: identifier) {
            if let groupIdentifier, let targetRulesFilename {
                invalidateReloadMarker(groupIdentifier: groupIdentifier, targetRulesFilename: targetRulesFilename)
                let result = await reloadIfNeededSerially(
                    identifier: identifier, targetRulesFilename: targetRulesFilename,
                    groupIdentifier: groupIdentifier, maxRetries: maxRetries
                )
                ContentBlockerReloadPolicy.record(
                    identifier: identifier, groupIdentifier: groupIdentifier, success: result.success,
                    attempts: result.attempts, disabledInSafari: result.disabledInSafari
                )
                return result
            }
            return await reloadWithRetryRaw(identifier: identifier, maxRetries: maxRetries)
        }
        guard let result = gatedResult else {
            return ReloadAttemptResult(
                success: false, attempts: 0, durationMs: 0,
                failureReason: ReloadFailureReason.anotherReloadInProgress
            )
        }
        return result
    }

    private static func reloadWithRetryRaw(
        identifier: String,
        maxRetries: Int,
        timeout: TimeInterval = reloadCompletionTimeout
    ) async -> ReloadAttemptResult {
        let startTime = Date()
        let elapsedMs = { Int(Date().timeIntervalSince(startTime) * 1000) }

        guard maxRetries > 0 else {
            return ReloadAttemptResult(
                success: false, attempts: 0, durationMs: elapsedMs(),
                failureReason: ReloadFailureReason.invalidArguments
            )
        }

        var lastFailureReason: String?
        for attempt in 1...maxRetries {
            if Task.isCancelled {
                return ReloadAttemptResult(
                    success: false,
                    attempts: max(0, attempt - 1),
                    durationMs: elapsedMs(),
                    failureReason: lastFailureReason ?? ReloadFailureReason.cancelled
                )
            }

            let result = await reloadContentBlocker(withIdentifier: identifier, timeout: timeout)
            if case .success = result {
                return ReloadAttemptResult(
                    success: true,
                    attempts: attempt,
                    durationMs: elapsedMs()
                )
            }
            if case .failure(let error) = result {
                lastFailureReason = LogErrorDescriber.describe(error)
            }

            // A timed-out attempt means Safari is not answering reload requests at
            // all; immediate retries only stack more long waits, so fail fast and
            // let the caller surface the error.
            if case .failure(let error) = result, error is ReloadTimedOutError {
                return ReloadAttemptResult(
                    success: false,
                    attempts: attempt,
                    durationMs: elapsedMs(),
                    failureReason: lastFailureReason
                )
            }

            guard attempt < maxRetries else {
                break
            }

            let delayMs = min(200 * attempt, 1500)
            do {
                try await TaskSleep.sleep(for: .milliseconds(delayMs))
            } catch {
                return ReloadAttemptResult(
                    success: false,
                    attempts: attempt,
                    durationMs: elapsedMs(),
                    failureReason: lastFailureReason ?? ReloadFailureReason.cancelled
                )
            }
        }

        return ReloadAttemptResult(
            success: false,
            attempts: maxRetries,
            durationMs: elapsedMs(),
            failureReason: lastFailureReason
        )
    }

    public static func invalidateReloadMarker(
        groupIdentifier: String,
        targetRulesFilename: String
    ) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else { return }

        let markerURL = reloadMarkerURL(
            targetRulesFilename: targetRulesFilename,
            containerURL: containerURL
        )
        let reloadLockURL = containerURL.appendingPathComponent(".\(targetRulesFilename).lock")
        try? withContentBlockerOutputLock(
            at: containerURL,
            targetRulesFilename: targetRulesFilename,
            lockURL: reloadLockURL
        ) {
            try? FileManager.default.removeItem(at: markerURL)
        }
    }

    private static func withContentBlockerOutputLock<T>(
        at appGroupURL: URL,
        targetRulesFilename: String,
        lockURL: URL? = nil,
        _ body: () throws -> T
    ) throws -> T {
        let lockURL = lockURL ?? appGroupURL.appendingPathComponent(".\(targetRulesFilename).lock")
        guard let fileLock = FileLock(filePath: lockURL.path),
              fileLock.lock(before: Date().addingTimeInterval(contentBlockerOutputLockTimeout)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { _ = fileLock.unlock() }
        return try body()
    }

    /// Saves the provided JSON content to the content blocker file in the shared container
    /// without attempting to convert the rules.
    ///
    /// - Parameters:
    ///   - jsonRules: Safari content blocker JSON contents in proper format.
    ///   - groupIdentifier: Group ID to use for the shared container where
    ///                      the file will be saved.
    /// - Returns: The rule count and whether the shared output bytes changed.
    public static func saveContentBlockerIfChanged(
        jsonRules: String,
        groupIdentifier: String,
        targetRulesFilename: String,
        containerURL explicitContainerURL: URL? = nil,
        knownRuleCount: Int? = nil
    ) throws -> ContentBlockerSaveResult {
        os_log(.info, "Saving pre-formatted JSON content blocker rules to %@", targetRulesFilename)
        let data = Data(jsonRules.utf8)
        // Callers that built the array pass its count; parsing a 20 MB array
        // again just to count it was a large share of each compile.
        guard let ruleCount = knownRuleCount ?? ContentBlockerRuleArray.count(data) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard let appGroupURL = explicitContainerURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let sharedFileURL = appGroupURL.appendingPathComponent(targetRulesFilename)
        // Compare before locking; under the lock only confirm the compared file is still current.
        let unchangedIdentity = mapOutput(sharedFileURL).flatMap { $0.data == data ? $0.identity : nil }
        let outputChanged = try withContentBlockerOutputLock(
            at: appGroupURL,
            targetRulesFilename: targetRulesFilename
        ) {
            let outputChanged = unchangedIdentity == nil || outputIdentity(sharedFileURL) != unchangedIdentity
            if outputChanged {
                try FilterArtifactStorage.write(data, to: sharedFileURL)
                os_log(.info, "Successfully saved rules to %@", sharedFileURL.path)
            } else {
                os_log(.info, "Skipped unchanged rules at %@", sharedFileURL.path)
            }
            return outputChanged
        }
        return ContentBlockerSaveResult(ruleCount: ruleCount, outputChanged: outputChanged)
    }

    public static func finalizeAndSaveContentBlockerIfWithinLimit(
        baseJSON: String,
        disabledSites: [String],
        knownBaseCount: Int? = nil,
        ruleLimit: Int = safariContentBlockerRuleLimit,
        groupIdentifier: String,
        targetRulesFilename: String,
        containerURL: URL? = nil,
        isCancelled: (() -> Bool)? = nil
    ) throws -> (ruleCount: Int, truncatedRuleCount: Int, outputChanged: Bool) {
        if Task.isCancelled || isCancelled?() == true { throw CancellationError() }
        let finalized = finalizeContentBlockerJSON(
            baseJSON: baseJSON,
            disabledSites: disabledSites,
            knownBaseCount: knownBaseCount,
            ruleLimit: ruleLimit
        )
        guard finalized.truncatedRuleCount == 0 else {
            return (
                ruleCount: finalized.ruleCount,
                truncatedRuleCount: finalized.truncatedRuleCount,
                outputChanged: false
            )
        }
        if Task.isCancelled || isCancelled?() == true { throw CancellationError() }
        let output = try saveContentBlockerIfChanged(
            jsonRules: finalized.json,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetRulesFilename,
            containerURL: containerURL,
            knownRuleCount: finalized.ruleCount
        )
        return (
            ruleCount: finalized.ruleCount,
            truncatedRuleCount: 0,
            outputChanged: output.outputChanged
        )
    }

    private static func targetSourceRuleProvenanceFilename(for targetRulesFilename: String) -> String {
        "\(targetRulesFilename).source-rule-provenance.json"
    }

    private static func loadTargetSourceRuleProvenance(
        targetRulesFilename: String,
        inputSignature: String,
        groupIdentifier: String,
        containerURL explicitContainerURL: URL? = nil
    ) -> [UUID: Int] {
        guard let containerURL = explicitContainerURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else { return [:] }
        let url = containerURL.appendingPathComponent(
            targetSourceRuleProvenanceFilename(for: targetRulesFilename)
        )
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(StoredTargetSourceRuleProvenance.self, from: data),
              stored.schemaVersion == 1, stored.inputSignature == inputSignature
        else { return [:] }
        return stored.decodedCounts
    }

    private static func saveTargetSourceRuleProvenance(
        _ counts: [UUID: Int],
        targetRulesFilename: String,
        inputSignature: String,
        groupIdentifier: String,
        containerURL: URL? = nil
    ) {
        let stored = StoredTargetSourceRuleProvenance(admittedSourceRuleCountsByFilterID: counts, inputSignature: inputSignature)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? saveBlockerListFile(
            contents: String(decoding: data, as: UTF8.self),
            groupIdentifier: groupIdentifier,
            filename: targetSourceRuleProvenanceFilename(for: targetRulesFilename),
            containerURL: containerURL
        )
    }

    /// Compiles rules for a specific content blocker target or reuses cached compilation results if available.
    public static func compileTargetRules(
        filters: [FilterList],
        orderedSelectedFilters: [FilterList],
        targetInfo: ContentBlockerTargetInfo,
        allTargets: [ContentBlockerTargetInfo],
        disabledSites: [String],
        extraRulesText: String?,
        groupIdentifier: String,
        containerURL: URL? = nil,
        isCancelled: (() -> Bool)? = nil
    ) throws -> ContentBlockerTargetOutcome {
        if Task.isCancelled || isCancelled?() == true {
            throw CancellationError()
        }
        // Normalize display ordering without losing newest-first overflow
        // priority. Both cache identity and conversion use this same order.
        let orderedSelectedFilters = ContentBlockerMappingService.orderedForCompilation(orderedSelectedFilters)
        let filters = ContentBlockerIncrementalCache.canonicalFilterOrder(filters)
        let rulesFilename = targetInfo.rulesFilename
        let cosmeticSites = CosmeticFilteringPreference.effectiveSites(groupIdentifier: groupIdentifier)
        // Every selected list can change cross-slot ownership or exception
        // context, even without affinity. Include all of them in cache identity.
        let assignedIDs = Set(filters.map(\.id))
        let affinityContributors = orderedSelectedFilters.filter {
            !assignedIDs.contains($0.id)
        }
        let signatureContainer = containerURL ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        let carveOuts = signatureContainer.map { RemoveParamDNRRuleGenerator.savedRedirectCarveOuts(containerURL: $0) } ?? ""
        let signatureExtras = (extraRulesText ?? "") + "\n" + carveOuts + "\n" + allTargets.map { "\($0.bundleIdentifier):\($0.slot)" }.joined(separator: "|")
        let currentSignature = ContentBlockerIncrementalCache.computeInputSignature(
            filters: filters,
            affinityContributors: affinityContributors,
            groupIdentifier: groupIdentifier,
            extraRulesText: signatureExtras,
            cosmeticSites: cosmeticSites,
            compileOrder: orderedSelectedFilters,
            containerURL: containerURL
        )
        let storedSignature = ContentBlockerIncrementalCache.loadInputSignature(
            targetRulesFilename: rulesFilename,
            groupIdentifier: groupIdentifier,
            containerURL: containerURL
        )

        if let currentSignature,
           currentSignature == storedSignature,
           ContentBlockerIncrementalCache.hasCoherentBaseRulesCache(
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier,
                containerURL: containerURL
           ) {
            let fastUpdate = try ContentBlockerService.fastUpdateDisabledSitesWithOutputChange(
                groupIdentifier: groupIdentifier,
                targetRulesFilename: rulesFilename,
                disabledSites: disabledSites,
                containerURL: containerURL,
                allowTruncation: true
            )
            let cachedAdvancedRules = ContentBlockerIncrementalCache.loadCachedAdvancedRules(
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier,
                containerURL: containerURL
            )
            let trimmedAdvanced = cachedAdvancedRules?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return ContentBlockerTargetOutcome(
                safariRulesCount: fastUpdate.safariRulesCount,
                truncatedRuleCount: fastUpdate.truncatedRuleCount,
                advancedRulesText: (trimmedAdvanced?.isEmpty == false) ? trimmedAdvanced : nil,
                reusedCachedBase: true,
                outputChanged: fastUpdate.outputChanged,
                admittedSourceRuleCountsByFilterID: loadTargetSourceRuleProvenance(
                    targetRulesFilename: rulesFilename,
                    inputSignature: currentSignature,
                    groupIdentifier: groupIdentifier,
                    containerURL: containerURL
                )
            )
        }

        guard let containerURL = containerURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ), let targetIndex = allTargets.firstIndex(of: targetInfo) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let distribution = ContentBlockerMappingService.plan(selectedFilters: orderedSelectedFilters, across: allTargets)
        let followsPlan = Set((distribution.filtersByTarget[targetInfo] ?? []).map(\.id)) == Set(filters.map(\.id))
        let selectedIDs = Set(orderedSelectedFilters.map(\.id))
        let planFilters = orderedSelectedFilters + filters.filter { !selectedIDs.contains($0.id) }
        let available = planFilters.compactMap { filter -> (FilterList, URL)? in
            ContentBlockerIncrementalCache.existingLocalFileURL(for: filter, containerURL: containerURL).map { (filter, $0) }
        }
        let indexes = Dictionary(uniqueKeysWithValues: available.enumerated().map { ($0.element.0.id, $0.offset) })
        let lists: [[String: Any]] = available.map { filter, url in
            ["id": filter.id.uuidString, "path": url.path, "trusted": filter.isTrustedSource,
             "scope": ["exclude": FilterListSiteExclusion.normalizedDomains(from: filter.appliedExcludedSites),
                       "only": filter.appliedSelectedSites.map { FilterListSiteExclusion.normalizedDomains(from: $0) } as Any? ?? NSNull()]]
        }
        let targets: [[String: Any]] = allTargets.map { target in
            let custom = target == targetInfo && !followsPlan
            let assigned = custom ? filters : distribution.filtersByTarget[target] ?? []
            let targetLists: [[String: Any]] = assigned.compactMap { filter in
                guard let index = indexes[filter.id] else { return nil }
                var item: [String: Any] = ["list": index]
                if !custom, let shard = distribution.shardsByTarget[target]?[filter.id] {
                    item["shard"] = [shard.index, shard.count]
                }
                return item
            }
            return ["slot": target.slot, "lists": targetLists]
        }
        let safari = SafariVersionDetection.current
        let request: [String: Any] = ["safari": [safari.major, safari.minor], "lists": lists, "targets": targets,
            "cosmetics": ["exclude": cosmeticSites.excludedSites,
                          "only": cosmeticSites.onlySelectedSites ? (cosmeticSites.selectedSites ?? []) as Any : NSNull(),
                          "generic": cosmeticSites.includesGeneric]]
        let requestData = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        let requestJSON = String(decoding: requestData, as: UTF8.self)
        let fingerprints = available.map { _, url -> String in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return "\(attributes?[.size] ?? 0)|\((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: "\n")
        let planKey = "wbe-plan|\(SafariVersionDetection.compilerIdentity)|\(requestJSON)|\(fingerprints)"
        let makePlan = { try WBEngine.Plan(requestJSON: requestJSON) }
        let plan = try CompilationScope.current.map { try $0.memoized(planKey, makePlan) } ?? makePlan()
        if Task.isCancelled || isCancelled?() == true { throw CancellationError() }
        let extras: [[String: Any]] = [
            ["text": embeddedCompatibilityRules, "trusted": true],
            ["text": extraRulesText ?? "", "trusted": true],
            ["text": RemoveParamDNRRuleGenerator.savedRedirectCarveOuts(containerURL: containerURL), "trusted": false]
        ]
        let extrasJSON = String(decoding: try JSONSerialization.data(withJSONObject: extras), as: UTF8.self)
        let compiled = try plan.compileTarget(targetIndex, extras: extrasJSON)
        if Task.isCancelled || isCancelled?() == true { throw CancellationError() }
        let baseJSON = compiled.stats.nativeRules == 0 ? inertContentBlockerRulesJSON : compiled.safariRulesJSON
        let baseCount = compiled.stats.nativeRules == 0 ? inertContentBlockerRuleCount : compiled.stats.nativeRules
        let advanced = compiled.runtimeRules.isEmpty ? nil : compiled.runtimeRules
        let admitted = Dictionary(uniqueKeysWithValues: (compiled.stats.admitted ?? [:]).compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
        let baseFilename = ContentBlockerIncrementalCache.baseRulesFilename(for: rulesFilename)
        let finalized = try finalizeAndSaveContentBlockerIfWithinLimit(
            baseJSON: baseJSON, disabledSites: disabledSites, knownBaseCount: baseCount,
            groupIdentifier: groupIdentifier, targetRulesFilename: rulesFilename, containerURL: containerURL,
            isCancelled: isCancelled
        )
        let conversion = (safariRulesCount: finalized.ruleCount, truncatedRuleCount: finalized.truncatedRuleCount,
                          advancedRulesText: advanced, outputChanged: finalized.outputChanged,
                          admittedSourceRuleCountsByFilterID: admitted)
        if finalized.truncatedRuleCount == 0 {
            _ = try saveContentBlockerIfChanged(jsonRules: baseJSON, groupIdentifier: groupIdentifier,
                targetRulesFilename: baseFilename, containerURL: containerURL, knownRuleCount: baseCount)
            try saveBlockerListFile(contents: String(baseCount), groupIdentifier: groupIdentifier, filename: "\(baseFilename).count", containerURL: containerURL)
            try saveBlockerListFile(contents: advanced ?? "", groupIdentifier: groupIdentifier, filename: ContentBlockerIncrementalCache.baseAdvancedRulesFilename(for: rulesFilename), containerURL: containerURL)
            try saveBlockerListFile(contents: SafariVersionDetection.compilerIdentity, groupIdentifier: groupIdentifier, filename: ContentBlockerIncrementalCache.baseCompilerFilename(for: rulesFilename), containerURL: containerURL)
            let digest = SHA256.hash(data: Data((requestJSON + extrasJSON + fingerprints).utf8)).map { String(format: "%02x", $0) }.joined()
            try saveBlockerListFile(contents: digest, groupIdentifier: groupIdentifier, filename: "\(baseFilename).sha256", containerURL: containerURL)
        }

        if let currentSignature, conversion.truncatedRuleCount == 0 {
            ContentBlockerIncrementalCache.saveInputSignature(
                currentSignature,
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier,
                containerURL: containerURL
            )
            saveTargetSourceRuleProvenance(
                conversion.admittedSourceRuleCountsByFilterID,
                targetRulesFilename: rulesFilename,
                inputSignature: currentSignature,
                groupIdentifier: groupIdentifier,
                containerURL: containerURL
            )
        }

        return ContentBlockerTargetOutcome(
            safariRulesCount: conversion.safariRulesCount,
            truncatedRuleCount: conversion.truncatedRuleCount,
            advancedRulesText: conversion.advancedRulesText,
            reusedCachedBase: false,
            outputChanged: conversion.outputChanged,
            admittedSourceRuleCountsByFilterID: conversion.admittedSourceRuleCountsByFilterID
        )
    }


    /// Fast update for disabled sites changes only - skips SafariConverterLib conversion
    /// Reads existing JSON files and re-injects ignore rules without full conversion
    ///
    /// - Parameters:
    ///   - groupIdentifier: Group ID to use for the shared container
    ///   - targetRulesFilename: Target filename for the rules file
    ///   - disabledSites: Sites where wBlock is disabled (ignore rules are injected for these).
    /// - Returns: A tuple containing the number of Safari content blocker rules and advanced rules text
    public static func fastUpdateDisabledSites(
        groupIdentifier: String,
        targetRulesFilename: String,
        disabledSites: [String],
        containerURL: URL? = nil
    ) throws -> (safariRulesCount: Int, advancedRulesText: String?) {
        let result = try fastUpdateDisabledSitesWithOutputChange(
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetRulesFilename,
            disabledSites: disabledSites,
            containerURL: containerURL,
            allowTruncation: false
        )
        return (
            safariRulesCount: result.safariRulesCount,
            advancedRulesText: result.advancedRulesText
        )
    }

    static func fastUpdateDisabledSitesWithOutputChange(
        groupIdentifier: String,
        targetRulesFilename: String,
        disabledSites: [String],
        containerURL explicitContainerURL: URL? = nil,
        allowTruncation: Bool = false
    ) throws -> (safariRulesCount: Int, truncatedRuleCount: Int, advancedRulesText: String?, outputChanged: Bool) {
        let sitesToUse = disabledSites

        guard let containerURL = explicitContainerURL ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        let baseFilename = ContentBlockerIncrementalCache.baseRulesFilename(for: targetRulesFilename)
        let baseCountFilename = "\(baseFilename).count"

        // Preferred path: use cached base JSON (no ignore rules) + cheap string injection.
        let baseURL = containerURL.appendingPathComponent(baseFilename)
        let baseCountURL = containerURL.appendingPathComponent(baseCountFilename)
        if ContentBlockerIncrementalCache.hasCoherentBaseRulesCache(
            targetRulesFilename: targetRulesFilename,
            groupIdentifier: groupIdentifier,
            containerURL: containerURL
        ),
           let baseJSON = try? String(contentsOf: baseURL, encoding: .utf8),
           let parsedBaseCount = ContentBlockerRuleArray.count(baseJSON),
           let baseCount = (try? String(contentsOf: baseCountURL, encoding: .utf8))
                .flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
           baseCount == parsedBaseCount {
            let finalized = try finalizeAndSaveContentBlockerIfWithinLimit(
                baseJSON: baseJSON,
                disabledSites: sitesToUse,
                knownBaseCount: baseCount,
                groupIdentifier: groupIdentifier,
                targetRulesFilename: targetRulesFilename,
                containerURL: containerURL
            )
            if finalized.truncatedRuleCount > 0 && !allowTruncation {
                throw CocoaError(.fileReadCorruptFile)
            }

            let advancedURL = containerURL.appendingPathComponent(
                ContentBlockerIncrementalCache.baseAdvancedRulesFilename(for: targetRulesFilename)
            )
            let advancedRulesText = try String(contentsOf: advancedURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let finalRuleCount = finalized.ruleCount

            os_log(.info, "Fast updated %@ with %d rules for %d disabled sites", targetRulesFilename, finalRuleCount, sitesToUse.count)
            return (
                safariRulesCount: finalRuleCount,
                truncatedRuleCount: finalized.truncatedRuleCount,
                advancedRulesText: advancedRulesText.isEmpty ? nil : advancedRulesText,
                outputChanged: finalized.outputChanged
            )
        }

        // Without a complete cache this path cannot safely preserve advanced
        // rules. The caller must take the full conversion path instead.
        throw CocoaError(.fileReadCorruptFile)
    }

    /// Applies disabled-site ignore rules without exceeding Safari's per-extension limit.
    /// When the combined list would overflow, trailing converted rules are dropped so
    /// the ignore rules still fit.
    public static func finalizeContentBlockerJSON(
        baseJSON: String,
        disabledSites: [String],
        knownBaseCount: Int? = nil,
        ruleLimit: Int = safariContentBlockerRuleLimit
    ) -> (json: String, ruleCount: Int, truncatedRuleCount: Int) {
        let limit = max(ruleLimit, 0)
        let sites = Array(
            DisabledSitesNormalizer.normalizedDomains(from: disabledSites).prefix(limit)
        )
        let baseCount = knownBaseCount ?? ContentBlockerRuleArray.count(baseJSON) ?? 0

        guard !sites.isEmpty else {
            if baseCount <= limit {
                return (baseJSON, baseCount, 0)
            }
            if let truncated = ContentBlockerRuleArray.truncated(baseJSON, to: limit) {
                return (truncated.json, truncated.ruleCount, max(0, baseCount - truncated.ruleCount))
            }
            return (baseJSON, min(baseCount, limit), max(0, baseCount - limit))
        }

        if baseCount + sites.count <= limit {
            return (
                injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sites),
                baseCount + sites.count,
                0
            )
        }

        let maxBase = max(limit - sites.count, 0)
        guard let truncated = ContentBlockerRuleArray.truncated(baseJSON, to: maxBase) else {
            if baseCount <= maxBase {
                return (
                    injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sites),
                    baseCount + sites.count,
                    0
                )
            }
            return (baseJSON, min(baseCount, limit), max(0, baseCount - maxBase))
        }

        return (
            injectIgnoreRulesForDisabledSites(json: truncated.json, disabledSites: sites),
            truncated.ruleCount + sites.count,
            max(0, baseCount - truncated.ruleCount)
        )
    }

    private static func escapeForJSONString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Saves the blocker list file contents to the shared directory specified by the group identifier.
    ///
    /// - Parameters:
    ///   - contents: String content to write to the blocker list file.
    ///   - groupIdentifier: App group identifier for accessing the shared container.
    private static func saveBlockerListFile(
        contents: String,
        groupIdentifier: String,
        filename: String,
        containerURL explicitContainerURL: URL? = nil
    ) throws {
        guard
            let appGroupURL = explicitContainerURL ?? FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier
            )
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        let sharedFileURL = appGroupURL.appendingPathComponent(filename)
        try FilterArtifactStorage.write(Data(contents.utf8), to: sharedFileURL)
        os_log(.info, "Successfully saved rules to %@", sharedFileURL.path)
    }

    private static func disabledSiteIgnoreRuleJSON(for site: String) -> String {
        let trimmedSite = site.trimmingCharacters(in: .whitespacesAndNewlines)
        // if-domain has no TLD wildcard; a list's `name.*` exclusion (#1032)
        // matches the page URL instead.
        if let pattern = FilterListSiteExclusion.wildcardTopURLPattern(trimmedSite) {
            return "{\"action\":{\"type\":\"ignore-previous-rules\"},\"trigger\":{\"url-filter\":\".*\",\"if-top-url\":[\"\(escapeForJSONString(pattern))\"]}}"
        }
        let wildcardDomain = trimmedSite.hasPrefix("*") ? trimmedSite : "*\(trimmedSite)"
        let escapedDomain = escapeForJSONString(wildcardDomain)

        return "{\"action\":{\"type\":\"ignore-previous-rules\"},\"trigger\":{\"url-filter\":\".*\",\"if-domain\":[\"\(escapedDomain)\"]}}"
    }
    
    /// Injects Safari content blocker ignore-previous-rules for disabled sites into existing JSON.
    /// This uses Safari's native ignore-previous-rules action to whitelist disabled sites.
    ///
    /// - Parameters:
    ///   - json: Existing Safari content blocker JSON string.
    ///   - disabledSites: Array of site hostnames to whitelist.
    /// - Returns: Modified JSON string with ignore rules injected.
    private static func injectIgnoreRulesForDisabledSites(json: String, disabledSites: [String]) -> String {
        guard !disabledSites.isEmpty else { return json }
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let openBracket = trimmed.firstIndex(of: "["),
              let closeBracket = trimmed.lastIndex(of: "]"),
              openBracket < closeBracket else {
            return json
        }

        let ignoreRules = disabledSites.map { disabledSiteIgnoreRuleJSON(for: $0) }.joined(separator: ",")
        guard !ignoreRules.isEmpty else { return trimmed }

        let inner = trimmed[trimmed.index(after: openBracket)..<closeBracket]
        if inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[\(ignoreRules)]"
        }

        return String(trimmed[..<closeBracket]) + "," + ignoreRules + "]"
    }
    
    /// Joins two content blocker rule arrays, keeping their order.
    static func concatenatedRuleArrays(_ first: String, _ second: String) -> String {
        func inner(_ json: String) -> Substring {
            let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let open = trimmed.firstIndex(of: "["), let close = trimmed.lastIndex(of: "]"), open < close else { return "" }
            return trimmed[trimmed.index(after: open)..<close]
        }
        let parts = [inner(first), inner(second)].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return "[" + parts.joined(separator: ",") + "]"
    }


    /// Whether the Scripts extension has a per-page engine to read. An upgrade
    /// from before wBlock 4 has none until its first apply.
    public static func hasPublishedFilterEngine(groupIdentifier: String) -> Bool {
        FilterEngineStore.hasPublishedEngine(groupIdentifier: groupIdentifier)
    }

    /// Publishes the per-page engine built from the advanced (runtime) rules of
    /// every blocker. Empty rules publish an empty engine.
    public static func publishCombinedFilterEngine(
        combinedAdvancedRules: String,
        groupIdentifier: String
    ) throws {
        try FilterEngineStore.publish(runtimeRules: combinedAdvancedRules, groupIdentifier: groupIdentifier)
    }
}

// MARK: - Safari Content Blocker functions

extension ContentBlockerService {

}

public nonisolated enum ContentBlockerChunkedHasher {
    public static let defaultChunkSize = 64 * 1024

    public static func update(
        with data: Data,
        hasher: inout SHA256,
        writingTo destinationHandle: FileHandle? = nil,
        chunkSize: Int = defaultChunkSize,
        isCancelled: (() -> Bool)? = nil
    ) throws {
        precondition(chunkSize > 0)
        if isCancelled?() == true {
            throw CancellationError()
        }
        var offset = data.startIndex
        while offset < data.endIndex {
            if isCancelled?() == true {
                throw CancellationError()
            }
            let end = min(offset + chunkSize, data.endIndex)
            let chunk = data[offset..<end]
            hasher.update(data: chunk)
            if let destinationHandle {
                try destinationHandle.write(contentsOf: Data(chunk))
            }
            offset = end
        }
    }

    public static func hexDigest(
        for data: Data,
        chunkSize: Int = defaultChunkSize,
        isCancelled: (() -> Bool)? = nil
    ) throws -> String {
        var hasher = SHA256()
        try update(
            with: data,
            hasher: &hasher,
            chunkSize: chunkSize,
            isCancelled: isCancelled
        )
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
