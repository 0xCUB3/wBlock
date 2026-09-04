//
//  ContentBlockerMappingService.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 8/12/25.
//

import Foundation

/// Shared slot-mapping logic used by the app and background auto-update flows.
/// This keeps target distribution behavior identical across processes.
public enum ContentBlockerMappingService {
    /// Order in which a target's lists are fed to the converter (#645). Safari's
    /// converter keeps the first rules and drops the rest when a target overflows,
    /// so the most recently updated lists go first and stale content is what gets
    /// cut. Ties fall back to the distribution order for determinism.
    public static func orderedForCompilation(_ selectedFilters: [FilterList]) -> [FilterList] {
        let distribution = orderedForDistribution(selectedFilters)
        let rank = Dictionary(uniqueKeysWithValues: distribution.enumerated().map { ($1.id, $0) })
        return distribution.sorted { lhs, rhs in
            let lhsDate = lhs.lastUpdated ?? .distantPast
            let rhsDate = rhs.lastUpdated ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return (rank[lhs.id] ?? 0) < (rank[rhs.id] ?? 0)
        }
    }

    /// Counts, per list, the rules that no earlier list in compile order already
    /// supplied (#644). Lines are compared after trimming; comments and headers
    /// are ignored the same way `FilterList.countRules` does.
    public static func uniqueRuleCounts(
        for selectedFilters: [FilterList],
        content: (FilterList) -> String?
    ) -> [UUID: Int] {
        var seen = Set<String>()
        var counts: [UUID: Int] = [:]
        for filter in orderedForCompilation(selectedFilters) {
            guard let text = content(filter) else { continue }
            var unique = 0
            text.enumerateLines { line, _ in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") { return }
                if seen.insert(trimmed).inserted { unique += 1 }
            }
            counts[filter.id] = unique
        }
        return counts
    }

    public static func orderedForDistribution(_ selectedFilters: [FilterList]) -> [FilterList] {
        selectedFilters.sorted { lhs, rhs in
            let lhsCount = lhs.sourceRuleCount ?? 0
            let rhsCount = rhs.sourceRuleCount ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Distributes selected filters across available content blocker targets by
    /// least-filled estimated source-rule count.
    ///
    /// - Parameters:
    ///   - selectedFilters: Filters to distribute.
    ///   - targets: Platform-specific content blocker targets.
    /// - Returns: Mapping of target -> assigned filter lists.
    public static func distribute(
        selectedFilters: [FilterList],
        across targets: [ContentBlockerTargetInfo]
    ) -> [ContentBlockerTargetInfo: [FilterList]] {
        guard !targets.isEmpty else { return [:] }

        var filtersByTarget: [ContentBlockerTargetInfo: [FilterList]] = Dictionary(
            uniqueKeysWithValues: targets.map { ($0, []) }
        )
        var estimatedSourceRulesByTarget: [ContentBlockerTargetInfo: Int] = Dictionary(
            uniqueKeysWithValues: targets.map { ($0, 0) }
        )

        let sortedFilters = orderedForDistribution(selectedFilters)

        for filter in sortedFilters {
            guard let destination = targets.min(by: {
                (estimatedSourceRulesByTarget[$0] ?? 0) < (estimatedSourceRulesByTarget[$1] ?? 0)
            }) else {
                break
            }

            filtersByTarget[destination, default: []].append(filter)
            estimatedSourceRulesByTarget[destination, default: 0] += filter.sourceRuleCount ?? 0
        }

        return filtersByTarget
    }
}
