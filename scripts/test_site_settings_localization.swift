import Foundation

@main
struct SiteSettingsLocalizationTests {
    static func main() {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let localizationRootURL = rootURL.appendingPathComponent("wBlock", isDirectory: true)
        let removedKeys = [
            "Whitelisted Domains",
            "Add Domain",
            "Delete Selected",
            "No Whitelisted Domains",
            "Manage Whitelist",
            "Manage Element Zapper Rules",
            "Add domains to disable ad blocking on specific sites",
            "Remove from Whitelist",
            "No Element Zapper Rules",
            "Refresh rules",
            "Zap elements on any website using the wBlock extension in Safari, then manage them here.",
            "Add Site",
            "wBlock is completely turned off on this site.",
            "No enabled userscripts match this site.",
            "Element Zapper Rules",
            "Search or add a site…"
        ]
        let expectedKeys = [
            "example.com",
            "Site Settings",
            "Added sites are whitelisted: wBlock is completely turned off on them.",
            "Whitelisted",
            "%d script off",
            "%d scripts off",
            "No Site Settings",
            "Whitelist a site here, or adjust userscripts and element zapper rules per site from the wBlock popup in Safari.",
            "Reset Site Settings",
            "This removes all settings for %@.",
            "Whitelist",  // log category; shared with the hub's terminology
            "Run on this site",
            "Apply rules on this site",
            "Changes take full effect after the next apply.",
            // Reused keys the Site Settings views depend on.
            "Disable on this site",
            "Content filtering",
            "Filtering off",
            "Userscripts",
            "Rule deleted",
            "Undo",
            "%d rule",
            "%d rules",
            "Cancel",
            "Remove"
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

                // NSDictionary silently keeps the last duplicate; scan raw lines
                // so accidental re-additions of an existing key get caught.
                guard let rawText = try? String(contentsOf: stringsURL, encoding: .utf8) else {
                    fail("failed to read raw text of \(stringsURL.path)")
                }
                for key in expectedKeys {
                    let prefix = "\"\(key)\" ="
                    let occurrences = rawText
                        .split(whereSeparator: \.isNewline)
                        .count { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
                    guard occurrences == 1 else {
                        fail("expected exactly one \"\(key)\" line in \(locale), found \(occurrences)")
                    }
                }

                for key in ["%d script off", "%d scripts off"] {
                    if let value = table[key], !value.contains("%d") {
                        fail("value for \"\(key)\" in \(locale) lost its %d placeholder")
                    }
                }
                if let value = table["This removes all settings for %@"], !value.contains("%@") {
                    fail("reset confirmation in \(locale) lost its %@ placeholder")
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
