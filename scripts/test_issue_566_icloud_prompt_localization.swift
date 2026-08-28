#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let localizationRoot = root.appendingPathComponent("wBlock", isDirectory: true)

let expectedTranslations: [String: String] = [
    "ar": "استخدام إعداد iCloud الحالي؟",
    "de": "Vorhandene iCloud-Einrichtung verwenden?",
    "el": "Χρήση υπάρχουσας ρύθμισης iCloud;",
    "en": "Use existing iCloud setup?",
    "es": "¿Usar configuración existente de iCloud?",
    "fr": "Utiliser la configuration iCloud existante ?",
    "hu": "Meglévő iCloud-beállítás használata?",
    "it": "Usare la configurazione iCloud esistente?",
    "ja": "既存のiCloud設定を使用しますか？",
    "ko": "기존 iCloud 설정을 사용할까요?",
    "pl": "Użyć istniejącej konfiguracji iCloud?",
    "pt-BR": "Usar configuração existente do iCloud?",
    "ro": "Folosești configurarea iCloud existentă?",
    "ru": "Использовать существующую настройку iCloud?",
    "tr": "Mevcut iCloud kurulumu kullanılsın mı?",
    "zh-Hans": "使用现有的 iCloud 设置？",
    "zh-Hant": "使用現有的 iCloud 設定？"
]

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

let key = "Use existing iCloud setup?"

// 1. Verify usage in SwiftUI views
let viewsToCheck = [
    "wBlock/OnboardingView.swift",
    "wBlock/SettingsView.swift"
]

for viewRelPath in viewsToCheck {
    let viewURL = root.appendingPathComponent(viewRelPath)
    guard let content = try? String(contentsOf: viewURL, encoding: .utf8) else {
        fail("could not read \(viewRelPath)")
    }
    guard content.contains("\"\(key)\"") else {
        fail("expected \(viewRelPath) to contain confirmationDialog with title \(key)")
    }
}

// 2. Verify each locale's strings table
for (locale, expectedTranslation) in expectedTranslations {
    let stringsURL = localizationRoot.appendingPathComponent("\(locale).lproj/Localizable.strings")
    guard let dict = NSDictionary(contentsOf: stringsURL) as? [String: String] else {
        fail("could not parse \(stringsURL.path)")
    }
    guard let actual = dict[key] else {
        fail("missing key \(key) in \(locale)")
    }
    guard actual == expectedTranslation else {
        fail("unexpected translation for \(locale): got \(actual.debugDescription), expected \(expectedTranslation.debugDescription)")
    }
    if locale != "en" && actual == key {
        fail("untranslated English key copied in \(locale)")
    }
}

guard expectedTranslations.count == 17 else {
    fail("expected 17 supported locales, got \(expectedTranslations.count)")
}

print("PASS (Issue 566 iCloud prompt title localized across all 17 languages)")
