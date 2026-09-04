import Foundation

/// Coordinates the macOS headless launch of the containing app (#528).
///
/// When the background agent is off, the Safari extension can still download
/// changed filter lists, but only the app can rebuild them and reload Safari.
/// Rather than ask the user to open the app, the extension launches it with a
/// marker argument. The app then runs as an accessory process (no Dock icon,
/// no window), performs the rebuild, and terminates itself.
public enum HeadlessLaunch {
    public enum Reason: String, Sendable {
        case popupUpdate = "popup-update"
        case stagedDownloads = "staged-downloads"
    }

    public static let argument = "--wblock-headless-update"
    public static let containingAppBundleIdentifier = "skula.wBlock"

    public static func arguments(for reason: Reason) -> [String] {
        [argument, reason.rawValue]
    }

    /// The reason encoded in the current process's launch arguments, if any.
    public static func reason(in arguments: [String] = ProcessInfo.processInfo.arguments) -> Reason? {
        guard let index = arguments.firstIndex(of: argument) else { return nil }
        let next = arguments.indices.contains(index + 1) ? arguments[index + 1] : ""
        return Reason(rawValue: next) ?? .popupUpdate
    }

    public static var isHeadlessProcess: Bool {
        reason() != nil
    }

    #if os(macOS)
    /// The containing app for an extension bundle at
    /// wBlock.app/Contents/PlugIns/<name>.appex.
    public static func containingAppURL(from bundleURL: URL = Bundle.main.bundleURL) -> URL? {
        var url = bundleURL
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// True when the extension has staged downloads and no resident process
    /// will pick them up: the app is closed and the background agent is off.
    public static func shouldAutoRebuildAfterStaging() async -> Bool {
        guard await ProtobufDataManager.shared.backgroundAgentDisabled else { return false }
        return !isContainingAppRunning()
    }

    public static func isContainingAppRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: containingAppBundleIdentifier)
            .contains { !$0.isTerminated }
    }
    #endif
}

#if os(macOS)
import AppKit
#endif
