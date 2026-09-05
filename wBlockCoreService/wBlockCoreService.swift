//
//  wBlockCoreService.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 5/23/25.
//

internal import ContentBlockerConverter
internal import FilterEngine
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
    public let advancedRulesText: String?
    public let reusedCachedBase: Bool
    public let outputChanged: Bool

    public init(safariRulesCount: Int, advancedRulesText: String?, reusedCachedBase: Bool) {
        self.init(
            safariRulesCount: safariRulesCount,
            advancedRulesText: advancedRulesText,
            reusedCachedBase: reusedCachedBase,
            outputChanged: true
        )
    }

    public init(
        safariRulesCount: Int,
        advancedRulesText: String?,
        reusedCachedBase: Bool,
        outputChanged: Bool
    ) {
        self.safariRulesCount = safariRulesCount
        self.advancedRulesText = advancedRulesText
        self.reusedCachedBase = reusedCachedBase
        self.outputChanged = outputChanged
    }
}

public struct ContentBlockerSaveResult: Sendable {
    public let ruleCount: Int
    public let outputChanged: Bool
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
    // 7: duplicate rule lines are dropped before conversion (#681).
    public static let embeddedCompatibilityRulesVersion = "7"
    private static let combinedEngineMarkerFileName = "combined-rules.sha256"
    private static let combinedEngineMarkerFormatVersion = 2
    private static let combinedEngineBuildLockFileName = "combined-engine-build.lock"
    private static let combinedEngineBuildLockTimeout: TimeInterval = 120
    private static let combinedEngineRequestLockFileName = "combined-engine-request.lock"
    private static let combinedEngineLatestRequestFileName = "combined-engine-latest.request"
    private static let combinedEngineRequestLockTimeout: TimeInterval = 2
    private static let engineFileLockTimeout: TimeInterval = 2
    private static let contentBlockerOutputLockTimeout: TimeInterval = 10
    private static let engineStorageFileNames = [
        Schema.FILTER_RULE_STORAGE_FILE_NAME,
        Schema.FILTER_ENGINE_INDEX_FILE_NAME,
        Schema.RULES_FILE_NAME,
        Schema.ENGINE_META_FILE_NAME,
    ]

    private enum CombinedEnginePublishError: Error {
        case supersededRequest
        case suspensionImminent
    }

    #if os(iOS)
    /// Defers app suspension while a combined-engine publish holds kernel file
    /// locks in the app group container. iOS kills any app that suspends while
    /// holding a file lock in a shared container (0xDEAD10CC). If the system
    /// decides to suspend anyway, the expiration callback flips a flag that the
    /// publish checkpoints observe to unwind and release the locks first.
    private final class EnginePublishSuspensionShield: @unchecked Sendable {
        private static let expirationUnwindTimeout: TimeInterval = 3

        private let condition = NSCondition()
        private var expired = false
        private var released = false

        init(reason: String) {
            ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { [weak self] isExpired in
                if isExpired {
                    // Runs when suspension is imminent: immediately when no
                    // background time is available, otherwise concurrently
                    // with the blocked non-expired invocation below. Build
                    // checkpoints unwind the publish; wait briefly for its
                    // deferred release before allowing suspension.
                    self?.markExpired()
                    self?.waitUntilReleased(
                        timeout: EnginePublishSuspensionShield.expirationUnwindTimeout
                    )
                } else {
                    // The assertion holds for as long as this invocation blocks.
                    self?.waitUntilReleased()
                }
            }
        }

        var isExpired: Bool {
            condition.lock()
            defer { condition.unlock() }
            return expired
        }

        private func markExpired() {
            condition.lock()
            expired = true
            condition.unlock()
        }

        private func waitUntilReleased(timeout: TimeInterval? = nil) {
            condition.lock()
            defer { condition.unlock() }

            if let timeout {
                let deadline = Date().addingTimeInterval(timeout)
                while !released && condition.wait(until: deadline) {}
            } else {
                while !released {
                    condition.wait()
                }
            }
        }

        func release() {
            condition.lock()
            guard !released else {
                condition.unlock()
                return
            }
            released = true
            condition.broadcast()
            condition.unlock()
        }
    }
    #endif

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

