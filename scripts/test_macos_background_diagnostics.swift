#!/usr/bin/env swift

import Foundation

let settings = try String(contentsOfFile: "wBlock/SettingsView.swift", encoding: .utf8)
let manager = try String(contentsOfFile: "wBlock/AutoUpdateLaunchAgentManager.swift", encoding: .utf8)

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

check(settings.contains("private var macOSAutoUpdateDiagnosticsView"), "macOS diagnostics surface must exist")
check(settings.contains("Text(\"Background Diagnostics\")"), "macOS diagnostics must be explicitly labeled")
check(settings.contains("macOSAutoUpdateDiagnosticsView"), "Auto-Update must contain the diagnostics surface")
let autoUpdateSection = settings.components(separatedBy: "private var autoUpdateSection: some View").last?
    .components(separatedBy: "private var macOSAutoUpdateDiagnosticsView: some View").first ?? ""
let header = autoUpdateSection.range(of: "} header: {")
let footer = autoUpdateSection.range(of: "} footer: {")
let updateNow = autoUpdateSection.range(of: "Label(\"Update Now\"", options: .backwards)
let diagnostics = autoUpdateSection.range(of: "macOSAutoUpdateDiagnosticsView")
check(updateNow!.lowerBound > header!.lowerBound && updateNow!.lowerBound < footer!.lowerBound, "macOS Update Now must live in the section header instead of a form row")
check(diagnostics!.lowerBound > footer!.lowerBound, "macOS diagnostics must sit beneath the schedule footer")
check(settings.contains(".font(.caption)"), "macOS diagnostics must use compact caption styling")
check(settings.contains("Text(launchAgentStatusLine)"), "Diagnostics must show the existing launch-agent status")
check(settings.contains("AutoUpdateLaunchAgentManager.shared.openLoginItemsSettings()"), "Diagnostics must reuse the existing Login Items action")
check(manager.contains("func currentStatus()") && manager.contains("func openLoginItemsSettings()"), "Diagnostics must use existing manager APIs")
check(!settings.contains("com.apple.security"), "Diagnostics must not add entitlement behavior")

print("PASS: macOS Background Diagnostics structure")
