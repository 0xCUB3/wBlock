internal import ContentBlockerConverter
import CryptoKit
import Foundation

public struct SafariContentBlockerAffinitySnapshot: Sendable {
    public let contentsByFilterID: [UUID: String]

    public var isEmpty: Bool { contentsByFilterID.isEmpty }
    public var filterIDs: Set<UUID> { Set(contentsByFilterID.keys) }

    public init(contentsByFilterID: [UUID: String] = [:]) {
        self.contentsByFilterID = contentsByFilterID
    }

    fileprivate init(
        filters: [FilterList],
        containerURL: URL
    ) {
        var contentsByFilterID: [UUID: String] = [:]
        for filter in filters {
            guard let sourceURL = SafariContentBlockerAffinityProcessor.sourceURL(
                for: filter,
                containerURL: containerURL
            ),
                let rawContent = try? String(contentsOfFile: sourceURL.path, encoding: .utf8),
                let content = SafariContentBlockerAffinityProcessor.affinitySourceContent(
                    for: filter,
                    rawContent: rawContent
                )
            else {
                continue
            }
            contentsByFilterID[filter.id] = content
        }
        self.contentsByFilterID = contentsByFilterID
    }

    public func content(for filterID: UUID) -> String? {
        contentsByFilterID[filterID]
    }
}

public enum SafariContentBlockerAffinityProcessor {
    fileprivate static let directivePrefix = "!#safari_cb_affinity"

    public static func sourceURL(for filter: FilterList, containerURL: URL) -> URL? {
        let primaryURL = containerURL.appendingPathComponent(
            ContentBlockerIncrementalCache.localFilename(for: filter)
        )
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            return primaryURL
        }

