#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let locales = ["ar", "de", "el", "en", "es", "fr", "hu", "it", "ja", "ko", "pl", "pt-BR", "ro", "ru", "tr", "zh-Hans", "zh-Hant"]
let nonEnglishLocales = locales.filter { $0 != "en" }

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func table(for locale: String) -> [String: String] {
    let url = root.appendingPathComponent("wBlock/\(locale).lproj/Localizable.strings")
    guard let value = NSDictionary(contentsOf: url) as? [String: String] else {
        fail("could not parse \(url.path)")
    }
    return value
}

func run(_ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            fail("command failed: \(arguments.joined(separator: " "))")
        }
        return String(data: data, encoding: .utf8) ?? ""
    } catch {
        fail("could not run \(arguments.joined(separator: " ")): \(error)")
    }
}

func unescapeSourceLiteral(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\t", with: "\t")
        .replacingOccurrences(of: "\\\"", with: "\"")
        .replacingOccurrences(of: "\\\\", with: "\\")
}

func sourceKeyOccurrences(for locale: String) -> [String: [Int]] {
    let path = root.appendingPathComponent("wBlock/\(locale).lproj/Localizable.strings")
    guard let contents = try? String(contentsOf: path, encoding: .utf8) else {
        fail("could not read \(path.path)")
    }
    let pattern = #"(?m)^[[:space:]]*\"((?:\\.|[^\"\\])*)\"[[:space:]]*="#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        fail("invalid localization table pattern")
    }

    var occurrences: [String: [Int]] = [:]
    let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
    for match in regex.matches(in: contents, range: range) {
        guard let keyRange = Range(match.range(at: 1), in: contents),
              let declarationRange = Range(match.range, in: contents)
        else { continue }
        let key = unescapeSourceLiteral(String(contents[keyRange]))
        let line = contents[..<declarationRange.lowerBound].reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        occurrences[key, default: []].append(line)
    }
    return occurrences
}

func localizedKeys(in sources: [(path: String, contents: String)]) -> Set<String> {
    let pattern = #"(?:String\s*\(\s*localized:\s*|LocalizedStrings\s*\.\s*(?:text|format)\s*\(\s*|NSLocalizedString\s*\(\s*)\"((?:\\.|[^\"\\])*)\""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        fail("invalid localization source pattern")
    }

    var keys = Set<String>()
    for (path, source) in sources {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
            keys.insert(unescapeSourceLiteral(String(source[keyRange])))
        }
        _ = path
    }
    return keys
}

func branchAddedSourceLocalizedKeys() -> Set<String> {
    let diffLines = run(["git", "diff", "origin/main", "--unified=0", "--", "wBlock"])
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
    let added = diffLines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }
        .map { String($0.dropFirst()) }
        .joined(separator: "\n")
    let removed = diffLines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }
        .map { String($0.dropFirst()) }
        .joined(separator: "\n")
    let addedKeys = localizedKeys(in: [(path: "git-added", contents: added)])
    let removedKeys = localizedKeys(in: [(path: "git-removed", contents: removed)])
    return addedKeys.subtracting(removedKeys)
}

func placeholderTokens(_ value: String) -> [String] {
    let pattern = #"%(?:\d+\$)?[@dif]"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.matches(in: value, range: range).compactMap { match in
        Range(match.range, in: value).map { String(value[$0]) }
    }
}

for locale in locales {
    let duplicates = sourceKeyOccurrences(for: locale).filter { $0.value.count > 1 }
    guard duplicates.isEmpty else {
        let details = duplicates.map { "\($0.key.debugDescription) at lines \($0.value)" }
            .joined(separator: "; ")
        fail("duplicate localization keys in \(locale): \(details)")
    }
}

let english = table(for: "en")
var tables: [String: [String: String]] = ["en": english]
for locale in nonEnglishLocales {
    let values = table(for: locale)
    tables[locale] = values
    guard Set(values.keys) == Set(english.keys) else {
        fail("key parity mismatch in \(locale)")
    }
}

// Every literal passed to the app's localization helpers must have a table entry.
let branchSourceKeys = branchAddedSourceLocalizedKeys()
for key in branchSourceKeys {
    guard english[key] != nil else {
        fail("source localization key is missing from en: \(key.debugDescription)")
    }
    for locale in locales {
        guard let value = tables[locale]?[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("source localization key is missing or empty in \(locale): \(key.debugDescription)")
        }
        guard placeholderTokens(value).sorted() == placeholderTokens(english[key]!).sorted() else {
            fail("placeholder mismatch for \(key.debugDescription) in \(locale)")
        }
    }
}

// Audit keys added to the English table on this branch. Catalog/list names are
// intentionally kept in their canonical form; all other copied English is a UI
// or message localization defect. German and Romanian use the same idiomatic
// word "Text" for the Text import mode.
let baseline = tableFromGit(ref: "origin/main", path: "wBlock/en.lproj/Localizable.strings")
let branchAddedKeys = Set(english.keys).subtracting(baseline.keys)
let intentionalCanonicalNames: Set<String> = [
    "AdGuard Allowlist", "Adblock Warning Removal List",
    "HaGeZi Pro Mini", "Mail Tracking Protection Filter", "Online Malicious URL Blocklist",
    "Stevo's AI Blocklist"
]
let idiomaticSameValue: [String: Set<String>] = ["Text": ["de", "ro"]]
for key in branchAddedKeys.subtracting(intentionalCanonicalNames) {
    for locale in nonEnglishLocales {
        let value = tables[locale]![key]!
        if value == key && !idiomaticSameValue[key, default: []].contains(locale) {
            fail("copied English for branch-added UI/message \(key.debugDescription) in \(locale)")
        }
    }
}

func tableFromGit(ref: String, path: String) -> [String: String] {
    let text = run(["git", "show", "\(ref):\(path)"])
    // Use a temporary file so Foundation applies the same .strings parsing rules
    // as the working-tree tables, including escaped/newline keys.
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    do {
        try text.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        guard let value = NSDictionary(contentsOf: tempURL) as? [String: String] else {
            fail("could not parse git table \(ref):\(path)")
        }
        return value
    } catch {
        fail("could not materialize git table \(ref):\(path): \(error)")
    }
}

print("PASS (\(branchSourceKeys.count) branch-added source keys; \(branchAddedKeys.count) branch-added English keys audited)")
