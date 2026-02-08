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

        let sortedFilters = selectedFilters.sorted { lhs, rhs in
            let lhsCount = lhs.sourceRuleCount ?? 0
            let rhsCount = rhs.sourceRuleCount ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.id.uuidString < rhs.id.uuidString
        }

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
