#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: "wBlock")
let locales = try FileManager.default.contentsOfDirectory(atPath: root.path)
    .filter { $0.hasSuffix(".lproj") }
    .sorted()
var failures: [String] = []
for locale in locales {
    let path = root.appendingPathComponent(locale).appendingPathComponent("Localizable.strings")
    let source = try String(contentsOf: path, encoding: .utf8)
    if !source.contains("\"HaGeZi Pro Mini\" = \"HaGeZi Pro Mini\";") {
        failures.append(locale)
    }
}
guard failures.isEmpty, locales.count == 17 else {
    fputs("FAIL: HaGeZi capitalization missing in \(failures.joined(separator: ", "))\n", stderr)
    exit(1)
}
print("PASS")
