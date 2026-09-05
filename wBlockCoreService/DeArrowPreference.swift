import Foundation

/// Reuses the existing preference storage so separating DeArrow preserves its options.
public enum DeArrowPreference {
    public typealias Settings = TubeCleanerDeArrowPreference.Settings
    public static let scriptURL = "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/dearrow/dist/dearrow.user.js"
    public static let settingsConstantName = "__wblockDeArrowSettings"

    public static func matches(scriptURL: URL?) -> Bool {
        scriptURL?.absoluteString == self.scriptURL
    }

    public static func configuredExecutableContent(_ content: String, settings: Settings) -> String {
        // Script enablement owns the on/off state; the legacy bit is only for migration.
        var configured = settings
        configured.enabled = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(configured)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "const \(settingsConstantName) = \(json);\n\(content)"
    }
}