        guard filter.isCustom,
              let legacyURL = ContentBlockerIncrementalCache.safeLegacyFileURL(
                  name: filter.name,
                  containerURL: containerURL
              ),
              FileManager.default.fileExists(atPath: legacyURL.path)
        else { return nil }
        return legacyURL
    }

    public static func snapshot(
        for filters: [FilterList],
        containerURL: URL
    ) -> SafariContentBlockerAffinitySnapshot {
        SafariContentBlockerAffinitySnapshot(filters: filters, containerURL: containerURL)
    }

    public static func detectFiltersWithAffinity(
        _ filters: [FilterList],
        containerURL: URL
    ) -> Set<UUID> {
        snapshot(for: filters, containerURL: containerURL).filterIDs
    }

    /// Returns the content that should participate in affinity-aware target
    /// distribution, or `nil` when the filter contributes only to its
    /// assigned target.
    ///
    /// Safari evaluates each content blocker extension's rule list
    /// independently, so an `@@` exception only cancels block rules compiled
    /// into the same extension. Custom filters land in a single slot while the
    /// block rule they except usually lives in another, so top-level exception
    /// rules in custom filters are wrapped in `!#safari_cb_affinity(all)`
    /// blocks automatically and replicated to every target (issue #531).
    /// Explicit affinity blocks authored by the user are preserved untouched.
    public static func affinitySourceContent(
        for filter: FilterList,
        rawContent: String
    ) -> String? {
        if filter.isCustom,
           let synthesized = contentWrappingCustomExceptionRules(in: rawContent) {
            return synthesized
        }
        return rawContent.contains(directivePrefix) ? rawContent : nil
    }

    /// Wraps top-level `@@` exception rules in `!#safari_cb_affinity(all)`
    /// blocks. Returns `nil` when the content has no top-level exceptions.
    private static func contentWrappingCustomExceptionRules(in content: String) -> String? {
        guard content.contains("@@") else { return nil }

        let openDirectivePrefix = directivePrefix + "("
        let lines = content.components(separatedBy: .newlines)
        var output: [String] = []
        output.reserveCapacity(lines.count + 8)
        var insideExplicitBlock = false
        var insideSynthesizedBlock = false
        var wrappedAnyException = false

        func closeSynthesizedBlock() {
            guard insideSynthesizedBlock else { return }
            output.append(directivePrefix)
            insideSynthesizedBlock = false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(openDirectivePrefix) {
                closeSynthesizedBlock()
                insideExplicitBlock = true
                output.append(line)
                continue
            }
            if trimmed == directivePrefix {
                closeSynthesizedBlock()
                insideExplicitBlock = false
                output.append(line)
                continue
            }
            if !insideExplicitBlock, trimmed.hasPrefix("@@") {
                if !insideSynthesizedBlock {
                    output.append(directivePrefix + "(all)")
                    insideSynthesizedBlock = true
                    wrappedAnyException = true
                }
                output.append(line)
                continue
            }
            closeSynthesizedBlock()
            output.append(line)
        }
        closeSynthesizedBlock()

        return wrappedAnyException ? output.joined(separator: "\n") : nil
    }

    @discardableResult
    public static func appendAffinityFilteredContribution(
        for filter: FilterList,
        includeBaseRules: Bool,
        target: ContentBlockerTargetInfo,
        allTargets: [ContentBlockerTargetInfo],
        affinitySnapshot: SafariContentBlockerAffinitySnapshot,
        destinationHandle: FileHandle,
        hasher: inout SHA256,
        newlineData: Data
    ) throws -> Bool {
        guard let content = affinitySnapshot.content(for: filter.id) else {
            return false
        }
        let filtered = filteredContent(
            from: content,
            includeBaseRules: includeBaseRules,
            target: target,
            allTargets: allTargets
        )
        guard !filtered.isEmpty else { return false }

        let filteredData = Data(filtered.utf8)
        hasher.update(data: filteredData)
        try destinationHandle.write(contentsOf: filteredData)
        hasher.update(data: newlineData)
        try destinationHandle.write(contentsOf: newlineData)
        return true
    }

    /// Compatibility overload for callers that load affinity sources on demand.
    @discardableResult
    public static func appendAffinityFilteredContribution(
        for filter: FilterList,
        includeBaseRules: Bool,
        target: ContentBlockerTargetInfo,
        allTargets: [ContentBlockerTargetInfo],
        containerURL: URL,
        destinationHandle: FileHandle,
        hasher: inout SHA256,
        newlineData: Data
    ) throws -> Bool {
        guard let sourceURL = sourceURL(for: filter, containerURL: containerURL) else {
            return false
        }
        let rawContent = try String(contentsOf: sourceURL, encoding: .utf8)
        let content = affinitySourceContent(for: filter, rawContent: rawContent) ?? rawContent
        return try appendAffinityFilteredContribution(
            for: filter,
            includeBaseRules: includeBaseRules,
            target: target,
            allTargets: allTargets,
            affinitySnapshot: SafariContentBlockerAffinitySnapshot(
                contentsByFilterID: [filter.id: content]
            ),
            destinationHandle: destinationHandle,
            hasher: &hasher,
            newlineData: newlineData
        )
    }

    public static func filteredContent(
        from content: String,
        includeBaseRules: Bool,
        target: ContentBlockerTargetInfo,
        allTargets: [ContentBlockerTargetInfo]
    ) -> String {
        guard allTargets.contains(target),
              let targetTypes = contentBlockerTypes(for: target),
              !targetTypes.isEmpty
        else {
            return includeBaseRules ? content : ""
        }

        let defaultType = includeBaseRules
            ? defaultContentBlockerType(for: target)
            : excludedDefaultContentBlockerType(for: targetTypes)
        let groupedRules = AffinityRulesGrouper.group(rules: [
            (defaultType, content.components(separatedBy: .newlines))
        ])

        var includedLines: [String] = []
        var seenLines: Set<String> = []
        for contentType in targetTypes {
            guard let rules = groupedRules[contentType] else { continue }
            for rule in rules where seenLines.insert(rule).inserted {
                includedLines.append(rule)
            }
        }

        return includedLines.joined(separator: "\n")
    }

    private static func defaultContentBlockerType(for target: ContentBlockerTargetInfo) -> ContentBlockerType {
        switch target.slot {
        case 1:
            return .general
        case 2:
            return .privacy
        case 3:
            return .security
        case 4:
            return .other
        case 5:
            return .custom
        default:
            return .other
        }
    }

    private static func contentBlockerTypes(for target: ContentBlockerTargetInfo) -> [ContentBlockerType]? {
        switch target.slot {
        case 1:
            return [.general]
        case 2:
            return [.privacy]
        case 3:
            return [.socialWidgetsAndAnnoyances, .security]
        case 4:
            return [.other]
        case 5:
            return [.custom]
        default:
            return nil
        }
    }

    private static func excludedDefaultContentBlockerType(
        for targetTypes: [ContentBlockerType]
    ) -> ContentBlockerType {
        ContentBlockerType.allCases.first { !targetTypes.contains($0) } ?? .general
    }

}
