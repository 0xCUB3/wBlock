import Foundation
import WBE

/// Swift face of the wbe engine (crates/wbe/include/wbe.h).
public enum WBEngine {
    public struct EngineError: LocalizedError {
        public let errorDescription: String?
        static func last() -> EngineError {
            EngineError(errorDescription: wbe_last_error().map { String(cString: $0) } ?? "wbe failed")
        }
    }

    /// Changes whenever the engine's outputs change for the same input.
    public static var outputVersion: UInt32 { wbe_output_version() }

    public struct Compiled {
        /// Safari content-blocker JSON array.
        public let safariRulesJSON: String
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

        enum CodingKeys: String, CodingKey {
            case lines, rules, dropped, admitted
            case nativeRules = "native_rules"
            case runtimeRules = "runtime_rules"
        }
    }

    public final class Plan: @unchecked Sendable {
        private let handle: OpaquePointer

        public init(requestJSON: String) throws {
            guard let handle = wbe_plan_new(requestJSON) else { throw EngineError.last() }
            self.handle = handle
        }

        deinit { wbe_plan_free(handle) }

        public func compileTarget(_ target: Int, extras: String) throws -> Compiled {
            guard target >= 0 else {
                throw EngineError(errorDescription: "target index out of bounds")
            }
            guard let result = wbe_plan_compile_target(handle, target, extras) else {
                throw EngineError.last()
            }
            defer { wbe_compile_free(result) }
            let statsJSON = String(cString: wbe_compile_stats_json(result))
            return Compiled(
                safariRulesJSON: String(cString: wbe_compile_webkit_json(result)),
                runtimeRules: String(cString: wbe_compile_runtime_text(result)),
                stats: try JSONDecoder().decode(Stats.self, from: Data(statsJSON.utf8))
            )
        }
    }

    /// Serializes a per-page engine for `runtimeRules`.
    public static func buildEngine(runtimeRules: String) throws -> Data {
        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard wbe_engine_build(runtimeRules, &bytes, &length), let bytes else {
            throw EngineError.last()
        }
        defer { wbe_bytes_free(bytes, length) }
        return Data(bytes: bytes, count: length)
    }

    /// The per-page engine. Not safe for concurrent use; callers serialize.
    public final class Engine {
        private let handle: OpaquePointer

        public init(data: Data) throws {
            let handle = data.withUnsafeBytes { raw in
                wbe_engine_open(raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
            }
            guard let handle else { throw EngineError.last() }
            self.handle = handle
        }

        deinit { wbe_engine_free(handle) }

        /// `{"hide":[..],"procedural":[..],"scriptlets":[[name, args..]],"generichide":bool}`.
        public func lookup(url: String) throws -> Data {
            guard let json = wbe_engine_lookup(handle, url) else { throw EngineError.last() }
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
