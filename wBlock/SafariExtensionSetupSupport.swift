import Foundation
import SafariServices
import wBlockCoreService
#if os(iOS)
import UIKit
#endif

enum SafariExtensionSetupSupport {
    struct ContentBlockerSlotState: Identifiable, Sendable {
        let id: Int
        let name: String
        let bundleIdentifier: String
        let isEnabled: Bool
    }

    #if os(macOS)
    static let scriptsExtensionIdentifier = "skula.wBlock.wBlock-Scripts"
    static let currentPlatform: Platform = .macOS
    #elseif os(iOS)
    static let scriptsExtensionIdentifier = "skula.wBlock.wBlock-Scripts--iOS-"
    static let currentPlatform: Platform = .iOS
    #endif

    static func contentBlockerSlotStates(forPlatform platform: Platform = currentPlatform) async -> [ContentBlockerSlotState] {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: platform)
        var results: [ContentBlockerSlotState] = []
        for target in targets {
            let isEnabled: Bool = await withCheckedContinuation { continuation in
                SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: target.bundleIdentifier) { state, error in
                    guard error == nil, let state = state else {
                        continuation.resume(returning: false)
                        return
                    }
                    continuation.resume(returning: state.isEnabled)
                }
            }
            results.append(
                ContentBlockerSlotState(
                    id: target.slot,
                    name: target.displayName,
                    bundleIdentifier: target.bundleIdentifier,
                    isEnabled: isEnabled
                )
            )
        }
        return results
    }

    static func allContentBlockersEnabled(forPlatform platform: Platform = currentPlatform) async -> Bool {
        let states = await contentBlockerSlotStates(forPlatform: platform)
        guard !states.isEmpty else { return false }
        return states.allSatisfy(\.isEnabled)
    }

    @MainActor
    static func openScriptsExtensionSettings() {
        #if os(macOS)
        SFSafariApplication.showPreferencesForExtension(
            withIdentifier: scriptsExtensionIdentifier
        ) { _ in }
        #elseif os(iOS)
        if #available(iOS 18.2, *) {
            SFSafariSettings.openExtensionsSettings(
                forIdentifiers: [scriptsExtensionIdentifier]
            ) { _ in }
            return
        }

        if let url = URL(string: "App-prefs:SAFARI&path=EXTENSIONS") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "App-prefs:") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    static func scriptsExtensionEnabledState() async -> Bool? {
        #if os(macOS)
        return await withCheckedContinuation { continuation in
            SFSafariExtensionManager.getStateOfSafariExtension(
                withIdentifier: scriptsExtensionIdentifier
            ) { state, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: state?.isEnabled)
            }
        }
        #elseif os(iOS)
        guard #available(iOS 18.2, *) else { return nil }
        return await withCheckedContinuation { continuation in
            SFSafariExtensionManager.getStateOfExtension(
                withIdentifier: scriptsExtensionIdentifier
            ) { state, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: state?.isEnabled)
            }
        }
        #endif
    }
}
