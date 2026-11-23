import Foundation
import SafariServices
import wBlockCoreService
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum SafariExtensionSetupSupport {
    struct ContentBlockerSlotState: Identifiable, Sendable {
        let id: Int
        let name: String
        let bundleIdentifier: String
        /// `nil` when Safari returned an error instead of a confirmed state.
        let rawIsEnabled: Bool?
        let isEnabled: Bool

        init(
            id: Int,
            name: String,
            bundleIdentifier: String,
            rawIsEnabled: Bool? = nil,
            isEnabled: Bool? = nil
        ) {
            self.id = id
            self.name = name
            self.bundleIdentifier = bundleIdentifier
            self.rawIsEnabled = rawIsEnabled
            self.isEnabled = isEnabled ?? (rawIsEnabled ?? false)
        }
    }

    #if os(macOS)
    static let scriptsExtensionIdentifier = "skula.wBlock.wBlock-Scripts"
    static let currentPlatform: Platform = .macOS
    #elseif os(iOS)
    static let scriptsExtensionIdentifier = "skula.wBlock.wBlock-Scripts--iOS-"
    static let currentPlatform: Platform = .iOS
    #endif

    // Safari lazily creates a shared XPC connection. Concurrent first queries
    // from onboarding can race its initialization and abort in xpc_connection_resume.
    @MainActor
    static func contentBlockerSlotStates(forPlatform platform: Platform = currentPlatform) async -> [ContentBlockerSlotState] {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: platform)
        var results: [ContentBlockerSlotState] = []
        for target in targets {
            let rawIsEnabled: Bool? = await withCheckedContinuation { continuation in
                SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: target.bundleIdentifier) { state, error in
                    guard error == nil, let state = state else {
                        continuation.resume(returning: nil)
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
                    rawIsEnabled: rawIsEnabled
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
        ) { error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
                    NSWorkspace.shared.openApplication(at: safariURL, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
        #elseif os(iOS)
        if #available(iOS 26.2, *) {
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

    @MainActor
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
        guard #available(iOS 26.2, *) else { return nil }
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