    /// Drops rule lines that repeat an earlier rule identity. Two lists
    /// that share rules (a fork of a list, or overlapping upstreams) otherwise
    /// send every shared rule to the converter twice, and each copy counts
    /// against Safari's per-extension limit (#681). Comments, section headers
    /// and `!#` preprocessor directives are kept, since their position matters.
    public static func deduplicatedRuleLines(_ lines: [String]) -> [String] {
        var seen = Set<String>(minimumCapacity: lines.count)
        var result: [String] = []
        result.reserveCapacity(lines.count)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard FilterRuleAnalysis.isRuleLine(trimmed), !trimmed.hasPrefix("!#") else {
                result.append(line)
                continue
            }
            if seen.insert(FilterRuleAnalysis.ruleIdentity(trimmed)).inserted {
                result.append(line)
            }
        }
        return result
    }

    private static func combinedRulesWithEmbeddedCompatibility(_ rawRules: String, siteRestriction: [String]?) -> String {
        let extraRules = siteRestriction.map { FilterListSiteExclusion.restrictingRules(embeddedCompatibilityRules, to: $0) }
            ?? embeddedCompatibilityRules
        let trimmedExtraRules = extraRules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExtraRules.isEmpty else { return rawRules }

        let trimmedBaseRules = rawRules.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseRules.isEmpty else { return trimmedExtraRules }

        return rawRules + "\n" + trimmedExtraRules
    }

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
        cosmeticFilteringEnabled: Bool = true
    ) -> String {
        let fingerprint = compatibilityRulesFingerprintHex() + "|identity-v2"
        // Only the disabled state is folded in so existing caches stay valid.
        let material = cosmeticFilteringEnabled
            ? "\(baseRulesHashHex)|\(fingerprint)"
            : "\(baseRulesHashHex)|\(fingerprint)|nocosmetic"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the default filter file contents from the main bundle.
    ///
    /// - Returns: The contents of the default filter list or an error message if the file cannot be read.
    public static func readDefaultFilterList() -> String {
        do {
            if let filePath = Bundle.main.url(forResource: "filter", withExtension: "txt") {
                return try String(contentsOf: filePath, encoding: .utf8)
            }

            return "Not found the default filter file"
        } catch {
            return "Failed to read the filter file: \(error)"
        }
    }

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
        let context: ReloadContext
    }

    private enum ReloadMarkerWriteResult {
        case written
        case paused
        case changed(ReloadSnapshot)
        case invalid
        case failed
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
              (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) != nil
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
        try withContentBlockerOutputLock(at: appGroupURL, targetRulesFilename: outputURL.lastPathComponent) {
            let marker = (try? Data(contentsOf: markerURL)).flatMap {
                try? JSONDecoder().decode(ReloadMarker.self, from: $0)
            }
            return ReloadSnapshot(
                marker: marker,
                outputDigest: try validOutputDigest(try? Data(contentsOf: outputURL)),
                context: currentReloadContext
            )
        }
    }

    private static func writeReloadMarkerIfUnchanged(
        markerURL: URL,
        outputURL: URL,
        appGroupURL: URL,
        expectedDigest: String?,
        expectedContext: ReloadContext,
        groupIdentifier: String
    ) throws -> ReloadMarkerWriteResult {
        try withContentBlockerOutputLock(at: appGroupURL, targetRulesFilename: outputURL.lastPathComponent) {
            if BlockingPauseStore.isContentBlockingPaused(groupIdentifier: groupIdentifier) {
                try? FileManager.default.removeItem(at: markerURL)
                return .paused
            }

            let snapshot = ReloadSnapshot(
                marker: nil,
                outputDigest: try validOutputDigest(try? Data(contentsOf: outputURL)),
                context: currentReloadContext
            )
            guard let outputDigest = snapshot.outputDigest else {
                try? FileManager.default.removeItem(at: markerURL)
                return .invalid
            }
            guard outputDigest == expectedDigest, snapshot.context == expectedContext else {
                try? FileManager.default.removeItem(at: markerURL)
                return .changed(snapshot)
            }

            let newMarker = ReloadMarker(
                schema: reloadMarkerSchema,
                outputDigest: outputDigest,
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
    private static func contentBlockerIsEnabled(identifier: String) async -> Bool {
        await withCheckedContinuation { continuation in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: identifier) { state, error in
                continuation.resume(returning: error == nil && state?.isEnabled == true)
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
            let rewritten = (try? withContentBlockerOutputLock(at: containerURL, targetRulesFilename: targetRulesFilename) {
                let data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
                guard try validOutputDigest(data) != nil else { return false }
                try data.write(to: outputURL, options: .atomic)
                try? FileManager.default.removeItem(at: markerURL)
                return true
            }) ?? false
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
                if enabled,
                   !BlockingPauseStore.isContentBlockingPaused(groupIdentifier: groupIdentifier),
                   reloadMarkerMatches(verified)
                {
                    return ReloadAttemptResult(success: true, skipped: true, attempts: 0, durationMs: 0)
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
                maxRetries: enabledInSafari ? maxRetries : 1,
                timeout: recovering ? ContentBlockerReloadPolicy.recoveryTimeout : reloadCompletionTimeout
            )
            totalAttempts += reload.attempts
            guard reload.success else {
                return ReloadAttemptResult(
                    success: false,
                    disabledInSafari: !enabledInSafari,
                    attempts: totalAttempts,
                    durationMs: elapsedMs(),
                    failureReason: enabledInSafari
                        ? reload.failureReason
                        : ReloadFailureReason.disabledInSafari
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
                expectedContext: snapshot.context,
                groupIdentifier: groupIdentifier
            ) {
            case .some(.written), .some(.paused):
                return ReloadAttemptResult(
                    success: true,
                    attempts: totalAttempts,
                    durationMs: elapsedMs()
                )
            case .some(.changed(let changed)):
                guard changed.outputDigest != nil else {
                    return ReloadAttemptResult(
                        success: false,
                        attempts: totalAttempts,
                        durationMs: elapsedMs(),
                        failureReason: ReloadFailureReason.outputUnreadable
                    )
                }
                snapshot = changed
                mustReloadNewestOutput = true
            case .some(.invalid), .some(.failed), .none:
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
        targetRulesFilename: String
    ) throws -> ContentBlockerSaveResult {
        os_log(.info, "Saving pre-formatted JSON content blocker rules to %@", targetRulesFilename)
        let data = Data(jsonRules.utf8)
        guard let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let sharedFileURL = appGroupURL.appendingPathComponent(targetRulesFilename)
        let outputChanged = try withContentBlockerOutputLock(
            at: appGroupURL,
            targetRulesFilename: targetRulesFilename
        ) {
            let outputChanged = (try? Data(contentsOf: sharedFileURL)) != data
            if outputChanged {
                try data.write(to: sharedFileURL, options: .atomic)
                os_log(.info, "Successfully saved rules to %@", sharedFileURL.path)
            } else {
                os_log(.info, "Skipped unchanged rules at %@", sharedFileURL.path)
            }
            return outputChanged
        }
        return ContentBlockerSaveResult(ruleCount: rules.count, outputChanged: outputChanged)
    }

    public static func saveContentBlocker(jsonRules: String, groupIdentifier: String, targetRulesFilename: String) throws -> Int {
        try saveContentBlockerIfChanged(
            jsonRules: jsonRules,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetRulesFilename
        ).ruleCount
    }

    /// Converts rules from a file, with a persistent on-disk cache keyed by the caller-provided SHA256.
    /// This avoids re-running SafariConverterLib when the combined rules for a target haven't changed.
    public static func convertFilterFromFile(
        rulesFileURL: URL,
        rulesSHA256Hex: String,
        groupIdentifier: String,
        targetRulesFilename: String,
        disabledSites: [String],
        isCancelled: (() -> Bool)? = nil
    ) throws -> (safariRulesCount: Int, advancedRulesText: String?) {
        let result = try convertFilterFromFileWithOutputChange(
            rulesFileURL: rulesFileURL,
            rulesSHA256Hex: rulesSHA256Hex,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetRulesFilename,
            disabledSites: disabledSites,
            isCancelled: isCancelled
        )
        return (
            safariRulesCount: result.safariRulesCount,
            advancedRulesText: result.advancedRulesText
        )
    }

    static func convertFilterFromFileWithOutputChange(
        rulesFileURL: URL,
        rulesSHA256Hex: String,
        groupIdentifier: String,
        targetRulesFilename: String,
        disabledSites: [String],
        cosmeticFilteringEnabled: Bool = true,
        compatibilitySiteRestriction: [String]? = nil,
        isCancelled: (() -> Bool)? = nil
    ) throws -> (safariRulesCount: Int, advancedRulesText: String?, outputChanged: Bool) {
        let cancellationRequested = {
            Task.isCancelled || isCancelled?() == true
        }
        let sitesToUse = disabledSites
        let effectiveRulesHash = effectiveRulesHashHex(
            baseRulesHashHex: rulesSHA256Hex + (compatibilitySiteRestriction.map { "|compatibilitySites=" + $0.sorted().joined(separator: ",") } ?? ""),
            cosmeticFilteringEnabled: cosmeticFilteringEnabled
        )

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let baseFilename = ContentBlockerIncrementalCache.baseRulesFilename(for: targetRulesFilename)
        let baseCountFilename = "\(baseFilename).count"
        let baseHashFilename = "\(baseFilename).sha256"
        let advancedFilename = ContentBlockerIncrementalCache.baseAdvancedRulesFilename(
            for: targetRulesFilename
        )

        let baseURL = containerURL.appendingPathComponent(baseFilename)
        let baseCountURL = containerURL.appendingPathComponent(baseCountFilename)
        let baseHashURL = containerURL.appendingPathComponent(baseHashFilename)
        let advancedURL = containerURL.appendingPathComponent(advancedFilename)

        if let cachedHash = try? String(contentsOf: baseHashURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            cachedHash == effectiveRulesHash,
            ContentBlockerIncrementalCache.hasCoherentBaseRulesCache(
                targetRulesFilename: targetRulesFilename,
                groupIdentifier: groupIdentifier
            ),
            let baseJSON = try? String(contentsOf: baseURL, encoding: .utf8),
            let parsedBaseCount = parsedContentBlockerRuleCount(baseJSON),
            let baseCount = (try? String(contentsOf: baseCountURL, encoding: .utf8))
                .flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
            baseCount == parsedBaseCount
        {
            if cancellationRequested() {
                throw CancellationError()
            }
            let finalized = finalizeContentBlockerJSON(
                baseJSON: baseJSON,
                disabledSites: sitesToUse,
                knownBaseCount: baseCount
            )
            if cancellationRequested() {
                throw CancellationError()
            }
            let output = try saveContentBlockerIfChanged(
                jsonRules: finalized.json,
                groupIdentifier: groupIdentifier,
                targetRulesFilename: targetRulesFilename
            )

            let advancedText =
                (try? String(contentsOf: advancedURL, encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }

            return (
                safariRulesCount: finalized.ruleCount,
                advancedRulesText: advancedText,
                outputChanged: output.outputChanged
            )
        }

        // Cache miss: read rules file and run conversion.
        if cancellationRequested() {
            throw CancellationError()
        }
        let combinedRules = try String(contentsOf: rulesFileURL, encoding: .utf8)
        var effectiveRules = combinedRulesWithEmbeddedCompatibility(combinedRules, siteRestriction: compatibilitySiteRestriction)
        if !cosmeticFilteringEnabled {
            effectiveRules = CosmeticFilteringPreference.strippingCosmeticRules(from: effectiveRules)
        }
        if cancellationRequested() {
            throw CancellationError()
        }
        let result = try convertRules(
            rules: effectiveRules,
            isCancelled: cancellationRequested
        )
        if cancellationRequested() {
            throw CancellationError()
        }

        _ = try saveContentBlockerIfChanged(
            jsonRules: result.safariRulesJSON,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: baseFilename
        )
        try saveBlockerListFile(contents: String(result.safariRulesCount), groupIdentifier: groupIdentifier, filename: baseCountFilename)
        try saveBlockerListFile(contents: result.advancedRulesText ?? "", groupIdentifier: groupIdentifier, filename: advancedFilename)

        let finalized = finalizeContentBlockerJSON(
            baseJSON: result.safariRulesJSON,
            disabledSites: sitesToUse,
            knownBaseCount: result.safariRulesCount
        )
        let output = try saveContentBlockerIfChanged(
            jsonRules: finalized.json,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetRulesFilename
        )
        try saveBlockerListFile(contents: effectiveRulesHash, groupIdentifier: groupIdentifier, filename: baseHashFilename)

        return (
            safariRulesCount: finalized.ruleCount,
            advancedRulesText: result.advancedRulesText,
            outputChanged: output.outputChanged
        )
    }

    /// Compiles rules for a specific content blocker target or reuses cached compilation results if available.
    public static func compileTargetRules(
        filters: [FilterList],
        orderedSelectedFilters: [FilterList],
        affinitySnapshot: SafariContentBlockerAffinitySnapshot,
        targetInfo: ContentBlockerTargetInfo,
        allTargets: [ContentBlockerTargetInfo],
        disabledSites: [String],
        extraRulesText: String?,
        groupIdentifier: String,
        isCancelled: (() -> Bool)? = nil
    ) throws -> ContentBlockerTargetOutcome {
        if Task.isCancelled || isCancelled?() == true {
            throw CancellationError()
        }
        // Use the same stable list order for cache identity and fresh output.
        // Sorting only the hash would reuse output from a different ordering.
        let filters = ContentBlockerIncrementalCache.canonicalFilterOrder(filters)
        let orderedSelectedFilters = ContentBlockerIncrementalCache.canonicalFilterOrder(orderedSelectedFilters)
        let rulesFilename = targetInfo.rulesFilename
        let cosmeticFilteringEnabled = CosmeticFilteringPreference.isEnabled(groupIdentifier: groupIdentifier)
        // Every selected list can change cross-slot ownership or exception
        // context, even without affinity. Include all of them in cache identity.
        let assignedIDs = Set(filters.map(\.id))
        let affinityContributors = orderedSelectedFilters.filter {
            !assignedIDs.contains($0.id)
        }
        let currentSignature = ContentBlockerIncrementalCache.computeInputSignature(
            filters: filters,
            affinityContributors: affinityContributors,
            groupIdentifier: groupIdentifier,
            extraRulesText: extraRulesText,
            cosmeticFilteringEnabled: cosmeticFilteringEnabled,
            compatibilitySiteRestriction: orderedSelectedFilters.isEmpty ? [] : orderedSelectedFilters.first?.activeSiteRestriction
        )
        let storedSignature = ContentBlockerIncrementalCache.loadInputSignature(
            targetRulesFilename: rulesFilename,
            groupIdentifier: groupIdentifier
        )

        if let currentSignature,
           currentSignature == storedSignature,
           ContentBlockerIncrementalCache.hasCoherentBaseRulesCache(
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier
           ) {
            let fastUpdate = try ContentBlockerService.fastUpdateDisabledSitesWithOutputChange(
                groupIdentifier: groupIdentifier,
                targetRulesFilename: rulesFilename,
                disabledSites: disabledSites
            )
            let cachedAdvancedRules = ContentBlockerIncrementalCache.loadCachedAdvancedRules(
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier
            )
            let trimmedAdvanced = cachedAdvancedRules?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return ContentBlockerTargetOutcome(
                safariRulesCount: fastUpdate.safariRulesCount,
                advancedRulesText: (trimmedAdvanced?.isEmpty == false) ? trimmedAdvanced : nil,
                reusedCachedBase: true,
                outputChanged: fastUpdate.outputChanged
            )
        }

        let conversion = try convertFiltersMemoryEfficient(
            filters: filters,
            orderedSelectedFilters: orderedSelectedFilters,
            affinitySnapshot: affinitySnapshot,
            targetInfo: targetInfo,
            allTargets: allTargets,
            disabledSites: disabledSites,
            extraRulesText: extraRulesText,
            cosmeticFilteringEnabled: cosmeticFilteringEnabled,
            groupIdentifier: groupIdentifier,
            isCancelled: isCancelled
        )

        if let currentSignature {
            ContentBlockerIncrementalCache.saveInputSignature(
                currentSignature,
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier
            )
        }

        return ContentBlockerTargetOutcome(
            safariRulesCount: conversion.safariRulesCount,
            advancedRulesText: conversion.advancedRulesText,
            reusedCachedBase: false,
            outputChanged: conversion.outputChanged
        )
    }

    /// Compatibility overload for callers that identify affinity filters by ID.
    public static func compileTargetRules(
        filters: [FilterList],
        orderedSelectedFilters: [FilterList],
        affinityFilterIDs: Set<UUID>,
        targetInfo: ContentBlockerTargetInfo,
        allTargets: [ContentBlockerTargetInfo],
        disabledSites: [String],
        extraRulesText: String?,
        groupIdentifier: String,
        isCancelled: (() -> Bool)? = nil
    ) throws -> ContentBlockerTargetOutcome {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        var contentsByFilterID: [UUID: String] = [:]
        for filter in orderedSelectedFilters where affinityFilterIDs.contains(filter.id) {
            guard let sourceURL = SafariContentBlockerAffinityProcessor.sourceURL(
                for: filter,
                containerURL: containerURL
            ) else {
                contentsByFilterID[filter.id] = ""
                continue
            }
            let rawContent = try String(contentsOf: sourceURL, encoding: .utf8)
            contentsByFilterID[filter.id] = SafariContentBlockerAffinityProcessor.affinitySourceContent(
                for: filter,
                rawContent: rawContent
            ) ?? rawContent
        }

        return try compileTargetRules(
            filters: filters,
            orderedSelectedFilters: orderedSelectedFilters,
            affinitySnapshot: SafariContentBlockerAffinitySnapshot(
                contentsByFilterID: contentsByFilterID
            ),
            targetInfo: targetInfo,
            allTargets: allTargets,
            disabledSites: disabledSites,
            extraRulesText: extraRulesText,
            groupIdentifier: groupIdentifier,
            isCancelled: isCancelled
        )
    }

    /// Choose one owner across slots with equal exception contexts. Safari
    /// exceptions are local to a slot; affinity copies must remain in place.
    private static func crossTargetDuplicateRules(
        filters: [FilterList], orderedFilters: [FilterList],
        snapshot: SafariContentBlockerAffinitySnapshot,
        target: ContentBlockerTargetInfo, targets: [ContentBlockerTargetInfo],
        containerURL: URL, isCancelled: () -> Bool
    ) throws -> [UUID: Set<String>] {
        let distribution = ContentBlockerMappingService.distribute(selectedFilters: orderedFilters, across: targets)
        guard Set((distribution[target] ?? []).map(\.id)) == Set(filters.map(\.id)) else {
            // Compatibility callers may supply a custom mapping we cannot infer.
            return [:]
        }
        var sources: [UUID: String] = [:]
        for filter in orderedFilters {
            if isCancelled() { throw CancellationError() }
            guard let url = SafariContentBlockerAffinityProcessor.sourceURL(for: filter, containerURL: containerURL) else { continue }
            sources[filter.id] = try String(contentsOf: url, encoding: .utf8)
        }
        var contexts: [ContentBlockerTargetInfo: String] = [:]
        var owners: [UUID: ContentBlockerTargetInfo] = [:]
        for slot in targets {
            let assigned = Set((distribution[slot] ?? []).map(\.id))
            for id in assigned { owners[id] = slot }
            var exceptions = Set<String>()
            for filter in orderedFilters {
                if isCancelled() { throw CancellationError() }
                var text: String
                if let affinity = snapshot.content(for: filter.id) {
                    text = SafariContentBlockerAffinityProcessor.filteredContent(
                        from: affinity, includeBaseRules: assigned.contains(filter.id), target: slot, allTargets: targets
                    )
                } else {
                    guard assigned.contains(filter.id), let source = sources[filter.id] else { continue }
                    text = source
                }
                text = FilterListSiteExclusion.applyingSiteRestrictions(text, for: filter)
                for line in text.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("@@") || trimmed.contains("#@") || trimmed.contains("$badfilter") || trimmed.contains(",badfilter") || trimmed.hasPrefix("!#") {
                        exceptions.insert(FilterRuleAnalysis.ruleIdentity(trimmed))
                    }
                }
            }
            let digest = SHA256.hash(data: Data(exceptions.sorted().joined(separator: "\n").utf8))
            contexts[slot] = digest.map { String(format: "%02x", $0) }.joined()
        }
        var seen: [String: ContentBlockerTargetInfo] = [:]
        var excluded: [UUID: Set<String>] = [:]
        for filter in orderedFilters {
            if isCancelled() { throw CancellationError() }
            guard snapshot.content(for: filter.id) == nil,
                  let raw = sources[filter.id], !raw.contains("!#"),
                  let slot = owners[filter.id], let context = contexts[slot] else { continue }
            let text = FilterListSiteExclusion.applyingSiteRestrictions(raw, for: filter)
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard FilterRuleAnalysis.isRuleLine(trimmed), !trimmed.hasPrefix("@@"), !trimmed.contains("#@") else { continue }
                let identity = FilterRuleAnalysis.ruleIdentity(trimmed)
                let key = context + "\n" + identity
                if let owner = seen[key], owner != slot {
                    excluded[filter.id, default: []].insert(identity)
                } else {
                    seen[key] = slot
                }
            }
        }
        return excluded
    }

    private static func convertFiltersMemoryEfficient(
        filters: [FilterList],
        orderedSelectedFilters: [FilterList],
        affinitySnapshot: SafariContentBlockerAffinitySnapshot,
        targetInfo: ContentBlockerTargetInfo,
        allTargets: [ContentBlockerTargetInfo],
        disabledSites: [String],
        extraRulesText: String?,
        cosmeticFilteringEnabled: Bool,
        groupIdentifier: String,
        isCancelled: (() -> Bool)?
    ) throws -> (safariRulesCount: Int, advancedRulesText: String?, outputChanged: Bool) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let tempURL = containerURL.appendingPathComponent("temp_\(targetInfo.bundleIdentifier).txt")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        let newlineData = Data("\n".utf8)
        let assignedFilterIDs = Set(filters.map(\.id))
        let cancellationRequested = {
            Task.isCancelled || isCancelled?() == true
        }

        let exclusions = try crossTargetDuplicateRules(
            filters: filters, orderedFilters: orderedSelectedFilters,
            snapshot: affinitySnapshot, target: targetInfo, targets: allTargets,
            containerURL: containerURL, isCancelled: cancellationRequested
        )

        for filter in orderedSelectedFilters {
            if cancellationRequested() {
                throw CancellationError()
            }
            let includeBaseRules = assignedFilterIDs.contains(filter.id)
            let hasAffinity = affinitySnapshot.content(for: filter.id) != nil
            guard includeBaseRules || hasAffinity else { continue }

            if hasAffinity {
                try SafariContentBlockerAffinityProcessor.appendAffinityFilteredContribution(
                    for: filter,
                    includeBaseRules: includeBaseRules,
                    target: targetInfo,
                    allTargets: allTargets,
                    affinitySnapshot: affinitySnapshot,
                    destinationHandle: fileHandle,
                    hasher: &hasher,
                    newlineData: newlineData,
                    isCancelled: cancellationRequested
                )
            } else if let sourceURL = SafariContentBlockerAffinityProcessor.sourceURL(
                for: filter,
                containerURL: containerURL
            ) {
                if let duplicates = exclusions[filter.id], !duplicates.isEmpty {
                    let raw = try String(contentsOf: sourceURL, encoding: .utf8)
                    let restricted = FilterListSiteExclusion.applyingSiteRestrictions(raw, for: filter)
                    let kept = restricted.components(separatedBy: .newlines).filter {
                        !duplicates.contains(FilterRuleAnalysis.ruleIdentity($0))
                    }
                    try ContentBlockerInputWriter.appendInline(
                        kept.joined(separator: "\n"), to: fileHandle, hasher: &hasher,
                        newlineData: newlineData, isCancelled: cancellationRequested
                    )
                } else if filter.excludedSites.isEmpty && filter.activeSiteRestriction == nil {
                    try ContentBlockerInputWriter.appendFile(
                        from: sourceURL,
                        to: fileHandle,
                        hasher: &hasher,
                        newlineData: newlineData,
                        policy: .strict,
                        isCancelled: cancellationRequested
                    )
                } else {
                    let rawContent = try String(contentsOf: sourceURL, encoding: .utf8)
                    try ContentBlockerInputWriter.appendInline(
                        FilterListSiteExclusion.applyingSiteRestrictions(rawContent, for: filter),
                        to: fileHandle,
                        hasher: &hasher,
                        newlineData: newlineData,
                        isCancelled: cancellationRequested
                    )
                }
            }
        }

        if let extraRulesText, !extraRulesText.isEmpty {
            try ContentBlockerInputWriter.appendInline(
                extraRulesText,
                to: fileHandle,
                hasher: &hasher,
                newlineData: newlineData,
                isCancelled: cancellationRequested
            )
        }

        let digest = hasher.finalize()
        let rulesSHA256Hex = digest.map { String(format: "%02x", $0) }.joined()

        return try ContentBlockerService.convertFilterFromFileWithOutputChange(
            rulesFileURL: tempURL,
            rulesSHA256Hex: rulesSHA256Hex,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetInfo.rulesFilename,
            disabledSites: disabledSites,
            cosmeticFilteringEnabled: cosmeticFilteringEnabled,
            compatibilitySiteRestriction: orderedSelectedFilters.isEmpty ? [] : orderedSelectedFilters.first?.activeSiteRestriction,
            isCancelled: cancellationRequested
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
        disabledSites: [String]
    ) throws -> (safariRulesCount: Int, advancedRulesText: String?) {
        let result = try fastUpdateDisabledSitesWithOutputChange(
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetRulesFilename,
            disabledSites: disabledSites
        )
        return (
            safariRulesCount: result.safariRulesCount,
            advancedRulesText: result.advancedRulesText
        )
    }

    static func fastUpdateDisabledSitesWithOutputChange(
        groupIdentifier: String,
        targetRulesFilename: String,
        disabledSites: [String]
    ) throws -> (safariRulesCount: Int, advancedRulesText: String?, outputChanged: Bool) {
        let sitesToUse = disabledSites

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw CocoaError(.fileNoSuchFile)
        }
        
        let baseFilename = ContentBlockerIncrementalCache.baseRulesFilename(for: targetRulesFilename)
        let baseCountFilename = "\(baseFilename).count"

        // Preferred path: use cached base JSON (no ignore rules) + cheap string injection.
        let baseURL = containerURL.appendingPathComponent(baseFilename)
        let baseCountURL = containerURL.appendingPathComponent(baseCountFilename)
        if ContentBlockerIncrementalCache.hasCoherentBaseRulesCache(
            targetRulesFilename: targetRulesFilename,
            groupIdentifier: groupIdentifier
        ),
           let baseJSON = try? String(contentsOf: baseURL, encoding: .utf8),
           let parsedBaseCount = parsedContentBlockerRuleCount(baseJSON),
           let baseCount = (try? String(contentsOf: baseCountURL, encoding: .utf8))
                .flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
           baseCount == parsedBaseCount {
            let finalized = finalizeContentBlockerJSON(
                baseJSON: baseJSON,
                disabledSites: sitesToUse,
                knownBaseCount: baseCount
            )
            let output = try saveContentBlockerIfChanged(
                jsonRules: finalized.json,
                groupIdentifier: groupIdentifier,
                targetRulesFilename: targetRulesFilename
            )

            let advancedURL = containerURL.appendingPathComponent(
                ContentBlockerIncrementalCache.baseAdvancedRulesFilename(for: targetRulesFilename)
            )
            let advancedRulesText = try String(contentsOf: advancedURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let finalRuleCount = finalized.ruleCount

            os_log(.info, "Fast updated %@ with %d rules for %d disabled sites", targetRulesFilename, finalRuleCount, sitesToUse.count)
            return (
                safariRulesCount: finalRuleCount,
                advancedRulesText: advancedRulesText.isEmpty ? nil : advancedRulesText,
                outputChanged: output.outputChanged
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
    ) -> (json: String, ruleCount: Int) {
        let limit = max(ruleLimit, 0)
        let sites = Array(
            DisabledSitesNormalizer.normalizedDomains(from: disabledSites).prefix(limit)
        )

        guard !sites.isEmpty else {
            if let knownBaseCount, knownBaseCount <= limit {
                return (baseJSON, knownBaseCount)
            }
            if let truncated = truncateContentBlockerJSON(baseJSON, to: limit) {
                return truncated
            }
            return (baseJSON, min(knownBaseCount ?? countRulesInJSON(baseJSON), limit))
        }

        let baseCount = knownBaseCount ?? countRulesInJSON(baseJSON)
        if baseCount + sites.count <= limit {
            return (
                injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sites),
                baseCount + sites.count
            )
        }

        let maxBase = max(limit - sites.count, 0)
        guard let truncated = truncateContentBlockerJSON(baseJSON, to: maxBase) else {
            if baseCount <= maxBase {
                return (
                    injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sites),
                    baseCount + sites.count
                )
            }
            return (baseJSON, min(baseCount, limit))
        }

        return (
            injectIgnoreRulesForDisabledSites(json: truncated.json, disabledSites: sites),
            truncated.ruleCount + sites.count
        )
    }

    private static func truncateContentBlockerJSON(
        _ json: String,
        to maxRules: Int
    ) -> (json: String, ruleCount: Int)? {
        guard maxRules >= 0 else { return nil }
        guard var rules = parseContentBlockerRules(json) else { return nil }
        if rules.count > maxRules {
            rules.removeLast(rules.count - maxRules)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return (text, rules.count)
    }

    private static func parseContentBlockerRules(_ json: String) -> [[String: Any]]? {
        guard let jsonData = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]])
    }

    private static func escapeForJSONString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func disabledSiteIgnoreRuleJSON(for site: String) -> String {
        let trimmedSite = site.trimmingCharacters(in: .whitespacesAndNewlines)
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
    
    /// Parses `json` once and returns its rule count, or nil when it is not a
    /// content blocker rule array. Cache hits compare this against the `.count`
    /// sidecar so a stale sidecar can never skip rule-limit truncation.
    private static func parsedContentBlockerRuleCount(_ json: String) -> Int? {
        guard let jsonData = json.data(using: .utf8),
              let rules = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        else { return nil }
        return rules.count
    }

    /// Counts the number of rules in a Safari content blocker JSON string.
    ///
    /// - Parameter json: Safari content blocker JSON string.
    /// - Returns: Number of rules in the JSON array.
    private static func countRulesInJSON(_ json: String) -> Int {
        do {
            guard let jsonData = json.data(using: .utf8),
                  let rules = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                return 0
            }
            return rules.count
        } catch {
            return 0
        }
    }
    
    /// Publishes the filter engine built from combined advanced rules from all filter groups.
    ///
    /// - Parameters:
    ///   - combinedAdvancedRules: Combined advanced rules text from all filter groups.
    ///   - groupIdentifier: Group ID to use for the shared container.
    public static func publishCombinedFilterEngine(
        combinedAdvancedRules: String,
        groupIdentifier: String
    ) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw WebExtension.WebExtensionError.containerURLNotFound(groupID: groupIdentifier)
        }

        let baseURL = containerURL.appendingPathComponent(Schema.BASE_DIR, isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let requestToken = try recordCombinedEngineRequest(at: baseURL)
        let safariVersion = SafariVersion.autodetect()
        let rulesData = Data(combinedAdvancedRules.utf8)

        #if os(iOS)
        // The section below holds exclusive kernel flocks on app group files for
        // the entire rebuild. Defer suspension while they are held and unwind
        // (releasing the locks) when suspension becomes imminent (0xDEAD10CC).
        let shield = EnginePublishSuspensionShield(reason: "wBlock combined engine publish")
        defer { shield.release() }
        let ensureNotSuspending: () throws -> Void = {
            if shield.isExpired {
                os_log(.info, "Abandoning combined filter engine publish before suspension")
                throw CombinedEnginePublishError.suspensionImminent
            }
        }
        let isEnginePublishCancelled = {
            shield.isExpired || Task.isCancelled
        }
        #else
        let ensureNotSuspending: () throws -> Void = {}
        let isEnginePublishCancelled = { Task.isCancelled }
        #endif

        let fingerprint = try combinedEngineFingerprint(
            rulesData: rulesData,
            safariVersion: safariVersion,
            isCancelled: isEnginePublishCancelled
        )

        try measure(label: combinedAdvancedRules.isEmpty ? "Clearing filter engine" : "Building combined filter engine") {
            try withCombinedEngineBuildLock(at: baseURL) {
                try ensureNotSuspending()
                let skipped = try withEngineCriticalSection(at: baseURL) {
                    try withCombinedEngineRequestLock(at: baseURL) {
                        try ensureCombinedEngineRequestIsCurrent(at: baseURL, requestToken: requestToken)
                        return try canSkipCombinedEnginePublish(
                            fingerprint: fingerprint,
                            baseURL: baseURL,
                            isCancelled: isEnginePublishCancelled
                        )
                    }
                }
                if skipped {
                    os_log(.info, "Skipping unchanged combined filter engine publish")
                    return
                }

                try ensureNotSuspending()
                let temporaryBuild = try buildTemporaryEngine(
                    rulesData: rulesData,
                    safariVersion: safariVersion,
                    baseURL: baseURL,
                    cancellationCheck: ensureNotSuspending,
                    isCancelled: isEnginePublishCancelled
                )
                defer { try? FileManager.default.removeItem(at: temporaryBuild.directory) }

                let published = try withEngineCriticalSection(at: baseURL) {
                    try withCombinedEngineRequestLock(at: baseURL) {
                        try ensureNotSuspending()
                        try ensureCombinedEngineRequestIsCurrent(at: baseURL, requestToken: requestToken)
                        if try canSkipCombinedEnginePublish(
                            fingerprint: fingerprint,
                            baseURL: baseURL,
                            isCancelled: isEnginePublishCancelled
                        ) {
                            return false
                        }

                        try publishEngineFiles(
                            from: temporaryBuild,
                            fingerprint: fingerprint,
                            baseURL: baseURL,
                            isCancelled: isEnginePublishCancelled
                        )
                        return true
                    }
                }

                if published {
                    os_log(
                        .info,
                        "Successfully published combined filter engine with %d characters of advanced rules",
                        combinedAdvancedRules.count
                    )
                }
            }
        }
    }

    public static func buildCombinedFilterEngine(combinedAdvancedRules: String, groupIdentifier: String) throws {
        try publishCombinedFilterEngine(
            combinedAdvancedRules: combinedAdvancedRules,
            groupIdentifier: groupIdentifier
        )
    }

    private struct CombinedEngineFingerprint: Equatable {
        let rulesHash: String
        let schemaVersion: Int
        let safariBuildContext: String
        let markerFormatVersion: Int
        let value: String
    }

    private struct TemporaryEngineBuild {
        let directory: URL
        let artifactDigests: [String: String]
    }

    private struct CombinedEngineMarker: Codable, Equatable {
        let markerFormatVersion: Int
        let schemaVersion: Int
        let safariBuildContext: String
        let rulesHash: String
        let fingerprint: String
        let artifactDigests: [String: String]
    }

    private static func combinedEngineFingerprint(
        rulesData: Data,
        safariVersion: SafariVersion,
        isCancelled: (() -> Bool)? = nil
    ) throws -> CombinedEngineFingerprint {
        let rulesHash = try combinedRulesHash(rulesData, isCancelled: isCancelled)
        let safariBuildContext = "\(currentPlatform)-safari-\(safariVersion.doubleValue)"
        let markerFormatVersion = combinedEngineMarkerFormatVersion
        let schemaVersion = Schema.VERSION
        let value = try combinedRulesHash(
            Data("\(markerFormatVersion)|\(schemaVersion)|\(safariBuildContext)|\(rulesHash)".utf8),
            isCancelled: isCancelled
        )
        return CombinedEngineFingerprint(
            rulesHash: rulesHash,
            schemaVersion: schemaVersion,
            safariBuildContext: safariBuildContext,
            markerFormatVersion: markerFormatVersion,
            value: value
        )
    }

    private static var currentPlatform: String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #else
        return "unknown"
        #endif
    }

    private static func combinedRulesHash(
        _ data: Data,
        isCancelled: (() -> Bool)? = nil
    ) throws -> String {
        try ContentBlockerChunkedHasher.hexDigest(
            for: data,
            isCancelled: {
                Task.isCancelled || isCancelled?() == true
            }
        )
    }

    private static func expectedMarker(
        for fingerprint: CombinedEngineFingerprint,
        artifactDigests: [String: String]
    ) -> CombinedEngineMarker {
        CombinedEngineMarker(
            markerFormatVersion: fingerprint.markerFormatVersion,
            schemaVersion: fingerprint.schemaVersion,
            safariBuildContext: fingerprint.safariBuildContext,
            rulesHash: fingerprint.rulesHash,
            fingerprint: fingerprint.value,
            artifactDigests: artifactDigests
        )
    }

    private static func canSkipCombinedEnginePublish(
        fingerprint: CombinedEngineFingerprint,
        baseURL: URL,
        isCancelled: (() -> Bool)? = nil
    ) throws -> Bool {
        let migrationMarkerURL = baseURL.appendingPathComponent(Schema.MIGRATION_MARKER_FILE_NAME)
        guard !FileManager.default.fileExists(atPath: migrationMarkerURL.path) else { return false }

        let markerURL = baseURL.appendingPathComponent(combinedEngineMarkerFileName)
        guard let markerData = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(CombinedEngineMarker.self, from: markerData),
              marker.markerFormatVersion == fingerprint.markerFormatVersion,
              marker.schemaVersion == fingerprint.schemaVersion,
              marker.safariBuildContext == fingerprint.safariBuildContext,
              marker.rulesHash == fingerprint.rulesHash,
              marker.fingerprint == fingerprint.value,
              Set(marker.artifactDigests.keys) == Set(engineStorageFileNames)
        else { return false }

        return try validatePublishedEngineFiles(
            at: baseURL,
            artifactDigests: marker.artifactDigests,
            isCancelled: isCancelled
        )
    }

    private static func validatePublishedEngineFiles(
        at baseURL: URL,
        artifactDigests: [String: String],
        isCancelled: (() -> Bool)? = nil
    ) throws -> Bool {
        guard Set(artifactDigests.keys) == Set(engineStorageFileNames) else { return false }
        return try engineArtifactDigests(
            at: baseURL,
            isCancelled: isCancelled
        ) == artifactDigests
    }

    private static func engineArtifactDigests(
        at baseURL: URL,
        isCancelled: (() -> Bool)? = nil
    ) throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try engineStorageFileNames.map { fileName in
            let data = try Data(contentsOf: baseURL.appendingPathComponent(fileName))
            return (
                fileName,
                try combinedRulesHash(data, isCancelled: isCancelled)
            )
        })
    }

    private static func validateTemporaryEngine(
        at directory: URL,
        fingerprint: CombinedEngineFingerprint,
        isCancelled: (() -> Bool)? = nil
    ) throws -> Bool {
        let artifactDigests = try engineArtifactDigests(
            at: directory,
            isCancelled: isCancelled
        )
        guard artifactDigests[Schema.RULES_FILE_NAME] == fingerprint.rulesHash,
              let metaData = try? Data(contentsOf: directory.appendingPathComponent(Schema.ENGINE_META_FILE_NAME)),
              let meta = EngineMeta.fromData(metaData),
              meta.schemaVersion == Int32(fingerprint.schemaVersion)
        else { return false }

        do {
            let storage = try FilterRuleStorage(
                fileURL: directory.appendingPathComponent(Schema.FILTER_RULE_STORAGE_FILE_NAME)
            )
            _ = try FilterEngine(
                storage: storage,
                indexFileURL: directory.appendingPathComponent(Schema.FILTER_ENGINE_INDEX_FILE_NAME)
            )

            let iterator = try storage.makeIterator()
            var decodedRuleCount = 0
            while iterator.next() != nil {
                decodedRuleCount += 1
            }
            return decodedRuleCount == storage.count
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return false
        }
    }

    private static func withCombinedEngineBuildLock<T>(at baseURL: URL, _ body: () throws -> T) throws -> T {
        guard let fileLock = FileLock(
            filePath: baseURL.appendingPathComponent(combinedEngineBuildLockFileName).path
        ), fileLock.lock(before: Date().addingTimeInterval(combinedEngineBuildLockTimeout)) else {
            throw WebExtension.WebExtensionError.buildEngineFailed(
                underlyingError: CocoaError(.fileWriteUnknown)
            )
        }
        defer { _ = fileLock.unlock() }
        return try body()
    }

    private static func withCombinedEngineRequestLock<T>(at baseURL: URL, _ body: () throws -> T) throws -> T {
        guard let fileLock = FileLock(
            filePath: baseURL.appendingPathComponent(combinedEngineRequestLockFileName).path
        ), fileLock.lock(before: Date().addingTimeInterval(combinedEngineRequestLockTimeout)) else {
            throw WebExtension.WebExtensionError.buildEngineFailed(
                underlyingError: CocoaError(.fileWriteUnknown)
            )
        }
        defer { _ = fileLock.unlock() }
        return try body()
    }

    private static func recordCombinedEngineRequest(at baseURL: URL) throws -> String {
        let token = UUID().uuidString
        try withCombinedEngineRequestLock(at: baseURL) {
            try Data(token.utf8).write(
                to: baseURL.appendingPathComponent(combinedEngineLatestRequestFileName),
                options: .atomic
            )
        }
        return token
    }

    private static func latestCombinedEngineRequestToken(at baseURL: URL) -> String? {
        guard let token = try? String(
            contentsOf: baseURL.appendingPathComponent(combinedEngineLatestRequestFileName),
            encoding: .utf8
        ) else {
            return nil
        }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedToken.isEmpty ? nil : trimmedToken
    }

    private static func ensureCombinedEngineRequestIsCurrent(
        at baseURL: URL,
        requestToken: String
    ) throws {
        guard latestCombinedEngineRequestToken(at: baseURL) == requestToken else {
            os_log(.info, "Abandoning superseded combined filter engine publish")
            throw CombinedEnginePublishError.supersededRequest
        }
    }

    private static func withEngineCriticalSection<T>(at baseURL: URL, _ body: () throws -> T) throws -> T {
        try WebExtensionGate.shared.withLock {
            try withEngineFileLock(at: baseURL, body)
        }
    }

    private static func withEngineFileLock<T>(at baseURL: URL, _ body: () throws -> T) throws -> T {
        guard let fileLock = FileLock(
            filePath: baseURL.appendingPathComponent(Schema.LOCK_FILE_NAME).path
        ), fileLock.lock(before: Date().addingTimeInterval(engineFileLockTimeout)) else {
            throw WebExtension.WebExtensionError.buildEngineFailed(
                underlyingError: CocoaError(.fileWriteUnknown)
            )
        }
        defer { _ = fileLock.unlock() }
        return try body()
    }

    private static func buildTemporaryEngine(
        rulesData: Data,
        safariVersion: SafariVersion,
        baseURL: URL,
        cancellationCheck: () throws -> Void,
        isCancelled: (() -> Bool)? = nil
    ) throws -> TemporaryEngineBuild {
        let fileManager = FileManager.default
        let temporaryDirectory = baseURL.appendingPathComponent(
            "engine-rebuild-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        do {
            let rulesURL = temporaryDirectory.appendingPathComponent(Schema.RULES_FILE_NAME)
            let storageURL = temporaryDirectory.appendingPathComponent(Schema.FILTER_RULE_STORAGE_FILE_NAME)
            let indexURL = temporaryDirectory.appendingPathComponent(Schema.FILTER_ENGINE_INDEX_FILE_NAME)
            let metaURL = temporaryDirectory.appendingPathComponent(Schema.ENGINE_META_FILE_NAME)

            try cancellationCheck()
            let rules = String(decoding: rulesData, as: UTF8.self)
            let storage = try FilterRuleStorage(
                from: rules.components(separatedBy: "\n"),
                for: safariVersion,
                fileURL: storageURL
            )
            try cancellationCheck()
            let engine = try FilterEngine(storage: storage)
            try engine.write(to: indexURL)
            try cancellationCheck()
            try rulesData.write(to: rulesURL, options: .atomic)

            try cancellationCheck()
            let meta = EngineMeta(
                timestamp: Date().timeIntervalSince1970,
                schemaVersion: Int32(Schema.VERSION)
            )
            try meta.toData().write(to: metaURL, options: .atomic)
            try cancellationCheck()

            let fingerprint = try combinedEngineFingerprint(
                rulesData: rulesData,
                safariVersion: safariVersion,
                isCancelled: isCancelled
            )
            guard try validateTemporaryEngine(
                at: temporaryDirectory,
                fingerprint: fingerprint,
                isCancelled: isCancelled
            ) else {
                throw WebExtension.WebExtensionError.buildEngineFailed(
                    underlyingError: CocoaError(.fileReadCorruptFile)
                )
            }
            let artifactDigests = try engineArtifactDigests(
                at: temporaryDirectory,
                isCancelled: isCancelled
            )
            return TemporaryEngineBuild(directory: temporaryDirectory, artifactDigests: artifactDigests)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private static func publishEngineFiles(
        from temporaryBuild: TemporaryEngineBuild,
        fingerprint: CombinedEngineFingerprint,
        baseURL: URL,
        isCancelled: (() -> Bool)? = nil
    ) throws {
        let migrationMarkerURL = baseURL.appendingPathComponent(Schema.MIGRATION_MARKER_FILE_NAME)
        try Data().write(to: migrationMarkerURL, options: .atomic)
        try invalidateExistingEngineMeta(at: baseURL)

        for fileName in engineStorageFileNames where fileName != Schema.ENGINE_META_FILE_NAME {
            try replaceEngineFile(
                temporaryBuild.directory.appendingPathComponent(fileName),
                in: baseURL,
                named: fileName
            )
        }
        try replaceEngineFile(
            temporaryBuild.directory.appendingPathComponent(Schema.ENGINE_META_FILE_NAME),
            in: baseURL,
            named: Schema.ENGINE_META_FILE_NAME
        )

        guard try validatePublishedEngineFiles(
            at: baseURL,
            artifactDigests: temporaryBuild.artifactDigests,
            isCancelled: isCancelled
        ) else {
            throw WebExtension.WebExtensionError.buildEngineFailed(
                underlyingError: CocoaError(.fileReadCorruptFile)
            )
        }

        let marker = expectedMarker(
            for: fingerprint,
            artifactDigests: temporaryBuild.artifactDigests
        )
        let markerData = try JSONEncoder().encode(marker)
        try markerData.write(
            to: baseURL.appendingPathComponent(combinedEngineMarkerFileName),
            options: .atomic
        )
        try FileManager.default.removeItem(at: migrationMarkerURL)
    }

    private static func invalidateExistingEngineMeta(at baseURL: URL) throws {
        let metaURL = baseURL.appendingPathComponent(Schema.ENGINE_META_FILE_NAME)
        guard FileManager.default.fileExists(atPath: metaURL.path) else { return }
        try FileManager.default.removeItem(at: metaURL)
    }

    private static func replaceEngineFile(_ sourceURL: URL, in baseURL: URL, named fileName: String) throws {
        let destinationURL = baseURL.appendingPathComponent(fileName)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: sourceURL)
        } else {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
    }
}

