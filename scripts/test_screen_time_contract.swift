import Foundation

func check(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func read(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

let manager = read("wBlock/ScreenTimeManager.swift")
let settings = read("wBlock/ScreenTimeSettingsView.swift")
let action = read("wBlock Shield Action/ShieldActionExtension.swift")
let monitorInfo = read("wBlock Device Activity Monitor/Info.plist")
let project = read("wBlock.xcodeproj/project.pbxproj")
let appEntitlements = read("wBlock/wBlock-ios.entitlements")

check(manager.contains("group.skula.wBlock") && manager.contains("FamilyActivitySelection"), "selection must use the App Group")
check(manager.contains("webDomainTokens") && manager.contains("categoryTokens") && manager.contains("clearShields"), "policy must cover domains, categories, and clearing")
check(manager.contains("requestAuthorization(for: .individual)") && manager.contains("requestAuthorization {"), "authorization APIs must include async and completion fallbacks")
check(manager.contains(".specific(categories, except: exceptions.webDomains)"), "domain exceptions must also bypass selected categories")
check(settings.contains("familyActivityPicker") && settings.contains("Before authorization"), "settings must explain and present the picker")
check(settings.contains("Open Settings") && settings.contains("authorizationStatus == .denied"), "denied authorization must direct users to Settings")
check(action.contains("15 * 60") && action.contains("completion(.none)"), "shield action must grant a controlled 15-minute exception")
check(action.contains("map(\\.expires)") && action.contains(".min()"), "multiple exceptions must restore at the earliest expiry")
check(monitorInfo.contains("com.apple.deviceactivity.monitor-extension"), "monitor extension point must match Apple's template")
check(appEntitlements.contains("com.apple.developer.family-controls"), "the iOS app must declare Family Controls")
for name in ["wBlock Shield Configuration", "wBlock Shield Action", "wBlock Device Activity Monitor"] {
    check(project.contains(name), "project must contain \(name)")
}
for locale in ["ar", "de", "el", "en", "es", "fr", "hu", "it", "ja", "ko", "pl", "pt-BR", "ro", "ru", "tr", "zh-Hans", "zh-Hant"] {
    let strings = read("wBlock/\(locale).lproj/Localizable.strings")
    check(strings.contains("\"Authorize Screen Time\" ="), "\(locale) must localize Screen Time authorization")
    let shieldStrings = read("wBlock Shield Configuration/\(locale).lproj/Localizable.strings")
    check(shieldStrings.contains("\"Allow for 15 Minutes\" ="), "\(locale) must localize the shield action")
}
print("PASS")
