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
                let content = try? String(contentsOf: sourceURL, encoding: .utf8),
                content.contains(SafariContentBlockerAffinityProcessor.directivePrefix)
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

        guard filter.isCustom else { return nil }
        let legacyURL = containerURL.appendingPathComponent("\(filter.name).txt")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
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