// MARK: - Safari Content Blocker functions

extension ContentBlockerService {
    private enum RuleConversionError: LocalizedError {
        case stoppedUnexpectedly

        var errorDescription: String? {
            "Rule conversion stopped without a cancellation request."
        }
    }

    /// Converts AdGuard rules into the Safari content blocking rules syntax.
    ///
    /// - Parameters:
    ///   - rules: AdGuard rules to convert.
    /// - Returns: A ConversionResult containing the converted Safari rules in JSON format
    ///           and advanced rules in text format, or nil when converter resources are unavailable.
    private static func convertRules(
        rules: String,
        isCancelled: (() -> Bool)? = nil
    ) throws -> ConversionResult {
        guard publicSuffixListResourcesAreAvailable() else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let cancellationRequested = {
            Task.isCancelled || isCancelled?() == true
        }
        if cancellationRequested() {
            throw CancellationError()
        }

        var filterRules = rules
        if !filterRules.isContiguousUTF8 {
            measure(label: "Make contigious UTF-8") {
                // This is super important for the conversion performance.
                // In a normal app make sure you're storing filter lists as
                // contigious UTF-8 strings.
                filterRules.makeContiguousUTF8()
            }
        }

        // Important: many filter lists use CRLF, which Swift can treat as a single `Character`.
        // Splitting on "\n" alone may fail and yield a single giant line, resulting in 0 converted rules.
        let lines = deduplicatedRuleLines(
            filterRules.split(whereSeparator: \.isNewline).map(String.init)
        )
        if cancellationRequested() {
            throw CancellationError()
        }

        let progress = Progress.discreteProgress(totalUnitCount: Int64(lines.count))
        let cancellationMonitor = DispatchSource.makeTimerSource(
            queue: DispatchQueue.global(qos: .utility)
        )
        cancellationMonitor.schedule(deadline: .now(), repeating: .milliseconds(20))
        cancellationMonitor.setEventHandler {
            if cancellationRequested() {
                progress.cancel()
            }
        }
        cancellationMonitor.resume()
        defer {
            cancellationMonitor.setEventHandler {}
            cancellationMonitor.cancel()
        }

        let result = measure(label: "Conversion") {
            ContentBlockerConverter().convertArray(
                rules: lines,
                safariVersion: .autodetect(),
                advancedBlocking: true,
                maxJsonSizeBytes: nil,
                progress: progress
            )
        }
        if cancellationRequested() {
            throw CancellationError()
        }
        if progress.isCancelled {
            throw RuleConversionError.stoppedUnexpectedly
        }
        return result
    }

