#!/usr/bin/env swift

import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let loader = try String(contentsOfFile: "wBlock/FilterListLoader.swift", encoding: .utf8)
expect(loader.contains("258_optimized.txt"), "missing LAN block filter URL")
expect(
    loader.contains("name: \"Block Outsider Intrusion into LAN\""),
    "missing Block Outsider Intrusion into LAN catalog entry"
)

let nameKey = "\"Block Outsider Intrusion into LAN\" = \"Block Outsider Intrusion into LAN\";"
let descKey =
    "\"Blocks public websites from reaching local network addresses and router admin pages. Can break some local apps.\""

let root = URL(fileURLWithPath: "wBlock")
let locales = try FileManager.default.contentsOfDirectory(atPath: root.path)
    .filter { $0.hasSuffix(".lproj") }
    .sorted()
var failures: [String] = []
for locale in locales {
    let path = root.appendingPathComponent(locale).appendingPathComponent("Localizable.strings")
    let source = try String(contentsOf: path, encoding: .utf8)
    if !source.contains(nameKey) || !source.contains(descKey) {
        failures.append(locale)
    }
}
expect(failures.isEmpty && locales.count == 17, "LAN block localization missing in \(failures.joined(separator: ", "))")

print("PASS")
