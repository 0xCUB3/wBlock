import Foundation

@main
struct LanguageSelectionLocalizationTests {
    static func main() {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let localizationRootURL = rootURL.appendingPathComponent("wBlock", isDirectory: true)
        let removedKeys = [
            "Choose the languages you browse in. wBlock will recommend matching filters next.",
            "Select the languages you browse websites in. wBlock only uses this to recommend regional ad filters.",
            "Choose filters for websites in other languages. You can fine-tune them later.",
            "No recommended regional filters."
        ]
        let expectedKeys = [
            "Select the languages (one or more) you browse websites in. wBlock only uses this to recommend regional ad filters.",
            "These filters add extra blocking power for your languages on top of the default lists, which already cover English and international sites. You can fine-tune them later.",
            "This doesn't change the app's display language, which always follows your device settings.",
            "No regional filters needed. The default filter lists already cover English and international sites.",
            "No regional filters available. However, the default filter lists already cover English and international sites.",
            "Other",
            "Adblock List for Albania and Kosovo",
            "Global Filters",
            "Raajje AdList",
            "RU AdList",
            "Community filter list that blocks ads on Albanian and Kosovar websites.",
            "EasyList supplement by eyeo for websites in Thai, Greek, Slovenian, Croatian, Serbian, Bosnian, and Filipino.",
            "Community filter list that blocks ads on Dhivehi (Maldivian) websites.",
            "Russian-language filter list that also covers Ukrainian, Kazakh, and Uzbek websites."
        ]

        do {
            let localeDirectories = try FileManager.default.contentsOfDirectory(
                at: localizationRootURL,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "lproj" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !localeDirectories.isEmpty else {
                fail("expected localization directories to exist")
            }

            for localeDirectory in localeDirectories {
                let locale = localeDirectory.lastPathComponent
                let stringsURL = localeDirectory.appendingPathComponent("Localizable.strings")
                guard let table = NSDictionary(contentsOf: stringsURL) as? [String: String] else {
                    fail("failed to parse \(stringsURL.path)")
                }

                for key in removedKeys where table[key] != nil {
                    fail("found removed key \"\(key)\" in \(locale)")
                }

                for key in expectedKeys {
                    guard let value = table[key] else {
                        fail("missing \"\(key)\" in \(locale)")
                    }
                    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        fail("empty value for \"\(key)\" in \(locale)")
                    }
                }
            }
        } catch {
            fail("localization test failed: \(error)")
        }

        print("PASS")
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
