//
//  AdGuardExtraHostManifest.swift
//  wBlockCoreService
//
//  Version-pinned host manifest for scoping the official AdGuard Extra
//  userscript away from non-matching sites (#1139).
//

import Foundation

public struct AdGuardExtraHostManifest: Sendable, Equatable {
    public static let schemaVersion = 1
    public static let fileName = "adguard-extra-hosts.json"
    public static let defaultRemoteURL = URL(string: BuiltInUserScripts.adGuardExtraHostManifestURL)!
    public static let maximumManifestBytes = 2 * 1024 * 1024

    public let schemaVersion: Int
    public let sourceURL: String
    public let version: String
    public let scriptSha256: String
    public let exactHosts: Set<String>
    public let wildcardRoots: Set<String>
    public let tinyShieldDomains: Set<String>
    public let hostCount: Int
    public let tinyShieldDomainCount: Int

    public var revisionToken: String {
        "\(version):\(scriptSha256)"
    }

    private struct RawManifest: Decodable {
        let schemaVersion: Int
        let sourceURL: String
        let version: String
        let scriptSha256: String
        let hosts: [String]
        let tinyShieldDomains: [String]
    }

    public static func decode(data: Data) -> AdGuardExtraHostManifest? {
        guard !data.isEmpty, data.count <= maximumManifestBytes else { return nil }
        guard let raw = try? JSONDecoder().decode(RawManifest.self, from: data) else { return nil }
        guard raw.schemaVersion == schemaVersion else { return nil }
        guard raw.sourceURL == BuiltInUserScripts.adGuardExtraURL else { return nil }

        let version = raw.version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return nil }

        let sha = raw.scriptSha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard sha.count == 64, sha.allSatisfy({ $0.isHexDigit }) else { return nil }

        var exactHosts = Set<String>()
        var wildcardRoots = Set<String>()
        exactHosts.reserveCapacity(raw.hosts.count)
        for entry in raw.hosts {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("*.") {
                if let root = normalizedHost(String(trimmed.dropFirst(2))) {
                    wildcardRoots.insert(root)
                }
            } else if let host = normalizedHost(trimmed) {
                exactHosts.insert(host)
            }
        }
        guard !exactHosts.isEmpty || !wildcardRoots.isEmpty else { return nil }

        var tinyShieldDomains = Set<String>()
        tinyShieldDomains.reserveCapacity(raw.tinyShieldDomains.count)
        for entry in raw.tinyShieldDomains {
            if let domain = normalizedHost(entry) {
                tinyShieldDomains.insert(domain)
            }
        }

        return AdGuardExtraHostManifest(
            schemaVersion: raw.schemaVersion,
            sourceURL: raw.sourceURL,
            version: version,
            scriptSha256: sha,
            exactHosts: exactHosts,
            wildcardRoots: wildcardRoots,
            tinyShieldDomains: tinyShieldDomains,
            hostCount: exactHosts.count + wildcardRoots.count,
            tinyShieldDomainCount: tinyShieldDomains.count
        )
    }

    public func matchesVersion(_ scriptVersion: String) -> Bool {
        let normalized = scriptVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalized.isEmpty && normalized == version
    }

    /// Mirrors AdGuard Extra's `shouldRunExtra(allHosts)` + `HostsMap.getPageScript`.
    public func matchesExtraHost(_ host: String) -> Bool {
        guard let normalized = Self.normalizedHost(host) else { return false }
        let stripped = normalized.hasPrefix("www.") ? String(normalized.dropFirst(4)) : normalized
        guard !stripped.isEmpty else { return false }
        if exactHosts.contains(stripped) {
            return true
        }
        let labels = stripped.split(separator: ".")
        if labels.count >= 2 {
            let root = "\(labels[labels.count - 2]).\(labels[labels.count - 1])"
            if wildcardRoots.contains(root) {
                return true
            }
        }
        return false
    }

    /// Mirrors AdGuard Extra's bundled `isHostnameAllowed(hostname, tinyShieldDomains)`.
    public func matchesTinyShieldHost(_ host: String) -> Bool {
        guard !tinyShieldDomains.isEmpty, let normalized = Self.normalizedHost(host) else {
            return false
        }
        var candidate = normalized[...]
        while true {
            if tinyShieldDomains.contains(String(candidate)) {
                return true
            }
            guard let dot = candidate.firstIndex(of: ".") else { return false }
            candidate = candidate[candidate.index(after: dot)...]
            if candidate.isEmpty { return false }
        }
    }

    /// When standalone tinyShield is enabled, AdGuard Extra only needs to run on its own
    /// `allHosts` entries. When standalone tinyShield is disabled, AdGuard Extra also
    /// handles its bundled tinyShield domains while still skipping the rest of the web.
    public func allowsAdGuardExtra(onHost host: String, standaloneTinyShieldActive: Bool) -> Bool {
        if matchesExtraHost(host) {
            return true
        }
        if !standaloneTinyShieldActive && matchesTinyShieldHost(host) {
            return true
        }
        return false
    }

    /// Suppresses standalone tinyShield only when AdGuard Extra is already running on
    /// this host and its bundled tinyShield covers the same host.
    public func shouldSuppressStandaloneTinyShield(
        onHost host: String,
        adGuardExtraRunningOnHost: Bool
    ) -> Bool {
        adGuardExtraRunningOnHost && matchesTinyShieldHost(host)
    }

    nonisolated static func loadCached(directories: [URL]) -> AdGuardExtraHostManifest? {
        UserScriptFileStorage.read(
            fileName: fileName,
            directories: directories
        ) { decode(data: $0) }
    }

    @discardableResult
    nonisolated static func saveCached(data: Data, directories: [URL]) -> Bool {
        guard decode(data: data) != nil, !directories.isEmpty else { return false }
        var wroteAny = false
        for directory in directories {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var url = directory.appendingPathComponent(fileName)
                try data.write(to: url, options: .atomic)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? url.setResourceValues(values)
                wroteAny = true
            } catch {
                continue
            }
        }
        return wroteAny
    }

    private static func normalizedHost(_ raw: String) -> String? {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host.isEmpty ? nil : host
    }
}
