import Foundation

@main
struct DarkReaderAppearancePreferenceTests {
    static func main() {
        let suite = "test.wblock.dark-reader-appearance.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("missing test defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        expect(
            DarkReaderAppearancePreference.storageSuiteName == "group.skula.wBlock",
            "the preference must use the shared app-group suite"
        )
        expect(
            DarkReaderAppearancePreference.matches(
                scriptURL: URL(string: DarkReaderAppearancePreference.scriptURL)
            ),
            "the canonical Dark Reader URL must receive runtime configuration"
        )
        expect(
            !DarkReaderAppearancePreference.matches(
                scriptURL: URL(string: "https://bundled.wblock.invalid/dark-reader.user.js")
            ),
            "legacy aliases must be migrated before runtime configuration"
        )

        expect(
            DarkReaderAppearancePreference.followsSystemAppearance(groupIdentifier: suite),
            "the preference must default to following system appearance"
        )

        expect(
            DarkReaderAppearancePreference.darkThemeDetectionMarkerName == "detectBuiltInDarkTheme",
            "the detection marker must match the adapter's detector function name"
        )

        DarkReaderAppearancePreference.setFollowsSystemAppearance(false, groupIdentifier: suite)
        expect(
            !DarkReaderAppearancePreference.followsSystemAppearance(groupIdentifier: suite),
            "the forced-dark preference was not persisted"
        )

        let forced = DarkReaderAppearancePreference.configuredExecutableContent(
            "window.__darkReaderProbe = true;",
            followsSystemAppearance: DarkReaderAppearancePreference.followsSystemAppearance(
                groupIdentifier: suite
            )
        )
        expect(
            forced.hasPrefix("const __wblockDarkReaderFollowsSystemAppearance = false;\n"),
            "forced-dark runtime configuration missing"
        )
        expect(forced.hasSuffix("window.__darkReaderProbe = true;"), "script content was not preserved")
        expect(!forced.contains("__wblockDarkReaderPreviousGlobal"), "page-global preservation wrapper must be absent")

        DarkReaderAppearancePreference.setFollowsSystemAppearance(true, groupIdentifier: suite)
        expect(
            DarkReaderAppearancePreference.followsSystemAppearance(groupIdentifier: suite),
            "the follow-system preference was not restored"
        )
        expect(!DarkReaderAppearancePreference.pureBlack(groupIdentifier: suite), "pure black must be opt-in")
        for follows in [false, true] {
            for pureBlack in [false, true] {
                DarkReaderAppearancePreference.setPureBlack(pureBlack, groupIdentifier: suite)
                expect(DarkReaderAppearancePreference.pureBlack(groupIdentifier: suite) == pureBlack,
                       "pure-black preference did not round-trip")
                let configured = DarkReaderAppearancePreference.configuredExecutableContent(
                    "window.__darkReaderProbe = true;", followsSystemAppearance: follows,
                    pureBlack: DarkReaderAppearancePreference.pureBlack(groupIdentifier: suite)
                )
                expect(configured.contains("const __wblockDarkReaderPureBlack = \(pureBlack);\n"),
                       "pure-black runtime configuration missing")
                expect(configured.hasPrefix("const __wblockDarkReaderFollowsSystemAppearance = \(follows);\n"),
                       "appearance mode changed with pure black")
                expect(configured.hasSuffix("window.__darkReaderProbe = true;"), "script content changed")
            }
        }
        print("PASS: Dark Reader appearance and pure-black preferences")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
