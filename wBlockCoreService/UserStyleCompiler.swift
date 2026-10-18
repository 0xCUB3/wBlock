//
//  UserStyleCompiler.swift
//  wBlockCoreService
//
// Offline, compiler-neutral UserCSS preprocessing. Execution is isolated by the
// public WebKit compiler host; backend definitions remain compiler-neutral.
//

import CryptoKit
import Foundation

public struct UserStyleCompilationRequest: Sendable, Hashable {
    public let source: String
    public let preprocessor: String
    public let variables: [UserStyleSupport.Variable]
    public let options: [String: String]
    public let sourceDigest: String

    public init(source: String, preprocessor: String, variables: [UserStyleSupport.Variable], options: [String: String] = [:], sourceDigest: String? = nil) {
        self.source = source
        self.preprocessor = preprocessor
        self.variables = variables
        self.options = options
        self.sourceDigest = sourceDigest ?? UserStylePreprocessorService.digest(source)
    }
}

public struct UserStyleCompiledArtifact: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let sourceDigest: String
    public let preprocessor: String
    public let compilerRevision: String
    public let optionsDigest: String
    public let compiledBodyDigest: String
    public let body: String

    public init(request: UserStyleCompilationRequest, compilerRevision: String, body: String) {
        schemaVersion = Self.currentSchemaVersion
        sourceDigest = request.sourceDigest
        preprocessor = UserStylePreprocessorService.normalize(request.preprocessor)
        self.compilerRevision = compilerRevision
        optionsDigest = UserStylePreprocessorService.optionsDigest(request.options)
        compiledBodyDigest = UserStylePreprocessorService.digest(body)
        self.body = body
    }
}

public protocol UserStylePreprocessorBackend: Sendable {
    var preprocessor: String { get }
    var compilerRevision: String { get }
    var maximumSourceBytes: Int { get }
    var maximumOutputBytes: Int { get }
    var consumesVariables: Bool { get }
    func compile(_ request: UserStyleCompilationRequest) throws -> String
}

public enum UserStylePreprocessorService {
    public static let lessRevision = "less-4.9.1-wblock-1"
    public static let stylusRevision = "stylus-0.64.0-wblock-2-bounded-offline"
    public static let maximumSourceBytes = 2 * 1024 * 1024
    public static let maximumOutputBytes = 10 * 1024 * 1024

    public static func normalize(_ preprocessor: String) -> String {
        let value = preprocessor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? "default" : value
    }

    public static func optionsDigest(_ options: [String: String]) -> String {
        digest(options.keys.sorted().map { "\($0)=\(options[$0] ?? "")" }.joined(separator: "\n"))
    }

    /// SHA256 hex digest of `source`. Memoized: cache keys derived from userstyle
    /// content are recomputed on every `compiledStyleBody` access and every
    /// parse-cache lookup, so hashing a large stylesheet each time was defeating
    /// the caches it was meant to serve. A dictionary lookup compares the string
    /// bytes once instead of hashing them. The cache is bounded both by entry
    /// count and by retained key bytes, since a single key may be a multi-megabyte
    /// stylesheet or compiled body.
    public static func digest(_ source: String) -> String {
        digestCacheLock.lock()
        defer { digestCacheLock.unlock() }
        if let cached = digestCache[source] {
            return cached
        }
        let digest = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let sourceBytes = source.utf8.count
        if digestCache.count >= digestCacheLimit
            || digestCacheBytes + sourceBytes > digestCacheByteLimit {
            digestCache.removeAll(keepingCapacity: true)
            digestCacheBytes = 0
        }
        digestCache[source] = digest
        digestCacheBytes += sourceBytes
        return digest
    }

    private static let digestCacheLock = NSLock()
    private static let digestCacheLimit = 512
    private static let digestCacheByteLimit = 32 * 1024 * 1024
    nonisolated(unsafe) private static var digestCache: [String: String] = [:]
    nonisolated(unsafe) private static var digestCacheBytes = 0

    public static func backend(for preprocessor: String) -> (any UserStylePreprocessorBackend)? {
        switch normalize(preprocessor) {
        case "less": return LessBackend()
        case "stylus": return StylusBackend()
        default: return nil
        }
    }

    public static func requiresCompilation(_ preprocessor: String) -> Bool { backend(for: preprocessor) != nil }
    public static func compilerRevision(for preprocessor: String) -> String? { backend(for: preprocessor)?.compilerRevision }

    public static func request(source: String, authoritativeContent: String, preprocessor: String, variables: [UserStyleSupport.Variable], options: [String: String] = [:]) -> UserStyleCompilationRequest {
        UserStyleCompilationRequest(source: source, preprocessor: preprocessor, variables: variables, options: options, sourceDigest: digest(authoritativeContent))
    }

