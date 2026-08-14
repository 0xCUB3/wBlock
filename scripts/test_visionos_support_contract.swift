#!/usr/bin/env swift

import Foundation

let project = try String(contentsOfFile: "wBlock.xcodeproj/project.pbxproj", encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func occurrenceCount(of needle: String) -> Int {
    project.components(separatedBy: needle).count - 1
}

let xrEnabled = "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = YES;"
let xrDisabled = "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;"
let visionEmbeddedExtension = "platformFilters = (ios, xros, );"

require(occurrenceCount(of: xrEnabled) == 20, "the app and every iOS extension configuration must allow iPad-compatible visionOS distribution")
require(!project.contains(xrDisabled), "no iOS extension configuration may opt out of visionOS compatibility")
require(occurrenceCount(of: visionEmbeddedExtension) == 6, "all six iOS Safari extensions must be embedded on visionOS")

print("PASS: visionOS compatibility settings")
