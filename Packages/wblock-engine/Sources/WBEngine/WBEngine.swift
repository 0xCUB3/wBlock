import Foundation
import WBE

/// Swift face of the wbe engine (crates/wbe/include/wbe.h).
public enum WBEngine {
    public struct EngineError: LocalizedError {
        public let errorDescription: String?
        public init(errorDescription: String?) {
            self.errorDescription = errorDescription
        }
        static func last() -> EngineError {
            EngineError(errorDescription: wbe_last_error().map { String(cString: $0) } ?? "wbe failed")
        }
    }

    /// Changes whenever the engine's outputs change for the same input.
    public static var outputVersion: UInt32 { wbe_output_version() }

    public struct Compiled {
        /// Safari content-blocker JSON array, as UTF-8 bytes.
        public let safariRulesJSON: Data
        /// Rules for the per-page engine, one per line.
        public let runtimeRules: String
        public let stats: Stats
    }

    public struct Stats: Decodable {
        public let lines: Int
        public let rules: Int
        public let nativeRules: Int
        public let runtimeRules: Int
        public let dropped: [String: Int]
        public let admitted: [String: Int]?
        /// `Plan.fingerprint` of the arguments that produced these stats.
        public let fingerprint: String?

        enum CodingKeys: String, CodingKey {
            case lines, rules, dropped, admitted, fingerprint
            case nativeRules = "native_rules"
            case runtimeRules = "runtime_rules"
        }
    }

    /// Drops the parsed lists kept between plans. Plans in use keep theirs.
    public static func clearParseCache() {
        wbe_clear_parse_cache()
    }

    /// A packing that exceeds the limits. `slots` are in target order.
    public struct Capacity: Decodable {
        public let rules: Int
        public let bytes: Int
        public let slots: [Slot]

        public struct Slot: Decodable {
            public let rules: Int
            public let bytes: Int
        }
    }

    public final class Plan: @unchecked Sendable {
        private let handle: OpaquePointer
        /// Nil when the packing fits. An over-capacity plan still compiles its
        /// targets for measurement, but its output must not be shipped.
        public let capacity: Capacity?
        /// The engine's message for `capacity`, nil when the plan fits.
        public let capacityMessage: String?

        public init(requestJSON: String) throws {
            guard let raw = wbe_plan_new(Self.withFileKeys(requestJSON)) else { throw EngineError.last() }
            // `raw` has no owner until `handle` is set, and a throw here skips
            // `deinit`, so it is freed on that path.
            let capacity: Capacity?
            let capacityMessage: String?
            do {
                if let json = wbe_plan_capacity_json(raw) {
                    capacity = try JSONDecoder().decode(Capacity.self, from: Data(String(cString: json).utf8))
                    capacityMessage = wbe_plan_capacity_message(raw).map { String(cString: $0) }
                } else {
                    capacity = nil
                    capacityMessage = nil
                }
            } catch {
                wbe_plan_free(raw)
                throw error
            }
            handle = raw
            self.capacity = capacity
            self.capacityMessage = capacityMessage
        }

        deinit { wbe_plan_free(handle) }

        /// The request with `cache_key` set on each file list, so the engine
        /// skips reading a file it has parsed and the file has not changed.
        /// A request that cannot be read is passed on unchanged.
        static func withFileKeys(_ requestJSON: String) -> String {
            guard var request = try? JSONSerialization.jsonObject(with: Data(requestJSON.utf8)) as? [String: Any],
                  var lists = request["lists"] as? [[String: Any]] else { return requestJSON }
            var changed = false
            for index in lists.indices where lists[index]["cache_key"] == nil {
                guard let path = lists[index]["path"] as? String, let key = fileKey(path) else { continue }
                lists[index]["cache_key"] = key
                changed = true
            }
            guard changed else { return requestJSON }
            request["lists"] = lists
            guard let data = try? JSONSerialization.data(withJSONObject: request, options: [.sortedKeys]) else {
                return requestJSON
            }
            return String(decoding: data, as: UTF8.self)
        }

        /// `path|inode|size|mtime`, which changes when the file is replaced or
        /// written. Read it before the file, so a change in between leaves the
        /// key stale rather than current.
        static func fileKey(_ path: String) -> String? {
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            return "\(path)|\(info.st_ino)|\(info.st_size)|\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)"
        }

