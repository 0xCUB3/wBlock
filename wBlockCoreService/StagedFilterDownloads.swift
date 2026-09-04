//
//  StagedFilterDownloads.swift
//  wBlockCoreService
//

import Foundation

/// Marker left in the app group when the Safari extension has downloaded
/// filter list files but could not rebuild the blockers (#528). The next
/// app-side auto-update run rebuilds from these files and clears it. An
/// empty ID list means "staging started, rebuild everything selected", which
/// covers the extension dying between a file write and the metadata save.
public enum StagedFilterDownloads {
    public struct Marker: Codable, Equatable, Sendable {
        public var filterIDs: [String]
        public var stagedAt: TimeInterval

        public init(filterIDs: [String], stagedAt: TimeInterval) {
            self.filterIDs = filterIDs
            self.stagedAt = stagedAt
        }
    }

    public static let filename = "staged-filter-updates.json"

    static func url(groupIdentifier: String = GroupIdentifier.shared.value) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func load(groupIdentifier: String = GroupIdentifier.shared.value) -> Marker? {
        guard let url = url(groupIdentifier: groupIdentifier),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Marker.self, from: data)
    }

    public static func save(filterIDs: [String], groupIdentifier: String = GroupIdentifier.shared.value) {
        guard let url = url(groupIdentifier: groupIdentifier),
              let data = try? JSONEncoder().encode(Marker(filterIDs: filterIDs, stagedAt: Date().timeIntervalSince1970))
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func clear(groupIdentifier: String = GroupIdentifier.shared.value) {
        guard let url = url(groupIdentifier: groupIdentifier) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
