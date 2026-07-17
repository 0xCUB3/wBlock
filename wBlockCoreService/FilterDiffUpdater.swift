//
//  FilterDiffUpdater.swift
//  wBlockCoreService
//
//  Differential/delta filter-list updates, compatible with the patch format
//  introduced by uBlock Origin 1.54 (`! Diff-Path:` / `! Diff-Expires:`
//  filter-list headers + RCS-style `.patch` files).
//
//  This file is intentionally pure Foundation + CryptoKit (no app-group or
//  networking dependencies) so it can be unit-tested in isolation and reused
//  from both the app and the background auto-update services. The networking
//  integration lives in `SharedAutoUpdateManager.attemptDeltaUpdate`.
//
//  Format reference (from the uBlock Origin source):
//    * Header directives are ordinary comment headers (NOT `!#` preprocessor
//      directives), e.g. `! Diff-Path: <path-or-URL>#<diff-name>`
//      and `! Diff-Expires: <value>` (e.g. "317 minutes", "5 days", "12 hours").
//      A `Diff-Path` whose value begins with `%` is an unresolved template and
//      is not delta-updatable.
//    * The patch file is a concatenation of blocks, each introduced by a header
//      line of the form:
//          diff name:<diff-name> lines:<N> checksum:<sha1-hex-prefix>
//      followed by exactly N RCS-format diff lines (`diff -n` output).
//    * The RCS diff commands are `a<line> <count>` (insert `count` lines after
//      `line`, 1-based) and `d<line> <count>` (delete `count` lines starting at
//      `line`, 1-based). An empty line terminates the diff.
//    * After applying the diff, the SHA-1 of the resulting text must start with
//      the block's `checksum` prefix. uBlock publishes the first 10 hex chars.
//

import Foundation
import CryptoKit

/// Metadata required to attempt a differential update for a single filter list.
public struct FilterDiffMetadata: Sendable, Equatable {
    /// Patch path/URL with any `#diff-name` fragment stripped.
    public let diffPath: String
    /// Selected diff block name (from the `#fragment`, falling back to
    /// `! Diff-Name:`). Delta updates are only attempted when non-empty.
    public let diffName: String
    /// Parsed `! Diff-Expires:` value in seconds. `0` means unspecified.
    public let diffExpiresSeconds: TimeInterval

    /// The raw (untrimmed) header values as found in the list, for diagnostics.
    public struct RawValues: Sendable, Equatable {
        public let diffPath: String?
        public let diffName: String?
        public let diffExpires: String?
    }
    public let raw: RawValues

    public init(
        diffPath: String,
        diffName: String,
        diffExpiresSeconds: TimeInterval,
        raw: RawValues
    ) {
        self.diffPath = diffPath
        self.diffName = diffName
        self.diffExpiresSeconds = diffExpiresSeconds
        self.raw = raw
    }
}

/// One parsed block from a `.patch` file.
public struct FilterDiffPatchBlock: Sendable, Equatable {
    public let name: String
    /// SHA-1 hex prefix the patched output must begin with.
    public let checksum: String
    /// The raw RCS diff text (N lines joined by `\n`).
    public let diffText: String

    public init(name: String, checksum: String, diffText: String) {
        self.name = name
        self.checksum = checksum
        self.diffText = diffText
    }
}

