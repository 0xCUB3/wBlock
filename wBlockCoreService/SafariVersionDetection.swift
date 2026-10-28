import Foundation

/// The Safari version the content-blocker output must target. An older Safari
/// rejects a whole rule list over one field it does not know, so this errs low:
/// it follows the OS release that first shipped each WebKit feature level.
enum SafariVersionDetection {
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
