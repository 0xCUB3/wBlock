import Foundation

@main
struct ApplyProgressLocalizationTests {
    static func main() {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let localizationRootURL = rootURL.appendingPathComponent("wBlock", isDirectory: true)
        let expectedKey = "Applying filters...\n(This may take a while)"
        let escapedKey = #"Applying filters...\n(This may take a while)"#

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
                let stringsURL = localeDirectory.appendingPathComponent("Localizable.strings")
                guard let table = NSDictionary(contentsOf: stringsURL) as? [String: String] else {
                    fail("failed to parse \(stringsURL.path)")
                }

                guard let value = table[expectedKey] else {
                    fail("missing localized apply progress key in \(localeDirectory.lastPathComponent)")
                }

                guard table[escapedKey] == nil else {
                    fail("found literal escaped apply progress key in \(localeDirectory.lastPathComponent)")
                }

                guard !value.contains(#"\n"#) else {
                    fail("apply progress value contains a literal \\n in \(localeDirectory.lastPathComponent)")
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
