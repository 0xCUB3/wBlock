import Foundation
import SafariServices
#if os(iOS)
import UIKit
#endif

#if os(macOS)
private func makeSafariExtensionSettingsHandler() -> @Sendable (Error?) -> Void {
    { _ in }
}

private func makeScriptsExtensionStateHandler(
    _ continuation: CheckedContinuation<Bool?, Never>
) -> @Sendable (SFSafariExtensionState?, Error?) -> Void {
    { state, error in
        guard error == nil else {
            continuation.resume(returning: nil)
            return
        }
        continuation.resume(returning: state?.isEnabled)
    }
}
#elseif os(iOS)
@available(iOS 26.2, *)
private func makeSafariExtensionSettingsHandler() -> @Sendable (Error?) -> Void {
    { _ in }
}

@available(iOS 26.2, *)
private func makeScriptsExtensionStateHandler(
    _ continuation: CheckedContinuation<Bool?, Never>
) -> @Sendable (SFSafariExtensionState?, Error?) -> Void {
    { state, error in
        guard error == nil else {
            continuation.resume(returning: nil)
            return
        }
        continuation.resume(returning: state?.isEnabled)
    }
}
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
            withIdentifier: scriptsExtensionIdentifier,
            completionHandler: makeSafariExtensionSettingsHandler()
        )
        #elseif os(iOS)
        if #available(iOS 26.2, *) {
            SFSafariSettings.openExtensionsSettings(
                forIdentifiers: [scriptsExtensionIdentifier],
                completionHandler: makeSafariExtensionSettingsHandler()
            )
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
                withIdentifier: scriptsExtensionIdentifier,
                completionHandler: makeScriptsExtensionStateHandler(continuation)
            )
        }
        #elseif os(iOS)
        guard #available(iOS 26.2, *) else { return nil }
        return await withCheckedContinuation { continuation in
            SFSafariExtensionManager.getStateOfExtension(
                withIdentifier: scriptsExtensionIdentifier,
                completionHandler: makeScriptsExtensionStateHandler(continuation)
            )
        }
        #endif
    }
}
