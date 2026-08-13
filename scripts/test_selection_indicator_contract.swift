#!/usr/bin/env swift

import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let indicator = try read("wBlock/SelectionIndicator.swift")
let onboarding = try read("wBlock/OnboardingView.swift")
let apply = try read("wBlock/ApplyChangesProgressView.swift")

require(indicator.contains("struct SelectionIndicator: View"), "missing shared selection indicator")
require(indicator.contains("Circle()\n                .fill"), "selected state must use a shape fill")
require(indicator.contains(".strokeBorder("), "unselected state must use a shape stroke")
require(indicator.contains("Image(systemName: \"checkmark\")"), "selected state must contain an explicit checkmark")
require(indicator.contains(".accessibilityHidden(true)"), "decorative indicator must not duplicate its button label")
require(onboarding.components(separatedBy: "SelectionIndicator(isSelected: isSelected)").count - 1 == 3, "all onboarding selection cards must use the shared indicator")
require(apply.contains("SelectionIndicator(isSelected: isSelected, size: 18)"), "apply selection row must use the shared indicator")
for source in [onboarding, apply] {
    require(!source.contains("isSelected ? \"checkmark.circle.fill\" : \"circle\""), "outlined SF Symbol selection pair must be removed")
}
require(onboarding.components(separatedBy: ".accessibilityAddTraits(isSelected ? .isSelected : [])").count - 1 >= 3, "onboarding cards must expose selected state")

print("PASS: shape-rendered selection indicators")
