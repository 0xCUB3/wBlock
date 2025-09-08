//
//  AutoUpdateStore.swift
//  wBlockCoreService
//
//  Lightweight JSON-backed storage for auto-update scheduler state and
//  HTTP validators (ETag/Last-Modified), persisted in the App Group.
//  This avoids UserDefaults and works from app and extensions.

import Foundation

public struct AutoUpdateState: Codable {
    public var enabled: Bool = true
    public var intervalHours: Double = 6
    public var lastCheck: TimeInterval? = nil
    public var nextEligible: TimeInterval? = nil
    // HTTP validators by filter UUID string
    public var etagByFilterId: [String: String] = [:]
    public var lastModifiedByFilterId: [String: String] = [:]
}

public actor AutoUpdateStore {
    public static let shared = AutoUpdateStore()

    private let filename = "auto_update_state.json"
    private var cached: AutoUpdateState? = nil

    private func fileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value)?.appendingPathComponent(filename)
    }

    public func load() -> AutoUpdateState {
        if let cached { return cached }
        guard let url = fileURL(), FileManager.default.fileExists(atPath: url.path) else {
            let def = AutoUpdateState()
            cached = def
            return def
        }
        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(AutoUpdateState.self, from: data)
            cached = state
            return state
        } catch {
            // Corrupt or unreadable; start fresh
            let def = AutoUpdateState()
            cached = def
            return def
        }
    }

    public func save(_ state: AutoUpdateState) {
        cached = state
        guard let url = fileURL() else { return }
        do {
            let data = try JSONEncoder().encode(state)
            // atomic write
            try data.write(to: url, options: .atomic)
        } catch {
            // Best-effort; ignore
        }
    }

    // Convenience helpers
    public func getIntervalHours() -> Double { load().intervalHours }
    public func setIntervalHours(_ hours: Double) { var s = load(); s.intervalHours = hours; save(s) }
    public func isEnabled() -> Bool { load().enabled }
    public func setEnabled(_ enabled: Bool) { var s = load(); s.enabled = enabled; save(s) }
    public func getLastCheck() -> TimeInterval? { load().lastCheck }
    public func setLastCheck(_ ts: TimeInterval?) { var s = load(); s.lastCheck = ts; save(s) }
    public func getNextEligible() -> TimeInterval? { load().nextEligible }
    public func setNextEligible(_ ts: TimeInterval?) { var s = load(); s.nextEligible = ts; save(s) }
    public func getETag(for filterId: String) -> String? { load().etagByFilterId[filterId] }
    public func setETag(_ etag: String?, for filterId: String) { var s = load(); if let e = etag { s.etagByFilterId[filterId] = e } else { s.etagByFilterId.removeValue(forKey: filterId) }; save(s) }
    public func getLastModified(for filterId: String) -> String? { load().lastModifiedByFilterId[filterId] }
    public func setLastModified(_ lm: String?, for filterId: String) { var s = load(); if let v = lm { s.lastModifiedByFilterId[filterId] = v } else { s.lastModifiedByFilterId.removeValue(forKey: filterId) }; save(s) }
}

