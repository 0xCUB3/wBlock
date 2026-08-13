#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlock/AppDelegate.swift", encoding: .utf8)
let expected = "await filterManager.performFilterUpdate(showProgress: true)"
guard source.contains(expected) else {
    fputs("FAIL: Apply Changes and Quit must enter the normal progress apply path\n", stderr)
    exit(1)
}
do {
    guard !source.contains("await filterManager.applyChanges()") else {
        fputs("FAIL: Apply Changes and Quit bypasses progress with direct applyChanges()\n", stderr)
        exit(1)
    }
}
print("PASS")
