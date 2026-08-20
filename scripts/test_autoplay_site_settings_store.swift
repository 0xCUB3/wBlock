#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ text: String, _ needle: String, in path: String) {
    guard text.contains(needle) else {
        fputs("FAIL: \(path) missing \(needle)\n", stderr)
        exit(1)
    }
}

func forbid(_ text: String, _ needle: String, in path: String) {
    guard !text.contains(needle) else {
        fputs("FAIL: \(path) must not contain \(needle)\n", stderr)
        exit(1)
    }
}

let protoPath = "wBlockCoreService/DataModels.proto"
let protobufPath = "wBlockCoreService/DataModels.pb.swift"
let extensionsPath = "wBlockCoreService/ProtobufDataManager+Extensions.swift"
let handlerPath = "wBlockCoreService/WebExtensionRequestHandler.swift"
let cloudPath = "wBlock/CloudSyncManager.swift"
let backupPath = "wBlock/BackupManager.swift"

let proto = try source(protoPath)
require(proto, "bool no_autoplay_enabled = 4;", in: protoPath)
require(proto, "repeated string no_autoplay_allowed_sites = 5;", in: protoPath)

let protobuf = try source(protobufPath)
for symbol in [
    "var noAutoplayEnabled: Bool = false",
    "var noAutoplayAllowedSites: [String] = []",
    "no_autoplay_enabled",
    "no_autoplay_allowed_sites",
    "case 4: try { try decoder.decodeSingularBoolField(value: &self.noAutoplayEnabled) }()",
    "case 5: try { try decoder.decodeRepeatedStringField(value: &self.noAutoplayAllowedSites) }()",
    "visitor.visitSingularBoolField(value: self.noAutoplayEnabled, fieldNumber: 4)",
    "visitor.visitRepeatedStringField(value: self.noAutoplayAllowedSites, fieldNumber: 5)",
    "lhs.noAutoplayEnabled != rhs.noAutoplayEnabled",
    "lhs.noAutoplayAllowedSites != rhs.noAutoplayAllowedSites",
] {
    require(protobuf, symbol, in: protobufPath)
}

let extensions = try source(extensionsPath)
for symbol in [
    "public var isNoAutoplayEnabled: Bool",
    "public var noAutoplayAllowedSites: [String]",
    "@discardableResult\n    public func setNoAutoplayEnabled(_ enabled: Bool) async -> Bool",
    "@discardableResult\n    public func setNoAutoplayAllowedSites(_ sites: [String]) async -> Bool",
    "public func setNoAutoplaySiteAllowed(_ allowed: Bool, onHost host: String) async -> Bool",
    "DisabledSitesNormalizer.normalizedDomains(from: sites)",
    "data.whitelist.noAutoplayAllowedSites = normalized",
    "Set(DisabledSitesNormalizer.normalizedDomains(",
    "from: data.whitelist.noAutoplayAllowedSites",
    "data.whitelist.noAutoplayAllowedSites = Array(sites).sorted()",
    "public func isNoAutoplayAllowed(onHost host: String) -> Bool",
    "DisabledSitesNormalizer.normalizedDomain(host)",
] {
    require(extensions, symbol, in: extensionsPath)
}
forbid(extensions, "HostMatcher.isHostDisabled(host: host, disabledSites: noAutoplayAllowedSites)", in: extensionsPath)

let handler = try source(handlerPath)
for symbol in [
    "case \"getNoAutoplayState\"",
    "case \"setNoAutoplayEnabled\"",
    "case \"setNoAutoplaySiteAllowed\"",
    "handleGetNoAutoplayState",
    "handleSetNoAutoplayEnabled",
    "handleSetNoAutoplaySiteAllowed",
    "refreshFromDiskIfModified(forceRead: true)",
    "\"siteAllowed\": siteAllowed",
    "\"error\": \"Missing host\"",
    "setNoAutoplaySiteAllowed(allowed, onHost: host)",
    "\"ok\": persisted",
] {
    require(handler, symbol, in: handlerPath)
}
forbid(handler, "sites.append(host)", in: handlerPath)

let cloud = try source(cloudPath)
for symbol in [
    "let noAutoplayEnabled: Bool?",
    "let noAutoplayAllowedSites: [String]?",
    "noAutoplayEnabled: content.noAutoplayEnabled",
    "noAutoplayAllowedSites: content.noAutoplayAllowedSites",
    "let noAutoplayEnabled = dataManager.isNoAutoplayEnabled",
    "let noAutoplayAllowedSites = dataManager.noAutoplayAllowedSites.sorted()",
    "let remoteNoAutoplayEnabled = payload.noAutoplayEnabled",
    "if let remoteNoAutoplayAllowedSites = payload.noAutoplayAllowedSites",
] {
    require(cloud, symbol, in: cloudPath)
}
forbid(cloud, "payload.noAutoplayEnabled ?? false", in: cloudPath)
forbid(cloud, "payload.noAutoplayAllowedSites ?? []", in: cloudPath)

let backup = try source(backupPath)
for symbol in [
    "var noAutoplayEnabled: Bool = false",
    "var noAutoplayAllowedSites: [String] = []",
    "decodeIfPresent(Bool.self, forKey: .noAutoplayEnabled) ?? false",
    "decodeIfPresent([String].self, forKey: .noAutoplayAllowedSites) ?? []",
    "noAutoplayEnabled: noAutoplayEnabled",
    "noAutoplayAllowedSites: noAutoplayAllowedSites",
    "setNoAutoplayEnabled(backup.noAutoplayEnabled)",
    "setNoAutoplayAllowedSites(backup.noAutoplayAllowedSites)",
] {
    require(backup, symbol, in: backupPath)
}

print("PASS: autoplay site settings store")
