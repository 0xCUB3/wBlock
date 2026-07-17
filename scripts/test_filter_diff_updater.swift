//
// scripts/test_filter_diff_updater.swift
//
// Regression + behavior coverage for `FilterDiffUpdater` (uBlock-Origin-style
// differential filter-list updates).
//
// Run via:
//   swiftc -parse-as-library \
//     wBlockCoreService/FilterDiffUpdater.swift \
//     scripts/test_filter_diff_updater.swift \
//     -o /tmp/difftest && /tmp/difftest
//
// Prints `PASS` on success, `FAIL: <message>` (exit 1) on the first divergence.
//

import Foundation

@main
struct FilterDiffUpdaterTests {
    static func main() {
        testExpiresParsing()
        testMetadataParsing()
        testTemplatePathIsNotDeltaUpdatable()
        testMissingDiffNameIsNotDeltaUpdatable()
        testMetadataDiffNameFallback()
        testPatchURLResolution()
        testPatchAvailabilityTime()
        testRealRcsDiffAppliesAndValidates()
        testChecksumMismatch()
        testMalformedPatchFails()

        print("PASS")
    }

    // MARK: - Expires

    static func testExpiresParsing() {
        expectEqual(FilterDiffExpiresParser.parseSeconds("317 minutes"), 317 * 60, "317 minutes → seconds")
        expectEqual(FilterDiffExpiresParser.parseSeconds("5 days"), 5 * 86_400, "5 days → seconds")
        expectEqual(FilterDiffExpiresParser.parseSeconds("12 hours"), 12 * 3_600, "12 hours → seconds")
        expectEqual(FilterDiffExpiresParser.parseSeconds("1 week"), 7 * 86_400, "1 week → seconds")
        expectEqual(FilterDiffExpiresParser.parseSeconds("7"), 7 * 86_400, "bare number → days")
        expectEqual(FilterDiffExpiresParser.parseSeconds("garbage"), 0, "garbage → 0")
        expectEqual(FilterDiffExpiresParser.parseSeconds(""), 0, "empty → 0")
        expectEqual(FilterDiffExpiresParser.parseSeconds("0 days"), 0, "zero is not a valid expiry")
    }

    // MARK: - Metadata

    static func testMetadataParsing() {
        let list = """
        ! Title: EasyList
        ! Diff-Path: https://cdn.example/patches/2025.11.10.1.patch#easylist
        ! Diff-Expires: 317 minutes
        ||example.com^
        """
        let meta = unwrap(FilterDiffUpdater.parseMetadata(from: list), "expected diff metadata")
        expectEqual(meta.diffPath, "https://cdn.example/patches/2025.11.10.1.patch", "diffPath strips #fragment")
        expectEqual(meta.diffName, "easylist", "diffName from #fragment")
        expectEqual(meta.diffExpiresSeconds, 317 * 60, "diffExpires seconds")
    }

    static func testTemplatePathIsNotDeltaUpdatable() {
        let list = """
        ! Diff-Path: %diffpath%#easylist
        """
        expect(
            FilterDiffUpdater.parseMetadata(from: list) == nil,
            "`%`-prefixed Diff-Path must not be delta-updatable"
        )
    }

    static func testMissingDiffNameIsNotDeltaUpdatable() {
        let list = """
        ! Diff-Path: https://cdn.example/patches/2025.11.10.1.patch
        """
        expect(
            FilterDiffUpdater.parseMetadata(from: list) == nil,
            "Diff-Path without a #fragment or Diff-Name must not be delta-updatable"
        )
    }

    static func testMetadataDiffNameFallback() {
        let list = """
        ! Diff-Path: https://cdn.example/patches/2025.11.10.1.patch
        ! Diff-Name: fallback-name
        """
        let meta = unwrap(FilterDiffUpdater.parseMetadata(from: list), "Diff-Name fallback should parse")
        expectEqual(meta.diffName, "fallback-name", "diffName falls back to ! Diff-Name:")
    }

    // MARK: - URL resolution

    static func testPatchURLResolution() {
        let listURL = URL(string: "https://subscribe.example.com/lists/easylist.txt")!
        let absolute = FilterDiffMetadata(
            diffPath: "https://cdn.example/patches/2025.11.10.1.patch",
            diffName: "easylist",
            diffExpiresSeconds: 0,
            raw: .init(diffPath: nil, diffName: nil, diffExpires: nil)
        )
        expectEqual(
            FilterDiffUpdater.resolvePatchURL(metadata: absolute, listURL: listURL)?.absoluteString,
            "https://cdn.example/patches/2025.11.10.1.patch",
            "absolute Diff-Path resolves verbatim"
        )

        let relative = FilterDiffMetadata(
            diffPath: "../patches/2025.11.10.1.patch",
            diffName: "easylist",
            diffExpiresSeconds: 0,
            raw: .init(diffPath: nil, diffName: nil, diffExpires: nil)
        )
        expectEqual(
            FilterDiffUpdater.resolvePatchURL(metadata: relative, listURL: listURL)?.absoluteString,
            "https://subscribe.example.com/patches/2025.11.10.1.patch",
            "relative Diff-Path resolves against list URL"
        )
    }

