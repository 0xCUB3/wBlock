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
    /// Refreshes download-derived metadata without changing the user configuration
    /// captured at the start of an apply run.
    public static func refreshingCompilationMetadata(
        snapshot: [FilterList],
        latest: [FilterList]
    ) -> [FilterList] {
        let latestByID = Dictionary(latest.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        return snapshot.map { filter in
            guard let current = latestByID[filter.id] else { return filter }
            var refreshed = filter
            refreshed.version = current.version
            refreshed.sourceRuleCount = current.sourceRuleCount
            refreshed.rawSourceRuleCount = current.rawSourceRuleCount
            refreshed.lastUpdated = current.lastUpdated
            refreshed.etag = current.etag
            refreshed.serverLastModified = current.serverLastModified
            return refreshed
        }
    }

    /// Order in which a target's lists are fed to the converter (#645). Safari's
    /// converter keeps the first rules and drops the rest when a target overflows,
    /// so the most recently updated lists go first and stale content is what gets
    /// cut. Ties fall back to the distribution order for determinism.
    public static func orderedForCompilation(_ selectedFilters: [FilterList]) -> [FilterList] {
        orderedForDistribution(selectedFilters).enumerated()
            .sorted { lhs, rhs in
                let lhsDate = lhs.element.lastUpdated ?? .distantPast
                let rhsDate = rhs.element.lastUpdated ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    public static func orderedForDistribution(_ selectedFilters: [FilterList]) -> [FilterList] {
        var latestByID: [UUID: FilterList] = [:]
        var firstIDs = Set<UUID>()
        for filter in selectedFilters {
            latestByID[filter.id] = filter
            firstIDs.insert(filter.id)
        }
        let uniqueFilters = firstIDs.compactMap { latestByID[$0] }
        return uniqueFilters.sorted { lhs, rhs in
            let lhsCount = lhs.sourceRuleCount ?? 0
            let rhsCount = rhs.sourceRuleCount ?? 0
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Distributes selected filters across available content blocker targets by
    /// least-filled estimated source-rule count.
    public static func distribute(
        selectedFilters: [FilterList],
        across targets: [ContentBlockerTargetInfo]
    ) -> [ContentBlockerTargetInfo: [FilterList]] {
        plan(selectedFilters: selectedFilters, across: targets).filtersByTarget
    }

    /// A list estimated above this many rules is split across blockers. The
    /// margin covers affinity rules, replicated exceptions, and conversion
    /// growth, none of which the source count includes.
    static let shardBudget = ContentBlockerService.safariContentBlockerRuleLimit * 4 / 5

    /// Each list goes whole to the least-filled blocker, largest first. A list
    /// too big for one blocker is split into equal shards that land on
    /// different blockers, so one list can no longer overflow a blocker
    /// while the others sit half empty.
    public static func plan(
        selectedFilters: [FilterList],
        across targets: [ContentBlockerTargetInfo]
    ) -> ContentBlockerDistribution {
        var distribution = ContentBlockerDistribution(
            filtersByTarget: Dictionary(uniqueKeysWithValues: targets.map { ($0, []) })
        )
        guard !targets.isEmpty else { return distribution }

        struct Item { let filter: FilterList; let order: Int; let shard: ContentBlockerShard?; let cost: Int }
        var items: [Item] = []
        for (order, filter) in orderedForDistribution(selectedFilters).enumerated() {
            let cost = filter.sourceRuleCount ?? 0
            let parts = min(targets.count, max(1, (cost + shardBudget - 1) / shardBudget))
            for index in 0..<parts {
                items.append(Item(
                    filter: filter, order: order,
                    shard: parts > 1 ? ContentBlockerShard(index: index, count: parts) : nil,
                    cost: (cost + parts - 1 - index) / parts
                ))
            }
        }
        items.sort { ($0.cost, $1.order, $1.shard?.index ?? 0) > ($1.cost, $0.order, $0.shard?.index ?? 0) }

        var load: [ContentBlockerTargetInfo: Int] = [:]
        for item in items {
            let free = targets.filter { distribution.shardsByTarget[$0]?[item.filter.id] == nil }
            guard let destination = (free.isEmpty ? targets : free).min(by: { load[$0, default: 0] < load[$1, default: 0] })
            else { break }
            distribution.filtersByTarget[destination, default: []].append(item.filter)
            if let shard = item.shard { distribution.shardsByTarget[destination, default: [:]][item.filter.id] = shard }
            load[destination, default: 0] += item.cost
        }
        return distribution
    }
}

public struct ContentBlockerDistribution: Sendable {
    public var filtersByTarget: [ContentBlockerTargetInfo: [FilterList]]
    /// The part of a split list each blocker compiles. Lists absent here
    /// compile whole into their blocker.
    public var shardsByTarget: [ContentBlockerTargetInfo: [UUID: ContentBlockerShard]] = [:]
}

/// One of `count` parts of a list too big for one blocker. The engine splits
/// block rules between the parts by a stable hash and keeps exceptions,
/// `$badfilter`, and directives in every part (wbe apply.rs).
public struct ContentBlockerShard: Hashable, Sendable {
    public let index: Int
    public let count: Int
}