    public static func validate(_ artifact: UserStyleCompiledArtifact, for request: UserStyleCompilationRequest) -> Bool {
        guard let backend = backend(for: request.preprocessor),
              artifact.schemaVersion == UserStyleCompiledArtifact.currentSchemaVersion,
              artifact.sourceDigest == request.sourceDigest,
              artifact.preprocessor == normalize(request.preprocessor),
              artifact.compilerRevision == backend.compilerRevision,
              artifact.optionsDigest == optionsDigest(request.options),
              artifact.compiledBodyDigest == digest(artifact.body),
              request.source.utf8.count <= backend.maximumSourceBytes,
              UserStyleCompiler.serializedInputSize(request) <= backend.maximumSourceBytes,
              artifact.body.utf8.count <= backend.maximumOutputBytes else { return false }
        return true
    }

    public static func compile(_ request: UserStyleCompilationRequest) throws -> UserStyleCompiledArtifact {
        guard let backend = backend(for: request.preprocessor) else {
            throw UserStyleCompiler.CompilationError(message: String(localized: "Userstyle compiler failed.", comment: "Generic userstyle compiler failure"))
        }
        guard request.source.utf8.count <= backend.maximumSourceBytes,
              UserStyleCompiler.serializedInputSize(request) <= backend.maximumSourceBytes else {
            throw UserStyleCompiler.CompilationError(message: String(localized: "Userstyle source exceeds the 2 MiB limit.", comment: "Userstyle compiler source size error"))
        }
        return UserStyleCompiledArtifact(request: request, compilerRevision: backend.compilerRevision, body: try backend.compile(request))
    }
}

private struct LessBackend: UserStylePreprocessorBackend {
    let preprocessor = "less"
    let compilerRevision = UserStylePreprocessorService.lessRevision
    let maximumSourceBytes = UserStylePreprocessorService.maximumSourceBytes
    let maximumOutputBytes = UserStylePreprocessorService.maximumOutputBytes
    let consumesVariables = true
    func compile(_ request: UserStyleCompilationRequest) throws -> String {
        try UserStyleCompiler.compileLess(request)
    }
}

private struct StylusBackend: UserStylePreprocessorBackend {
    let preprocessor = "stylus"
    let compilerRevision = UserStylePreprocessorService.stylusRevision
    let maximumSourceBytes = UserStylePreprocessorService.maximumSourceBytes
    let maximumOutputBytes = UserStylePreprocessorService.maximumOutputBytes
    let consumesVariables = true
    func compile(_ request: UserStyleCompilationRequest) throws -> String {
        let variables = UserStyleCompiler.variableMap(request.variables)
        return try UserStyleCompiler.callJSONBridge(resource: "stylus-jsc", extension: "js", function: "StylusCompile", request: ["source": request.source, "variables": variables])
    }
}

enum UserStyleCompiler {
    struct CompilationError: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    static let maximumSourceBytes = UserStylePreprocessorService.maximumSourceBytes
    static let maximumOutputBytes = UserStylePreprocessorService.maximumOutputBytes
#if DEBUG
    /// Test-only resource-name overrides; production always loads packaged resources.
    nonisolated(unsafe) static var compilerSourceOverrides: [String: String] = [:]
    nonisolated(unsafe) static var debugDeadlineOverride: TimeInterval?

    static var compilerSourceOverride: String?
#endif

    static func serializedInputSize(_ request: UserStyleCompilationRequest) -> Int {
        serializedInputSize(source: request.source, metadata: [
            "preprocessor": request.preprocessor,
            "variables": request.variables.map { ["name": $0.name, "value": $0.value] },
            "options": request.options
        ])
    }

    private static func serializedInputSize(source: String, metadata: [String: Any]) -> Int {
        guard let data = try? JSONSerialization.data(withJSONObject: metadata) else { return Int.max }
        return source.utf8.count + data.count
    }

    static func compile(_ source: String, variables: [UserStyleSupport.Variable]) throws -> String {
        try compileLess(UserStyleCompilationRequest(source: source, preprocessor: "less", variables: variables))
    }

    static func compileLess(_ request: UserStyleCompilationRequest) throws -> String {
        let globals = variableMap(request.variables)
        let bridgeRequest: [String: Any] = ["source": request.source, "variables": globals]
        guard JSONSerialization.isValidJSONObject(bridgeRequest),
              serializedInputSize(source: request.source, metadata: ["variables": globals]) <= maximumSourceBytes else {
            throw CompilationError(message: String(localized: "Userstyle source exceeds the 2 MiB limit.", comment: "Userstyle compiler source size error"))
        }
#if DEBUG
        let bundle = compilerSourceOverrides["less.min"] ?? compilerSourceOverride ?? loadCompilerBundle("less.min", extension: "js")
#else
        let bundle = loadCompilerBundle("less.min", extension: "js")
#endif
        guard let bundle else { throw CompilationError(message: String(localized: "Userstyle compiler resource is missing.", comment: "Userstyle compiler resource error")) }
        let adapter = """
        function(request) { return new Promise(function(resolve) {
            var failure = null;
            less.render(request.source, {filename:'file:///userstyle.less', javascriptEnabled: false, processImports: false, globalVars:request.variables}, function(error, output) {
                // globalVars adds one line ahead of the source.
                if (error) failure = {message:error.message || String(error), line:error.line == null ? null : error.line - 1, column:error.column};
                resolve(JSON.stringify(failure ? {error:failure} : {css:output && output.css}));
            });
        }); }
        """
        let object = try UserStyleCompilerExecutionHost.run(runtime: bundle, request: bridgeRequest, adapter: adapter)
        return try extractCSS(object)
    }