    private static func publicSuffixListResourcesAreAvailable() -> Bool {
        let bundleName = "swift-psl_PublicSuffixList"
        let candidateURLs = [
            Bundle.main.resourceURL,
            Bundle(for: ContentBlockerServiceBundleMarker.self).resourceURL,
            Bundle.main.bundleURL
        ].compactMap { $0 }

        for candidateURL in candidateURLs {
            guard let resourceBundle = Bundle(
                url: candidateURL.appendingPathComponent("\(bundleName).bundle")
            ) else { continue }

            let requiredResources = ["common", "negated", "asterisk"]
            let missingResources = requiredResources.filter { resourceName in
                guard let resourceURL = resourceBundle.url(
                    forResource: resourceName,
                    withExtension: "bin"
                ),
                FileManager.default.isReadableFile(atPath: resourceURL.path),
                let resourceValues = try? resourceURL.resourceValues(forKeys: [.fileSizeKey]),
                let fileSize = resourceValues.fileSize,
                fileSize > 0
                else { return true }
                return false
            }

            if missingResources.isEmpty {
                return true
            }

            os_log(
                .error,
                "Public Suffix List bundle is missing or unreadable resource(s): %@ (%@)",
                missingResources.joined(separator: ", "),
                resourceBundle.bundleURL.path
            )
        }

        os_log(.error, "Could not locate a usable swift-psl_PublicSuffixList resource bundle")
        return false
    }

