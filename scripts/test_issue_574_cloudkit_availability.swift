import Foundation

@main
struct Issue574CloudKitAvailabilityContract {
    static func main() throws {
        func source(_ path: String) throws -> String {
            try String(contentsOfFile: path, encoding: .utf8)
        }
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
        }
        func body(_ signature: String, in source: String, before nextSignature: String) -> String {
            guard let start = source.range(of: signature),
                  let end = source.range(of: nextSignature, range: start.upperBound..<source.endIndex) else {
                return ""
            }
            return String(source[start.lowerBound..<end.lowerBound])
        }

        let cloud = try source("wBlock/CloudSyncManager.swift")
        let settings = try source("wBlock/SettingsView.swift")
        let entitlements = try source("wBlock/wBlock-DirectDistribution.entitlements")

        expect(cloud.contains("@Published private(set) var isCloudKitAvailable: Bool"), "CloudSyncManager must expose CloudKit availability")
        expect(cloud.contains("isCloudKitAvailable = Self.hasCloudKitEntitlement"), "availability must come from the entitlement check")
        expect(cloud.contains("guard isCloudKitAvailable else {\n            logger.info(\"CloudKit unavailable (no iCloud entitlement)\")"), "database creation must be guarded by availability")
        expect(body("func setEnabled", in: cloud, before: "func syncNow").contains("guard isCloudKitAvailable else { return }"), "enabling sync must be ignored when CloudKit is unavailable")
        expect(body("func syncNow", in: cloud, before: "struct RemoteConfigProbe").contains("guard isCloudKitAvailable else { return }"), "manual and launch sync must be guarded by availability")
        expect(body("func probeRemoteConfig", in: cloud, before: "func downloadAndApplyLatestRemoteConfig").contains("guard isCloudKitAvailable else"), "CloudKit probes must be guarded by availability")
        expect(body("func downloadAndApplyLatestRemoteConfig", in: cloud, before: "// MARK: - Local change tracking").contains("guard isCloudKitAvailable else { return false }"), "remote downloads must be guarded by availability")
        expect(body("private func uploadLatestPayload", in: cloud, before: "// MARK: - Two-way sync").contains("guard isCloudKitAvailable else { return }"), "uploads must be guarded by availability")
        expect(body("private func performTwoWaySync", in: cloud, before: "private func decodePayload").contains("guard isCloudKitAvailable else { return }"), "two-way sync must be guarded by availability")
        expect(body("private func fetchRecord", in: cloud, before: "private func saveRecord").contains("guard isCloudKitAvailable, let database"), "CloudKit fetches must require availability")
        expect(body("private func saveRecord", in: cloud, before: "private func saveRecordWithConflictResolution").contains("guard isCloudKitAvailable, let database"), "CloudKit saves must require availability")
        expect(!cloud.contains("iCloud is not available in this build"), "unavailable direct builds must not create a fake sync error")
        expect(cloud.contains("if !isCloudKitAvailable {\n            lastErrorMessage = nil\n            setStatus(.off)"), "unavailable builds must clear stale errors without using SyncStatus.error")

        let binding = body("private var syncEnabledBinding", in: settings, before: "private var pauseBlockingBinding")
        let section = body("private var syncSection", in: settings, before: "private var pauseBlockingSection")
        let probe = body("private func probeAndEnableSync", in: settings, before: "}\nextension SettingsView")
        expect(binding.contains("guard syncManager.isCloudKitAvailable else { return }"), "the toggle binding must not probe or change preferences when unavailable")
        expect(section.contains(".disabled(!syncManager.isCloudKitAvailable)"), "the unavailable iCloud Sync toggle must be disabled")
        expect(section.contains("if syncManager.isCloudKitAvailable && syncManager.isEnabled"), "Sync Now must be hidden when unavailable")
        expect(section.contains("This GitHub/Homebrew build cannot use iCloud Sync. The App Store/TestFlight build can."), "the unavailable-build footer must explain where sync works")
        expect(probe.contains("guard syncManager.isCloudKitAvailable else { return }"), "probeAndEnableSync must not probe when unavailable")
        expect(!entitlements.contains("com.apple.developer.icloud-services"), "DirectDistribution entitlements must continue to omit CloudKit")

        let localizationKey = "\"This GitHub/Homebrew build cannot use iCloud Sync. The App Store/TestFlight build can.\" ="
        let localizationRoot = URL(fileURLWithPath: "wBlock")
        let localizations = try FileManager.default.contentsOfDirectory(at: localizationRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
        expect(localizations.count == 17, "all 17 localization directories must be checked")
        for localization in localizations {
            let strings = try String(contentsOf: localization.appendingPathComponent("Localizable.strings"), encoding: .utf8)
            expect(strings.contains(localizationKey), "missing unavailable-build footer in \(localization.lastPathComponent)")
        }

        print("PASS: issue #574 CloudKit availability contract")
    }
}
