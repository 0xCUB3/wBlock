import Foundation
import SafariServices
#if os(iOS)
import UIKit
#endif

enum SafariExtensionSetupSupport {
    #if os(macOS)
    static let scriptsExtensionIdentifier = "skula.wBlock.wBlock-Scripts"
    #elseif os(iOS)
    static let scriptsExtensionIdentifier = "skula.wBlock.wBlock-Scripts--iOS-"
    #endif

    @MainActor
    static func openScriptsExtensionSettings() {
        #if os(macOS)
        SFSafariApplication.showPreferencesForExtension(
            withIdentifier: scriptsExtensionIdentifier
        ) { _ in }
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
