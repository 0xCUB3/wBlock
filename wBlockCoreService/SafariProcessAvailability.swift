//
//  SafariProcessAvailability.swift
//  wBlockCoreService
//

import Foundation
#if os(macOS)
import AppKit
#endif

/// macOS-only process checks for Safari and Safari Technology Preview.
public enum SafariProcessAvailability {
    /// True when Safari or Safari Technology Preview has a running, non-terminated instance.
    public static var isSafariOrTechnologyPreviewRunning: Bool {
        #if os(macOS)
        let bundleIdentifiers = [
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview"
        ]
        return bundleIdentifiers.contains { bundleIdentifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .contains { !$0.isTerminated }
        }
        #else
        return false
        #endif
    }
}
