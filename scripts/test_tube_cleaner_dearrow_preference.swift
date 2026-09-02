import Foundation

@main
struct TubeCleanerDeArrowPreferenceTests {
    static func main() {
        let suite = "test.wblock.tube-cleaner-dearrow.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("missing test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }

        expect(
            TubeCleanerDeArrowPreference.matches(scriptURL: URL(string: TubeCleanerDeArrowPreference.scriptURL)),
            "the canonical Tube Cleaner URL must receive runtime configuration"
        )
        expect(
            !TubeCleanerDeArrowPreference.matches(scriptURL: URL(string: DarkReaderAppearancePreference.scriptURL)),
            "Dark Reader must not receive Tube Cleaner configuration"
        )

        let defaultsValue = TubeCleanerDeArrowPreference.settings(groupIdentifier: suite)
        expect(!defaultsValue.enabled, "DeArrow must default to off")
        expect(defaultsValue.replaceTitles && defaultsValue.replaceThumbnails && defaultsValue.showOriginalOnHover
            && !defaultsValue.randomThumbnails, "defaults must match the script's previous localStorage defaults")

        var settings = defaultsValue
        settings.enabled = true
        settings.randomThumbnails = true
        TubeCleanerDeArrowPreference.setSettings(settings, groupIdentifier: suite)
        expect(
            TubeCleanerDeArrowPreference.settings(groupIdentifier: suite) == settings,
            "settings must round-trip through the app group"
        )

        let configured = TubeCleanerDeArrowPreference.configuredExecutableContent(
            "window.__probe = true;", settings: settings
        )
        expect(
            configured.hasPrefix("const __wblockTubeCleanerDeArrow = {\"enabled\":true,\"randomThumbnails\":true,\"replaceThumbnails\":true,\"replaceTitles\":true,\"showOriginalOnHover\":true};\n"),
            "the prepended constant must carry sorted JSON the script can read: \(configured.prefix(160))"
        )
        expect(configured.hasSuffix("window.__probe = true;"), "script content was not preserved")
        print("PASS: Tube Cleaner DeArrow preference")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
