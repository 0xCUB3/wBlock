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
internal import ZIPFoundation
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

    /// Version marker for built-in compatibility rules that are appended to
    /// every conversion. Bump this when changing `embeddedCompatibilityRules`
    /// so cached base JSON gets invalidated.
    private static let embeddedCompatibilityRulesVersion = "5"
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
    }

    /// Built-in compatibility rules that improve blocking of common dynamic ad script
    /// patterns and dynamic ad containers across filter sets.
    ///
    /// YouTube rules use trusted response replacement for pre-parse string
    /// replacement (faster than json-prune-fetch-response which works post-parse).
    /// Sourced from uAssets, translated to AdGuard syntax.
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
www.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '"adPlacements"', '"no_ads"', 'player?')
www.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '"adSlots"', '"no_ads"', 'player?')
www.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '"adPlacements"', '"no_ads"', 'player?')
www.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '"adSlots"', '"no_ads"', 'player?')
www.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '"adPlacements"', '"no_ads"', 'get_watch?')
www.youtube.com#%#//scriptlet('trusted-replace-xhr-response', '"adSlots"', '"no_ads"', 'get_watch?')
www.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '"adPlacements"', '"no_ads"', 'get_watch?')
www.youtube.com#%#//scriptlet('trusted-replace-fetch-response', '"adSlots"', '"no_ads"', 'get_watch?')
www.youtube.com#%#//scriptlet('set-constant', 'ytInitialPlayerResponse.playerAds', 'undefined')
www.youtube.com#%#//scriptlet('set-constant', 'ytInitialPlayerResponse.adPlacements', 'undefined')
www.youtube.com#%#//scriptlet('set-constant', 'ytInitialPlayerResponse.adSlots', 'undefined')
www.youtube.com#%#//scriptlet('set-constant', 'playerResponse.playerAds', 'undefined')
www.youtube.com#%#//scriptlet('set-constant', 'playerResponse.adPlacements', 'undefined')
www.youtube.com#%#//scriptlet('set-constant', 'playerResponse.adSlots', 'undefined')
"""

    private static func combinedRulesWithEmbeddedCompatibility(_ rawRules: String) -> String {
        let trimmedExtraRules = embeddedCompatibilityRules.trimmingCharacters(in: .whitespacesAndNewlines)
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
    private static func effectiveRulesHashHex(baseRulesHashHex: String) -> String {
        let fingerprint = compatibilityRulesFingerprintHex()
        let material = "\(baseRulesHashHex)|\(fingerprint)"
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

    /// Converts AdGuard rules and exports them as a ZIP archive.
    ///
    /// - Parameters:
    ///   - rules: AdGuard syntax rules to be converted.
    /// - Returns: Data object containing a ZIP archive with Safari content blocker JSON and advanced rules,
    ///           or nil if the archive creation fails.
    public static func exportConversionResult(rules: String) -> Data? {
        guard let result = try? convertRules(rules: rules) else { return nil }

        // We'll use a variable so we can modify the JSON string
        var safariRulesJSON = result.safariRulesJSON
        let advancedRulesText = result.advancedRulesText

        // Attempt to pretty-print the JSON
        if let data = safariRulesJSON.data(using: .utf8),
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.prettyPrinted]
            ),
            let prettyString = String(data: prettyData, encoding: .utf8)
        {
            safariRulesJSON = prettyString
        }

        // Pass the newly formatted JSON string to the ZIP creation
        return createZipArchive(
            safariRulesJSON: safariRulesJSON,
            advancedRulesText: advancedRulesText
        )
    }

    public struct ReloadAttemptResult: Sendable {
        public let success: Bool
        public let skipped: Bool
        public let attempts: Int
        public let durationMs: Int

        public init(success: Bool, skipped: Bool = false, attempts: Int, durationMs: Int) {
            self.success = success
            self.skipped = skipped
            self.attempts = attempts
            self.durationMs = durationMs
        }
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
    private static let maxReloadVerificationPasses = 3
    private static let reloadCoordinator = ReloadCoordinator()

    private static var currentReloadContext: ReloadContext {
        #if os(iOS)
        let platform = "iOS"
        #else
        let platform = "macOS"
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let info = Bundle.main.infoDictionary ?? [:]
        return ReloadContext(
            schema: reloadMarkerSchema,
            platform: platform,
            osVersion: osVersion,
            appVersion: info["CFBundleShortVersionString"] as? String ?? "",
            appBuild: info["CFBundleVersion"] as? String ?? ""
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

    private static func validOutputDigest(_ data: Data?) -> String? {
        guard let data,
              !data.isEmpty,
              (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) != nil
        else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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
                outputDigest: validOutputDigest(try? Data(contentsOf: outputURL)),
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
                outputDigest: validOutputDigest(try? Data(contentsOf: outputURL)),
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
            await reloadIfNeededSerially(
                identifier: identifier,
                targetRulesFilename: targetRulesFilename,
                groupIdentifier: groupIdentifier,
                maxRetries: maxRetries
            )
        }
        guard let result = gatedResult else {
            return ReloadAttemptResult(success: false, attempts: 0, durationMs: 0)
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
            return ReloadAttemptResult(success: false, attempts: 0, durationMs: elapsedMs())
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
        guard var snapshot = try? readReloadSnapshot(
            markerURL: markerURL,
            outputURL: outputURL,
            appGroupURL: containerURL
        ), snapshot.outputDigest != nil else {
            invalidateMarker()
            return ReloadAttemptResult(success: false, attempts: 0, durationMs: elapsedMs())
        }

        var totalAttempts = 0
        var mustReloadNewestOutput = false
        for _ in 0..<maxReloadVerificationPasses {
            if !mustReloadNewestOutput,
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
                        durationMs: elapsedMs()
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
                    durationMs: elapsedMs()
                )
            }

            // Do not let another caller observe a stale certification while this reload is in flight.
            invalidateMarker()

            let reload = await reloadWithRetryRaw(identifier: identifier, maxRetries: maxRetries)
            totalAttempts += reload.attempts
            guard reload.success else {
                return ReloadAttemptResult(
                    success: false,
                    attempts: totalAttempts,
                    durationMs: elapsedMs()
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
                    durationMs: elapsedMs()
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
                        durationMs: elapsedMs()
                    )
                }
                snapshot = changed
                mustReloadNewestOutput = true
            case .some(.invalid), .some(.failed), .none:
                invalidateMarker()
                return ReloadAttemptResult(
                    success: false,
                    attempts: totalAttempts,
                    durationMs: elapsedMs()
                )
            }
        }

        return ReloadAttemptResult(
            success: false,
            attempts: totalAttempts,
            durationMs: elapsedMs()
        )
    }


    /// Reloads the Safari content blocker extension with the specified identifier.
    ///
    /// - Parameters:
    ///   - identifier: Bundle ID of the content blocker extension to reload.
    /// - Returns: A Result indicating success or containing an error if the reload failed.
    @MainActor
    public static func reloadContentBlocker(
        withIdentifier identifier: String
    ) async -> Result<Void, Error> {
        os_log(.info, "Start reloading the content blocker")

        let error: Error? = await withCheckedContinuation { continuation in
            SFContentBlockerManager.reloadContentBlocker(withIdentifier: identifier) { error in
                continuation.resume(returning: error)
            }
        }

        let result: Result<Void, Error> = if let error { .failure(error) } else { .success(()) }

        switch result {
        case .success:
            os_log(.info, "Content blocker reloaded successfully.")
        case .failure(let error):
            // WKErrorDomain error 6 is a common error when the content blocker
            // cannot access the blocker list file.
            if error.localizedDescription.contains("WKErrorDomain error 6") {
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
            return ReloadAttemptResult(success: false, attempts: 0, durationMs: 0)
        }
        let gatedResult = await reloadCoordinator.withGate(key: identifier) {
            if let groupIdentifier, let targetRulesFilename {
                invalidateReloadMarker(
                    groupIdentifier: groupIdentifier,
                    targetRulesFilename: targetRulesFilename
                )
            }
            return await reloadWithRetryRaw(identifier: identifier, maxRetries: maxRetries)
        }
        guard let result = gatedResult else {
            return ReloadAttemptResult(success: false, attempts: 0, durationMs: 0)
        }
        return result
    }

    private static func reloadWithRetryRaw(
        identifier: String,
        maxRetries: Int
    ) async -> ReloadAttemptResult {
        let startTime = Date()
        let elapsedMs = { Int(Date().timeIntervalSince(startTime) * 1000) }

        guard maxRetries > 0 else {
            return ReloadAttemptResult(success: false, attempts: 0, durationMs: elapsedMs())
        }

        for attempt in 1...maxRetries {
            if Task.isCancelled {
                return ReloadAttemptResult(
                    success: false,
                    attempts: max(0, attempt - 1),
                    durationMs: elapsedMs()
                )
            }

            let result = await reloadContentBlocker(withIdentifier: identifier)
            if case .success = result {
                return ReloadAttemptResult(
                    success: true,
                    attempts: attempt,
                    durationMs: elapsedMs()
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
                    durationMs: elapsedMs()
                )
            }
        }

        return ReloadAttemptResult(
            success: false,
            attempts: maxRetries,
            durationMs: elapsedMs()
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
        disabledSites: [String]
    ) throws -> (safariRulesCount: Int, advancedRulesText: String?) {
        let result = try convertFilterFromFileWithOutputChange(
            rulesFileURL: rulesFileURL,
            rulesSHA256Hex: rulesSHA256Hex,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetRulesFilename,
            disabledSites: disabledSites
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
        disabledSites: [String]
    ) throws -> (safariRulesCount: Int, advancedRulesText: String?, outputChanged: Bool) {
        let sitesToUse = disabledSites
        let effectiveRulesHash = effectiveRulesHashHex(baseRulesHashHex: rulesSHA256Hex)

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
            isValidContentBlockerJSON(baseJSON),
            let baseCount = (try? String(contentsOf: baseCountURL, encoding: .utf8))
                .flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        {
            let finalJSON = injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sitesToUse)
            let output = try saveContentBlockerIfChanged(
                jsonRules: finalJSON,
                groupIdentifier: groupIdentifier,
                targetRulesFilename: targetRulesFilename
            )

            let advancedText =
                (try? String(contentsOf: advancedURL, encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }

            return (
                safariRulesCount: baseCount + sitesToUse.count,
                advancedRulesText: advancedText,
                outputChanged: output.outputChanged
            )
        }

        // Cache miss: read rules file and run conversion.
        let combinedRules = try String(contentsOf: rulesFileURL, encoding: .utf8)
        let effectiveRules = combinedRulesWithEmbeddedCompatibility(combinedRules)
        let result = try convertRules(rules: effectiveRules)

        _ = try saveContentBlockerIfChanged(
            jsonRules: result.safariRulesJSON,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: baseFilename
        )
        try saveBlockerListFile(contents: String(result.safariRulesCount), groupIdentifier: groupIdentifier, filename: baseCountFilename)
        try saveBlockerListFile(contents: result.advancedRulesText ?? "", groupIdentifier: groupIdentifier, filename: advancedFilename)

        let finalJSON = injectIgnoreRulesForDisabledSites(json: result.safariRulesJSON, disabledSites: sitesToUse)
        let output = try saveContentBlockerIfChanged(
            jsonRules: finalJSON,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetRulesFilename
        )
        try saveBlockerListFile(contents: effectiveRulesHash, groupIdentifier: groupIdentifier, filename: baseHashFilename)

        return (
            safariRulesCount: result.safariRulesCount + sitesToUse.count,
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
        groupIdentifier: String
    ) throws -> ContentBlockerTargetOutcome {
        let rulesFilename = targetInfo.rulesFilename
        let hasAffinityFilters = !affinitySnapshot.isEmpty
        let currentSignature = hasAffinityFilters
            ? nil
            : ContentBlockerIncrementalCache.computeInputSignature(
                filters: filters,
                groupIdentifier: groupIdentifier,
                extraRulesText: extraRulesText
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

        if hasAffinityFilters {
            ContentBlockerIncrementalCache.invalidateInputSignature(
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier
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
            groupIdentifier: groupIdentifier
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
        groupIdentifier: String
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
            contentsByFilterID[filter.id] = try String(contentsOf: sourceURL, encoding: .utf8)
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
            groupIdentifier: groupIdentifier
        )
    }

    private static func convertFiltersMemoryEfficient(
        filters: [FilterList],
        orderedSelectedFilters: [FilterList],
        affinitySnapshot: SafariContentBlockerAffinitySnapshot,
        targetInfo: ContentBlockerTargetInfo,
        allTargets: [ContentBlockerTargetInfo],
        disabledSites: [String],
        extraRulesText: String?,
        groupIdentifier: String
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

        for filter in orderedSelectedFilters {
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
                    newlineData: newlineData
                )
            } else if let sourceURL = SafariContentBlockerAffinityProcessor.sourceURL(
                for: filter,
                containerURL: containerURL
            ) {
                try ContentBlockerInputWriter.appendFile(
                    from: sourceURL,
                    to: fileHandle,
                    hasher: &hasher,
                    newlineData: newlineData,
                    policy: .strict
                )
            }
        }

        if let extraRulesText, !extraRulesText.isEmpty {
            try ContentBlockerInputWriter.appendInline(
                extraRulesText,
                to: fileHandle,
                hasher: &hasher,
                newlineData: newlineData
            )
        }

        let digest = hasher.finalize()
        let rulesSHA256Hex = digest.map { String(format: "%02x", $0) }.joined()

        return try ContentBlockerService.convertFilterFromFileWithOutputChange(
            rulesFileURL: tempURL,
            rulesSHA256Hex: rulesSHA256Hex,
            groupIdentifier: groupIdentifier,
            targetRulesFilename: targetInfo.rulesFilename,
            disabledSites: disabledSites
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
           isValidContentBlockerJSON(baseJSON),
           let baseCount = (try? String(contentsOf: baseCountURL, encoding: .utf8))
                .flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
            let finalJSON = injectIgnoreRulesForDisabledSites(json: baseJSON, disabledSites: sitesToUse)
            let output = try saveContentBlockerIfChanged(
                jsonRules: finalJSON,
                groupIdentifier: groupIdentifier,
                targetRulesFilename: targetRulesFilename
            )

            let advancedURL = containerURL.appendingPathComponent(
                ContentBlockerIncrementalCache.baseAdvancedRulesFilename(for: targetRulesFilename)
            )
            let advancedRulesText = try String(contentsOf: advancedURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let finalRuleCount = baseCount + sitesToUse.count

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
    
    private static func isValidContentBlockerJSON(_ json: String) -> Bool {
        guard let jsonData = json.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]) != nil
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
        let fingerprint = combinedEngineFingerprint(rulesData: rulesData, safariVersion: safariVersion)

        try measure(label: combinedAdvancedRules.isEmpty ? "Clearing filter engine" : "Building combined filter engine") {
            try withCombinedEngineBuildLock(at: baseURL) {
                let skipped = try withEngineCriticalSection(at: baseURL) {
                    try withCombinedEngineRequestLock(at: baseURL) {
                        try ensureCombinedEngineRequestIsCurrent(at: baseURL, requestToken: requestToken)
                        return canSkipCombinedEnginePublish(fingerprint: fingerprint, baseURL: baseURL)
                    }
                }
                if skipped {
                    os_log(.info, "Skipping unchanged combined filter engine publish")
                    return
                }

                let temporaryBuild = try buildTemporaryEngine(
                    rulesData: rulesData,
                    safariVersion: safariVersion,
                    baseURL: baseURL
                )
                defer { try? FileManager.default.removeItem(at: temporaryBuild.directory) }

                let published = try withEngineCriticalSection(at: baseURL) {
                    try withCombinedEngineRequestLock(at: baseURL) {
                        try ensureCombinedEngineRequestIsCurrent(at: baseURL, requestToken: requestToken)
                        if canSkipCombinedEnginePublish(fingerprint: fingerprint, baseURL: baseURL) {
                            return false
                        }

                        try publishEngineFiles(
                            from: temporaryBuild,
                            fingerprint: fingerprint,
                            baseURL: baseURL
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

    /// Clears the filter engine by building it with empty rules.
    ///
    /// - Parameters:
    ///   - groupIdentifier: Group ID to use for the shared container.
    public static func clearFilterEngine(groupIdentifier: String) throws {
        try publishCombinedFilterEngine(combinedAdvancedRules: "", groupIdentifier: groupIdentifier)
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
        safariVersion: SafariVersion
    ) -> CombinedEngineFingerprint {
        let rulesHash = combinedRulesHash(rulesData)
        let safariBuildContext = "\(currentPlatform)-safari-\(safariVersion.doubleValue)"
        let markerFormatVersion = combinedEngineMarkerFormatVersion
        let schemaVersion = Schema.VERSION
        let value = combinedRulesHash(
            Data("\(markerFormatVersion)|\(schemaVersion)|\(safariBuildContext)|\(rulesHash)".utf8)
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

    private static func combinedRulesHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
        baseURL: URL
    ) -> Bool {
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

        return validatePublishedEngineFiles(at: baseURL, artifactDigests: marker.artifactDigests)
    }

    private static func validatePublishedEngineFiles(
        at baseURL: URL,
        artifactDigests: [String: String]
    ) -> Bool {
        guard Set(artifactDigests.keys) == Set(engineStorageFileNames) else { return false }
        return (try? engineArtifactDigests(at: baseURL)) == artifactDigests
    }

    private static func engineArtifactDigests(at baseURL: URL) throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try engineStorageFileNames.map { fileName in
            let data = try Data(contentsOf: baseURL.appendingPathComponent(fileName))
            return (fileName, combinedRulesHash(data))
        })
    }

    private static func validateTemporaryEngine(
        at directory: URL,
        fingerprint: CombinedEngineFingerprint
    ) -> Bool {
        guard let artifactDigests = try? engineArtifactDigests(at: directory),
              artifactDigests[Schema.RULES_FILE_NAME] == fingerprint.rulesHash,
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
        baseURL: URL
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

            let rules = String(decoding: rulesData, as: UTF8.self)
            let storage = try FilterRuleStorage(
                from: rules.components(separatedBy: "\n"),
                for: safariVersion,
                fileURL: storageURL
            )
            let engine = try FilterEngine(storage: storage)
            try engine.write(to: indexURL)
            try rulesData.write(to: rulesURL, options: .atomic)

            let meta = EngineMeta(
                timestamp: Date().timeIntervalSince1970,
                schemaVersion: Int32(Schema.VERSION)
            )
            try meta.toData().write(to: metaURL, options: .atomic)

            let fingerprint = combinedEngineFingerprint(rulesData: rulesData, safariVersion: safariVersion)
            guard validateTemporaryEngine(at: temporaryDirectory, fingerprint: fingerprint),
                  let artifactDigests = try? engineArtifactDigests(at: temporaryDirectory)
            else {
                throw WebExtension.WebExtensionError.buildEngineFailed(
                    underlyingError: CocoaError(.fileReadCorruptFile)
                )
            }
            return TemporaryEngineBuild(directory: temporaryDirectory, artifactDigests: artifactDigests)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private static func publishEngineFiles(
        from temporaryBuild: TemporaryEngineBuild,
        fingerprint: CombinedEngineFingerprint,
        baseURL: URL
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

        guard validatePublishedEngineFiles(at: baseURL, artifactDigests: temporaryBuild.artifactDigests) else {
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
    /// Converts AdGuard rules into the Safari content blocking rules syntax.
    ///
    /// - Parameters:
    ///   - rules: AdGuard rules to convert.
    /// - Returns: A ConversionResult containing the converted Safari rules in JSON format
    ///           and advanced rules in text format, or nil when converter resources are unavailable.
    private static func convertRules(rules: String) throws -> ConversionResult {
        guard publicSuffixListResourcesAreAvailable() else {
            throw CocoaError(.fileReadNoSuchFile)
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
        let lines = filterRules.split(whereSeparator: \.isNewline).map(String.init)

        return measure(label: "Conversion") {
            ContentBlockerConverter().convertArray(
                rules: lines,
                safariVersion: .autodetect(),
                advancedBlocking: true,
                maxJsonSizeBytes: nil,
                progress: nil
            )
        }
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

    /// Creates a ZIP archive containing Safari content blocker rules and advanced rules.
    ///
    /// The archive will always include "content-blocker.json" and optionally "advanced-rules.txt"
    /// if advanced rules are provided.
    ///
    /// - Parameters:
    ///   - safariRulesJSON: JSON string containing Safari content blocker rules.
    ///   - advancedRulesText: Optional text string containing advanced blocking rules.
    /// - Returns: Data object representing the ZIP archive, or nil if archive creation fails.
    private static func createZipArchive(
        safariRulesJSON: String,
        advancedRulesText: String?
    ) -> Data? {
        // 1. Prepare data from strings
        guard let contentBlockerData = safariRulesJSON.data(using: .utf8) else {
            return nil
        }
        let advancedData = advancedRulesText?.data(using: .utf8)

        do {
            // 3. Create the Archive object with ZipFoundation
            let archive = try Archive(accessMode: .create)

            // 4. Add content-blocker.json entry
            try archive.addEntry(
                with: "content-blocker.json",
                type: .file,
                uncompressedSize: Int64(contentBlockerData.count),
                bufferSize: 65536
            ) { position, size -> Data in
                // Called repeatedly with chunks of at most `bufferSize` bytes
                // until the whole entry has been provided.
                return contentBlockerData.subdata(
                    in: Data.Index(position)..<Int(position) + size
                )
            }

            // 5. Add advanced-rules.txt if present
            if let advancedData = advancedData {
                try archive.addEntry(
                    with: "advanced-rules.txt",
                    type: .file,
                    uncompressedSize: Int64(advancedData.count),
                    bufferSize: 65536
                ) { position, size -> Data in
                    // Called repeatedly with chunks of at most `bufferSize` bytes
                    // until the whole entry has been provided.
                    return advancedData.subdata(in: Data.Index(position)..<Int(position) + size)
                }
            }

            // 6. Zip creation complete
            return archive.data
        } catch {
            os_log(
                .error,
                "Error while creating a ZIP archive with rules: %@",
                error.localizedDescription
            )

            return nil
        }
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
        chunkSize: Int = 64 * 1024
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return false }
        do {
            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            defer { try? sourceHandle.close() }
            while true {
                let chunk = try sourceHandle.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
                try destinationHandle.write(contentsOf: chunk)
            }
            hasher.update(data: newlineData)
            try destinationHandle.write(contentsOf: newlineData)
            return true
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
        newlineData: Data
    ) throws {
        let rulesData = Data(rulesText.utf8)
        hasher.update(data: rulesData)
        try destinationHandle.write(contentsOf: rulesData)
        hasher.update(data: newlineData)
        try destinationHandle.write(contentsOf: newlineData)
    }
}