    /// Saves the blocker list file contents to the shared directory specified by the group identifier.
    ///
    /// - Parameters:
    ///   - contents: String content to write to the blocker list file.
    ///   - groupIdentifier: App group identifier for accessing the shared container.
    private static func saveBlockerListFile(contents: String, groupIdentifier: String, filename: String) throws {
        guard
            let appGroupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier
            )
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        let sharedFileURL = appGroupURL.appendingPathComponent(filename)
        try Data(contents.utf8).write(to: sharedFileURL, options: .atomic)
        os_log(.info, "Successfully saved rules to %@", sharedFileURL.path)
    }

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

public nonisolated enum ContentBlockerInputWriter {
    public enum AppendPolicy {
        case strict
        case permissive((Error) -> Void)
    }

    @discardableResult
    public static func appendFile(
        from sourceURL: URL,
        to destinationHandle: FileHandle,
        hasher: inout SHA256,
        newlineData: Data,
        policy: AppendPolicy,
        chunkSize: Int = 64 * 1024,
        isCancelled: (() -> Bool)? = nil
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return false }
        do {
            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            defer { try? sourceHandle.close() }
            while true {
                if isCancelled?() == true {
                    throw CancellationError()
                }
                let chunk = try sourceHandle.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
                try destinationHandle.write(contentsOf: chunk)
            }
            hasher.update(data: newlineData)
            try destinationHandle.write(contentsOf: newlineData)
            return true
        } catch let error as CancellationError {
            throw error
        } catch {
            switch policy {
            case .strict:
                throw error
            case let .permissive(report):
                report(error)
                return false
            }
        }
    }

    public static func appendInline(
        _ rulesText: String,
        to destinationHandle: FileHandle,
        hasher: inout SHA256,
        newlineData: Data,
        isCancelled: (() -> Bool)? = nil
    ) throws {
        let rulesData = Data(rulesText.utf8)
        try ContentBlockerChunkedHasher.update(
            with: rulesData,
            hasher: &hasher,
            writingTo: destinationHandle,
            isCancelled: isCancelled
        )
        try ContentBlockerChunkedHasher.update(
            with: newlineData,
            hasher: &hasher,
            writingTo: destinationHandle,
            isCancelled: isCancelled
        )
    }
}