    // MARK: - Patch availability timing

    static func testPatchAvailabilityTime() {
        let expires = TimeInterval(317 * 60)
        let meta = FilterDiffMetadata(
            diffPath: "https://cdn.example/patches/2025.11.10.1.patch",
            diffName: "easylist",
            diffExpiresSeconds: expires,
            raw: .init(diffPath: nil, diffName: nil, diffExpires: nil)
        )

        var components = DateComponents()
        components.year = 2025
        components.month = 11
        components.day = 10
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        let midnight = Calendar(identifier: .gregorian).date(from: components)!
        let expected = midnight.addingTimeInterval(60 + expires) // slot 1 = 1 minute + expires

        let actual = unwrap(
            FilterDiffUpdater.patchAvailabilityTime(metadata: meta),
            "date-versioned Diff-Path should yield an availability time"
        )
        expectEqual(actual, expected, "patch availability = midnight UTC + slot minutes + expires")

        let noVersion = FilterDiffMetadata(
            diffPath: "https://cdn.example/patches/latest.patch",
            diffName: "easylist",
            diffExpiresSeconds: expires,
            raw: .init(diffPath: nil, diffName: nil, diffExpires: nil)
        )
        expect(
            FilterDiffUpdater.patchAvailabilityTime(metadata: noVersion) == nil,
            "Diff-Path without a date version should not yield an availability time"
        )
    }

    // MARK: - Real RCS diff (from `diff -n`)

    /// Fixture mirrors an actual `diff -n old.txt new.txt` patch where
    /// `old.txt = "a\nb\nc\n"` and `new.txt = "a\nB\nc\nd\ne\n"`.
    /// SHA-1("a\nB\nc\nd\ne\n") = d875d7babac21cccbeabd7409e5a596aecd6533a.
    static func testRealRcsDiffAppliesAndValidates() {
        let baseline = "a\nb\nc\n"
        let expectedPatched = "a\nB\nc\nd\ne\n"
        let expectedChecksum = "d875d7baba" // first 10 hex chars of the SHA-1

        let patch = """
        diff name:easylist lines:6 checksum:\(expectedChecksum)
        d2 1
        a2 1
        B
        a3 2
        d
        e
        """

        let blocks = unwrap(FilterDiffUpdater.parsePatchFile(patch), "patch file should parse")
        let block = unwrap(blocks["easylist"], "patch should contain the easylist block")

        switch FilterDiffUpdater.applyBlock(block, to: baseline) {
        case .success(let patched):
            expectEqual(patched, expectedPatched, "patched text must equal the expected new list")
        case .badPatch:
            fail("applyBlock reported badPatch for a valid RCS diff")
        case .checksumMismatch(let expected, let computed):
            fail("applyBlock reported checksum mismatch: expected \(expected), computed \(computed)")
        }
    }

    static func testChecksumMismatch() {
        let baseline = "a\nb\nc\n"
        let patch = """
        diff name:easylist lines:6 checksum:deadbeef
        d2 1
        a2 1
        B
        a3 2
        d
        e
        """
        let blocks = unwrap(FilterDiffUpdater.parsePatchFile(patch), "patch should parse")
        let block = unwrap(blocks["easylist"], "block present")
        switch FilterDiffUpdater.applyBlock(block, to: baseline) {
        case .checksumMismatch:
            break // expected
        default:
            fail("expected checksum mismatch for a wrong checksum")
        }
    }

    static func testMalformedPatchFails() {
        let baseline = "a\nb\nc\n"
        let patch = """
        diff name:easylist lines:1 checksum:0000000000
        x2 1
        """
        let blocks = unwrap(FilterDiffUpdater.parsePatchFile(patch), "patch should parse at block level")
        let block = unwrap(blocks["easylist"], "block present")
        switch FilterDiffUpdater.applyBlock(block, to: baseline) {
        case .badPatch:
            break // expected
        default:
            fail("expected badPatch for an unparseable RCS command")
        }
    }
}

// MARK: - Test helpers

private func expect(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("FAIL: \(message)\n  actual:   \(actual)\n  expected: \(expected)\n", stderr)
        exit(1)
    }
}

private func unwrap<T>(_ value: T?, _ message: String) -> T {
    guard let value else {
        fail(message)
    }
    return value
}

private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}
