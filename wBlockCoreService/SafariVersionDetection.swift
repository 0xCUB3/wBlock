import Foundation
internal import WBEngine

/// The Safari version the content-blocker output must target. An older Safari
/// rejects a whole rule list over one field it does not know, so this errs low:
/// it follows the OS release that first shipped each WebKit feature level.
enum SafariVersionDetection {
    /// What a compiled output depends on besides its input: the engine's
    /// output version and the Safari level it targeted. Every cache of engine
    /// output is keyed on it, so nothing compiled by an older engine (or by
    /// AdGuard's converter before wBlock 4) or for another Safari is reused.
    static var compilerIdentity: String {
        let safari = current
        return "wbe-\(WBEngine.outputVersion)|safari-\(safari.major).\(safari.minor)"
    }

    static var current: (major: UInt16, minor: UInt16) {
        #if os(macOS)
        if #available(macOS 26, *) { return (26, 0) }
        if #available(macOS 13.3, *) { return (16, 4) }
        if #available(macOS 13, *) { return (16, 0) }
        return (15, 4)
        #else
        if #available(iOS 26, *) { return (26, 0) }
        if #available(iOS 16.4, *) { return (16, 4) }
        if #available(iOS 16, *) { return (16, 0) }
        return (15, 4)
        #endif
    }
}
