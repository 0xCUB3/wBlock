import Foundation

@main
struct LanguageSelectionLocalizationTests {
    static func main() {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let localizationRootURL = rootURL.appendingPathComponent("wBlock", isDirectory: true)
        let removedKey = "Choose the languages you browse in. wBlock will recommend matching filters next."
        let expectedKeys = [
            "Select the languages you browse websites in. wBlock only uses this to recommend regional ad filters.",
            "This doesn't change the app's display language, which always follows your device settings.",
            "No regional filters needed. The default filter lists already cover English and international sites.",
            "Other"
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

                guard table[removedKey] == nil else {
                    fail("found removed language picker key in \(locale)")
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