        /// The fingerprint `compileTarget` compares with `knownFingerprint` for
        /// blocker `target` compiled with `extras`. A caller stores it as the
        /// 16 hex digits `String(format: "%016llx", fingerprint)`, which is the
        /// form `known_targets` takes.
        public func targetFingerprint(_ target: Int, extras: String) throws -> UInt64 {
            guard target >= 0 else {
                throw EngineError(errorDescription: "target index out of bounds")
            }
            let fingerprint = wbe_plan_target_fingerprint(handle, target, extras)
            // Zero is a fingerprint too; only a set error means failure.
            guard fingerprint != 0 || String(cString: wbe_last_error()).isEmpty else {
                throw EngineError.last()
            }
            return fingerprint
        }

        /// Compiles the blocker unless `knownFingerprint` is the fingerprint its
        /// output has now (`compiled.stats.fingerprint`); then nil, and nothing
        /// was compiled.
        public func compileTarget(_ target: Int, extras: String, knownFingerprint: UInt64?) throws -> Compiled? {
            guard target >= 0 else {
                throw EngineError(errorDescription: "target index out of bounds")
            }
            guard let result = wbe_plan_compile_target(
                handle, target, extras, knownFingerprint != nil, knownFingerprint ?? 0
            ) else {
                throw EngineError.last()
            }
            if wbe_compile_unchanged(result) {
                wbe_compile_free(result)
                return nil
            }
            // The result owns the strings the accessors return, so it is freed
            // only after they are read, or, for the webkit JSON, with its Data.
            let stats: Stats
            do {
                stats = try JSONDecoder().decode(Stats.self, from: Data(String(cString: wbe_compile_stats_json(result)).utf8))
            } catch {
                wbe_compile_free(result)
                throw error
            }
            let runtimeRules = String(cString: wbe_compile_runtime_text(result))
            let webkit = wbe_compile_webkit_json(result)!
            let length = strlen(webkit)
            guard length > 0 else {
                wbe_compile_free(result)
                return Compiled(safariRulesJSON: Data(), runtimeRules: runtimeRules, stats: stats)
            }
            // The engine's buffer is handed over, not copied: it is freed when
            // the Data is released.
            let safariRulesJSON = Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: UnsafeRawPointer(webkit)),
                count: length,
                deallocator: .custom { _, _ in wbe_compile_free(result) }
            )
            return Compiled(safariRulesJSON: safariRulesJSON, runtimeRules: runtimeRules, stats: stats)
        }
    }

    /// Serializes a per-page engine for `runtimeRules`.
    public static func buildEngine(runtimeRules: String) throws -> Data {
        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard wbe_engine_build(runtimeRules, &bytes, &length), let bytes else {
            throw EngineError.last()
        }
        guard length > 0 else {
            wbe_bytes_free(bytes, length)
            return Data()
        }
        // The engine's buffer is handed over, not copied: freed with the Data.
        return Data(bytesNoCopy: UnsafeMutableRawPointer(bytes), count: length, deallocator: .custom { pointer, count in
            wbe_bytes_free(pointer.assumingMemoryBound(to: UInt8.self), count)
        })
    }

    /// The per-page engine. Not safe for concurrent use; callers serialize.
    public final class Engine {
        private let handle: OpaquePointer

        /// Maps the engine that starts `offset` bytes into the file at `path`.
        /// Replace the file by rename; never write it in place while open.
        public init(path: String, offset: Int) throws {
            guard let handle = wbe_engine_open(path, offset) else { throw EngineError.last() }
            self.handle = handle
        }

        deinit { wbe_engine_free(handle) }

        /// `{"hide":[..],"procedural":[..],"scriptlets":[[name, args..]],"generichide":bool}`.
        /// `topUrl` is the page embedding a subframe, nil for a top frame.
        public func lookup(url: String, topUrl: String? = nil) throws -> Data {
            guard let json = wbe_engine_lookup(handle, url, topUrl) else { throw EngineError.last() }
            defer { wbe_string_free(json) }
            return Data(bytes: json, count: strlen(json))
        }
    }

    /// The registrable domain (eTLD+1) of `host`, or nil for a public suffix.
    public static func registrableDomain(of host: String) -> String? {
        guard let root = wbe_registrable_domain(host) else { return nil }
        defer { wbe_string_free(root) }
        return String(cString: root)
    }

    /// The parsed form of one rule line as JSON, for the rule editor.
    public static func classify(line: String) -> Data? {
        guard let json = wbe_classify_line(line) else { return nil }
        defer { wbe_string_free(json) }
        return Data(bytes: json, count: strlen(json))
    }
}
