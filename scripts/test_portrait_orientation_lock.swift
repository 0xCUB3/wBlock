#!/usr/bin/env swift
import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let settings = try read("wBlock/SettingsView.swift")
let appDelegate = try read("wBlock/AppDelegate.swift")
let lock = try read("wBlock/PortraitOrientationLock.swift")

check(lock.contains("static let storageKey = \"lockPortraitOrientation\""), "must persist under lockPortraitOrientation")
check(lock.contains("UIInterfaceOrientationMask"), "must expose an orientation mask")
check(lock.contains(".portrait"), "locked mask must be portrait")
check(lock.contains(".allButUpsideDown"), "iPhone unlocked mask must match Info.plist")
check(lock.contains("userInterfaceIdiom == .pad ? .all"), "iPad unlocked mask must allow all orientations")
check(lock.contains("requestGeometryUpdate"), "must request a geometry update when the lock changes")
check(lock.contains("setNeedsUpdateOfSupportedInterfaceOrientations"), "must refresh supported orientations")
check(lock.contains("attemptRotationToDeviceOrientation"), "must still rotate on iOS 15")

check(appDelegate.contains("supportedInterfaceOrientationsFor"), "AppDelegate must publish the lock mask")
check(appDelegate.contains("PortraitOrientationLock.mask"), "AppDelegate must use the shared lock mask")
check(appDelegate.contains("PortraitOrientationLock.apply()"), "launch must apply a stored portrait lock")

let displayStart = settings.range(of: "private var displaySection")
check(displayStart != nil, "iOS settings must have a display section")
if let displayStart {
    let before = String(settings[..<displayStart.lowerBound])
    check(before.contains("#if os(iOS)"), "display section must be iOS-only")
}
check(settings.contains("@AppStorage(PortraitOrientationLock.storageKey)"), "Settings must bind the portrait lock")
check(settings.contains("Toggle(\"Lock Portrait Orientation\""), "Settings must expose the portrait lock toggle")
check(settings.contains("Keeps the app in portrait even if the device is rotated."), "Settings must explain the portrait lock")
check(settings.contains("PortraitOrientationLock.apply()"), "toggling must apply the lock immediately")
check(settings.contains("displaySection"), "iOS settings list must include the display section")

let locales = ["ar", "de", "el", "en", "es", "fr", "hu", "it", "ja", "ko", "pl", "pt-BR", "ro", "ru", "tr", "zh-Hans", "zh-Hant"]
let keys = [
    "Lock Portrait Orientation",
    "Keeps the app in portrait even if the device is rotated."
]
var english: [String: String] = [:]
for locale in locales {
    let url = URL(fileURLWithPath: "wBlock/\(locale).lproj/Localizable.strings")
    guard let table = NSDictionary(contentsOf: url) as? [String: String] else {
        fputs("FAIL: could not parse \(locale)\n", stderr)
        exit(1)
    }
    for key in keys {
        guard let value = table[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fputs("FAIL: missing \(key) in \(locale)\n", stderr)
            exit(1)
        }
        if locale == "en" {
            english[key] = value
        } else if value == key || value == english[key] {
            fputs("FAIL: copied English for \(key) in \(locale)\n", stderr)
            exit(1)
        }
    }
}

print("PASS")
