//
//  UserScriptPatternBudget.swift
//  wBlockCoreService
//
//  Scripts like tinyShield carry tens of thousands of @match lines. The source
//  file is authoritative and every reader hydrates from it before matching, so
//  persisting those arrays only inflates the store every process decodes on
//  each read. Records over this budget keep their patterns on disk only.
//

import Foundation

extension UserScript {
    public static let maximumPersistedPatternBytes = 16_384

    public var persistedPatternBytes: Int {
        [matches, excludeMatches, includes, excludes].reduce(0) { total, array in
            array.reduce(total) { $0 + $1.utf8.count }
        }
    }

    public var exceedsPersistedPatternBudget: Bool {
        persistedPatternBytes > Self.maximumPersistedPatternBytes
    }

    /// Returns a copy whose pattern arrays are empty. Callers must confirm the
    /// script's source file exists first; hydration re-parses the arrays from it.
    public func withoutPersistedPatterns() -> UserScript {
        var trimmed = self
        trimmed.matches = []
        trimmed.excludeMatches = []
        trimmed.includes = []
        trimmed.excludes = []
        return trimmed
    }
}
