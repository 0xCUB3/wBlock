import CryptoKit
import Foundation

public enum SafariContentBlockerAffinityProcessor {
    private static let directivePrefix = "!#safari_cb_affinity"

    private enum BlockDestination {
        case baseRulesOnly
        case targetSlots(Set<Int>)
    }

    private enum Directive {
        case start(BlockDestination)
        case end
    }

    public static func sourceURL(for filter: FilterList, containerURL: URL) -> URL? {
        let primaryURL = containerURL.appendingPathComponent(
            ContentBlockerIncrementalCache.localFilename(for: filter)
        )
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            return primaryURL
        }

        let legacyURL = containerURL.appendingPathComponent(
            ContentBlockerIncrementalCache.legacyLocalFilename(for: filter)
        )
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
        return legacyURL
    }

    public static func detectFiltersWithAffinity(
        _ filters: [FilterList],
        containerURL: URL,
        sourceOverrides: [UUID: URL] = [:]
    ) -> Set<UUID> {
        var affinityFilterIDs: Set<UUID> = []

        for filter in filters {
            guard let sourceURL = sourceOverrides[filter.id] ?? sourceURL(for: filter, containerURL: containerURL),
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
        sourceURLOverride: URL? = nil,
        destinationHandle: FileHandle,
        hasher: inout SHA256,
        newlineData: Data
    ) throws -> Bool {
        guard let sourceURL = sourceURLOverride ?? sourceURL(for: filter, containerURL: containerURL) else {
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
        let availableSlots = Set(allTargets.map(\.slot))
        var destinationStack: [BlockDestination] = []
        var includedLines: [String] = []

        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if let directive = parseDirective(trimmed, availableSlots: availableSlots) {
                switch directive {
                case .start(let destination):
                    destinationStack.append(destination)
                case .end:
                    if !destinationStack.isEmpty {
                        destinationStack.removeLast()
                    }
                }
                return
            }

            let shouldInclude: Bool
            if let destination = destinationStack.last {
                switch destination {
                case .baseRulesOnly:
                    shouldInclude = includeBaseRules
                case .targetSlots(let slots):
                    shouldInclude = slots.contains(target.slot)
                }
            } else {
                shouldInclude = includeBaseRules
            }

            if shouldInclude {
                includedLines.append(line)
            }
        }

        return includedLines.joined(separator: "\n")
    }

    private static func parseDirective(
        _ trimmed: String,
        availableSlots: Set<Int>
    ) -> Directive? {
        guard trimmed.hasPrefix(directivePrefix) else { return nil }

        if trimmed == directivePrefix {
            return .end
        }

        let suffix = String(trimmed.dropFirst(directivePrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard suffix.first == "(", suffix.last == ")" else {
            return .start(.baseRulesOnly)
        }

        let tokenBody = suffix.dropFirst().dropLast()
        let rawTokens = tokenBody.split(separator: ",", omittingEmptySubsequences: true)
        var slots: Set<Int> = []

        for rawToken in rawTokens {
            let token = String(rawToken)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            slots.formUnion(mappedSlots(for: token, availableSlots: availableSlots))
        }

        if slots.isEmpty {
            return .start(.baseRulesOnly)
        }

        return .start(.targetSlots(slots))
    }

    private static func mappedSlots(
        for token: String,
        availableSlots: Set<Int>
    ) -> Set<Int> {
        switch token {
        case "all":
            return availableSlots
        case "general":
            return availableSlots.contains(1) ? [1] : []
        case "privacy":
            return availableSlots.contains(2) ? [2] : []
        case "social", "security":
            return availableSlots.contains(3) ? [3] : []
        case "other":
            return availableSlots.contains(4) ? [4] : []
        case "custom":
            return availableSlots.contains(5) ? [5] : []
        default:
            return []
        }
    }
}
