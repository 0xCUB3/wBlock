//
//  MacLoginItemManager.swift
//  wBlock
//
//  Provides a unified API to enable/disable start-at-login using SMAppService
//  when available. Falls back to LaunchAgent as a best-effort if Login Item
//  helper is not embedded. MAS builds should include a Login Item target with
//  bundle identifier set in `loginItemIdentifier`.

import Foundation

#if os(macOS)
import ServiceManagement
import os.log

enum MacLoginItemManager {
    // Update to match the embedded Login Item target bundle identifier if present
    private static let loginItemIdentifier = "com.alexanderskula.wblock.LoginItem"
    private static let log = Logger(subsystem: "com.skula.wBlock", category: "LoginItem")

    static func isAvailable() -> Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            let item = try SMAppService.loginItem(identifier: loginItemIdentifier)
            return item.status == .enabled
        } catch {
            log.error("LoginItem not found: \(error.localizedDescription)")
            // Fallback: check LaunchAgent plist exists
            return launchAgentPlistURL().map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        }
    }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            let item = try SMAppService.loginItem(identifier: loginItemIdentifier)
            if enabled {
                try item.register()
                log.info("Login Item registered")
                reportStatus()
                // If SM is enabled, purge any stale container-scoped LaunchAgent fallback
                purgeContainerLaunchAgentIfPresent()
            } else {
                try item.unregister()
                log.info("Login Item unregistered")
                reportStatus()
                purgeContainerLaunchAgentIfPresent()
            }
        } catch {
            log.error("Failed to change Login Item state: \(error.localizedDescription)")
            // Fallback to LaunchAgent only if we can write to the real user LaunchAgents folder (non-sandbox)
            if enabled {
                if let url = launchAgentPlistURL(), !url.path.contains("/Containers/") {
                    registerLaunchAgent()
                } else {
                    log.error("Skipping LaunchAgent fallback: sandboxed home resolves to container path; use SMAppService (macOS 13+) instead")
                }
            } else {
                if let url = launchAgentPlistURL(), !url.path.contains("/Containers/") {
                    removeLaunchAgent()
                } else {
                    // Remove container-scoped plist if any
                    purgeContainerLaunchAgentIfPresent()
                }
            }
        }
    }

    // MARK: - Diagnostics
    @available(macOS 13.0, *)
    static func reportStatus() {
        do {
            let item = try SMAppService.loginItem(identifier: loginItemIdentifier)
            log.info("SMAppService status: \(String(describing: item.status.rawValue)) (enabled=\(item.status == .enabled ? "true":"false"))")
        } catch {
            log.error("SMAppService status error: \(error.localizedDescription)")
        }
        if let url = embeddedLoginItemURL() {
            log.info("Embedded Login Item located at: \(url.path)")
        } else {
            log.error("Embedded Login Item not found under Contents/Library/LoginItems; embedding may be misconfigured")
        }
        if let plist = launchAgentPlistURL(), FileManager.default.fileExists(atPath: plist.path) {
            log.info("LaunchAgent fallback installed at: \(plist.path)")
        }
    }

    /// Try to find the embedded login item bundle matching the identifier.
    static func embeddedLoginItemURL() -> URL? {
        guard let appURL = Bundle.main.bundleURL as URL?,
              let loginItemsDir = Optional(appURL.appendingPathComponent("Contents/Library/LoginItems")),
              FileManager.default.fileExists(atPath: loginItemsDir.path) else { return nil }
        // Enumerate .app bundles and check their CFBundleIdentifier
        guard let items = try? FileManager.default.contentsOfDirectory(at: loginItemsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for item in items where item.pathExtension == "app" {
            let infoPlist = item.appendingPathComponent("Contents/Info.plist")
            if let dict = NSDictionary(contentsOf: infoPlist) as? [String: Any],
               let id = dict["CFBundleIdentifier"] as? String,
               id == loginItemIdentifier {
                return item
            }
        }
        return nil
    }

    // MARK: - LaunchAgent fallback
    private static func launchAgentIdentifier() -> String {
        (Bundle.main.bundleIdentifier ?? "com.alexanderskula.wblock") + ".filter-updater"
    }

    private static func launchAgentPlistURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let launchAgentsDir = home.appendingPathComponent("Library/LaunchAgents")
        return launchAgentsDir.appendingPathComponent("\(launchAgentIdentifier()).plist")
    }

    private static func registerLaunchAgent() {
        guard let bundlePath = Bundle.main.bundlePath as String?,
              let plistPath = launchAgentPlistURL(), !plistPath.path.contains("/Containers/") else { return }
        do {
            try FileManager.default.createDirectory(at: plistPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            let launchAgent: [String: Any] = [
                "Label": launchAgentIdentifier(),
                "ProgramArguments": ["/usr/bin/open", "-j", "-g", "-a", bundlePath, "--args", "--background-filter-update"],
                "StartInterval": 6 * 60 * 60,
                "RunAtLoad": false,
                "KeepAlive": false,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: launchAgent, format: .xml, options: 0)
            try data.write(to: plistPath)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            proc.arguments = ["load", "-w", plistPath.path]
            try? proc.run(); proc.waitUntilExit()
            log.info("LaunchAgent fallback registered")
        } catch {
            log.error("LaunchAgent fallback failed: \(error.localizedDescription)")
        }
    }

    private static func removeLaunchAgent() {
        guard let plistPath = launchAgentPlistURL(), !plistPath.path.contains("/Containers/") else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["unload", plistPath.path]
        try? proc.run(); proc.waitUntilExit()
        try? FileManager.default.removeItem(at: plistPath)
        log.info("LaunchAgent fallback removed")
    }

    /// Remove container-scoped LaunchAgent plist if it exists (not used by launchctl).
    private static func purgeContainerLaunchAgentIfPresent() {
        // In sandbox, the "home" resolves to a container; remove any stale plist there to avoid confusion
        if let containerPlist = launchAgentPlistURL(), containerPlist.path.contains("/Containers/") {
            if FileManager.default.fileExists(atPath: containerPlist.path) {
                try? FileManager.default.removeItem(at: containerPlist)
                log.info("Removed stale container-scoped LaunchAgent: \(containerPlist.path)")
            }
        }
    }
}
#endif
