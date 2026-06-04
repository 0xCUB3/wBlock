internal import ContentBlockerConverter
import CryptoKit
import Foundation

public enum SafariContentBlockerAffinityProcessor {
    private static let directivePrefix = "!#safari_cb_affinity"

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

    public static func detectFiltersWithAffinity(
        _ filters: [FilterList],
        containerURL: URL
    ) -> Set<UUID> {
        var affinityFilterIDs: Set<UUID> = []

        for filter in filters {
            guard let sourceURL = sourceURL(for: filter, containerURL: containerURL),
                  let content = try? String(contentsOf: sourceURL, encoding: .utf8),
                  content.contains(directivePrefix)
            else {
                continue
            }

            affinityFilterIDs.insert(filter.id)
        }

        return affinityFilterIDs
    }

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

        let content = try String(contentsOf: sourceURL, encoding: .utf8)
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
