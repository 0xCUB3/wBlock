#!/usr/bin/env swift
import Foundation

let source = try String(contentsOfFile: "wBlockCoreService/UserScript.swift", encoding: .utf8)
let start = source.range(of: "public enum UserScriptURLSupport {")!.lowerBound
let end = source.range(of: "public enum UserScriptImportLimits", range: start..<source.endIndex)!.lowerBound
let support = String(source[start..<end])
let testProgram = #"""
import Foundation

__SUPPORT__

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    expect(actual == expected, "\(message)\nactual: \(actual)\nexpected: \(expected)")
}
func expectValid(_ rawURL: String, expectedPath: String, _ message: String) {
    guard let url = UserScriptURLSupport.validatedRemoteURL(from: rawURL) else {
        fputs("FAIL: \(message)\n", stderr); exit(1)
    }
    expectEqual(url.path, expectedPath, message)
}

expectValid("https://example.com/script.js", expectedPath: "/script.js", "plain .js URL")
expectValid("https://example.com/script.user.js", expectedPath: "/script.user.js", ".user.js URL")
expect(UserScriptURLSupport.validatedRemoteURL(from: "https://example.com/script.txt") == nil, "reject non-script extension")
expect(UserScriptURLSupport.validatedRemoteURL(from: "ftp://example.com/script.js") == nil, "reject non-http(s) URL")
expectValid("https://example.com/raw?file=script.user.js", expectedPath: "/raw", "filename in query")
expectValid("https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=userscript/bpc.en.user.js", expectedPath: "/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw", "gitflic URL")
expect(UserScriptURLSupport.validatedRemoteURL(from: "https://example.com/raw?file=script.txt") == nil, "reject unsupported query filename")
expectEqual(UserScriptURLSupport.displayName(forRemoteURL: URL(string: "https://example.com/foo.js")!), "foo", "strip .js")
expectEqual(UserScriptURLSupport.displayName(forRemoteURL: URL(string: "https://example.com/foo.user.js")!), "foo", "strip .user.js")
expectEqual(UserScriptURLSupport.normalizePastedURL("\nhttps://example.com/script.user.js\n\n"), "https://example.com/script.user.js", "strip blank lines")
expectEqual(UserScriptURLSupport.normalizePastedURL("https://greasyfork.org/scripts/123-very-long-name/\nscript.user.js"), "https://greasyfork.org/scripts/123-very-long-name/script.user.js", "rejoin wrapped URL")
let bulk = "https://example.com/one.user.js\nhttps://example.com/two.user.js"
expectEqual(UserScriptURLSupport.normalizePastedURL(bulk), bulk, "preserve complete bulk URLs")
expectEqual(UserScriptURLSupport.parseRemoteURLs(from: bulk).map(\.lastPathComponent), ["one.user.js", "two.user.js"], "parse bulk URLs")
expectEqual(UserScriptURLSupport.parseRemoteURLs(from: "https://example.com/wrapped/\nscript.user.js").map(\.lastPathComponent), ["script.user.js"], "parse wrapped single URL")
expect(UserScriptURLSupport.parseRemoteURLs(from: "https://example.com/one.user.js\nnot a URL").isEmpty, "reject mixed valid and invalid lines")
print("PASS")
"""#.replacingOccurrences(of: "__SUPPORT__", with: support)

let temporaryURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("wblock-userscript-url-\(UUID().uuidString).swift")
try testProgram.write(to: temporaryURL, atomically: true, encoding: .utf8)
defer { try? FileManager.default.removeItem(at: temporaryURL) }

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["swift", temporaryURL.path]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