/// Pure parser + applier for uBlock-Origin-style differential updates.
public enum FilterDiffUpdater {
    /// Parses `! Diff-Path:`, `! Diff-Name:` and `! Diff-Expires:` from the first
    /// ~1 KB of a filter list's raw text.
    ///
    /// Returns `nil` when the list is not delta-updatable: no `Diff-Path`, an
    /// unresolved template (`%`-prefixed) path, or no usable diff name.
    public static func parseMetadata(from content: String) -> FilterDiffMetadata? {
        let head = String(content.prefix(1024))

        let rawDiffPath = extractField("Diff-Path", from: head)
        let rawDiffName = extractField("Diff-Name", from: head)
        let rawDiffExpires = extractField("Diff-Expires", from: head)

        guard let fullDiffPath = rawDiffPath, !fullDiffPath.isEmpty else {
            return nil
        }
        // uBO treats `%`-prefixed Diff-Path values as unresolved templates.
        if fullDiffPath.hasPrefix("%") { return nil }

        // Split off `#diff-name` fragment.
        var pathPart = fullDiffPath
        var nameFromFragment: String?
        if let hashRange = pathPart.range(of: "#") {
            let fragment = String(pathPart[hashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !fragment.isEmpty {
                nameFromFragment = fragment
            }
            pathPart = String(pathPart[..<hashRange.lowerBound])
        }
        pathPart = pathPart.trimmingCharacters(in: .whitespaces)

        let diffName = nameFromFragment ?? rawDiffName?.trimmingCharacters(in: .whitespaces)
        guard let resolvedName = diffName, !resolvedName.isEmpty else {
            return nil
        }
        guard !pathPart.isEmpty else { return nil }

        let expiresSeconds = rawDiffExpires.map { FilterDiffExpiresParser.parseSeconds($0) } ?? 0

        return FilterDiffMetadata(
            diffPath: pathPart,
            diffName: resolvedName,
            diffExpiresSeconds: expiresSeconds,
            raw: .init(
                diffPath: rawDiffPath,
                diffName: rawDiffName,
                diffExpires: rawDiffExpires
            )
        )
    }

    /// Resolves `diffPath` (relative or absolute) against the filter list URL,
    /// mirroring uBO's `new URL(path, cdnURL)`.
    public static func resolvePatchURL(metadata: FilterDiffMetadata, listURL: URL) -> URL? {
        let trimmed = metadata.diffPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        return URL(string: trimmed, relativeTo: listURL)?.absoluteURL
    }

    /// Extracts the embedded `YYYY.M.D.H` date-version from the patch path, if any,
    /// and applies the `Diff-Expires` window: the result is the earliest wall-clock
    /// time at which the patch is expected to exist on the CDN.
    ///
    /// Returns `nil` when no date version is embedded (no timing gate).
    public static func patchAvailabilityTime(metadata: FilterDiffMetadata, now: Date = Date()) -> Date? {
        guard let match = dateVersionRegex.firstMatch(
            in: metadata.diffPath,
            range: NSRange(location: 0, length: metadata.diffPath.utf16.count)
        ),
            match.numberOfRanges >= 5,
            let y = Range(match.range(at: 1), in: metadata.diffPath).flatMap({ Int(metadata.diffPath[$0]) }),
            let m = Range(match.range(at: 2), in: metadata.diffPath).flatMap({ Int(metadata.diffPath[$0]) }),
            let d = Range(match.range(at: 3), in: metadata.diffPath).flatMap({ Int(metadata.diffPath[$0]) }),
            let slot = Range(match.range(at: 4), in: metadata.diffPath).flatMap({ Int(metadata.diffPath[$0]) })
        else {
            return nil
        }

        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        guard let midnight = Calendar(identifier: .gregorian).date(from: components) else {
            return nil
        }
        // The slot number doubles as "minutes past midnight UTC" in uBO's
        // convention (one slot per minute in practice).
        let slotSeconds = TimeInterval(slot) * 60
        return midnight.addingTimeInterval(slotSeconds + metadata.diffExpiresSeconds)
    }

    /// Parses a `.patch` file into a map of `diff-name` -> block. Returns `nil`
    /// if the file contains no valid block (or any block is structurally invalid).
    public static func parsePatchFile(_ patchText: String) -> [String: FilterDiffPatchBlock]? {
        let diffLines = patchText.components(separatedBy: "\n")
        let lineCount = diffLines.count
        var index = 0
        var result: [String: FilterDiffPatchBlock] = [:]

        while index < lineCount {
            let line = diffLines[index]
            index += 1
            if !line.hasPrefix("diff ") { continue }

            let tokens = line.split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            var name: String?
            var checksum: String?
            var declaredLines = 0
            for token in tokens {
                guard let colonIndex = token.firstIndex(of: ":") else { continue }
                let key = String(token[..<colonIndex])
                if key.isEmpty { continue }
                let value = String(token[token.index(after: colonIndex)...])
                switch key {
                case "name":
                    name = value
                case "checksum":
                    checksum = value
                case "lines":
                    declaredLines = Int(value) ?? 0
                default:
                    break
                }
            }

            guard let resolvedName = name,
                  let resolvedChecksum = checksum,
                  declaredLines > 0
            else {
                return nil
            }

            let available = max(0, min(declaredLines, lineCount - index))
            let blockText: String
            if available > 0 {
                blockText = diffLines[index..<(index + available)].joined(separator: "\n")
            } else {
                blockText = ""
            }
            index += declaredLines

            if result[resolvedName] == nil {
                result[resolvedName] = FilterDiffPatchBlock(
                    name: resolvedName,
                    checksum: resolvedChecksum,
                    diffText: blockText
                )
            }
        }

        return result.isEmpty ? nil : result
    }

    /// Applies the RCS-format `diffText` to `baseline` and returns the patched
    /// text. Returns `nil` on any structural or bounds error. Mirrors uBO's
    /// `applyPatch` (Perl/RCS `diff -n` dialect).
    public static func applyRCSDiff(_ rcsDiff: String, to baseline: String) -> String? {
        // Match uBO: split on `\n` only (preserves a trailing empty element when
        // the baseline ends with a newline, which acts as a sentinel for appends).
        var lines = baseline.components(separatedBy: "\n")
        let diffLines = rcsDiff.components(separatedBy: "\n")
        let diffCount = diffLines.count

        var diffIndex = 0
        var adjust = 0

        while diffIndex < diffCount {
            let diffLine = diffLines[diffIndex]
            diffIndex += 1
            if diffLine.isEmpty { break }

            guard let parsed = parseRCSCommand(diffLine) else { return nil }
            let op = parsed.operation
            let line = parsed.line
            let count = parsed.count
            let adjustedLine = line + adjust

            switch op {
            case .delete:
                // `d<line> <count>`: remove `count` elements starting at
                // 0-based index `line - 1`. uBO clamps implicitly via splice.
                guard adjustedLine >= 1, adjustedLine <= lines.count else { return nil }
                let startIndex = adjustedLine - 1
                let removable = min(count, lines.count - startIndex)
                if removable > 0 {
                    lines.removeSubrange(startIndex..<(startIndex + removable))
                }
                adjust -= count
            case .add:
                // `a<line> <count>`: insert `count` new lines (read from the
                // following diff lines) at 0-based index `line`.
                guard adjustedLine >= 0, adjustedLine <= lines.count else { return nil }
                guard diffIndex + count <= diffCount else { return nil }
                let insertion = Array(diffLines[diffIndex..<(diffIndex + count)])
                lines.insert(contentsOf: insertion, at: adjustedLine)
                diffIndex += count
                adjust += count
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Applies `block` to `baseline` and verifies the SHA-1 checksum prefix.
    public enum ApplyOutcome: Sendable, Equatable {
        case success(patchedText: String)
        case badPatch
        case checksumMismatch(expected: String, computed: String)
    }
    public static func applyBlock(_ block: FilterDiffPatchBlock, to baseline: String) -> ApplyOutcome {
        guard let patched = applyRCSDiff(block.diffText, to: baseline) else {
            return .badPatch
        }
        let digest = Insecure.SHA1.hash(data: Data(patched.utf8))
        let computed = digest.map { String(format: "%02x", $0) }.joined()
        if computed.hasPrefix(block.checksum.lowercased()) {
            return .success(patchedText: patched)
        }
        return .checksumMismatch(
            expected: block.checksum,
            computed: String(computed.prefix(block.checksum.count))
        )
    }

    // MARK: - Private

    private enum RCSOperation { case add, delete }
    private struct RCSCommand {
        let operation: RCSOperation
        let line: Int
        let count: Int
    }

    private static let dateVersionRegex: NSRegularExpression = {
        // YYYY.M.D.H embedded in the patch path/filename.
        let pattern = #"(\d+)\.(\d+)\.(\d+)\.(\d+)"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let expiresRegex: NSRegularExpression = {
        let pattern = #"(?i)(\d+)\s*([wdhm]?)"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let commandRegex: NSRegularExpression = {
        let pattern = #"^([ad])(\d+) (\d+)$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static func parseRCSCommand(_ line: String) -> RCSCommand? {
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = commandRegex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 4,
              let opRange = Range(match.range(at: 1), in: line),
              let lineRange = Range(match.range(at: 2), in: line),
              let countRange = Range(match.range(at: 3), in: line),
              let lineNumber = Int(line[lineRange]),
              let count = Int(line[countRange])
        else {
            return nil
        }
        let operation: RCSOperation
        switch line[opRange] {
        case "a": operation = .add
        case "d": operation = .delete
        default: return nil
        }
        return RCSCommand(operation: operation, line: lineNumber, count: count)
    }

    /// Extracts the first `! Field-Name:` / `# Field-Name:` header value from a
    /// block of text, mirroring uBO's `extractMetadataFromList` regex
    /// `^(?:! *|# +)Field(?: +|-)Name: *(.+)$` (case-insensitive).
    private static func extractField(_ fieldName: String, from content: String) -> String? {
        // Allow `-`, single space, or multiple spaces between the hyphen-separated
        // words of the field name.
        let escapedPattern = fieldName
            .split(separator: "-")
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "(?: +|-)")
        let pattern = "^(?:!\\s*|#\\s+)" + escapedPattern + ":\\s*(.+?)\\s*$"

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .anchorsMatchLines]
        ) else {
            return nil
        }

        let nsContent = content
        let range = NSRange(location: 0, length: nsContent.utf16.count)
        guard let match = regex.firstMatch(in: nsContent, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: nsContent)
        else {
            return nil
        }
        let value = String(nsContent[valueRange])
        return value.isEmpty ? nil : value
    }
}

/// Parses `! Diff-Expires:` (and `! Expires:`) durations into seconds.
public enum FilterDiffExpiresParser {
    /// Formats supported: `<n> week(s)`, `<n> day(s)`, `<n> hour(s)`,
    /// `<n> minute(s)`, or a bare `<n>` (treated as days, per ABP convention).
    /// Returns `0` when the value cannot be parsed.
    public static func parseSeconds(_ value: String) -> TimeInterval {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let range = NSRange(location: 0, length: trimmed.utf16.count)
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(\d+)\s*([wdhm]?)"#, options: []),
              let match = regex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges > 2,
              let numberRange = Range(match.range(at: 1), in: trimmed),
              let number = Int(trimmed[numberRange]),
              number > 0
        else {
            return 0
        }

        let unitRange = Range(match.range(at: 2), in: trimmed)
        let unit = unitRange.map { String(trimmed[$0]).lowercased() } ?? ""

        switch unit {
        case "w": return TimeInterval(number) * 7 * 86_400
        case "d": return TimeInterval(number) * 86_400
        case "h": return TimeInterval(number) * 3_600
        case "m": return TimeInterval(number) * 60
        default: return TimeInterval(number) * 86_400
        }
    }
}