    /// UserCSS metadata may repeat variable names. The last
    /// declaration wins deterministically instead of trapping on duplicate keys.
    static func variableMap(_ variables: [UserStyleSupport.Variable]) -> [String: String] {
        var result: [String: String] = [:]
        for variable in variables {
            result[variable.name] = variable.value
        }
        return result
    }

    static func callJSONBridge(resource: String, extension: String, function: String, request: [String: Any]) throws -> String {
        let source = request["source"] as? String ?? ""
        var metadata = request
        metadata.removeValue(forKey: "source")
        guard JSONSerialization.isValidJSONObject(request),
              serializedInputSize(source: source, metadata: metadata) <= maximumSourceBytes else { throw CompilationError(message: String(localized: "Userstyle compiler input could not be serialized.", comment: "Userstyle compiler serialization error")) }
#if DEBUG
        let runtime = compilerSourceOverrides[resource] ?? loadCompilerBundle(resource, extension: `extension`)
#else
        let runtime = loadCompilerBundle(resource, extension: `extension`)
#endif
        guard let runtime else { throw CompilationError(message: String(localized: "Userstyle compiler resource is missing.", comment: "Userstyle compiler resource error")) }
        let adapter = "function(request) { var r = (typeof \(function) === 'function') ? \(function)(request) : null; return typeof r === 'string' ? r : JSON.stringify(r); }"
        let object = try UserStyleCompilerExecutionHost.run(runtime: runtime, request: request, adapter: adapter)
        return try extractCSS(object)
    }

    private static func extractCSS(_ object: [String: Any]) throws -> String {
        if let error = object["error"] as? String {
            throw CompilationError(message: format(error: error, line: object["line"], column: object["column"]))
        }
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? String(localized: "Userstyle compiler failed.", comment: "Generic userstyle compiler failure")
            throw CompilationError(message: format(error: message, line: error["line"], column: error["column"]))
        }
        guard let css = object["css"] as? String else { throw CompilationError(message: String(localized: "Userstyle compiler returned no CSS.", comment: "Userstyle compiler empty output error")) }
        guard css.utf8.count <= maximumOutputBytes else { throw CompilationError(message: String(localized: "Userstyle compiler output exceeds the 10 MiB limit.", comment: "Userstyle compiler output size error")) }
        return css
    }

    private static func format(error: String, line: Any?, column: Any?) -> String {
        let lineNumber: Int? = (line as? NSNumber).map { max(1, $0.intValue) }
        let columnNumber = (column as? NSNumber)?.intValue
        if let lineNumber, let columnNumber {
            return String(format: String(localized: "line %@, column %@: %@", comment: "Userstyle compiler diagnostic location"), "\(lineNumber)", "\(columnNumber)", error)
        }
        if let lineNumber {
            return String(format: String(localized: "line %@: %@", comment: "Userstyle compiler diagnostic location"), "\(lineNumber)", error)
        }
        if let columnNumber {
            return String(format: String(localized: "column %@: %@", comment: "Userstyle compiler diagnostic location"), "\(columnNumber)", error)
        }
        return error
    }

    private static let compilerBundleCacheLock = NSLock()
    nonisolated(unsafe) private static var compilerBundleCache: [String: String] = [:]

    /// Compiler bundles are immutable app resources of a few hundred KB each;
    /// cache them so repeated compilations do not re-read them from disk.
    private static func loadCompilerBundle(_ name: String, extension: String) -> String? {
        let cacheKey = "\(name).\(`extension`)"
        compilerBundleCacheLock.lock()
        defer { compilerBundleCacheLock.unlock() }
        if let cached = compilerBundleCache[cacheKey] {
            return cached
        }
        let bundle = Bundle(for: BundleMarker.self)
        guard let url = bundle.url(forResource: name, withExtension: `extension`, subdirectory: "UserStyleCompiler") ?? bundle.url(forResource: name, withExtension: `extension`),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        compilerBundleCache[cacheKey] = source
        return source
    }

    private final class BundleMarker: NSObject {}
}
